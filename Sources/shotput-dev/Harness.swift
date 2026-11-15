// Offscreen checks for the parts that normally need a screen: the editor window and the selection
// overlay. Nothing here is ordered on screen. Views are driven with synthetic mouse events and
// rendered straight into bitmaps.
import AppKit
@testable import ShotputKit

private var failures = 0

private func expect(_ condition: Bool, _ label: String) {
    print(condition ? "  ok    \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

@MainActor
private func mouse(_ type: NSEvent.EventType, _ view: NSView, _ point: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
    )!
}

@MainActor
private func drag(_ view: NSView, from a: CGPoint, to b: CGPoint, flags: NSEvent.ModifierFlags = [], release: Bool = true) {
    view.mouseDown(with: mouse(.leftMouseDown, view, a, flags: flags))
    for step in 1 ... 8 {
        view.mouseDragged(with: mouse(.leftMouseDragged, view, a + (b - a) * (CGFloat(step) / 8), flags: flags))
    }
    if release { view.mouseUp(with: mouse(.leftMouseUp, view, b, flags: flags)) }
}

@MainActor
private func click(_ view: NSView, at point: CGPoint, clicks: Int = 1) {
    view.mouseDown(with: mouse(.leftMouseDown, view, point, clicks: clicks))
    view.mouseUp(with: mouse(.leftMouseUp, view, point, clicks: clicks))
}

private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }

/// A fake app screenshot with a sidebar, a toolbar, text rows, and a button.
private func mockScreenshot(size: CGSize, scale: CGFloat) -> CGImage {
    bitmap(width: Int(size.width * scale), height: Int(size.height * scale)) { ctx in
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(rgb(0xF1F0ED))
        ctx.fill(CGRect(x: 0, y: 0, width: 150, height: size.height))
        ctx.fill(CGRect(x: 150, y: 0, width: size.width - 150, height: 44))
        for row in 0 ..< 9 {
            ctx.setFillColor(rgb(0xA6A29A))
            ctx.fill(CGRect(x: 18, y: 64 + CGFloat(row) * 26, width: 90 + CGFloat(row % 3) * 14, height: 8))
            ctx.setFillColor(rgb(0x2B2A26, 0.75))
            ctx.fill(CGRect(x: 180, y: 76 + CGFloat(row) * 24, width: 300 - CGFloat(row % 4) * 46, height: 7))
        }
        ctx.setFillColor(rgb(0x1F6FE5))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 470, y: 290, width: 110, height: 32), cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
    }
}

// MARK: Editor

@MainActor
func editorHarness(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    for key in ["editor.toolName", "editor.styles", "editor.snapsToEdges", "NSToolbar Configuration editor.markup"] {
        UserDefaults.standard.removeObject(forKey: key)
    }

    let capture = Capture(image: mockScreenshot(size: CGSize(width: 620, height: 360), scale: 2), scale: 2)
    let controller = EditorWindowController(capture: capture)
    controller.layOut()
    guard let window = controller.window else { fatalError("no window") }
    let canvas = controller.canvas
    let model = controller.model
    settle()

    print("editor")
    expect(canvas.frame.size == CGSize(width: 620, height: 360), "canvas matches the image's point size")
    expect(model.tool == .arrow, "opens on the arrow tool")

    drag(canvas, from: CGPoint(x: 400, y: 250), to: CGPoint(x: 468, y: 300))
    expect(model.annotations.count == 1 && model.selectedID == model.annotations[0].id, "dragging draws an arrow and selects it")

    click(canvas, at: CGPoint(x: 560, y: 120))
    expect(model.annotations.count == 1, "a bare click with a shape tool adds nothing")
    expect(!model.canRedo && model.canUndo, "and leaves no stray undo step")

    model.setTool(.rectangle)
    drag(canvas, from: CGPoint(x: 172, y: 64), to: CGPoint(x: 490, y: 132))
    model.setTool(.ellipse)
    model.setColor(.green)
    drag(canvas, from: CGPoint(x: 6, y: 50), to: CGPoint(x: 140, y: 110), flags: .shift)
    if case let .ellipse(rect)? = model.annotations.last?.kind {
        expect(abs(rect.width - rect.height) < 0.01, "shift constrains an ellipse to a circle")
    } else {
        expect(false, "ellipse was created")
    }

    model.setTool(.counter)
    model.setColor(.blue)
    click(canvas, at: CGPoint(x: 164, y: 80))
    click(canvas, at: CGPoint(x: 164, y: 200))
    let numbers = model.annotations.compactMap { annotation -> Int? in
        if case let .counter(_, number) = annotation.kind { return number }
        return nil
    }
    expect(numbers == [1, 2], "step numbers count up")

    model.setTool(.redact)
    drag(canvas, from: CGPoint(x: 196, y: 186), to: CGPoint(x: 420, y: 250))
    expect(model.annotations.last?.tool == .redact, "dragging over empty space redacts")
    model.setTool(.highlight)
    model.setColor(.yellow)
    drag(canvas, from: CGPoint(x: 176, y: 142), to: CGPoint(x: 400, y: 160))

    model.setTool(.pen)
    model.setColor(.violet)
    canvas.mouseDown(with: mouse(.leftMouseDown, canvas, CGPoint(x: 20, y: 300)))
    for i in 1 ... 30 {
        let p = CGPoint(x: 20 + CGFloat(i) * 4, y: 300 + sin(CGFloat(i) / 3) * 12)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, canvas, p))
    }
    canvas.mouseUp(with: mouse(.leftMouseUp, canvas, CGPoint(x: 140, y: 300)))

    let redactID = model.annotations.first { $0.tool == .redact }?.id
    model.setTool(.arrow)
    click(canvas, at: CGPoint(x: 300, y: 220))
    expect(model.selectedID == redactID, "a click inside a solid mark selects it")
    drag(canvas, from: CGPoint(x: 300, y: 220), to: CGPoint(x: 300, y: 224))
    expect(model.annotations.first { $0.id == redactID }?.frame.minY == 190, "and once selected it drags")
    model.undo()

    // Text: click to start, type, commit. It lands on top of the redaction rather than moving it.
    model.setTool(.text)
    model.setColor(.red)
    let beforeText = model.annotations.count
    canvas.mouseDown(with: mouse(.leftMouseDown, canvas, CGPoint(x: 330, y: 232)))
    if let editor = canvas.subviews.compactMap({ $0 as? NSTextView }).first {
        editor.string = "Wrong colour"
        canvas.commitText()
        expect(model.annotations.count == beforeText + 1, "typed text becomes a label")
        expect(model.annotations.last?.style.text == .pill, "labels are filled by default")
    } else {
        expect(false, "clicking with the text tool opens an inline editor")
    }

    // Moving: grab the arrow by its shaft.
    model.setTool(.arrow)
    let arrowID = model.annotations[0].id
    let before = model.annotations[0].endpoints!
    drag(canvas, from: CGPoint(x: 434, y: 275), to: CGPoint(x: 444, y: 265))
    let after = model.annotations[0].endpoints!
    expect(model.annotations[0].id == arrowID && abs(after.from.x - before.from.x - 10) < 0.01
        && abs(after.from.y - before.from.y + 10) < 0.01, "dragging an existing mark moves it")
    expect(model.annotations.count == beforeText + 1, "moving a mark does not draw a new one")

    // Undo and redo.
    let count = model.annotations.count
    model.undo()
    expect(model.annotations[0].endpoints!.from == before.from, "undo restores the move in one step")
    model.undo()
    expect(model.annotations.count == count - 1, "undo removes the last mark")
    model.redo()
    model.redo()
    expect(model.annotations.count == count && model.annotations[0].endpoints!.from == after.from, "redo brings both back")

    // Style applies to the selection.
    click(canvas, at: CGPoint(x: 444, y: 265))
    expect(model.selectedID == arrowID, "clicking a mark selects it")
    model.setStyle { $0.size = 10 }
    expect(model.annotations[0].style.size == 10, "changing size restyles the selection")
    model.setStyle { $0.arrow = .double; $0.curved = true }
    expect(model.annotations[0].style.arrow == .double && model.annotations[0].bend != nil,
           "arrow style and the curved toggle reshape the selected arrow")
    model.undo()
    expect(model.annotations[0].style.arrow == .tapered && model.annotations[0].bend == nil, "and undo takes that back in one step")
    model.setColor(.teal, coalesce: "picker")
    model.setColor(.pink, coalesce: "picker")
    model.undo()
    expect(model.annotations[0].color == .red, "dragging through the colour picker undoes as one step")
    model.selectedID = nil
    expect(model.style(for: .arrow).size == 10, "the tool remembers the last size picked")

    // Per-tool styles and the new tools.
    model.setTool(.rectangle)
    model.setStyle { $0.fill = .tinted; $0.dashed = true; $0.cornerRadius = 16 }
    drag(canvas, from: CGPoint(x: 520, y: 150), to: CGPoint(x: 610, y: 200))
    expect(model.annotations.last?.style.fill == .tinted && model.annotations.last?.style.dashed == true,
           "a new rectangle takes the tool's style")
    model.setTool(.filledRectangle)
    drag(canvas, from: CGPoint(x: 500, y: 20), to: CGPoint(x: 600, y: 40))
    expect(model.annotations.last?.tool == .filledRectangle, "the filled rectangle tool draws a solid box")
    model.setTool(.spotlight)
    drag(canvas, from: CGPoint(x: 496, y: 310), to: CGPoint(x: 612, y: 352))
    expect(model.annotations.last?.tool == .spotlight, "the spotlight tool lights an area")
    let redaction = model.annotations.first { $0.tool == .redact }!.id
    model.selectedID = redaction
    for mode in RedactMode.allCases {
        model.setStyle { $0.redaction = mode }
        let flat = AnnotationRenderer().flatten(base: model.base, scale: model.scale, annotations: model.annotations, outputScale: 1)
        expect(flat != nil, "redaction renders as \(mode.rawValue)")
    }
    model.setStyle { $0.redaction = .blurSecure }
    model.selectedID = nil
    model.setTool(.select)
    drag(canvas, from: CGPoint(x: 40, y: 330), to: CGPoint(x: 120, y: 340))
    expect(model.selectedID == nil && model.annotations.allSatisfy({ $0.tool != .select }), "the select tool draws nothing")

    // Export.
    let flat = AnnotationRenderer().flatten(base: model.base, scale: model.scale, annotations: model.annotations, outputScale: model.scale)
    expect(flat?.width == 1240 && flat?.height == 720, "export keeps full resolution")
    let reduced = AnnotationRenderer().flatten(base: model.base, scale: model.scale, annotations: model.annotations, outputScale: 1)
    expect(reduced?.width == 620 && reduced?.height == 360, "standard-resolution export halves it")

    // Crop mode: a box with handles, held to a shape if asked, applied with Crop.
    let arrowStart = model.annotations[0].endpoints!.from
    model.beginCrop()
    expect(model.crop?.rect == CGRect(x: 0, y: 0, width: 620, height: 360), "crop opens on the whole image")
    model.snapsToEdges = false
    drag(canvas, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 150, y: 44))
    expect(model.crop?.rect == CGRect(x: 150, y: 44, width: 470, height: 316), "dragging a corner handle resizes the box")
    model.snapsToEdges = true
    drag(canvas, from: CGPoint(x: 150, y: 44), to: CGPoint(x: 146, y: 47))
    expect(model.crop?.rect.minX == 150 && model.crop?.rect.minY == 44, "with snapping on, the handle sticks to the sidebar and toolbar edges")
    model.applyCrop()
    settle()
    expect(model.crop == nil && model.size == CGSize(width: 470, height: 316), "Crop resizes the image")
    expect(abs(model.annotations[0].endpoints!.from.x - (arrowStart.x - 150)) < 0.01, "crop moves marks with it")
    model.undo()
    expect(model.size == CGSize(width: 620, height: 360), "undo restores the uncropped image")

    model.beginCrop()
    model.setCropAspect(.square)
    expect(model.crop.map { abs($0.rect.width - $0.rect.height) < 0.01 } ?? false, "a 1:1 ratio squares the box")
    model.setCropPixelSize(width: 400, height: nil)
    expect(model.crop.map { $0.rect.width == 200 && $0.rect.height == 200 } ?? false, "typing a width in pixels keeps the ratio")
    model.cancelCrop()
    expect(model.size == CGSize(width: 620, height: 360), "Cancel leaves the image alone")

    model.rotate(clockwise: true)
    expect(model.size == CGSize(width: 360, height: 620), "rotating turns the image")
    let turned = model.annotations[0].endpoints!.from
    expect(abs(turned.x - (360 - arrowStart.y)) < 0.01 && abs(turned.y - arrowStart.x) < 0.01, "and turns the marks with it")
    model.flip(horizontally: true)
    model.resample(toPixels: CGSize(width: 360, height: 620))
    expect(model.size == CGSize(width: 180, height: 310), "resizing halves the image")
    model.revertToOriginal()
    expect(model.size == CGSize(width: 620, height: 360), "Revert to Original brings the first image back")
    expect(model.annotations[0].endpoints!.from.distance(to: arrowStart) < 0.01, "with every mark where it was drawn")
    expect(!model.canRevert, "and there is nothing more to revert")

    model.beginCrop()
    settle()
    window.displayIfNeeded()
    settle()
    if let frameView = window.contentView?.superview,
       let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let image = rep.cgImage { write(image, scale: 2, to: path.replacingOccurrences(of: ".png", with: "-crop.png")) }
    }
    model.cancelCrop()
    // The spotlight dims the whole render, so it goes before the window is captured.
    model.perform { $0.removeAll { $0.tool == .spotlight } }
    model.setTool(.arrow)
    model.showToast("Copied")
    settle()

    window.displayIfNeeded()
    settle()
    guard let frameView = window.contentView?.superview,
          let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { fatalError("no frame view") }
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    if let image = rep.cgImage { write(image, scale: 2, to: path) }
    if let flat { write(flat, scale: 2, to: path.replacingOccurrences(of: ".png", with: "-export.png")) }
    drawingChecks(expect, render: path.replacingOccurrences(of: ".png", with: "-curves.png"))
    print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
}

// MARK: Selection overlay

@MainActor
func overlayHarness(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    guard let screen = NSScreen.main else { fatalError("no screen") }
    let size = screen.frame.size
    let scale: CGFloat = 2

    // Front window first, as the window server reports them.
    let front = CGRect(x: 200, y: 200, width: 600, height: 400)
    let back = CGRect(x: 500, y: 300, width: 700, height: 450)
    let still = bitmap(width: Int(size.width * scale), height: Int(size.height * scale)) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(rgb(0x4A8FB0))
        ctx.fill(CGRect(origin: .zero, size: size))
        for (rect, hex) in [(back, 0xFBFBF9), (front, 0x222220)] {
            ctx.setFillColor(rgb(UInt(hex)))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(rgb(0xE5484D))
            ctx.fillEllipse(in: CGRect(x: rect.minX + 14, y: rect.maxY - 24, width: 12, height: 12))
        }
    }
    let shot = DisplayShot(screen: screen, image: still, scale: scale)
    let windows = [WindowInfo(id: 1, frame: front), WindowInfo(id: 2, frame: back)]
    let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - 30)

    let overlay = SelectionOverlay(mode: .area)
    var outcome: SelectionOverlay.Outcome?
    overlay.completion = { outcome = $0 }
    let view = OverlayView(overlay: overlay, shot: shot, windows: windows, visibleFrame: visible, showHint: true)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
    window.contentView = view

    func render(_ suffix: String) {
        guard let layer = view.layer else { return }
        let image = bitmap(width: Int(size.width), height: Int(size.height)) { layer.render(in: $0) }
        write(image, scale: 1, to: path.replacingOccurrences(of: ".png", with: "-\(suffix).png"))
    }

    print("overlay")
    view.pointerMoved(to: CGPoint(x: 204, y: 420))
    expect(view.pointer == CGPoint(x: 200, y: 420), "pointer snaps to a visible window edge")
    view.pointerMoved(to: CGPoint(x: 204, y: 420), snapping: false)
    expect(view.pointer == CGPoint(x: 204, y: 420), "holding command turns snapping off")
    view.pointerMoved(to: CGPoint(x: 503, y: 450))
    expect(view.pointer.x == 503, "an edge hidden behind another window does not snap")
    view.pointerMoved(to: CGPoint(x: 503, y: 700))
    expect(view.pointer.x == 500, "the same edge snaps where it is visible")
    view.pointerMoved(to: CGPoint(x: 900, y: size.height - 33))
    expect(view.pointer.y == size.height - 30, "pointer snaps to the menu bar edge")
    view.pointerMoved(to: CGPoint(x: 203, y: 597))
    expect(view.pointer == CGPoint(x: 200, y: 600), "pointer snaps to a window corner")
    render("hover")

    drag(view, from: CGPoint(x: 203, y: 597), to: CGPoint(x: 640, y: 330), release: false)
    render("drag")
    view.mouseUp(with: mouse(.leftMouseUp, view, CGPoint(x: 640, y: 330)))
    if case let .area(rect, _)? = outcome {
        expect(rect == CGRect(x: 200, y: 330, width: 440, height: 270), "selection reports the snapped rect, got \(rect)")
        let crop = shot.crop(rect)
        expect(crop?.width == 880 && crop?.height == 540, "crop is pixel exact at 2x")
        if let crop {
            write(crop, scale: 2, to: path.replacingOccurrences(of: ".png", with: "-crop.png"))
        }
    } else {
        expect(false, "releasing the drag finishes with an area")
    }

    // Window mode.
    let picker = SelectionOverlay(mode: .window)
    var picked: SelectionOverlay.Outcome?
    picker.completion = { picked = $0 }
    let pickerView = OverlayView(overlay: picker, shot: shot, windows: windows, visibleFrame: visible, showHint: false)
    let pickerWindow = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
    pickerWindow.contentView = pickerView
    pickerView.pointerMoved(to: CGPoint(x: 700, y: 500))
    if let layer = pickerView.layer {
        let image = bitmap(width: Int(size.width), height: Int(size.height)) { layer.render(in: $0) }
        write(image, scale: 1, to: path.replacingOccurrences(of: ".png", with: "-window.png"))
    }
    pickerView.mouseUp(with: mouse(.leftMouseUp, pickerView, CGPoint(x: 700, y: 500)))
    if case let .window(info, _)? = picked {
        expect(info.id == 1, "window mode picks the frontmost window under the pointer")
    } else {
        expect(false, "clicking in window mode picks a window")
    }
    print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
}

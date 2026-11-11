// Frames of the real app for the launch film in LaunchFilm/. Nothing is ordered on screen: the
// selection overlay, the editor and the welcome guide are driven offscreen, as in Harness.swift,
// and each frame is written out with where the pointer was, so the edit can draw it in step.
//
//   shotput-dev film-capture <dir>   reads <dir>/plan.json and <dir>/still.png
//   shotput-dev film-onboard <dir>   reads <dir>/plan.json
import AppKit
import SwiftUI
@testable import ShotputKit

private struct Plan: Decodable {
    struct P: Decodable { let x: CGFloat; let y: CGFloat }
    struct R: Decodable { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat; var id: Int? }
    struct Overlay: Decodable { let start: P; let moveFrom, moveTo, down, dragTo, up: Double }
    struct Editor: Decodable {
        let arrowFrom, arrowTo, label: P
        let text: String
        let moveFrom, moveTo, down, dragTo, up, toolKey, labelMoveFrom, labelMoveTo, labelClick: Double
        let typeFrom, typeEvery, commit, done, end: Double
    }
    struct Onboard: Decodable { let permission, granted, shortcuts, mouse, ready, end: Double }
    let capture: R
    let windows: [R]
    let overlay: Overlay
    let thumb: P
    let editor: Editor
    let onboard: Onboard
}

private let fps = 60.0

private func smooth(_ t: Double) -> Double {
    let t = min(max(t, 0), 1)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

/// A gentle arc between two points, the way a hand moves a mouse rather than a ruler.
private func arc(_ a: CGPoint, _ b: CGPoint, _ t: Double, bend: CGFloat = 0.12) -> CGPoint {
    let mid = lerp(a, b, 0.5)
    let control = CGPoint(x: mid.x - (b.y - a.y) * bend, y: mid.y + (b.x - a.x) * bend)
    let u = CGFloat(t)
    return CGPoint(
        x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * control.x + u * u * b.x,
        y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * control.y + u * u * b.y
    )
}

/// Writes frames on a background queue so encoding never holds up the main thread.
private final class FrameWriter {
    let dir: URL
    private let queue = DispatchQueue(label: "film.writer", qos: .userInitiated, attributes: .concurrent)
    private let group = DispatchGroup()
    private(set) var meta: [[String: Any]] = []

    init(_ dir: URL) {
        self.dir = dir
        try? FileManager.default.removeItem(at: dir)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func add(_ image: CGImage, jpeg: Bool = false, _ info: [String: Any]) {
        let name = String(format: "%05d.%@", meta.count, jpeg ? "jpg" : "png")
        var info = info
        info["file"] = name
        meta.append(info)
        let url = dir.appendingPathComponent(name)
        queue.async(group: group) {
            let rep = NSBitmapImageRep(cgImage: image)
            let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.93])
                : rep.representation(using: .png, properties: [:])
            try? data?.write(to: url)
        }
    }

    func finish(extra: [String: Any] = [:]) {
        group.wait()
        var doc = extra
        doc["frames"] = meta
        let data = try! JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: dir.appendingPathComponent("frames.json"))
        print("wrote \(meta.count) frames to \(dir.path)")
    }
}

private func loadPlan(_ dir: URL) -> Plan {
    let data = try! Data(contentsOf: dir.appendingPathComponent("plan.json"))
    return try! JSONDecoder().decode(Plan.self, from: data)
}

@MainActor
private func event(_ type: NSEvent.EventType, _ view: NSView, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
    )!
}

private func pump(_ seconds: Double = 1 / 240) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
private func useAppIcon() {
    let icon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/AppIcon.icns")
    if let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }
}

/// A window that always draws as the active one. macOS will not let a command-line process
/// take activation, so the film's windows say they are key and main instead.
private final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor
private func makeKeyOffscreen(_ window: NSWindow) {
    object_setClass(window, ActiveLookingWindow.self)
    window.setFrameOrigin(CGPoint(x: -30000, y: -30000))
    window.orderFrontRegardless()
    window.becomeKey()
    window.becomeMain()
    pump(0.3)
}

// MARK: Capture and annotate

@MainActor
func filmCapture(dir path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: .aqua)
    UserDefaults.standard.removeObject(forKey: "editor.tool")
    UserDefaults.standard.removeObject(forKey: "editor.color")
    UserDefaults.standard.removeObject(forKey: "editor.weight")

    let dir = URL(fileURLWithPath: path)
    let plan = loadPlan(dir)
    guard let source = NSImage(contentsOf: dir.appendingPathComponent("still.png")),
          let still = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("no still.png") }
    let size = CGSize(width: CGFloat(still.width) / 2, height: CGFloat(still.height) / 2)
    guard let screen = NSScreen.screens.first(where: { $0.frame.size == size }) else {
        fatalError("needs a display that is \(Int(size.width)) by \(Int(size.height)) points")
    }
    // Plan coordinates are top-left; AppKit's are bottom-left.
    func appkit(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    func top(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    func appkit(_ r: Plan.R) -> CGRect { CGRect(x: r.x, y: size.height - r.y - r.h, width: r.w, height: r.h) }

    // The selection overlay over the frozen still.
    let shot = DisplayShot(screen: screen, image: still, scale: 2)
    let windows = plan.windows.map { WindowInfo(id: CGWindowID($0.id ?? 0), frame: appkit($0)) }
    let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - 30)
    let overlay = SelectionOverlay(mode: .area)
    var outcome: SelectionOverlay.Outcome?
    overlay.completion = { outcome = $0 }
    let view = OverlayView(overlay: overlay, shot: shot, windows: windows, visibleFrame: visible, showHint: true)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
    window.contentView = view

    let o = plan.overlay
    let a = CGPoint(x: plan.capture.x, y: plan.capture.y)
    let b = CGPoint(x: plan.capture.x + plan.capture.w, y: plan.capture.y + plan.capture.h)
    let start = CGPoint(x: o.start.x, y: o.start.y)
    let overlayFrames = FrameWriter(dir.appendingPathComponent("overlay"))
    var pressed = false
    view.pointerMoved(to: appkit(start))
    for frame in 0 ... Int(o.up * fps) {
        let t = Double(frame) / fps
        var raw: CGPoint
        if t < o.down {
            raw = arc(start, a, smooth((t - o.moveFrom) / (o.moveTo - o.moveFrom)), bend: -0.1)
        } else {
            raw = lerp(a, b, smooth((t - o.down - 0.05) / (o.dragTo - o.down - 0.05)))
        }
        if t >= o.down && !pressed {
            view.mouseDown(with: event(.leftMouseDown, view, appkit(a)))
            pressed = true
            raw = a
        } else if pressed {
            view.mouseDragged(with: event(.leftMouseDragged, view, appkit(raw)))
        } else {
            view.pointerMoved(to: appkit(raw))
        }
        guard let layer = view.layer else { fatalError("no layer") }
        let image = bitmap(width: still.width, height: still.height) { ctx in
            ctx.scaleBy(x: 2, y: 2)
            layer.render(in: ctx)
        }
        let p = top(view.pointer)
        overlayFrames.add(image, jpeg: true, ["t": t, "x": p.x, "y": p.y, "down": pressed])
    }
    view.mouseUp(with: event(.leftMouseUp, view, appkit(b)))
    guard case let .area(rect, _)? = outcome, let crop = shot.crop(rect) else { fatalError("the drag did not finish with an area") }
    let captureTop = CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    overlayFrames.finish(extra: ["capture": ["x": captureTop.minX, "y": captureTop.minY, "w": captureTop.width, "h": captureTop.height]])
    write(crop, scale: 2, to: dir.appendingPathComponent("capture.png").path)

    // The editor, opened where the capture was taken.
    let capture = Capture(image: crop, scale: 2, screenRect: rect, screen: screen)
    let controller = EditorWindowController(capture: capture)
    controller.layOut()
    guard let editorWindow = controller.window, let frameView = editorWindow.contentView?.superview else { fatalError("no editor window") }
    let canvas = controller.canvas
    let model = controller.model
    // Keep the frame layOut chose for the maths, then park the window far off every display and
    // make it key, so it draws as the active window does: coloured lights, a live Done button.
    let placed = editorWindow.frame
    makeKeyOffscreen(editorWindow)
    editorWindow.makeFirstResponder(canvas)
    editorWindow.displayIfNeeded()
    pump(0.4)

    let e = plan.editor
    func canvasPoint(_ p: Plan.P) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    /// Canvas points (flipped, image space) to screen points with a top-left origin.
    func onScreen(_ p: CGPoint) -> CGPoint {
        let inWindow = canvas.convert(p, to: nil)
        let screenPoint = CGPoint(x: placed.minX + inWindow.x, y: placed.minY + inWindow.y)
        return top(screenPoint)
    }
    func fromScreen(_ p: CGPoint) -> CGPoint {
        let s = appkit(p)
        let inWindow = CGPoint(x: s.x - placed.minX, y: s.y - placed.minY)
        return canvas.convert(inWindow, from: nil)
    }

    let thumb = CGPoint(x: plan.thumb.x, y: plan.thumb.y)
    let tail = onScreen(canvasPoint(e.arrowFrom))
    let tip = onScreen(canvasPoint(e.arrowTo))
    let labelPoint = onScreen(canvasPoint(e.label))
    let editorFrames = FrameWriter(dir.appendingPathComponent("editor"))
    var state = 0
    var typed = 0
    var textView: NSTextView?
    var key: String?
    var keyAt = -1.0
    for frame in 0 ... Int(e.end * fps) {
        let t = Double(frame) / fps
        var pointer: CGPoint
        if t < e.down {
            pointer = arc(thumb, tail, smooth((t - e.moveFrom) / (e.moveTo - e.moveFrom)))
        } else if t < e.labelMoveFrom {
            pointer = lerp(tail, tip, smooth((t - e.down - 0.05) / (e.dragTo - e.down - 0.05)))
        } else {
            pointer = arc(tip, labelPoint, smooth((t - e.labelMoveFrom) / (e.labelMoveTo - e.labelMoveFrom)), bend: 0.2)
        }
        let local = fromScreen(pointer)
        switch state {
        case 0 where t >= e.down:
            canvas.mouseDown(with: event(.leftMouseDown, canvas, local)); state = 1
        case 1 where t >= e.up:
            canvas.mouseUp(with: event(.leftMouseUp, canvas, local)); state = 2
        case 1:
            canvas.mouseDragged(with: event(.leftMouseDragged, canvas, local))
        case 2 where t >= e.toolKey:
            model.setTool(.text); key = "T"; keyAt = t; state = 3
        case 3 where t >= e.labelClick:
            canvas.mouseDown(with: event(.leftMouseDown, canvas, local))
            canvas.mouseUp(with: event(.leftMouseUp, canvas, local))
            textView = canvas.subviews.compactMap { $0 as? NSTextView }.first
            if textView == nil { print("  FAIL  the text tool opened no editor") }
            state = 4
        case 4 where t >= e.typeFrom:
            let due = min(e.text.count, Int((t - e.typeFrom) / e.typeEvery) + 1)
            while typed < due, let textView {
                let ch = e.text[e.text.index(e.text.startIndex, offsetBy: typed)]
                textView.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
                typed += 1
            }
            if t >= e.commit { canvas.commitText(); key = "return"; keyAt = t; state = 5 }
        case 5 where t >= e.done:
            key = "return"; keyAt = t; state = 6
        default: break
        }
        pump()
        frameView.displayIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { fatalError("no rep") }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let image = rep.cgImage else { fatalError("no image") }
        var info: [String: Any] = ["t": t, "x": pointer.x, "y": pointer.y, "down": state == 1, "typing": state == 4]
        if let key, t - keyAt < 0.001 { info["key"] = key }
        editorFrames.add(image, info)
    }
    let f = placed
    editorFrames.finish(extra: ["window": ["x": f.minX, "y": size.height - f.maxY, "w": f.width, "h": f.height]])

    let flat = AnnotationRenderer().flatten(base: model.base, scale: model.scale, annotations: model.annotations, outputScale: model.scale)
    if let flat { write(flat, scale: 2, to: dir.appendingPathComponent("annotated.png").path) }
}

// MARK: Welcome guide

@MainActor
func filmOnboard(dir path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: .aqua)
    useAppIcon()
    let dir = URL(fileURLWithPath: path)
    let plan = loadPlan(dir).onboard

    let state = OnboardingState(step: .welcome)
    let host = NSHostingView(rootView: OnboardingView(state: state).background(Color(nsColor: Palette.background)))
    host.appearance = NSAppearance(named: .aqua)
    // The same window the app builds, so the frame view supplies the real traffic lights.
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = Palette.background
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    makeKeyOffscreen(window)
    guard let frameView = window.contentView?.superview else { fatalError("no frame view") }
    // Build every step once first, so the first appearance of each one does not stall a frame.
    for step in OnboardingWindowController.Step.allCases.reversed() {
        state.step = step
        pump(0.5)
        if let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) { frameView.cacheDisplay(in: frameView.bounds, to: rep) }
    }
    pump(0.5)

    // The guide plays in real time, so frames are taken as fast as they come and stamped.
    let frames = FrameWriter(dir.appendingPathComponent("onboard"))
    let schedule: [(Double, () -> Void)] = [
        (plan.permission, { state.step = .permission }),
        (plan.granted, { OnboardingState.assumeScreenRecording = true }),
        (plan.shortcuts, { state.step = .shortcuts }),
        (plan.mouse, { state.step = .mouse }),
        (plan.ready, { state.step = .ready }),
    ]
    var next = 0
    let began = Date()
    var lastShot = -1.0
    while true {
        let t = Date().timeIntervalSince(began)
        if t > plan.end { break }
        while next < schedule.count, t >= schedule[next].0 {
            schedule[next].1()
            next += 1
        }
        pump(1 / 500)
        if t - lastShot < 1 / fps { continue }
        lastShot = t
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let image = rep.cgImage { frames.add(image, ["t": t, "step": state.step.rawValue]) }
    }
    frames.finish()
}

import AppKit

/// Full-screen selection UI over a frozen still of each display. Because the screen is frozen,
/// menus and hover states survive, and the crop is exactly the pixels you were looking at.
@MainActor
final class SelectionOverlay {
    enum Mode { case area, window }

    enum Outcome {
        /// `rect` is in the shot's screen-local, bottom-left point coordinates.
        case area(rect: CGRect, shot: DisplayShot)
        case window(WindowInfo, shot: DisplayShot)
        case cancelled
    }

    private(set) var mode: Mode
    private var panels: [NSPanel] = []
    private var views: [OverlayView] = []
    var completion: ((Outcome) -> Void)?

    init(mode: Mode) { self.mode = mode }

    func present(shots: [DisplayShot], windows: [WindowInfo], completion: @escaping (Outcome) -> Void) {
        self.completion = completion
        let showHint = Settings.shared.consumeOverlayHint()

        for shot in shots {
            let frame = shot.screen.frame
            let panel = OverlayPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = true
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.acceptsMouseMovedEvents = true

            let local = windows.map {
                WindowInfo(id: $0.id, frame: $0.frame.offsetBy(dx: -frame.minX, dy: -frame.minY), ownerName: $0.ownerName)
            }
            let visible = shot.screen.visibleFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
            let view = OverlayView(overlay: self, shot: shot, windows: local, visibleFrame: visible, showHint: showHint)
            panel.contentView = view
            panel.setFrame(frame, display: true)
            panels.append(panel)
            views.append(view)
        }

        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        for (panel, view) in zip(panels, views) {
            panel.orderFrontRegardless()
            if NSMouseInRect(mouse, panel.frame, false) {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
                view.pointerMoved(to: view.convert(panel.convertPoint(fromScreen: mouse), from: nil))
            }
        }
    }

    func toggleMode() {
        mode = mode == .area ? .window : .area
        views.forEach { $0.modeDidChange() }
    }

    func finish(_ outcome: Outcome) {
        guard let completion else { return }
        self.completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        completion(outcome)
    }

    func cancel() { finish(.cancelled) }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    private static let snapDistance: CGFloat = 7
    private static let loupeSize: CGFloat = 116
    private static let loupeZoom: CGFloat = 6

    private unowned let overlay: SelectionOverlay
    private let shot: DisplayShot
    private let windows: [WindowInfo]
    private let visibleFrame: CGRect

    private let dim = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let horizontalGuide = CALayer()
    private let verticalGuide = CALayer()
    private let loupe = CALayer()
    private let loupeClip = CALayer()
    private let loupeImage = CALayer()
    private let reticle = CAShapeLayer()
    private let badge = CALayer()
    private let badgeText = CATextLayer()
    private let hint = CALayer()
    /// Rides beside the pointer while picking a window: what to do next.
    private let pointerTag = CALayer()
    private let pointerTagText = CATextLayer()

    private var anchor: CGPoint?
    private var selection: CGRect?
    private(set) var pointer = CGPoint.zero
    private var hovered: WindowInfo?
    private var isMovingSelection = false

    init(overlay: SelectionOverlay, shot: DisplayShot, windows: [WindowInfo], visibleFrame: CGRect, showHint: Bool) {
        self.overlay = overlay
        self.shot = shot
        self.windows = windows
        self.visibleFrame = visibleFrame
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))

        let root = CALayer()
        root.contents = shot.image
        root.contentsGravity = .resize
        layer = root
        wantsLayer = true
        buildLayers(in: root, showHint: showHint)

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: currentCursor) }

    /// A pointing hand over windows, since a window is picked with a click, and a crosshair for areas.
    private var currentCursor: NSCursor { overlay.mode == .window ? .pointingHand : .crosshair }

    // MARK: Layers

    private func buildLayers(in root: CALayer, showHint: Bool) {
        let scale = shot.scale
        let accent = Palette.accent.cgColor

        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.3).cgColor
        dim.frame = bounds
        root.addSublayer(dim)

        outline.fillColor = nil
        outline.lineWidth = 1
        outline.shadowColor = NSColor.black.cgColor
        outline.shadowOpacity = 0.5
        outline.shadowRadius = 1.5
        outline.shadowOffset = .zero
        outline.frame = bounds
        root.addSublayer(outline)

        for guide in [horizontalGuide, verticalGuide] {
            guide.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            root.addSublayer(guide)
        }

        let size = Self.loupeSize
        loupe.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        loupe.cornerRadius = size / 2
        loupe.shadowColor = NSColor.black.cgColor
        loupe.shadowOpacity = 0.35
        loupe.shadowRadius = 10
        loupe.shadowOffset = CGSize(width: 0, height: -4)
        loupeClip.frame = loupe.bounds
        loupeClip.cornerRadius = size / 2
        loupeClip.masksToBounds = true
        loupeClip.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
        loupeClip.borderWidth = 1.5
        loupeClip.backgroundColor = NSColor.black.cgColor
        // The loupe is a second view onto the same still, scaled about the pointer.
        loupeImage.contents = shot.image
        loupeImage.contentsGravity = .resize
        loupeImage.magnificationFilter = .nearest
        loupeImage.bounds = bounds
        loupeImage.position = CGPoint(x: size / 2, y: size / 2)
        loupeImage.transform = CATransform3DMakeScale(Self.loupeZoom, Self.loupeZoom, 1)
        loupeClip.addSublayer(loupeImage)
        let cell = Self.loupeZoom
        reticle.path = CGPath(
            rect: CGRect(x: size / 2 - cell / 2, y: size / 2 - cell / 2, width: cell, height: cell), transform: nil
        )
        reticle.fillColor = nil
        reticle.strokeColor = accent
        reticle.lineWidth = 1
        loupeClip.addSublayer(reticle)
        loupe.addSublayer(loupeClip)
        root.addSublayer(loupe)

        badge.backgroundColor = NSColor(hex: 0x191917, alpha: 0.82).cgColor
        badge.cornerRadius = 6
        badge.cornerCurve = .continuous
        badgeText.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badgeText.fontSize = 11
        badgeText.foregroundColor = NSColor.white.cgColor
        badgeText.alignmentMode = .center
        badgeText.contentsScale = scale
        badge.addSublayer(badgeText)
        badge.isHidden = true
        root.addSublayer(badge)

        pointerTag.backgroundColor = NSColor(hex: 0x191917, alpha: 0.86).cgColor
        pointerTag.cornerRadius = 8
        pointerTag.cornerCurve = .continuous
        pointerTag.borderWidth = 1
        pointerTag.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        pointerTagText.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        pointerTagText.fontSize = 12
        pointerTagText.foregroundColor = NSColor.white.cgColor
        pointerTagText.alignmentMode = .center
        pointerTagText.contentsScale = scale
        pointerTag.addSublayer(pointerTagText)
        pointerTag.isHidden = true
        root.addSublayer(pointerTag)

        if showHint {
            let text = CATextLayer()
            let string = L("Drag to capture an area. Space picks a window. Esc cancels.")
            let font = NSFont.systemFont(ofSize: 13, weight: .medium)
            let width = ceil((string as NSString).size(withAttributes: [.font: font]).width)
            text.string = string
            text.font = font
            text.fontSize = 13
            text.foregroundColor = NSColor.white.cgColor
            text.alignmentMode = .center
            text.contentsScale = scale
            text.frame = CGRect(x: 16, y: 8, width: width, height: 18)
            hint.backgroundColor = NSColor(hex: 0x191917, alpha: 0.82).cgColor
            hint.cornerRadius = 17
            hint.frame = CGRect(x: (bounds.width - width - 32) / 2, y: visibleFrame.minY + 32, width: width + 32, height: 34)
            hint.addSublayer(text)
            root.addSublayer(hint)
        }

        setPointerChromeHidden(true)
        refresh()
    }

    private func setPointerChromeHidden(_ hidden: Bool) {
        withoutAnimation {
            loupe.isHidden = hidden || overlay.mode == .window || !Settings.shared.showsMagnifier
            horizontalGuide.isHidden = hidden || overlay.mode == .window || anchor != nil
            verticalGuide.isHidden = horizontalGuide.isHidden
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// Redraws the dim, outline, and size badge for the current selection or hovered window.
    private func refresh() {
        withoutAnimation {
            let path = CGMutablePath()
            path.addRect(bounds)
            var cutout: CGRect?
            var radius: CGFloat = 0

            if overlay.mode == .window, let hovered {
                cutout = hovered.frame.intersection(bounds)
                radius = 12
                // A bright ring that hugs the window with a soft glow, over a faint wash, so the
                // window reads as lifted rather than boxed.
                outline.strokeColor = NSColor.white.cgColor
                outline.lineWidth = 3
                outline.fillColor = Palette.accent.cgColor.copy(alpha: 0.08)
                outline.shadowColor = NSColor.white.cgColor
                outline.shadowOpacity = 0.55
                outline.shadowRadius = 8
                outline.shadowOffset = .zero
            } else if overlay.mode == .area, let selection, selection.width > 0, selection.height > 0 {
                cutout = selection
                outline.strokeColor = NSColor.white.cgColor
                outline.lineWidth = 1
                outline.fillColor = nil
                outline.shadowOpacity = 0
            }

            if let cutout, !cutout.isNull {
                let shape = CGPath(roundedRect: cutout, cornerWidth: radius, cornerHeight: radius, transform: nil)
                path.addPath(shape)
                outline.path = shape
                showBadge(for: cutout, name: overlay.mode == .window ? hovered?.ownerName : nil)
            } else {
                outline.path = nil
                badge.isHidden = true
            }
            dim.path = path
            updatePointerTag()
        }
    }

    private func updatePointerTag() {
        guard overlay.mode == .window, bounds.contains(pointer) else {
            pointerTag.isHidden = true
            return
        }
        let string = hovered == nil ? L("Move to a window") : L("Click to capture")
        if pointerTagText.string as? String != string {
            let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let width = ceil((string as NSString).size(withAttributes: [.font: font]).width) + 20
            pointerTag.bounds = CGRect(x: 0, y: 0, width: width, height: 26)
            pointerTagText.frame = CGRect(x: 0, y: 5, width: width, height: 16)
            pointerTagText.string = string
        }
        // Below and right of the hand, clear of the fingertip, kept on screen.
        let size = pointerTag.bounds.size
        var origin = CGPoint(x: pointer.x + 10, y: pointer.y - 30 - size.height)
        if origin.x + size.width > bounds.width - 4 { origin.x = pointer.x - 10 - size.width }
        if origin.y < 4 { origin.y = pointer.y + 24 }
        pointerTag.frame = CGRect(origin: origin, size: size)
        pointerTag.isHidden = false
    }

    private func showBadge(for rect: CGRect, name: String? = nil) {
        let dimensions = "\(Int(rect.width)) × \(Int(rect.height))"
        let string = name.map { "\($0)  \(dimensions)" } ?? dimensions
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let textWidth = ceil((string as NSString).size(withAttributes: [.font: font]).width)
        let size = CGSize(width: textWidth + 14, height: 22)
        var origin = CGPoint(x: rect.maxX - size.width, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.minY + 8; origin.x -= 8 }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        badge.frame = CGRect(origin: origin, size: size)
        badgeText.string = string
        badgeText.frame = CGRect(x: 0, y: 3.5, width: size.width, height: 15)
        badge.isHidden = false
    }

    // MARK: Snapping

    /// Pulls the point onto nearby window and screen edges. An edge only counts where it is
    /// actually visible, so windows hidden behind others do not create phantom snaps.
    private func snapped(_ p: CGPoint, enabled: Bool) -> (point: CGPoint, x: Bool, y: Bool) {
        var result = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        guard enabled, Settings.shared.snapsToEdges else { return (result.clamped(to: bounds), false, false) }
        let reach = Self.snapDistance
        var bestX = reach, bestY = reach
        var hitX = false, hitY = false

        func isFrontmost(at probe: CGPoint, index: Int) -> Bool {
            !windows[..<index].contains { $0.frame.contains(probe) }
        }

        for (index, window) in windows.enumerated() {
            let frame = window.frame
            if p.y >= frame.minY - reach, p.y <= frame.maxY + reach {
                let probeY = min(max(p.y, frame.minY + 1), frame.maxY - 1)
                for (edge, inward) in [(frame.minX, 1.0), (frame.maxX, -1.0)] where abs(edge - p.x) < bestX {
                    if isFrontmost(at: CGPoint(x: edge + inward, y: probeY), index: index) {
                        bestX = abs(edge - p.x)
                        result.x = edge
                        hitX = true
                    }
                }
            }
            if p.x >= frame.minX - reach, p.x <= frame.maxX + reach {
                let probeX = min(max(p.x, frame.minX + 1), frame.maxX - 1)
                for (edge, inward) in [(frame.minY, 1.0), (frame.maxY, -1.0)] where abs(edge - p.y) < bestY {
                    if isFrontmost(at: CGPoint(x: probeX, y: edge + inward), index: index) {
                        bestY = abs(edge - p.y)
                        result.y = edge
                        hitY = true
                    }
                }
            }
        }

        for edge in [bounds.minX, bounds.maxX, visibleFrame.minX, visibleFrame.maxX] where abs(edge - p.x) < bestX {
            bestX = abs(edge - p.x)
            result.x = edge
            hitX = true
        }
        for edge in [bounds.minY, bounds.maxY, visibleFrame.minY, visibleFrame.maxY] where abs(edge - p.y) < bestY {
            bestY = abs(edge - p.y)
            result.y = edge
            hitY = true
        }
        return (result.clamped(to: bounds), hitX, hitY)
    }

    // MARK: Pointer

    func modeDidChange() {
        anchor = nil
        selection = nil
        hovered = nil
        window?.invalidateCursorRects(for: self)
        currentCursor.set()
        pointerMoved(to: pointer)
    }

    func pointerMoved(to raw: CGPoint, snapping: Bool = true) {
        if overlay.mode == .window {
            pointer = raw
            hovered = windows.first { $0.frame.contains(raw) }
            setPointerChromeHidden(true)
            refresh()
            return
        }

        let snap = snapped(raw, enabled: snapping)
        pointer = snap.point
        setPointerChromeHidden(false)
        withoutAnimation {
            let accent = Palette.accent.cgColor
            let plain = NSColor.white.withAlphaComponent(0.7).cgColor
            verticalGuide.frame = CGRect(x: pointer.x - 0.5, y: 0, width: 1, height: bounds.height)
            verticalGuide.backgroundColor = snap.x ? accent : plain
            horizontalGuide.frame = CGRect(x: 0, y: pointer.y - 0.5, width: bounds.width, height: 1)
            horizontalGuide.backgroundColor = snap.y ? accent : plain

            let size = Self.loupeSize
            let gap: CGFloat = 22
            var center = CGPoint(x: pointer.x + gap + size / 2, y: pointer.y - gap - size / 2)
            if center.x + size / 2 > bounds.maxX - 8 { center.x = pointer.x - gap - size / 2 }
            if center.y - size / 2 < bounds.minY + 8 { center.y = pointer.y + gap + size / 2 }
            loupe.position = center
            loupeImage.anchorPoint = CGPoint(x: pointer.x / bounds.width, y: pointer.y / bounds.height)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if window?.isKeyWindow == false {
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
        }
        pointerMoved(to: convert(event.locationInWindow, from: nil), snapping: !event.modifierFlags.contains(.command))
    }

    override func mouseExited(with event: NSEvent) {
        guard anchor == nil else { return }
        hovered = nil
        setPointerChromeHidden(true)
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        guard overlay.mode == .area else { return }
        pointerMoved(to: convert(event.locationInWindow, from: nil), snapping: !event.modifierFlags.contains(.command))
        anchor = pointer
        selection = CGRect(origin: pointer, size: .zero)
        withoutAnimation { hint.opacity = 0 }
        setPointerChromeHidden(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard overlay.mode == .area, let start = anchor else { return }
        let previous = pointer
        pointerMoved(to: convert(event.locationInWindow, from: nil), snapping: !event.modifierFlags.contains(.command))

        if isMovingSelection, let current = selection {
            // Space held: slide the whole selection, as the system screenshot tool does.
            var moved = current
            moved.origin.x = min(max(current.minX + pointer.x - previous.x, 0), bounds.width - current.width)
            moved.origin.y = min(max(current.minY + pointer.y - previous.y, 0), bounds.height - current.height)
            anchor = CGPoint(x: start.x + moved.minX - current.minX, y: start.y + moved.minY - current.minY)
            selection = moved
        } else {
            var end = pointer
            if event.modifierFlags.contains(.shift) {
                let side = max(abs(end.x - start.x), abs(end.y - start.y))
                end = CGPoint(
                    x: start.x + (end.x < start.x ? -side : side), y: start.y + (end.y < start.y ? -side : side)
                ).clamped(to: bounds)
            }
            selection = CGRect(from: start, to: end)
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        if overlay.mode == .window {
            if let hovered { overlay.finish(.window(hovered, shot: shot)) }
            return
        }
        defer { anchor = nil; isMovingSelection = false }
        guard let rect = selection?.integral.intersection(bounds), rect.width >= 4, rect.height >= 4 else {
            selection = nil
            refresh()
            setPointerChromeHidden(false)
            return
        }
        overlay.finish(.area(rect: rect, shot: shot))
    }

    override func rightMouseDown(with event: NSEvent) { overlay.cancel() }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            overlay.cancel()
        case 49:
            guard !event.isARepeat else { return }
            if anchor != nil {
                isMovingSelection = true
            } else {
                overlay.toggleMode()
            }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isMovingSelection = false }
    }
}


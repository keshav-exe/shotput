import AppKit

/// Screenshots floated above every window: where they were taken, at their real size, until closed.
/// Move one by dragging it (it snaps to the screen's edges and to other floats, so two can sit side
/// by side), resize from any edge or by scrolling, and ⌥-scroll to fade it. Double-click to annotate,
/// ⌥-drag to drop it into another app as a file, right-click for the rest.
@MainActor
final class FloatingShots {
    static let shared = FloatingShots()

    private(set) var panels: [FloatPanel] = []

    var isEmpty: Bool { panels.isEmpty }

    func float(_ capture: Capture) {
        if let existing = panels.first(where: { $0.capture === capture }) {
            existing.orderFrontRegardless()
            return
        }
        let panel = FloatPanel(capture: capture, frame: Self.frame(for: capture))
        panel.onClose = { [weak self] closed in self?.panels.removeAll { $0 === closed } }
        panels.append(panel)
        panel.present()
    }

    func closeAll() {
        panels.forEach { $0.dismiss() }
    }

    /// Exactly where it was taken when that's known and on screen, else centred under the pointer.
    /// Never larger than most of the screen, so a full-screen capture still leaves room to work.
    private static func frame(for capture: Capture) -> CGRect {
        let screen = capture.screen ?? NSScreen.underMouse ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var size = capture.pointSize
        let limit = CGSize(width: visible.width * 0.7, height: visible.height * 0.7)
        let fit = min(1, limit.width / size.width, limit.height / size.height)
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        if fit == 1, let origin = capture.screenRect, visible.contains(origin.insetBy(dx: 1, dy: 1)) {
            return CGRect(origin: origin.origin, size: size)
        }
        let center = fit == 1 ? (capture.screenRect?.center ?? visible.center) : visible.center
        var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame.integral
    }

    /// Pulls a moving frame onto a nearby edge: the screen's, or another float's, so floats line
    /// up side by side or stack, flush or with tops and bottoms aligned.
    static func snap(_ frame: CGRect, to others: [CGRect], within screen: CGRect?, reach: CGFloat = 10) -> CGRect {
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        if let screen { xs += [screen.minX, screen.maxX]; ys += [screen.minY, screen.maxY] }
        for other in others {
            // Only frames near enough on the other axis to count as neighbours.
            if other.maxY + reach > frame.minY && other.minY - reach < frame.maxY { xs += [other.minX, other.maxX] }
            if other.maxX + reach > frame.minX && other.minX - reach < frame.maxX { ys += [other.minY, other.maxY] }
        }
        func nearest(_ edges: [CGFloat], _ targets: [CGFloat]) -> CGFloat? {
            var best: CGFloat?
            for edge in edges {
                for target in targets where abs(target - edge) <= reach {
                    let shift = target - edge
                    if best.map({ abs(shift) < abs($0) }) ?? true { best = shift }
                }
            }
            return best
        }
        var result = frame
        if let dx = nearest([frame.minX, frame.maxX], xs) { result.origin.x += dx }
        if let dy = nearest([frame.minY, frame.maxY], ys) { result.origin.y += dy }
        return result
    }

    /// Frames a moving float may snap to: the other floats.
    fileprivate func snapTargets(excluding panel: FloatPanel) -> [CGRect] {
        panels.filter { $0 !== panel && $0.isVisible }.map(\.frame)
    }
}

/// One floating screenshot's window. It takes keys when clicked, without bringing Shotput forward.
final class FloatPanel: NSPanel {
    let capture: Capture
    var onClose: ((FloatPanel) -> Void)?
    fileprivate var isLocked = false

    init(capture: Capture, frame: CGRect) {
        self.capture = capture
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        contentAspectRatio = capture.pointSize
        contentView = FloatView(capture: capture, panel: self)
        setAccessibilityLabel(L("Floating screenshot"))
    }

    override var canBecomeKey: Bool { true }

    func present() {
        let final = frame
        alphaValue = 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion { setFrame(final.insetBy(dx: final.width * 0.02, dy: final.height * 0.02), display: true) }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            animator().alphaValue = 1
            animator().setFrame(final, display: true)
        }
    }

    func dismiss() {
        onClose?(self)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    /// Pixels shown per pixel captured, for the size badge: 100% is the screenshot's real size.
    var zoom: CGFloat { frame.width / max(capture.pointSize.width, 1) }

    /// Resizes about a point in the window, keeping that point under the pointer.
    func resize(by factor: CGFloat, about anchor: CGPoint) {
        guard !isLocked else { return }
        let size = capture.pointSize
        let minWidth = max(80, 80 * size.width / max(size.height, 1))
        let maxWidth = size.width * 4
        let width = min(max(frame.width * factor, minWidth), maxWidth)
        let height = width * size.height / size.width
        let fx = (anchor.x - frame.minX) / frame.width
        let fy = (anchor.y - frame.minY) / frame.height
        setFrame(CGRect(x: anchor.x - width * fx, y: anchor.y - height * fy, width: width, height: height).integral, display: true)
    }

    func setActualSize() {
        guard !isLocked else { return }
        resize(by: 1 / zoom, about: frame.center)
    }
}

// MARK: - The view

private final class FloatView: NSView, NSDraggingSource, NSMenuItemValidation {
    private let capture: Capture
    private weak var panel: FloatPanel?

    private let hud = NSStackView()
    private let closeButton: NSButton
    private let badge = NSTextField(labelWithString: "")
    private let badgeBox = NSVisualEffectView()
    private var badgeTimer: Timer?

    private enum Gesture {
        case move(startMouse: CGPoint, startFrame: CGRect)
        case resize(edges: Edges, startMouse: CGPoint, startFrame: CGRect)
        case fileDrag
    }
    private var gesture: Gesture?
    private var mouseDownEvent: NSEvent?

    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4)
        static let top = Edges(rawValue: 8)
    }

    private static let grip: CGFloat = 8
    private static let radius: CGFloat = 8

    init(capture: Capture, panel: FloatPanel) {
        self.capture = capture
        self.panel = panel
        closeButton = NSButton.glassCircle(.close, label: L("Close"), target: nil, action: #selector(NSWindow.performClose(_:)))
        super.init(frame: CGRect(origin: .zero, size: panel.frame.size))
        autoresizingMask = [.width, .height]
        wantsLayer = true
        guard let layer else { return }
        layer.contents = capture.image
        layer.contentsGravity = .resize
        layer.cornerRadius = Self.radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer.magnificationFilter = .trilinear
        layer.minificationFilter = .trilinear

        closeButton.target = self
        closeButton.action = #selector(closeFloat)
        closeButton.controlSize = .small
        closeButton.alphaValue = 0
        addSubview(closeButton)

        hud.orientation = .horizontal
        hud.spacing = 6
        hud.alphaValue = 0
        hud.translatesAutoresizingMaskIntoConstraints = false
        for (icon, label, action) in [
            (Icon.copy, L("Copy"), #selector(copy(_:))),
            (Icon.save, L("Save"), #selector(saveDocument(_:))),
            (Icon.annotate, L("Annotate"), #selector(annotate(_:))),
        ] {
            let button = NSButton.glassCircle(icon, label: label, target: self, action: action)
            button.controlSize = .small
            hud.addArrangedSubview(button)
        }
        addSubview(hud)

        badgeBox.material = .hudWindow
        badgeBox.blendingMode = .withinWindow
        badgeBox.state = .active
        badgeBox.wantsLayer = true
        badgeBox.layer?.cornerRadius = 10
        badgeBox.alphaValue = 0
        badgeBox.translatesAutoresizingMaskIntoConstraints = false
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .labelColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeBox.addSubview(badge)
        addSubview(badgeBox)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            hud.centerXAnchor.constraint(equalTo: centerXAnchor),
            hud.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            badgeBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            badgeBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: badgeBox.leadingAnchor, constant: 9),
            badge.trailingAnchor.constraint(equalTo: badgeBox.trailingAnchor, constant: -9),
            badge.topAnchor.constraint(equalTo: badgeBox.topAnchor, constant: 3),
            badge.bottomAnchor.constraint(equalTo: badgeBox.bottomAnchor, constant: -3),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self
        ))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L("Floating screenshot. Double-click to annotate."))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Hover

    /// Small floats keep their controls out of the way: only the close button, and the menu.
    private var showsHUD: Bool { bounds.width >= 150 && bounds.height >= 90 }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        NSCursor.arrow.set()
    }

    private func setHovered(_ hovered: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hovered ? 0.15 : 0.22
            closeButton.animator().alphaValue = hovered ? 1 : 0
            hud.animator().alphaValue = hovered && showsHUD ? 1 : 0
        }
    }

    // MARK: Pointer

    private func edges(at point: CGPoint) -> Edges {
        guard panel?.isLocked == false else { return [] }
        var edges: Edges = []
        if point.x < Self.grip { edges.insert(.left) }
        if point.x > bounds.width - Self.grip { edges.insert(.right) }
        if point.y < Self.grip { edges.insert(.bottom) }
        if point.y > bounds.height - Self.grip { edges.insert(.top) }
        return edges
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let edges = edges(at: convert(event.locationInWindow, from: nil))
        if edges.isEmpty { NSCursor.arrow.set(); return }
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        if horizontal && vertical {
            let rising = edges == [.right, .top] || edges == [.left, .bottom]
            (rising ? NSCursor.frameResize(position: .topRight, directions: .all) : NSCursor.frameResize(position: .topLeft, directions: .all)).set()
        } else if horizontal {
            NSCursor.columnResize.set()
        } else {
            NSCursor.rowResize.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel else { return }
        panel.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            gesture = nil
            annotate(nil)
            return
        }
        mouseDownEvent = event
        let mouse = NSEvent.mouseLocation
        let edges = edges(at: convert(event.locationInWindow, from: nil))
        if !edges.isEmpty {
            gesture = .resize(edges: edges, startMouse: mouse, startFrame: panel.frame)
        } else if event.modifierFlags.contains(.option) {
            gesture = .fileDrag
        } else if !panel.isLocked {
            gesture = .move(startMouse: mouse, startFrame: panel.frame)
        } else {
            gesture = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel, let gesture else { return }
        let mouse = NSEvent.mouseLocation
        switch gesture {
        case let .move(start, frame):
            var moved = frame.offsetBy(dx: mouse.x - start.x, dy: mouse.y - start.y)
            // ⌘ while dragging turns snapping off, for a free placement.
            if !event.modifierFlags.contains(.command) { moved = snapped(moved, for: panel) }
            panel.setFrameOrigin(moved.origin)
        case let .resize(edges, start, frame):
            panel.setFrame(resized(frame, edges: edges, by: CGPoint(x: mouse.x - start.x, y: mouse.y - start.y)), display: true)
            showBadge(String(format: "%d%%", Int((panel.zoom * 100).rounded())))
        case .fileDrag:
            self.gesture = nil
            beginFileDrag(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        gesture = nil
        mouseDownEvent = nil
    }

    /// Keeps the aspect ratio, growing from the dragged edge with the opposite one fixed.
    private func resized(_ frame: CGRect, edges: Edges, by delta: CGPoint) -> CGRect {
        let aspect = capture.pointSize.width / max(capture.pointSize.height, 1)
        var dw: CGFloat = 0
        if edges.contains(.right) { dw = delta.x } else if edges.contains(.left) { dw = -delta.x }
        var dh: CGFloat = 0
        if edges.contains(.top) { dh = delta.y } else if edges.contains(.bottom) { dh = -delta.y }
        // Whichever edge moved further leads; the other follows the ratio.
        let width: CGFloat
        if abs(dw) >= abs(dh * aspect) { width = frame.width + dw } else { width = frame.width + dh * aspect }
        let minWidth = max(80, 80 * aspect)
        let w = min(max(width, minWidth), capture.pointSize.width * 4)
        let h = w / aspect
        let x = edges.contains(.left) ? frame.maxX - w : (edges.contains(.right) ? frame.minX : frame.midX - w / 2)
        let y = edges.contains(.bottom) ? frame.maxY - h : (edges.contains(.top) ? frame.minY : frame.midY - h / 2)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    private func snapped(_ frame: CGRect, for panel: FloatPanel) -> CGRect {
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panel.screen)?.visibleFrame
        return FloatingShots.snap(frame, to: FloatingShots.shared.snapTargets(excluding: panel), within: screen)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let panel else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            panel.alphaValue = min(1, max(0.15, panel.alphaValue + delta / 300))
            showBadge(String(format: L("Opacity %d%%"), Int((panel.alphaValue * 100).rounded())))
        } else {
            panel.resize(by: 1 + delta / 400, about: NSEvent.mouseLocation)
            showBadge(String(format: "%d%%", Int((panel.zoom * 100).rounded())))
        }
    }

    override func magnify(with event: NSEvent) {
        panel?.resize(by: 1 + event.magnification, about: NSEvent.mouseLocation)
        if let panel { showBadge(String(format: "%d%%", Int((panel.zoom * 100).rounded()))) }
    }

    private func showBadge(_ text: String) {
        badge.stringValue = text
        badgeBox.alphaValue = 1
        badgeTimer?.invalidate()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    self?.badgeBox.animator().alphaValue = 0
                }
            }
        }
    }

    // MARK: Dragging out

    private func beginFileDrag(_ event: NSEvent) {
        guard let url = capture.temporaryFile() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = NSImage(cgImage: capture.image, size: capture.pointSize)
        let size = bounds.size.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
        let point = convert((mouseDownEvent ?? event).locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [item], event: mouseDownEvent ?? event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: closeFloat() // Esc
        case 36, 76: annotate(nil) // Return
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "c": copy(nil)
        case "s": saveDocument(nil)
        case "w": closeFloat()
        case "e": annotate(nil)
        case "=", "+": panel?.resize(by: 1.25, about: panel?.frame.center ?? .zero)
        case "-": panel?.resize(by: 0.8, about: panel?.frame.center ?? .zero)
        case "0": panel?.setActualSize()
        default: return super.performKeyEquivalent(with: event)
        }
        if let panel { showBadge(String(format: "%d%%", Int((panel.zoom * 100).rounded()))) }
        return true
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "", tag: Int = 0) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            item.tag = tag
            return item
        }
        _ = add(L("Copy"), #selector(copy(_:)), "c")
        _ = add(L("Save…"), #selector(saveDocument(_:)), "s")
        _ = add(L("Annotate"), #selector(annotate(_:)), "e")
        menu.addItem(.separator())
        _ = add(L("Actual Size"), #selector(actualSize(_:)), "0")
        let opacity = NSMenuItem(title: L("Opacity"), action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for percent in [100, 75, 50, 25] {
            let item = levels.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.state = Int(((panel?.alphaValue ?? 1) * 100).rounded()) == percent ? .on : .off
        }
        opacity.submenu = levels
        menu.addItem(opacity)
        let lock = add(L("Lock Position and Size"), #selector(toggleLock(_:)))
        lock.state = panel?.isLocked == true ? .on : .off
        let shadow = add(L("Shadow"), #selector(toggleShadow(_:)))
        shadow.state = panel?.hasShadow == true ? .on : .off
        menu.addItem(.separator())
        _ = add(L("Close"), #selector(closeFloat), "w")
        if FloatingShots.shared.panels.count > 1 {
            _ = add(L("Close All Floating Screenshots"), #selector(closeAll))
        }
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(actualSize(_:)) { return panel?.isLocked == false }
        return true
    }

    @objc func copy(_ sender: Any?) {
        guard let png = capture.png() else { return }
        Output.copyToClipboard(png.data)
        showBadge(L("Copied"))
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let file = capture.fileData() else { return }
        Output.save(file, relativeTo: nil) { [weak self] url in
            if url != nil { self?.showBadge(L("Saved")) }
        }
    }

    /// The editor takes over the screenshot; the float steps aside for it.
    @objc func annotate(_ sender: Any?) {
        EditorManager.shared.open(capture)
        panel?.dismiss()
    }

    @objc private func actualSize(_ sender: Any?) {
        panel?.setActualSize()
        showBadge("100%")
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        panel?.alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func toggleLock(_ sender: Any?) {
        guard let panel else { return }
        panel.isLocked.toggle()
        showBadge(panel.isLocked ? L("Locked") : L("Unlocked"))
    }

    @objc private func toggleShadow(_ sender: Any?) {
        panel?.hasShadow.toggle()
        panel?.invalidateShadow()
    }

    @objc private func closeFloat() { panel?.dismiss() }
    @objc private func closeAll() { FloatingShots.shared.closeAll() }

    override func layout() {
        super.layout()
        if hud.alphaValue > 0 && !showsHUD { hud.alphaValue = 0 }
    }
}

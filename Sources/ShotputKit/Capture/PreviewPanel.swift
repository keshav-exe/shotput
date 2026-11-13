import AppKit

/// The floating thumbnail shown after a capture. Click to annotate, drag it into another app as a
/// file, or leave it and it goes away. It never takes focus, so pasting is not interrupted.
@MainActor
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private var panel: NSPanel?
    private var dismissal: Timer?

    func show(_ capture: Capture) {
        dismiss(animated: false)

        let size = Self.thumbnailSize(for: capture.pointSize)
        // The panel is larger than the thumbnail by a transparent margin that holds its shadow.
        let frame = Self.frame(for: size, capture: capture).insetBy(dx: -Self.margin, dy: -Self.margin)
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system window shadow adds a light rim in dark mode; the thumbnail draws its own.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let view = PreviewView(capture: capture, size: size)
        view.onHover = { [weak self] inside in inside ? self?.dismissal?.invalidate() : self?.scheduleDismissal() }
        view.onAnnotate = { [weak self] in
            self?.dismiss()
            EditorManager.shared.open(capture)
        }
        view.onCopy = { [weak self] in
            if let png = capture.png() { Output.copyToClipboard(png.data) }
            // Long enough to see the check land, short enough not to linger.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.dismiss() }
        }
        view.onPin = { [weak self] in
            guard PinStore.shared.pin(capture) else { return }
            self?.flyToMenuBar()
        }
        view.onDragStart = { [weak self] in
            self?.dismissal?.invalidate()
            PinShelf.shared.show(for: capture)
        }
        view.onDragEnd = { PinShelf.shared.hide() }
        view.onSave = { [weak self] in
            self?.dismiss()
            guard let file = capture.fileData() else { return }
            Output.save(file, relativeTo: nil) { _ in }
        }
        view.onClose = { [weak self] in self?.dismiss() }
        let host = ShadowHost(frame: CGRect(origin: .zero, size: frame.size))
        view.frame = host.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        panel.contentView = host
        self.panel = panel

        // The thumbnail leaves from where the capture was taken and settles in its corner, so
        // it is clear where the screenshot went. Without a known origin it slides in from the edge.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fromLeft = frame.midX < (capture.screen ?? NSScreen.underMouse)?.frame.midX ?? 0
        var start = frame.offsetBy(dx: fromLeft ? -16 : 16, dy: 0)
        if let origin = capture.screenRect, !origin.intersects(frame) {
            start = CGRect(x: origin.midX - frame.width / 2, y: origin.midY - frame.height / 2, width: frame.width, height: frame.height)
        }
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : start, display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = start.center.distance(to: frame.center) > 120 ? 0.42 : 0.25
            // Quick out of the gate, gentle landing.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        })
        scheduleDismissal()
    }

    /// Shrinks the thumbnail into the menu bar icon, so a pin visibly goes where it is kept.
    private func flyToMenuBar() {
        dismissal?.invalidate()
        guard let panel else { return }
        self.panel = nil
        let target = MenuBarAnchor.target(on: panel.screen)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            NotificationCenter.default.post(name: .shotputDidPin, object: nil)
            return
        }
        let end = CGRect(x: target.midX - 9, y: target.midY - 6, width: 18, height: 12).insetBy(dx: -Self.margin, dy: -Self.margin)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.2)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0.35
        }, completionHandler: {
            panel.orderOut(nil)
            NotificationCenter.default.post(name: .shotputDidPin, object: nil)
        })
    }

    func dismiss(animated: Bool = true) {
        dismissal?.invalidate()
        dismissal = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func scheduleDismissal() {
        dismissal?.invalidate()
        let seconds = Settings.shared.previewDuration
        guard seconds > 0 else { return }
        dismissal = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    // MARK: Placement

    private static let margin: CGFloat = 24

    private static func thumbnailSize(for image: CGSize) -> CGSize {
        let limit = CGSize(width: 232, height: 148)
        let fit = min(limit.width / max(image.width, 1), limit.height / max(image.height, 1), 1)
        return CGSize(width: max(image.width * fit, 140), height: max(image.height * fit, 84))
    }

    /// Picks the corner of the capture's screen that is closest to the pointer without covering
    /// what was just captured, so the preview is one short move away and never in the way.
    private static func frame(for size: CGSize, capture: Capture) -> CGRect {
        let screen = capture.screen ?? NSScreen.underMouse ?? NSScreen.screens[0]
        let area = screen.visibleFrame.insetBy(dx: 20, dy: 20)
        let corners: [Settings.Corner: CGRect] = [
            .bottomLeft: CGRect(x: area.minX, y: area.minY, width: size.width, height: size.height),
            .bottomRight: CGRect(x: area.maxX - size.width, y: area.minY, width: size.width, height: size.height),
            .topLeft: CGRect(x: area.minX, y: area.maxY - size.height, width: size.width, height: size.height),
            .topRight: CGRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height),
        ]
        let preference = Settings.shared.previewCorner
        if let fixed = corners[preference] { return fixed }

        let mouse = NSEvent.mouseLocation
        let byDistance = corners.values.sorted { $0.center.distance(to: mouse) < $1.center.distance(to: mouse) }
        let captured = capture.screenRect ?? .null
        return byDistance.first { !$0.insetBy(dx: -12, dy: -12).intersects(captured) } ?? byDistance[0]
    }
}

/// Draws the thumbnail's shadow, two layers deep, around whatever rounded view it holds.
private final class ShadowHost: NSView {
    private let ambient = CALayer()
    private let contact = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for (shadow, radius, opacity, offset) in [(ambient, 16.0, 0.32, -6.0), (contact, 2.0, 0.22, -1.0)] {
            shadow.shadowColor = NSColor.black.cgColor
            shadow.shadowRadius = radius
            shadow.shadowOpacity = Float(opacity)
            shadow.shadowOffset = CGSize(width: 0, height: offset)
            layer?.addSublayer(shadow)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        guard let thumbnail = subviews.first else { return }
        let path = CGPath(roundedRect: thumbnail.frame, cornerWidth: Metrics.chipRadius, cornerHeight: Metrics.chipRadius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [ambient, contact].forEach { $0.frame = bounds; $0.shadowPath = path }
        CATransaction.commit()
    }
}

private final class PreviewView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var onAnnotate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onPin: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private let capture: Capture
    private var copyButton: NSButton?
    private let closeButton = NSView()
    private let scrim = CALayer()
    private let buttons = NSStackView()
    private var mouseDownLocation: CGPoint?
    private var didDrag = false

    init(capture: Capture, size: CGSize) {
        self.capture = capture
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = Metrics.chipRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = Palette.surfaceMuted.cgColor
        layer.contents = capture.image
        // Small captures sit centred at their real size. Larger ones fill the thumbnail.
        let image = capture.pointSize
        layer.contentsGravity = image.width <= size.width && image.height <= size.height ? .center : .resizeAspectFill
        layer.contentsScale = capture.scale
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor

        scrim.frame = bounds
        scrim.backgroundColor = NSColor(hex: 0x191917, alpha: 0.55).cgColor
        scrim.opacity = 0
        layer.addSublayer(scrim)

        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.alphaValue = 0
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.addArrangedSubview(button(.annotate, L("Annotate"), #selector(annotate)))
        let copy = button(.copy, L("Copy again"), #selector(copyAgain))
        copyButton = copy
        buttons.addArrangedSubview(copy)
        buttons.addArrangedSubview(button(.save, L("Save"), #selector(save)))
        buttons.addArrangedSubview(button(.pin, L("Pin to the menu bar"), #selector(pin)))
        addSubview(buttons)
        // Dismiss sits apart in the corner, as on the system's own screenshot thumbnail.
        let dismiss = button(.close, L("Dismiss"), #selector(close))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.alphaValue = 0
        closeButton.addSubview(dismiss)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismiss.topAnchor.constraint(equalTo: closeButton.topAnchor),
            dismiss.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            dismiss.leadingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            dismiss.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
        setAccessibilityLabel(L("Screenshot preview. Click to annotate."))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func button(_ icon: Icon, _ label: String, _ action: Selector) -> NSButton {
        NSButton.glassCircle(icon, label: label, target: self, action: action)
    }

    @objc private func annotate() { onAnnotate?() }
    @objc private func copyAgain() {
        copyButton?.confirm(restoring: .copy)
        onCopy?()
    }
    @objc private func pin() { onPin?() }
    @objc private func save() { onSave?() }
    @objc private func close() { onClose?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        onHover?(hovered)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            scrim.opacity = hovered ? 1 : 0
            buttons.animator().alphaValue = hovered ? 1 : 0
            closeButton.animator().alphaValue = hovered ? 1 : 0
        }
    }

    // MARK: Click to annotate, drag to export

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let start = mouseDownLocation,
              start.distance(to: event.locationInWindow) > 4,
              let file = capture.temporaryFile() else { return }
        didDrag = true
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: capture.image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
        onDragStart?()
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag, mouseDownLocation != nil { onAnnotate?() }
        mouseDownLocation = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnd?()
        if operation != [] { onClose?() }
    }
}

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
        let frame = Self.frame(for: size, capture: capture)
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
            self?.dismiss()
        }
        view.onSave = { [weak self] in
            self?.dismiss()
            guard let png = capture.png() else { return }
            Output.save(png.data, named: ImageCoding.timestampedName(for: capture.date), relativeTo: nil) { _ in }
        }
        view.onClose = { [weak self] in self?.dismiss() }
        panel.contentView = view
        self.panel = panel

        // Slide in from the nearest screen edge.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fromLeft = frame.midX < (capture.screen ?? NSScreen.underMouse)?.frame.midX ?? 0
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: fromLeft ? -16 : 16, dy: 0), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        scheduleDismissal()
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

    private static func thumbnailSize(for image: CGSize) -> CGSize {
        let limit = CGSize(width: 232, height: 148)
        let fit = min(limit.width / max(image.width, 1), limit.height / max(image.height, 1), 1)
        return CGSize(width: max(image.width * fit, 132), height: max(image.height * fit, 84))
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

private final class PreviewView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var onAnnotate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let capture: Capture
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
        buttons.addArrangedSubview(button("pencil.tip.crop.circle", "Annotate", #selector(annotate)))
        buttons.addArrangedSubview(button("doc.on.doc", "Copy again", #selector(copyAgain)))
        buttons.addArrangedSubview(button("square.and.arrow.down", "Save", #selector(save)))
        buttons.addArrangedSubview(button("xmark", "Dismiss", #selector(close)))
        addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
        setAccessibilityLabel("Screenshot preview. Click to annotate.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func annotate() { onAnnotate?() }
    @objc private func copyAgain() { onCopy?() }
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
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag, mouseDownLocation != nil { onAnnotate?() }
        mouseDownLocation = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onClose?() }
    }
}

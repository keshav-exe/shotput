import AppKit

/// One pinned capture. Click copies, Option-click annotates, dragging drops the file into any
/// app, and the corner button unpins.
@MainActor
final class PinCell: NSView, NSDraggingSource {
    var onDone: (() -> Void)?
    private let pin: PinStore.Pin
    private let ring = CALayer()
    private let remove: NSButton
    private var downAt: CGPoint?
    private var dragged = false

    init(pin: PinStore.Pin, frame: CGRect) {
        self.pin = pin
        remove = NSButton.glassCircle(.close, label: "Unpin", target: nil, action: #selector(unpin))
        remove.controlSize = .small
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = Palette.surfaceMuted.cgColor
        layer.contents = PinStore.shared.thumbnail(for: pin)
        layer.contentsGravity = .resizeAspectFill
        ring.frame = bounds
        ring.cornerRadius = 10
        ring.cornerCurve = .continuous
        ring.borderWidth = 0.5
        ring.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        layer.addSublayer(ring)

        remove.target = self
        remove.isHidden = true
        addSubview(remove)
        NSLayoutConstraint.activate([
            remove.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: pin.date, relativeTo: Date())
        toolTip = [pin.appName, when].compactMap { $0 }.joined(separator: ", ") + "\nClick to copy, Option-click to annotate, or drag"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Pinned screenshot, \(when)")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        remove.isHidden = !hovered
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        ring.borderWidth = hovered ? 2 : 0.5
        ring.borderColor = hovered ? Palette.accent.cgColor : NSColor.labelColor.withAlphaComponent(0.12).cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
        dragged = false
        layer?.opacity = 0.8
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let downAt, downAt.distance(to: event.locationInWindow) > 4 else { return }
        dragged = true
        layer?.opacity = 1
        let url = PinStore.shared.url(for: pin) as NSURL
        let item = NSDraggingItem(pasteboardWriter: url)
        item.setDraggingFrame(bounds, contents: PinStore.shared.thumbnail(for: pin))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1
        defer { downAt = nil }
        guard !dragged, downAt != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.modifierFlags.contains(.option) {
            onDone?()
            PinStore.shared.open(pin)
        } else {
            PinStore.shared.copy(pin)
            onDone?()
            HUD.show("Copied pinned screenshot")
        }
    }

    @objc private func unpin() {
        // The menu stays open and redraws the grid without this pin.
        PinStore.shared.remove(pin)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onDone?() }
}

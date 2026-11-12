import AppKit

/// One pinned capture. What a click does is the tray's call, since it depends on whether pins
/// are being picked. Dragging drops the file, or every picked file, into any app.
@MainActor
final class PinCell: NSView, NSDraggingSource {
    let pin: PinStore.Pin
    /// A click that wasn't a drag, with the modifiers held.
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    /// The pins a drag from this cell carries: the picked ones when this is one of them.
    var dragPins: (() -> [PinStore.Pin])?
    var onDragEnded: (() -> Void)?

    var isSelected = false {
        didSet { if isSelected != oldValue { updateChrome() } }
    }

    private let ring = CALayer()
    private let remove: NSButton
    private let tick = NSImageView()
    private var downAt: CGPoint?
    private var dragged = false
    private var isHovered = false

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
        layer.addSublayer(ring)

        remove.target = self
        addSubview(remove)

        // A filled tick in the corner marks a picked pin, as Photos and Finder do.
        tick.image = Icon.checkmark.image(size: 10, weight: .bold, label: "Selected")
        tick.imageScaling = .scaleNone
        tick.contentTintColor = .white
        tick.wantsLayer = true
        tick.layer?.backgroundColor = Palette.accent.cgColor
        tick.layer?.cornerRadius = 10
        tick.layer?.borderWidth = 1.5
        tick.layer?.borderColor = NSColor.white.cgColor
        tick.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tick)

        NSLayoutConstraint.activate([
            remove.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            tick.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            tick.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            tick.widthAnchor.constraint(equalToConstant: 20),
            tick.heightAnchor.constraint(equalToConstant: 20),
        ])

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: pin.date, relativeTo: Date())
        toolTip = [pin.appName, when].compactMap { $0 }.joined(separator: ", ")
            + "\nClick to copy, ⌥-click to annotate, ⌘-click to pick several, or drag"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Pinned screenshot, \(when)")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateChrome() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateChrome() }

    private func updateChrome() {
        remove.isHidden = !isHovered || isSelected
        tick.isHidden = !isSelected
        setAccessibilitySelected(isSelected)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        ring.borderWidth = isSelected ? 3 : isHovered ? 2 : 0.5
        ring.borderColor = isSelected || isHovered ? Palette.accent.cgColor : NSColor.labelColor.withAlphaComponent(0.12).cgColor
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
        let pins = dragPins?() ?? [pin]
        // A small fanned stack under the pointer, one image per pin.
        let items = pins.enumerated().map { index, pin -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: PinStore.shared.url(for: pin) as NSURL)
            let offset = CGFloat(min(index, 4)) * 6
            let image = PinStore.shared.thumbnail(for: pin).map { NSImage(cgImage: $0, size: .zero) }
            item.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: image)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1
        defer { downAt = nil }
        guard !dragged, downAt != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(event.modifierFlags)
    }

    @objc private func unpin() {
        // The tray stays open and redraws without this pin.
        PinStore.shared.remove(pin)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onDragEnded?() }
}

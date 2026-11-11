import AppKit

/// What a left click on the menu bar icon opens: the pinned captures in a strip that scrolls
/// sideways. A transient popover, so Esc and clicks elsewhere close it the way they close any
/// popover; a pin that gets used closes it too.
@MainActor
final class PinTray: NSObject, NSPopoverDelegate {
    static let shared = PinTray()

    private static let inset: CGFloat = 14
    private static let cell = CGSize(width: 136, height: 86)
    private static let gap: CGFloat = 8
    private static let size = CGSize(width: 452, height: 14 + 20 + 10 + 86 + 14)

    private let popover = NSPopover()
    private var observer: Any?
    private var closedAt = Date.distantPast

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = Self.size
    }

    func toggle(from button: NSView) {
        if popover.isShown {
            close()
            return
        }
        // A click on the icon closes the transient popover before the icon's own action runs.
        // That click was meant to close it, so it must not open it again.
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
        let controller = NSViewController()
        controller.view = makeContent()
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        observer = NotificationCenter.default.addObserver(forName: PinStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.contentViewController?.view = self?.makeContent() ?? NSView() }
        }
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        popover.contentViewController = nil
    }

    // MARK: Content

    private func makeContent() -> NSView {
        // The popover draws its own material, so the content is a plain view.
        let content = NSView(frame: CGRect(origin: .zero, size: Self.size))

        let pins = PinStore.shared.pins
        let title = label("Pinned", size: 13, weight: .semibold, color: .labelColor)
        title.frame.origin = CGPoint(x: Self.inset, y: Self.size.height - Self.inset - 18)
        content.addSubview(title)

        if pins.isEmpty {
            content.addSubview(emptyState(in: CGRect(x: Self.inset, y: Self.inset, width: Self.size.width - Self.inset * 2, height: Self.cell.height)))
            return content
        }

        let count = label("\(pins.count) of \(PinStore.limit)", size: 12, weight: .regular, color: .secondaryLabelColor)
        count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        count.sizeToFit()
        count.frame.origin = CGPoint(x: title.frame.maxX + 6, y: title.frame.minY + 1)
        content.addSubview(count)

        let clear = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clear.isBordered = false
        clear.font = .systemFont(ofSize: 12, weight: .medium)
        clear.contentTintColor = .secondaryLabelColor
        clear.sizeToFit()
        clear.frame.origin = CGPoint(x: Self.size.width - Self.inset - clear.frame.width, y: title.frame.minY)
        clear.toolTip = "Remove every pin"
        content.addSubview(clear)

        let width = CGFloat(pins.count) * Self.cell.width + CGFloat(max(pins.count - 1, 0)) * Self.gap + Self.inset * 2
        let strip = NSView(frame: CGRect(x: 0, y: 0, width: max(width, Self.size.width), height: Self.cell.height))
        for (index, pin) in pins.enumerated() {
            let cell = PinCell(pin: pin, frame: CGRect(
                x: Self.inset + CGFloat(index) * (Self.cell.width + Self.gap), y: 0, width: Self.cell.width, height: Self.cell.height
            ))
            cell.onDone = { [weak self] in self?.close() }
            strip.addSubview(cell)
        }
        let scroll = SidewaysScrollView(frame: CGRect(x: 0, y: Self.inset, width: Self.size.width, height: Self.cell.height))
        scroll.documentView = strip
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        content.addSubview(scroll)
        scroll.updateFades()
        return content
    }

    private func emptyState(in frame: CGRect) -> NSView {
        let box = NSView(frame: frame)
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        let headline = label("Nothing pinned yet", size: 13, weight: .medium, color: .labelColor)
        let detail = label("Drag a preview up to the menu bar, or use its pin.", size: 12, weight: .regular, color: .secondaryLabelColor)
        let text = NSStackView(views: [headline, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let capture = NSButton(title: "Capture Area", target: self, action: #selector(captureArea))
        capture.bezelStyle = .push
        capture.keyEquivalent = "\r"
        for view in [text, capture] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        // Both sides centre on the box's middle, so the text never sinks onto the border.
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            text.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            capture.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            capture.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: capture.leadingAnchor, constant: -12),
        ])
        return box
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.sizeToFit()
        return field
    }

    @objc private func clearAll() { PinStore.shared.removeAll() }

    @objc private func captureArea() {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { HotAction.area.perform() }
    }
}

/// A horizontal strip that a plain mouse wheel scrolls too, with edges that fade where more
/// pins are hidden.
private final class SidewaysScrollView: NSScrollView {
    private let fade = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dy) > abs(dx), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x - dy * step, 0), max(document.frame.width - contentView.bounds.width, 0))
        contentView.setBoundsOrigin(origin)
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        updateFades()
    }

    @objc private func boundsChanged() { updateFades() }

    func updateFades() {
        guard let document = documentView else { return }
        fade.frame = bounds
        let width = max(bounds.width, 1)
        let edge = 28 / width
        let offset = contentView.bounds.minX
        let leading: CGFloat = offset > 1 ? 0 : 1
        let trailing: CGFloat = offset + contentView.bounds.width < document.frame.width - 1 ? 0 : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.colors = [
            NSColor.black.withAlphaComponent(leading).cgColor, NSColor.black.cgColor,
            NSColor.black.cgColor, NSColor.black.withAlphaComponent(trailing).cgColor,
        ]
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        CATransaction.commit()
    }
}

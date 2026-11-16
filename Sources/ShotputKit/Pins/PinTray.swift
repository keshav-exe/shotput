import AppKit

/// The pinned captures and files, in the notch island (see NotchDrop) or, with pins set to the
/// menu bar, in a popover under the icon. The same content either way: in a strip that scrolls
/// sideways. A transient popover, so Esc and clicks elsewhere close it the way they close any
/// popover; a pin that gets used closes it too. ⌘-click, ⇧-click, or Select picks several pins
/// to copy, drag, or unpin together. With more than one kind of thing pinned, filters narrow the
/// strip to one kind, and dragging a pin sideways within the tray reorders it.
@MainActor
final class PinTray: NSObject, NSPopoverDelegate {
    static let shared = PinTray()

    private static let inset: CGFloat = 14
    private static let cell = CGSize(width: 136, height: 86)
    private static let gap: CGFloat = 8
    private static let baseSize = CGSize(width: 452, height: 14 + 20 + 10 + 86 + 14)
    /// The filter row, when there's more than one kind to filter by.
    private static let filterRow: CGFloat = 32
    private static var size: CGSize {
        CGSize(width: baseSize.width, height: baseSize.height + (showsFilters ? filterRow : 0))
    }

    /// Kinds of thing pinned right now, in a fixed order.
    private static var kinds: [PinStore.Pin.Kind] {
        let present = Set(PinStore.shared.pins.map(\.kind))
        return PinStore.Pin.Kind.allCases.filter(present.contains)
    }

    private static var showsFilters: Bool { kinds.count > 1 }

    /// The kind the strip shows, or nil for everything. Kept between openings.
    private var filter: PinStore.Pin.Kind?

    /// The pins the strip shows, in the tray's order.
    private var visiblePins: [PinStore.Pin] {
        let pins = PinStore.shared.pins
        guard let filter, Self.kinds.contains(filter), Self.showsFilters else { return pins }
        return pins.filter { $0.kind == filter }
    }

    private let popover = NSPopover()
    private var observer: Any?
    private var closedAt = Date.distantPast

    private var cells: [PinCell] = []
    private weak var content: NSView?
    private weak var header: NSView?
    private var isPicking = false
    private var picked: [UUID] = []
    private var lastClicked: Int?

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
        popover.contentSize = Self.size
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        observer = NotificationCenter.default.addObserver(forName: PinStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ids = Set(PinStore.shared.pins.map(\.id))
                self.picked.removeAll { !ids.contains($0) }
                if ids.isEmpty { self.isPicking = false }
                self.popover.contentSize = Self.size
                self.popover.contentViewController?.view = self.makeContent()
            }
        }
    }

    /// Set while the notch island hosts the tray: closing closes the island instead.
    private var notchClose: (() -> Void)?

    func close() {
        if let notchClose {
            notchClose()
        } else {
            popover.performClose(nil)
        }
    }

    static var contentSize: CGSize { size }

    /// The tray for the notch island to show. `onClose` is how a used pin, or Esc, closes it.
    func notchContent(onClose: @escaping () -> Void) -> NSView {
        if popover.isShown { popover.performClose(nil) }
        notchClose = onClose
        isPicking = false
        picked = []
        lastClicked = nil
        return makeContent()
    }

    /// The tray drawn again after the pins changed, keeping what's picked.
    func refreshedNotchContent() -> NSView {
        let ids = Set(PinStore.shared.pins.map(\.id))
        picked.removeAll { !ids.contains($0) }
        if ids.isEmpty { isPicking = false }
        return makeContent()
    }

    func notchDidClose() {
        notchClose = nil
        isPicking = false
        picked = []
        lastClicked = nil
        cells = []
    }

    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
        isPicking = false
        picked = []
        lastClicked = nil
        cells = []
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        popover.contentViewController = nil
    }

    // MARK: Content

    private func makeContent() -> NSView {
        // The popover draws its own material, so the content is a plain view.
        let content = NSView(frame: CGRect(origin: .zero, size: Self.size))

        let pins = PinStore.shared.pins
        self.content = content

        if pins.isEmpty {
            let title = label(L("Pinned"), size: 13, weight: .semibold, color: .labelColor)
            title.frame.origin = CGPoint(x: Self.inset, y: Self.size.height - Self.inset - 18)
            content.addSubview(title)
            content.addSubview(emptyState(in: CGRect(x: Self.inset, y: Self.inset, width: Self.size.width - Self.inset * 2, height: Self.cell.height)))
            return content
        }

        installHeader(in: content)
        if Self.showsFilters { installFilters(in: content) }

        cells = []
        let shown = visiblePins
        let strip = PinStripView(frame: CGRect(x: 0, y: 0, width: Self.size.width, height: Self.cell.height))
        strip.layout = PinStripView.Layout(inset: Self.inset, cell: Self.cell, gap: Self.gap, minimumWidth: Self.size.width)
        for (index, pin) in shown.enumerated() {
            let cell = PinCell(pin: pin, frame: CGRect(origin: .zero, size: Self.cell))
            cell.onClick = { [weak self] flags in self?.clicked(index, flags: flags) }
            cell.dragPins = { [weak self, pin] in self?.dragged(from: pin) ?? [pin] }
            cell.onDragEnded = { [weak self] reordered in if !reordered { self?.close() } }
            cell.onNudge = { [weak self, pin] step in self?.nudge(pin, by: step) }
            cell.isSelected = picked.contains(pin.id)
            strip.addSubview(cell)
            cells.append(cell)
        }
        strip.cells = cells
        strip.onReorder = { [weak self] ids, index in self?.reorder(ids, to: index) }
        strip.arrange(animated: false)
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

    // MARK: Filters

    /// All, then one segment per kind that's pinned, each with how many.
    private func installFilters(in content: NSView) {
        let kinds = Self.kinds
        let pins = PinStore.shared.pins
        let control = NSSegmentedControl()
        control.segmentCount = kinds.count + 1
        control.trackingMode = .selectOne
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        control.setLabel(String(format: L("All %d"), pins.count), forSegment: 0)
        control.setToolTip(L("Every pin"), forSegment: 0)
        for (offset, kind) in kinds.enumerated() {
            let segment = offset + 1
            control.setImage(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title), forSegment: segment)
            control.setLabel("\(pins.filter { $0.kind == kind }.count)", forSegment: segment)
            control.setToolTip(kind.title, forSegment: segment)
            control.setImageScaling(.scaleProportionallyDown, forSegment: segment)
        }
        let selected = filter.flatMap { kinds.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        control.selectedSegment = selected
        control.target = self
        control.action = #selector(filterChanged(_:))
        control.setAccessibilityLabel(L("Show"))
        control.sizeToFit()
        control.frame.origin = CGPoint(x: Self.inset, y: Self.inset + Self.cell.height + 8)
        content.addSubview(control)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        let kinds = Self.kinds
        filter = sender.selectedSegment > 0 && kinds.indices.contains(sender.selectedSegment - 1) ? kinds[sender.selectedSegment - 1] : nil
        // What's picked stays picked, even while filtered out of sight.
        lastClicked = nil
        redraw()
    }

    /// The tray drawn again in place, in the popover or the notch.
    private func redraw() {
        if popover.isShown {
            popover.contentViewController?.view = makeContent()
        } else if notchClose != nil {
            NotificationCenter.default.post(name: PinStore.didChange, object: nil)
        }
    }

    // MARK: Order

    /// Pins dropped back in the strip at a position among the pins it shows.
    private func reorder(_ ids: [UUID], to index: Int) {
        let shown = visiblePins.filter { !ids.contains($0.id) }
        let all = PinStore.shared.pins.filter { !ids.contains($0.id) }
        let target: UUID?
        if index < shown.count {
            target = shown[index].id
        } else if let last = shown.last, let position = all.firstIndex(of: last), position + 1 < all.count {
            // After the last pin shown: before whatever follows it, filtered out or not.
            target = all[position + 1].id
        } else {
            target = nil
        }
        PinStore.shared.move(ids, before: target)
    }

    private func nudge(_ pin: PinStore.Pin, by step: Int) {
        let shown = visiblePins
        guard let index = shown.firstIndex(of: pin) else { return }
        let destination = min(max(index + step, 0), shown.count - 1)
        guard destination != index else { return }
        // Positions count the pins other than this one, so the destination reads the same both ways.
        reorder([pin.id], to: destination)
    }

    // MARK: Header

    /// L("Pinned, 3 of 15") with Select and Clear, or, while picking, how many are picked and what
    /// to do with them.
    private func installHeader(in content: NSView) {
        header?.removeFromSuperview()
        let bar = NSView(frame: CGRect(x: Self.inset, y: Self.size.height - Self.inset - 22, width: Self.size.width - Self.inset * 2, height: 24))
        let pins = PinStore.shared.pins

        let title: NSTextField
        if isPicking {
            title = label(picked.isEmpty ? L("Pick pins") : picked.count == 1 ? L("1 picked") : "\(picked.count) picked",
                          size: 13, weight: .semibold, color: .labelColor)
            title.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            title.sizeToFit()
        } else {
            title = label(L("Pinned"), size: 13, weight: .semibold, color: .labelColor)
        }
        title.frame.origin = CGPoint(x: 0, y: 2)
        bar.addSubview(title)

        if !isPicking {
            let count = label("\(pins.count) of \(PinStore.limit)", size: 12, weight: .regular, color: .secondaryLabelColor)
            count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            count.sizeToFit()
            count.frame.origin = CGPoint(x: title.frame.maxX + 6, y: 3)
            bar.addSubview(count)
        }

        let actions: [(String, Selector, String, Bool)] = isPicking
            ? [(L("Copy"), #selector(copyPicked), L("Copy the picked pins"), !picked.isEmpty),
               (L("Unpin"), #selector(unpinPicked), L("Unpin the picked pins"), !picked.isEmpty),
               (L("Done"), #selector(stopPicking), L("Stop picking"), true)]
            : [(L("Select"), #selector(startPicking), L("Pick several pins, or ⌘-click them"), true),
               (L("Clear"), #selector(clearAll), L("Remove every pin"), true)]
        var x = bar.bounds.width
        for (title, action, help, enabled) in actions.reversed() {
            let button = NSButton(title: title, target: self, action: action)
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: title == L("Done") || title == L("Copy") ? .semibold : .medium)
            button.contentTintColor = title == L("Done") || (title == L("Copy") && enabled) ? .controlAccentColor : .secondaryLabelColor
            button.isEnabled = enabled
            button.toolTip = help
            button.sizeToFit()
            // Text buttons get a target wider and taller than their words.
            button.frame.size = CGSize(width: button.frame.width + 12, height: 24)
            x -= button.frame.width
            button.frame.origin = CGPoint(x: x + 6, y: (bar.bounds.height - button.frame.height) / 2)
            x -= 2
            bar.addSubview(button)
        }
        content.addSubview(bar)
        header = bar
    }

    // MARK: Picking

    private func clicked(_ index: Int, flags: NSEvent.ModifierFlags) {
        let pins = visiblePins
        guard pins.indices.contains(index) else { return }
        let pin = pins[index]
        if !isPicking && !flags.contains(.command) && !flags.contains(.shift) {
            close()
            if flags.contains(.option) {
                PinStore.shared.open(pin)
            } else {
                PinStore.shared.copy(pin)
                HUD.show(pin.isCapture ? L("Copied pinned screenshot") : L("Copied pinned file"))
            }
            return
        }
        isPicking = true
        if flags.contains(.shift), let last = lastClicked, pins.indices.contains(last) {
            // A range adds to what's picked, the way Finder does.
            for i in min(last, index) ... max(last, index) where !picked.contains(pins[i].id) { picked.append(pins[i].id) }
        } else if let position = picked.firstIndex(of: pin.id) {
            picked.remove(at: position)
        } else {
            picked.append(pin.id)
        }
        lastClicked = index
        refreshPicking()
    }

    private func dragged(from pin: PinStore.Pin) -> [PinStore.Pin] {
        guard isPicking, picked.contains(pin.id) else { return [pin] }
        return pickedPins
    }

    /// The picked pins in the order they were picked.
    private var pickedPins: [PinStore.Pin] {
        let pins = PinStore.shared.pins
        return picked.compactMap { id in pins.first { $0.id == id } }
    }

    private func refreshPicking() {
        for cell in cells { cell.isSelected = picked.contains(cell.pin.id) }
        if let content { installHeader(in: content) }
    }

    @objc private func startPicking() {
        isPicking = true
        refreshPicking()
    }

    @objc private func stopPicking() {
        isPicking = false
        picked = []
        lastClicked = nil
        refreshPicking()
    }

    @objc private func copyPicked() {
        let pins = pickedPins
        guard !pins.isEmpty else { return }
        PinStore.shared.copy(pins)
        close()
        HUD.show(PinTray.copiedMessage(pins))
    }

    @objc private func unpinPicked() {
        let pins = pickedPins
        isPicking = false
        picked = []
        PinStore.shared.remove(pins)
    }

    /// Whole sentences for each mix, so every one can be translated.
    private static func copiedMessage(_ pins: [PinStore.Pin]) -> String {
        let captures = pins.allSatisfy(\.isCapture)
        let files = !pins.contains(where: \.isCapture)
        if pins.count == 1 { return captures ? L("Copied pinned screenshot") : L("Copied pinned file") }
        let format = captures ? L("Copied %d screenshots") : files ? L("Copied %d files") : L("Copied %d pins")
        return String(format: format, pins.count)
    }

    private func emptyState(in frame: CGRect) -> NSView {
        let box = NSView(frame: frame)
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        let headline = label(L("Nothing pinned yet"), size: 13, weight: .medium, color: .labelColor)
        let detail = label(
            NotchGeometry.hasHardwareNotch ? L("Drag a preview or any file to the notch.") : L("Drag a preview or any file to the top of the screen."),
            size: 12, weight: .regular, color: .secondaryLabelColor
        )
        let text = NSStackView(views: [headline, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let capture = NSButton(title: L("Capture Area"), target: self, action: #selector(captureArea))
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

/// The row of pins. It lays the cells out, and takes pins dragged back into it: the others slide
/// apart to show where they'll land, like icons in the Dock, and letting go there reorders them.
private final class PinStripView: NSView {
    struct Layout {
        var inset: CGFloat = 14
        var cell = CGSize(width: 136, height: 86)
        var gap: CGFloat = 8
        var minimumWidth: CGFloat = 452
    }

    var layout = Layout()
    var cells: [PinCell] = []
    /// The dragged pins' ids, and the position among the other pins to put them at.
    var onReorder: (([UUID], Int) -> Void)?

    private var dragged: Set<UUID> = []
    private var gapIndex: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.shotputPin])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Places every cell, leaving room at the drop position while a drag is over the strip.
    func arrange(animated: Bool) {
        let staying = cells.filter { !dragged.contains($0.pin.id) }
        let slots = gapIndex == nil ? cells.count : staying.count + 1
        let width = layout.inset * 2 + CGFloat(slots) * layout.cell.width + CGFloat(max(slots - 1, 0)) * layout.gap
        setFrameSize(CGSize(width: max(width, layout.minimumWidth), height: layout.cell.height))

        let step = layout.cell.width + layout.gap
        func place() {
            if let gapIndex {
                for (index, cell) in staying.enumerated() {
                    let slot = index >= gapIndex ? index + 1 : index
                    cell.animator().frame.origin = CGPoint(x: layout.inset + CGFloat(slot) * step, y: 0)
                }
            } else {
                for (index, cell) in cells.enumerated() {
                    cell.animator().frame.origin = CGPoint(x: layout.inset + CGFloat(index) * step, y: 0)
                }
            }
            for cell in cells {
                cell.animator().alphaValue = gapIndex != nil && dragged.contains(cell.pin.id) ? 0 : 1
            }
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !reduceMotion ? 0.2 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            context.allowsImplicitAnimation = true
            place()
        }
    }

    private func ids(in info: NSDraggingInfo) -> [UUID] {
        (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .shotputPin).flatMap(UUID.init(uuidString:)) }
    }

    /// The position among the staying pins that a drop at this point takes.
    private func index(at point: CGPoint) -> Int {
        let staying = cells.filter { !dragged.contains($0.pin.id) }
        let step = layout.cell.width + layout.gap
        let slot = Int(((point.x - layout.inset + layout.gap / 2) / step).rounded(.down))
        return min(max(slot, 0), staying.count)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let moving = ids(in: sender)
        guard !moving.isEmpty, sender.draggingSource is PinCell else { return [] }
        dragged = Set(moving)
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !dragged.isEmpty else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        scrollIfNearEdge(point)
        let target = index(at: point)
        if target != gapIndex {
            gapIndex = target
            arrange(animated: true)
        }
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Out of the tray: back as they were, and the drag carries the pins to another app.
        gapIndex = nil
        dragged = []
        arrange(animated: true)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let gapIndex, !dragged.isEmpty else { return false }
        let moving = cells.map(\.pin.id).filter(dragged.contains)
        let ordered = moving.isEmpty ? ids(in: sender) : moving
        self.gapIndex = nil
        dragged = []
        onReorder?(ordered, gapIndex)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if gapIndex != nil {
            gapIndex = nil
            dragged = []
            arrange(animated: true)
        }
    }

    /// Near either end of what's showing, the strip scrolls to reveal more places to drop.
    private func scrollIfNearEdge(_ point: CGPoint) {
        guard let clip = enclosingScrollView?.contentView else { return }
        let visible = clip.bounds
        let edge: CGFloat = 36
        var origin = visible.origin
        if point.x < visible.minX + edge {
            origin.x -= 10
        } else if point.x > visible.maxX - edge {
            origin.x += 10
        } else {
            return
        }
        origin.x = min(max(origin.x, 0), max(bounds.width - visible.width, 0))
        clip.setBoundsOrigin(origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }
}

import AppKit

/// The thumbnails shown after captures, gathered in one corner. A new one lands in front and the
/// rest step back into a stack; point at the stack and it fans out so every one is in reach.
/// Click the front one to annotate, any other to bring it to the front. They never take focus,
/// so pasting is not interrupted, and each leaves on its own after the time set in Settings.
@MainActor
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private final class Card {
        let capture: Capture
        let panel: NSPanel
        let view: PreviewView
        /// The thumbnail's own size, before the stack shrinks it.
        let size: CGSize
        var timer: Timer?

        init(capture: Capture, panel: NSPanel, view: PreviewView, size: CGSize) {
            self.capture = capture
            self.panel = panel
            self.view = view
            self.size = size
        }
    }

    /// Front first.
    private var cards: [Card] = []
    private var screen: NSScreen?
    private var isSpread = false
    /// Follows the pointer while it's over the stack. Runs only then.
    private var hoverPoll: Timer?
    private var leftAt: Date?

    /// More than this and the oldest makes room.
    private static let limit = 12
    private static let margin: CGFloat = 24
    private static let inset: CGFloat = 20
    private static let gap: CGFloat = 10
    /// How far each card behind the front one shows past it.
    private static let peek: CGFloat = 9
    private static let visibleBehind = 3

    var isEmpty: Bool { cards.isEmpty }

    private var cornerWatch: Any?

    private init() {
        // A new corner in Settings moves the stack there straight away.
        cornerWatch = Settings.shared.$previewCorner.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.cards.isEmpty else { return }
                self.apply(self.layout(), duration: 0.3)
            }
        }
    }

    func show(_ capture: Capture) {
        if let existing = cards.firstIndex(where: { $0.capture === capture }) {
            bringToFront(existing)
            return
        }
        let size = Self.thumbnailSize(for: capture.pointSize)
        // Made at its real size: a window that starts at zero squeezes the thumbnail out of
        // place as it grows.
        let initial = CGRect(origin: .zero, size: CGSize(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2))
        let panel = NSPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system window shadow adds a light rim in dark mode; the thumbnail draws its own.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let view = PreviewView(capture: capture, size: size)
        let card = Card(capture: capture, panel: panel, view: view, size: size)
        wire(card)
        let host = ShadowHost(frame: initial, inset: Self.margin)
        host.addSubview(view)
        panel.contentView = host

        screen = capture.screen ?? NSScreen.underMouse ?? NSScreen.screens.first
        cards.insert(card, at: 0)
        while cards.count > Self.limit, let oldest = cards.last { remove(oldest, animated: true) }

        // The thumbnail leaves from where the capture was taken and settles in its corner, so
        // it is clear where the screenshot went. Without a known origin it slides in from the edge.
        let frames = layout()
        let final = frames[0]
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start = final.offsetBy(dx: Settings.shared.previewCorner.isLeft ? -16 : 16, dy: 0)
        if let origin = capture.screenRect, !origin.intersects(final) {
            start = CGRect(x: origin.midX - final.width / 2, y: origin.midY - final.height / 2, width: final.width, height: final.height)
        }
        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? final : start, display: true)
        panel.orderFrontRegardless()
        apply(frames, skipping: card, duration: 0.3)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = start.center.distance(to: final.center) > 120 ? 0.42 : 0.25
            // Quick out of the gate, gentle landing.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(final, display: true)
        }
        if isSpread || hoverPoll != nil { card.view.setControlsVisible(false) } else { scheduleDismissals() }
    }

    private func wire(_ card: Card) {
        let capture = card.capture
        let view = card.view
        view.onHover = { [weak self] inside in if inside { self?.pointerEntered() } }
        view.onClick = { [weak self, weak card] in
            guard let self, let card, let index = self.cards.firstIndex(where: { $0 === card }) else { return }
            if index == 0 {
                self.remove(card, animated: true)
                EditorManager.shared.open(capture)
            } else {
                self.bringToFront(index)
            }
        }
        view.onAnnotate = { [weak self, weak card] in
            if let card { self?.remove(card, animated: true) }
            EditorManager.shared.open(capture)
        }
        view.onCopy = { [weak self, weak card] in
            if let png = capture.png() { Output.copyToClipboard(png.data) }
            // Long enough to see the check land, short enough not to linger.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if let card { self?.remove(card, animated: true) } }
        }
        view.onPin = { [weak self, weak card] in
            guard let card, PinStore.shared.pin(capture) else { return }
            self?.flyToPins(card)
        }
        view.onFloat = { [weak self, weak card] in
            if let card { self?.remove(card, animated: false) }
            FloatingShots.shared.float(capture)
        }
        view.onDragStart = { [weak self] in
            self?.cancelDismissals()
            NotchDrop.shared.beginDragging(capture)
        }
        view.onSave = { [weak self, weak card] in
            if let card { self?.remove(card, animated: true) }
            guard let file = capture.fileData() else { return }
            Output.save(file, relativeTo: nil) { _ in }
        }
        view.onClose = { [weak self, weak card] in if let card { self?.remove(card, animated: true) } }
        view.onCloseAll = { [weak self] in self?.dismissAll() }
        view.stackCount = { [weak self] in self?.cards.count ?? 0 }
    }

    // MARK: The stack

    private func bringToFront(_ index: Int) {
        guard cards.indices.contains(index), index > 0 else { return }
        let card = cards.remove(at: index)
        cards.insert(card, at: 0)
        apply(layout(), duration: 0.32)
        syncHover()
    }

    /// Where each card goes: stacked in the corner, or fanned out from it while pointed at.
    private func layout() -> [CGRect] {
        guard let screen = screen ?? NSScreen.screens.first, let front = cards.first else { return [] }
        let corner = Settings.shared.previewCorner
        let area = screen.visibleFrame.insetBy(dx: Self.inset, dy: Self.inset)
        let up: CGFloat = corner.isTop ? -1 : 1
        let edge = corner.isTop ? area.maxY : area.minY

        if isSpread {
            // Each at its own size, one after another away from the corner. When they'd run off
            // the screen they overlap instead, evenly, so each keeps a strip to click.
            let total = cards.reduce(0) { $0 + $1.size.height } + Self.gap * CGFloat(cards.count - 1)
            let room = area.height
            let squeeze = total > room && cards.count > 1
                ? max(0, (room - (cards.last?.size.height ?? 0)) / (total - (cards.last?.size.height ?? 0)))
                : 1
            var offset: CGFloat = 0
            return cards.map { card in
                let rect = Self.margined(card.size, nearEdge: edge + offset * up, corner: corner, area: area)
                offset += (card.size.height + Self.gap) * min(1, squeeze)
                return rect
            }
        }

        let frontRect = Self.margined(front.size, nearEdge: edge, corner: corner, area: area).insetBy(dx: Self.margin, dy: Self.margin)
        return cards.indices.map { index in
            guard index > 0 else { return frontRect.insetBy(dx: -Self.margin, dy: -Self.margin) }
            // Behind the front card, a little smaller, its far edge showing past the one before.
            let depth = CGFloat(min(index, Self.visibleBehind))
            let scale = 1 - 0.06 * depth
            let width = (frontRect.width * scale).rounded(), height = (frontRect.height * scale).rounded()
            let y = corner.isTop ? frontRect.minY - depth * Self.peek : frontRect.maxY + depth * Self.peek - height
            return CGRect(x: (frontRect.midX - width / 2).rounded(), y: y, width: width, height: height)
                .insetBy(dx: -Self.margin, dy: -Self.margin)
        }
    }

    private static func margined(_ size: CGSize, nearEdge: CGFloat, corner: Settings.Corner, area: CGRect) -> CGRect {
        let x = corner.isLeft ? area.minX : area.maxX - size.width
        let y = corner.isTop ? nearEdge - size.height : nearEdge
        return CGRect(x: x, y: y, width: size.width, height: size.height).insetBy(dx: -margin, dy: -margin)
    }

    /// Moves every card to its place, front on top, the deepest ones faded out behind.
    private func apply(_ frames: [CGRect], skipping skipped: Card? = nil, duration: TimeInterval) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, card) in cards.enumerated() {
            if index == 0 { card.panel.orderFrontRegardless() } else {
                card.panel.order(.below, relativeTo: cards[index - 1].panel.windowNumber)
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            for (index, card) in cards.enumerated() where card !== skipped && frames.indices.contains(index) {
                card.panel.animator().setFrame(frames[index], display: true)
                let hidden = !isSpread && index > Self.visibleBehind
                card.panel.animator().alphaValue = hidden ? 0 : 1
            }
        }
    }

    // MARK: Pointing at the stack

    func pointerEntered() {
        cancelDismissals()
        leftAt = nil
        if !isSpread, cards.count > 1 {
            isSpread = true
            apply(layout(), duration: 0.3)
        }
        syncHover()
        guard hoverPoll == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverPoll = timer
    }

    /// Cards slide under a still pointer as the stack fans out, which AppKit's hover tracking
    /// never notices, so the stack looks for itself.
    private func followPointer() {
        guard !cards.isEmpty else { return endHover() }
        let mouse = NSEvent.mouseLocation
        let over = cards.contains { thumbnail(of: $0).insetBy(dx: -14, dy: -14).contains(mouse) }
        if over || NSEvent.pressedMouseButtons != 0 {
            leftAt = nil
        } else if let leftAt {
            if Date().timeIntervalSince(leftAt) > 0.3 { endHover() }
        } else {
            leftAt = Date()
        }
        syncHover()
    }

    private func endHover() {
        hoverPoll?.invalidate()
        hoverPoll = nil
        leftAt = nil
        cards.forEach { $0.view.setControlsVisible(false) }
        if isSpread {
            isSpread = false
            apply(layout(), duration: 0.28)
        }
        scheduleDismissals()
    }

    /// Controls show on the one card under the pointer, the topmost where they overlap.
    private func syncHover() {
        let mouse = NSEvent.mouseLocation
        let pointed = hoverPoll == nil && !isSpread ? nil : cards.first { thumbnail(of: $0).contains(mouse) }
        for card in cards { card.view.setControlsVisible(card === pointed) }
    }

    /// The card itself, without the margin its shadow lives in. Where it's going, not where it
    /// is mid-animation, so hovering doesn't flicker as cards slide.
    private func thumbnail(of card: Card) -> CGRect {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return .null }
        let frames = layout()
        let frame = frames.indices.contains(index) ? frames[index] : card.panel.frame
        return frame.insetBy(dx: Self.margin, dy: Self.margin)
    }

    // MARK: Leaving

    private func scheduleDismissals() {
        cancelDismissals()
        let seconds = Settings.shared.previewDuration
        guard seconds > 0 else { return }
        // A beat apart, the front one first, so a stack drains card by card rather than all at once.
        for (index, card) in cards.enumerated() {
            let stagger = Double(index) * 0.15
            card.timer = Timer.scheduledTimer(withTimeInterval: seconds + stagger, repeats: false) { [weak self, weak card] _ in
                MainActor.assumeIsolated {
                    guard let self, let card, self.hoverPoll == nil else { return }
                    self.remove(card, animated: true)
                }
            }
        }
    }

    private func cancelDismissals() {
        cards.forEach { $0.timer?.invalidate(); $0.timer = nil }
    }

    private func remove(_ card: Card, animated: Bool) {
        card.timer?.invalidate()
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        let panel = card.panel
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
        if cards.count < 2 { isSpread = false }
        if cards.isEmpty {
            hoverPoll?.invalidate()
            hoverPoll = nil
        } else {
            apply(layout(), duration: 0.26)
        }
    }

    /// Closes the preview of one capture, as the editor opens on it.
    func dismiss(_ capture: Capture) {
        if let card = cards.first(where: { $0.capture === capture }) { remove(card, animated: true) }
    }

    func dismissAll() {
        for card in cards { remove(card, animated: true) }
    }

    /// Shrinks the thumbnail into the notch (or the menu bar icon), so a pin visibly goes where
    /// it is kept.
    private func flyToPins(_ card: Card) {
        card.timer?.invalidate()
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        if cards.count < 2 { isSpread = false }
        if !cards.isEmpty { apply(layout(), duration: 0.26) }
        let panel = card.panel
        let target = Settings.shared.pinTarget == .notch
            ? (NotchGeometry.resting().map { $0.hangingRect($0.size) } ?? MenuBarAnchor.target(on: panel.screen))
            : MenuBarAnchor.target(on: panel.screen)
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

    private static func thumbnailSize(for image: CGSize) -> CGSize {
        let limit = CGSize(width: 232, height: 148)
        let fit = min(limit.width / max(image.width, 1), limit.height / max(image.height, 1), 1)
        return CGSize(width: max(image.width * fit, 140), height: max(image.height * fit, 84)).rounded
    }
}

private extension CGSize {
    var rounded: CGSize { CGSize(width: width.rounded(), height: height.rounded()) }
}

/// Draws the thumbnail's shadow, two layers deep, around whatever rounded view it holds.
private final class ShadowHost: NSView {
    private let ambient = CALayer()
    private let contact = CALayer()
    /// The margin the shadow lives in, all round the thumbnail.
    private let inset: CGFloat

    init(frame: NSRect, inset: CGFloat) {
        self.inset = inset
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let thumbnail = subviews.first else { return }
        // Placed here on every layout, never left to autoresizing: as the stack gathers and fans
        // out its windows change size, and the thumbnail must always fill them less the margin.
        thumbnail.frame = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: thumbnail.frame, cornerWidth: Metrics.chipRadius, cornerHeight: Metrics.chipRadius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [ambient, contact].forEach { $0.frame = bounds; $0.shadowPath = path }
        CATransaction.commit()
    }
}

private final class PreviewView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onCloseAll: (() -> Void)?
    var stackCount: () -> Int = { 1 }
    var onAnnotate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onPin: (() -> Void)?
    var onFloat: (() -> Void)?
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
        // Small captures sit centred at their real size. Larger ones fill the thumbnail.
        let image = capture.pointSize
        let fits = image.width <= size.width && image.height <= size.height
        layer.contentsGravity = fits ? .center : .resizeAspectFill
        layer.contentsScale = capture.scale
        if fits {
            layer.contents = capture.image
        } else {
            // A 5K screenshot is some 60 MB on the graphics card; the card shows 232 points of
            // it. Scale it down once, off the main thread, to the pixels actually drawn.
            let source = capture.image
            let target = size
            DispatchQueue.global(qos: .userInitiated).async {
                let thumbnail = Self.thumbnail(source, filling: target, scale: 2)
                DispatchQueue.main.async { [weak layer] in
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer?.contentsScale = 2
                    layer?.contents = thumbnail ?? source
                    CATransaction.commit()
                }
            }
        }
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
        buttons.addArrangedSubview(button(.float, L("Float on screen"), #selector(floatOnScreen)))
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

    /// The image scaled to cover `size` points at `scale`, keeping its shape.
    nonisolated private static func thumbnail(_ image: CGImage, filling size: CGSize, scale: CGFloat) -> CGImage? {
        let fill = max(size.width * scale / CGFloat(image.width), size.height * scale / CGFloat(image.height))
        guard fill < 1 else { return image }
        let width = Int((CGFloat(image.width) * fill).rounded(.up)), height = Int((CGFloat(image.height) * fill).rounded(.up))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func button(_ icon: Icon, _ label: String, _ action: Selector) -> NSButton {
        NSButton.glassCircle(icon, label: label, target: self, action: action)
    }

    @objc private func annotate() { onAnnotate?() }
    @objc private func copyAgain() {
        copyButton?.confirm(restoring: .copy)
        onCopy?()
    }
    @objc private func pin() { onPin?() }
    @objc private func floatOnScreen() { onFloat?() }
    @objc private func save() { onSave?() }
    @objc private func close() { onClose?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Cards change size as the stack gathers and fans out; the scrim follows.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = bounds
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    private var controlsVisible = false

    /// The stack decides which card shows its controls: only the one under the pointer.
    func setControlsVisible(_ hovered: Bool) {
        guard hovered != controlsVisible else { return }
        controlsVisible = hovered
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
        if !didDrag, mouseDownLocation != nil { onClick?() }
        mouseDownLocation = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        add(L("Annotate"), #selector(annotate))
        add(L("Copy"), #selector(copyAgain))
        add(L("Save…"), #selector(save))
        add(L("Float on screen"), #selector(floatOnScreen))
        add(L("Pin"), #selector(pin))
        menu.addItem(.separator())
        add(L("Close"), #selector(close))
        if stackCount() > 1 { add(L("Close All Previews"), #selector(closeAll)) }
        return menu
    }

    @objc private func closeAll() { onCloseAll?() }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnd?()
        if operation != [] { onClose?() }
    }
}

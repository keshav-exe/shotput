import AppKit
import Combine
import Observation
import UniformTypeIdentifiers

/// What's being dragged, as the island describes it.
struct DragPayload {
    var count = 0
    /// The one file's name, when there is one file.
    var name: String?
    /// Up to three, fanned under the pointer's file.
    var icons: [NSImage] = []
    /// A preview's screenshot, which pins as a capture rather than as a file.
    var capture: Capture?
}

/// The island's state: how far it has opened, and what it's showing.
@MainActor
@Observable
final class NotchDropModel {
    enum Phase: Equatable {
        /// Just the notch. On screens without one, nothing at all.
        case hidden
        /// At rest with pins waiting: ears beside the notch, a pin and how many, like a badge.
        case badge
        /// Something pinnable is being dragged somewhere: the notch grows ears to say it can take it.
        case armed
        /// The drag is heading for the notch: it opens into a well.
        case near
        /// Over the well. Letting go pins.
        case targeted
        /// Pinned, and how many.
        case pinned(Int)
        case alreadyPinned
        case failed
        /// The pins themselves, opened from the notch, its ears or the menu bar icon.
        case tray
    }

    var phase: Phase = .hidden
    /// Clove is wearing its own ears, so at rest the pins sit in a bubble past them instead.
    var showsSideBubble = false
    /// Counts up as pins arrive, so the badge can pop.
    var bump = 0
    /// The tray's AppKit content, while the tray is open.
    var trayView: NSView?
    /// What a click on the notch or its ears does. Set by the controller.
    @ObservationIgnored var openTray: () -> Void = {}
    var geometry: NotchGeometry?
    var payload = DragPayload()
    /// How many pins the tray holds, for "4 of 15".
    var total = 0

    var isHardware: Bool { geometry?.isHardware ?? true }
    var isMenuBar: Bool { geometry?.isMenuBar ?? false }
    /// The Dynamic Island on a screen without a notch.
    var isFloating: Bool { geometry?.isFloating ?? false }
    /// The space at the top of an open island: the notch's height, kept clear of the camera, or
    /// a thin margin on the floating island, which has no camera to clear.
    var band: CGFloat { isFloating ? 6 : notchSize.height }
    var notchSize: CGSize { geometry?.size ?? CGSize(width: 190, height: 32) }

    var isPanel: Bool {
        switch phase {
        case .hidden, .armed, .badge: false
        default: true
        }
    }

    /// Resting: the bare notch or its badge, ready for a click.
    var isResting: Bool { phase == .hidden || phase == .badge }

    var isMoment: Bool {
        switch phase {
        case .pinned, .alreadyPinned, .failed: true
        default: false
        }
    }

    // MARK: Size

    static let shoulder: CGFloat = 10
    /// The bubble beside Clove's ears: notch-dark, a little shorter than the notch.
    static let sideBubbleSize = CGSize(width: 46, height: 24)
    static let sideBubbleGap: CGFloat = 6

    /// The bubble's centre, from the notch's centre: past Clove's right ear, and a gap.
    var sideBubbleOffset: CGFloat {
        notchSize.width / 2 + NotchApps.companionEarReach + Self.sideBubbleGap + Self.sideBubbleSize.width / 2
    }
    static let earWidth: CGFloat = 40

    /// The gap between the menu bar and a card hanging under its icon.
    static let menuBarGap: CGFloat = 6

    /// The island's outer size for a phase, shoulders included. Under the menu bar it's the
    /// card's size plus the menu bar it hangs below.
    func size(for phase: Phase) -> CGSize {
        let notch = notchSize
        if isMenuBar {
            let card = cardSize(for: phase)
            return CGSize(width: card.width, height: notch.height + Self.menuBarGap + card.height)
        }
        let body: CGSize
        switch phase {
        case .hidden: body = notch
        case .armed, .badge: body = CGSize(width: notch.width + Self.earWidth * 2, height: notch.height)
        case .tray:
            let tray = PinTray.contentSize
            body = CGSize(width: max(tray.width + 8, notch.width + 150), height: band + tray.height + 6)
        case .near: body = CGSize(width: max(360, notch.width + 150), height: band + 84)
        case .targeted: body = CGSize(width: max(388, notch.width + 178), height: band + 96)
        case .pinned, .alreadyPinned, .failed: body = CGSize(width: max(340, notch.width + 130), height: band + (isFloating ? 66 : 60))
        }
        return CGSize(width: body.width + shoulderRadius(for: phase) * 2, height: body.height)
    }

    var size: CGSize { size(for: phase) }

    /// The card under the menu bar icon: a small pill while a drag is elsewhere, the well as it
    /// comes close.
    func cardSize(for phase: Phase) -> CGSize {
        switch phase {
        case .hidden, .badge, .tray: CGSize(width: 64, height: 30)
        case .armed: CGSize(width: 68, height: 30)
        case .near: CGSize(width: 360, height: 84)
        case .targeted: CGSize(width: 388, height: 96)
        case .pinned, .alreadyPinned, .failed: CGSize(width: 340, height: 60)
        }
    }

    var cardRadius: CGFloat {
        switch phase {
        case .hidden, .armed, .badge, .tray: 15
        default: 24
        }
    }

    func shoulderRadius(for phase: Phase) -> CGFloat {
        // Floating free of the screen's edge, there's no menu bar to pour out of.
        if isFloating { return 0 }
        return switch phase {
        case .hidden, .armed, .badge: 6
        default: Self.shoulder
        }
    }

    var shoulderRadius: CGFloat { shoulderRadius(for: phase) }

    var bottomRadius: CGFloat {
        switch phase {
        case .hidden, .armed, .badge: isHardware ? 10 : notchSize.height / 2
        case .pinned, .alreadyPinned, .failed: 22
        case .near, .targeted, .tray: 26
        }
    }
}

/// Shotput's pins live in the notch, both ways in and out:
/// - Drag anything pinnable (a preview, or files from Finder or any other app) and the notch grows
///   ears, opens into a well as the drag comes close, and pins what's let go over it.
/// - At rest it wears its pins like a badge: ears with a pin and how many. Hover to peek at the
///   tray, click to open it; Esc or a click anywhere else closes it. The bare notch opens it too.
/// - With Clove running the notch itself is Clove's to open, so only the ears answer the pointer;
///   clicking them claims the notch (Clove folds) and opens the tray there. While Clove's own
///   island is open the ears step out of its way.
/// With another notch app in charge of the notch, Settings can hang the well, and the tray, under
/// the menu bar icon instead.
@MainActor
final class NotchDrop {
    static let shared = NotchDrop()

    let model = NotchDropModel()
    private let window = NotchWindow()
    /// Takes the drop. A window of its own, sized to the well, so the drawing canvas never
    /// catches a drag meant for the app beneath it.
    private let catcher: NSPanel
    private var monitors: [Any] = []

    private var poll: Timer?
    private var releaseTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var isDropping = false
    /// The drop has said how it went, and closes on its own once that's been read.
    private var hasOutcome = false
    /// Clove's island was open when the drag began, so Shotput waits, unseen, until the drag
    /// comes for the notch, and only then claims it and opens.
    private var isWaitingForCompanion = false

    private var observers: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    /// The tray was clicked open, or clicked into: it stays until Esc or a click elsewhere.
    /// Peeked open by hovering, it closes as the pointer leaves.
    private var isTrayFocused = false
    private init() {
        window.contentView = NotchDropHostingView(model: model)

        catcher = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        catcher.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        catcher.isOpaque = false
        // Fully clear windows let drags through. This one is clear to the eye only.
        catcher.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        catcher.hasShadow = false
        catcher.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        catcher.animationBehavior = .none
        let target = DropTargetView()
        target.drop = self
        catcher.contentView = target
        model.openTray = { [weak self] in self?.openTray(focused: true) }
    }

    /// Listens for drags that start in other apps. A global mouse monitor needs no permission.
    func start() {
        guard monitors.isEmpty else { return }
        NotchApps.listen()
        // Mouse-downs only: a drag is spotted by looking at the drag pasteboard a few times while
        // the button stays down, never by hearing every one of a drag's 120 events a second.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseWentDown() }
        }) {
            monitors.append(monitor)
        }
        installKeyMonitor()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: PinStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pinsChanged() }
        })
        for name in [NotchApps.companionDidChange, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.followActiveDisplay()
                    self?.refreshRest()
                }
            })
        }
        subscriptions.append(Settings.shared.$islandPlacement.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followActiveDisplay()
                self?.refreshRest()
            }
        })
        subscriptions.append(Settings.shared.$showsPinBadge.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRest() }
        })
        followActiveDisplay()
        subscriptions.append(Settings.shared.$pinTarget.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeTray()
                self?.refreshRest()
            }
        })
        refreshRest()
    }

    private var subscriptions: [AnyCancellable] = []

    // MARK: At rest

    /// Pins arrived or left: the badge counts them, and pops when one arrives.
    private func pinsChanged() {
        let count = PinStore.shared.pins.count
        if count > model.total { model.bump += 1 }
        model.total = count
        if model.phase == .tray {
            model.trayView = PinTray.shared.refreshedNotchContent()
        } else {
            refreshRest()
        }
    }

    /// A drag, a moment or the tray has the island: rest waits for it.
    private var isBusy: Bool {
        poll != nil || isDropping || isWaitingForCompanion || !model.isResting
    }

    /// The notch rests as a badge when there are pins, the bare notch when there aren't. With
    /// Clove running, the badge steps aside while Clove's own island is open.
    private var restPhase: NotchDropModel.Phase {
        // The floating island never rests in view: in the middle of the menu bar it would sit
        // over app menus. It shows only while there's a drag, a moment, or the tray.
        guard model.total > 0, Settings.shared.showsPinBadge, !model.isFloating else { return .hidden }
        guard NotchApps.companionIsRunning else { return .badge }
        return NotchApps.companionIsOpen || NotchApps.companionShowsEars ? .hidden : .badge
    }

    /// Clove has ears up and nothing open: the pins step out into a bubble past them.
    private var restShowsSideBubble: Bool {
        model.total > 0 && NotchApps.companionIsRunning && NotchApps.companionShowsEars && !NotchApps.companionIsOpen
    }

    private func sideBubbleRect(_ geometry: NotchGeometry) -> CGRect {
        let size = NotchDropModel.sideBubbleSize
        let midY = geometry.screenFrame.maxY - model.notchSize.height / 2
        return CGRect(x: geometry.midX + model.sideBubbleOffset - size.width / 2, y: midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Where the resting notch answers the pointer, in screen coordinates. Without Clove it's
    /// the notch, its ears, and a sliver below so reaching for it needs no pixel-perfect aim.
    /// With Clove the notch is Clove's, so only the ears, and only while they're showing.
    private func restingHotRects(_ geometry: NotchGeometry) -> [CGRect] {
        // The floating island, out of sight, mustn't catch clicks meant for the menu bar.
        if geometry.isFloating && model.phase == .hidden { return [] }
        let band = model.notchSize.height + 4
        let island = geometry.hangingRect(CGSize(width: model.size(for: .badge).width, height: band))
        // Without ears showing, only the notch itself: the menu bar beside it stays the menu bar's.
        guard NotchApps.companionIsRunning else {
            return [model.phase == .badge ? island : geometry.hangingRect(CGSize(width: model.notchSize.width, height: band))]
        }
        if model.showsSideBubble { return [sideBubbleRect(geometry).insetBy(dx: -4, dy: -4)] }
        guard model.phase == .badge else { return [] }
        let ear = NotchDropModel.earWidth + model.shoulderRadius(for: .badge)
        return [
            CGRect(x: island.minX, y: island.minY, width: ear, height: band),
            CGRect(x: island.maxX - ear, y: island.minY, width: ear, height: band),
        ]
    }

    func refreshRest() {
        model.total = PinStore.shared.pins.count
        guard !isBusy else { return }
        guard Settings.shared.pinTarget == .notch, let geometry = NotchGeometry.resting() else {
            model.showsSideBubble = false
            model.phase = .hidden
            window.orderOut(nil)
            hideZones()
            return
        }
        place(geometry)
        model.phase = restPhase
        model.showsSideBubble = restShowsSideBubble
        if NotchApps.companionIsRunning && model.phase == .hidden && !model.showsSideBubble {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
        updateZones()
    }

    private func place(_ geometry: NotchGeometry) {
        guard model.geometry != geometry || !window.isVisible else { return }
        model.geometry = geometry
        window.setFrame(geometry.windowFrame, display: true)
        window.appearance = geometry.isMenuBar ? nil : NSAppearance(named: .darkAqua)
    }

    // MARK: Following the display you're using

    private var activeObservers: [Any] = []
    private var activeTimer: Timer?

    /// With the island on the display you're using, it moves when you switch apps or windows to
    /// another one. Only while it rests: an open island never jumps out from under the pointer.
    private func followActiveDisplay() {
        activeObservers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        activeObservers = []
        activeTimer?.invalidate()
        activeTimer = nil
        guard Settings.shared.islandPlacement == .active, NSScreen.screens.count > 1 else { return }
        activeObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.moveToActiveDisplay() }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.moveToActiveDisplay() }
            },
        ]
        // Other apps' windows moving between displays don't notify; look now and then.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveToActiveDisplay() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        activeTimer = timer
    }

    private func moveToActiveDisplay() {
        guard !isBusy, let geometry = NotchGeometry.resting(), geometry != model.geometry else { return }
        refreshRest()
    }

    // MARK: The tray

    /// The menu bar icon's left click, with pins at the notch.
    func toggleTray() {
        if model.phase == .tray { closeTray() } else { openTray(focused: true) }
    }

    func openTray(focused: Bool) {
        guard Settings.shared.pinTarget == .notch, poll == nil, !isDropping else { return }
        hoverTask?.cancel()
        leaveTask?.cancel()
        collapseTask?.cancel()
        if model.phase != .tray {
            // A notch stays put; without one, the tray opens on the display you're pointing at.
            guard let resting = NotchGeometry.resting() else { return }
            let geometry = resting.isFloating ? (NotchGeometry.underPointer() ?? resting) : resting
            place(geometry)
            // Clove folds on the claim, so the tray opens out of a bare notch.
            if NotchApps.companionIsRunning { NotchApps.claim() }
            model.showsSideBubble = false
            model.total = PinStore.shared.pins.count
            model.trayView = PinTray.shared.notchContent { [weak self] in self?.closeTray() }
            window.orderFrontRegardless()
            model.phase = .tray
        }
        if focused {
            isTrayFocused = true
            window.allowsKey = true
            window.makeKey()
        }
        hideZones()
        watchPointerForTray()
        followTrayPointer(NSEvent.mouseLocation)
    }

    func closeTray() {
        guard model.phase == .tray else { return }
        hoverTask?.cancel()
        stopWatchingPointer()
        isTrayFocused = false
        if window.isKeyWindow { window.resignKey() }
        window.allowsKey = false
        PinTray.shared.notchDidClose()
        model.phase = restPhase
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            // The tray leaves while the island closes over it.
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, self.model.isResting else { return }
            self.model.trayView = nil
            NotchApps.release()
            self.refreshRest()
        }
    }

    // MARK: Pointer

    /// Esc closes the tray while it holds the keyboard. A local monitor: it hears only keys
    /// already headed for Shotput.
    private func installKeyMonitor() {
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            return MainActor.assumeIsolated {
                guard self.model.phase == .tray else { return event }
                self.closeTray()
                return nil
            }
        }) {
            monitors.append(keys)
        }
    }

    /// At rest the island answers the pointer through small invisible windows over its hot
    /// spots. The window server tracks the pointer over them for free, so Shotput hears nothing
    /// until the pointer is actually there: no wake-up for every mouse move on the Mac.
    private var zones: [HotZone] = []

    private func updateZones() {
        guard let geometry = model.geometry, window.isVisible, model.isResting, !isBusy else { return hideZones() }
        let rects = restingHotRects(geometry)
        while zones.count < rects.count {
            let zone = HotZone(level: NSWindow.Level(rawValue: window.level.rawValue + 1))
            zone.onEnter = { [weak self] in self?.zoneEntered() }
            zone.onExit = { [weak self] in
                self?.hoverTask?.cancel()
                self?.hoverTask = nil
            }
            zone.onClick = { [weak self] in self?.openTray(focused: true) }
            zones.append(zone)
        }
        for (index, zone) in zones.enumerated() {
            if index < rects.count {
                zone.setFrame(rects[index], display: false)
                zone.orderFrontRegardless()
            } else {
                zone.orderOut(nil)
            }
        }
    }

    private func hideZones() {
        hoverTask?.cancel()
        hoverTask = nil
        zones.forEach { $0.orderOut(nil) }
    }

    /// Hovering the badge, or the bubble beside Clove's ears, peeks at the tray. The bare notch
    /// only opens on a click.
    private func zoneEntered() {
        guard model.phase == .badge || (model.phase == .hidden && model.showsSideBubble),
              NSEvent.pressedMouseButtons == 0, hoverTask == nil else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled else { return }
            self.hoverTask = nil
            if self.model.isResting, self.zones.contains(where: { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }) {
                self.openTray(focused: false)
            }
        }
    }

    /// While the tray is open, and only then, Shotput follows the pointer everywhere: to close a
    /// peeked tray as the pointer leaves, and any tray on a click elsewhere.
    private var trayMonitors: [Any] = []

    private func watchPointerForTray() {
        guard trayMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event, isLocal: false) }
        }) {
            trayMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event, isLocal: true) }
            return event
        }) {
            trayMonitors.append(local)
        }
    }

    private func stopWatchingPointer() {
        trayMonitors.forEach(NSEvent.removeMonitor)
        trayMonitors = []
        leaveTask?.cancel()
        leaveTask = nil
        setIgnoresPointer(true)
    }

    /// What `ignoresMouseEvents` was last set to, so the window server only hears about changes.
    private var isIgnoringPointer = true

    private func setIgnoresPointer(_ ignores: Bool) {
        guard ignores != isIgnoringPointer else { return }
        isIgnoringPointer = ignores
        window.ignoresMouseEvents = ignores
    }

    private func handlePointer(_ event: NSEvent, isLocal: Bool) {
        guard model.phase == .tray else { return stopWatchingPointer() }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if isLocal && event.window === window {
                // A click into a peeked tray keeps it open.
                if !isTrayFocused {
                    isTrayFocused = true
                    window.allowsKey = true
                    window.makeKey()
                }
            } else if MenuBarAnchor.frame()?.contains(NSEvent.mouseLocation) == true {
                // Shotput's own menu bar icon: its click toggles the tray, so leave it to that,
                // or the tray would close here and open again on the same click.
            } else {
                // Anywhere else: another app, the menu bar, Shotput's own windows.
                closeTray()
                return
            }
        }
        followTrayPointer(NSEvent.mouseLocation)
    }

    /// Clicks reach the open tray and fall through everywhere else. A peeked tray closes once
    /// the pointer has left it.
    private func followTrayPointer(_ location: CGPoint) {
        guard let geometry = model.geometry, model.phase == .tray else { return }
        let island = geometry.hangingRect(model.size)
        setIgnoresPointer(!island.insetBy(dx: -2, dy: -2).contains(location))
        guard !isTrayFocused else { return }
        // A little slack round the edge, so a pointer that drifts off for a moment doesn't snap it shut.
        if island.insetBy(dx: -14, dy: -14).contains(location) {
            leaveTask?.cancel()
            leaveTask = nil
        } else if leaveTask == nil {
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self, !Task.isCancelled else { return }
                self.leaveTask = nil
                if !self.isTrayFocused { self.closeTray() }
            }
        }
    }

    // MARK: Spotting drags in other apps

    private var dragCheck: Timer?

    /// Something may be about to be dragged. While the button stays down, glance at the drag
    /// pasteboard every tenth of a second for up to a second: a drag that hasn't written it by
    /// then is moving a window or selecting text, not carrying anything.
    private func mouseWentDown() {
        dragCheck?.invalidate()
        dragCheck = nil
        guard Settings.shared.pinsDraggedFiles, poll == nil else { return }
        let baseline = NSPasteboard(name: .drag).changeCount
        let started = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                guard NSEvent.pressedMouseButtons & 1 != 0, Date().timeIntervalSince(started) < 1.1 else {
                    timer.invalidate()
                    self.dragCheck = nil
                    return
                }
                let pasteboard = NSPasteboard(name: .drag)
                // The dragging app writes the pasteboard a moment into the drag, so keep looking.
                guard pasteboard.changeCount != baseline else { return }
                timer.invalidate()
                self.dragCheck = nil
                if let payload = Self.payload(from: pasteboard) { self.arm(payload) }
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        dragCheck = timer
    }

    // MARK: Shotput's own drags

    /// A preview being dragged. Its drag never reaches the global monitor, so it says so itself.
    func beginDragging(_ capture: Capture) {
        var payload = DragPayload(count: 1, capture: capture)
        payload.icons = [NSImage(cgImage: capture.image, size: capture.pointSize)]
        arm(payload)
    }

    /// Files pinned without a drag, by the pin shortcut: the island opens straight onto saying so.
    func announcePinned(_ count: Int, icons: [NSImage]) {
        arm(DragPayload(count: count, icons: icons), polling: false)
        DispatchQueue.main.async { [weak self] in self?.finish(pinned: count) }
    }

    // MARK: Showing

    private func arm(_ payload: DragPayload, polling: Bool = true) {
        let atNotch = Settings.shared.pinTarget == .notch
        guard let geometry = atNotch ? NotchGeometry.underPointer() : NotchGeometry.menuBar() else { return }
        releaseTask?.cancel()
        collapseTask?.cancel()
        isDropping = false
        hasOutcome = false
        isWaitingForCompanion = atNotch && polling && NotchApps.companionIsOpen && !model.isPanel
        if model.phase == .tray {
            // A drag begun from the tray, or over it: the tray gives way to the well.
            isTrayFocused = false
            if window.isKeyWindow { window.resignKey() }
            window.allowsKey = false
            PinTray.shared.notchDidClose()
            model.trayView = nil
            model.phase = restPhase
        }
        hideZones()
        stopWatchingPointer()
        model.showsSideBubble = false

        model.payload = payload
        model.total = PinStore.shared.pins.count
        if model.geometry != geometry || !window.isVisible {
            model.phase = model.isResting && model.geometry == geometry ? model.phase : .hidden
            model.geometry = geometry
            window.setFrame(geometry.windowFrame, display: true)
            window.appearance = geometry.isMenuBar ? nil : NSAppearance(named: .darkAqua)
        }
        // The well's own size, flush with the top, plus a little slack below it.
        let well = geometry.hangingRect(model.size(for: .targeted))
        catcher.setFrame(CGRect(x: well.minX, y: well.minY - 8, width: well.width, height: well.height + 8), display: false)
        guard !isWaitingForCompanion else {
            startPolling()
            return
        }
        show(atNotch: atNotch)

        guard polling else { return }
        // A frame at notch size first, so the island grows out of it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isResting || self.model.isMoment else { return }
            self.model.phase = .armed
            self.track()
        }
        startPolling()
    }

    private func show(atNotch: Bool) {
        if atNotch { NotchApps.claim() }
        window.orderFrontRegardless()
        catcher.orderFrontRegardless()
    }

    /// Follows the pointer while the button is down: near the notch it opens, away it closes
    /// back to ears. Polling works the same for drags from any app, Shotput's included.
    private func startPolling() {
        poll?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func track() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            released()
            return
        }
        guard let geometry = model.geometry else { return }
        let location = NSEvent.mouseLocation
        let reach = geometry.hangingRect(CGSize(width: 600, height: model.notchSize.height + 170))
        if isWaitingForCompanion {
            guard reach.contains(location) else { return }
            // Heading for the notch after all: Clove folds on the claim, and the island opens.
            isWaitingForCompanion = false
            show(atNotch: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.isResting else { return }
                    self.model.phase = .near
            }
            return
        }
        switch model.phase {
        case .armed where reach.contains(location):
            model.phase = .near
        case .near where !reach.contains(location):
            model.phase = .armed
        default:
            break
        }
    }

    private func released() {
        poll?.invalidate()
        poll = nil
        isWaitingForCompanion = false
        // The drop lands just after the button comes up. Give it the moment before closing.
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, !self.isDropping, !self.hasOutcome else { return }
            self.collapse()
        }
    }

    private func collapse(after delay: Duration = .zero) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            self.catcher.orderOut(nil)
            // Back to rest: the badge if there are pins, else the bare notch. When rest is on
            // another display, fade out here first, so the badge never shows on the wrong one.
            self.model.total = PinStore.shared.pins.count
            let isHome = NotchGeometry.resting() == self.model.geometry
            self.model.phase = isHome ? self.restPhase : .hidden
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, self.model.isResting else { return }
            self.model.payload = DragPayload()
            NotchApps.release()
            self.refreshRest()
        }
    }

    // MARK: Dropping

    fileprivate func dragEntered() -> NSDragOperation {
        switch model.phase {
        case .armed, .near, .targeted: break
        default: return []
        }
        if let capture = model.payload.capture, PinStore.shared.contains(capture) {
            model.phase = .alreadyPinned
            return []
        }
        if model.phase != .targeted {
            model.phase = .targeted
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        return .copy
    }

    fileprivate func dragExited() {
        switch model.phase {
        case .targeted: model.phase = .near
        case .alreadyPinned: model.phase = .near
        default: break
        }
    }

    fileprivate func drop(_ pasteboard: NSPasteboard) -> Bool {
        guard model.phase == .targeted else { return false }
        isDropping = true
        if let capture = model.payload.capture {
            guard PinStore.shared.pin(capture) else {
                finish(pinned: 0, already: true)
                return false
            }
            finish(pinned: 1)
            return true
        }

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            Task { finish(pinned: await PinStore.shared.pin(files: urls)) }
            return true
        }

        // Photos, Mail and browsers hand over a promise; the file is written once it's dropped.
        let promises = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
        if !promises.isEmpty, let folder = Self.temporaryFolder() {
            var received: [URL] = []
            let group = DispatchGroup()
            for promise in promises {
                group.enter()
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                    if error == nil { received.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                Task { @MainActor in
                    let count = await PinStore.shared.pin(files: received)
                    try? FileManager.default.removeItem(at: folder)
                    self.finish(pinned: count)
                }
            }
            return true
        }

        // A picture with no file behind it, such as one dragged out of a web page.
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
           let folder = Self.temporaryFolder() {
            let file = folder.appendingPathComponent(ImageCoding.timestampedName())
            guard (try? png.write(to: file)) != nil else { return false }
            Task {
                let count = await PinStore.shared.pin(files: [file])
                try? FileManager.default.removeItem(at: folder)
                finish(pinned: count)
            }
            return true
        }
        finish(pinned: 0)
        return false
    }

    private func finish(pinned count: Int, already: Bool = false) {
        isDropping = false
        hasOutcome = true
        catcher.orderOut(nil)
        model.total = PinStore.shared.pins.count
        if count > 0 {
            model.phase = .pinned(count)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            NotificationCenter.default.post(name: .shotputDidPin, object: nil)
        } else {
            model.phase = already ? .alreadyPinned : .failed
        }
        collapse(after: .milliseconds(count > 0 ? 1500 : 1800))
    }

    // MARK: Reading the drag

    /// What a drag holds, if any of it can be pinned: files, promised files, or a picture.
    static func payload(from pasteboard: NSPasteboard) -> DragPayload? {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            return DragPayload(
                count: urls.count,
                name: urls.count == 1 ? FileManager.default.displayName(atPath: urls[0].path) : nil,
                icons: urls.prefix(3).map(icon(for:))
            )
        }
        let promises = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
        if !promises.isEmpty {
            let icons = promises.prefix(3).map { promise in
                NSWorkspace.shared.icon(for: promise.fileTypes.first.flatMap(UTType.init) ?? .data)
            }
            return DragPayload(count: promises.count, icons: icons)
        }
        if NSImage.canInit(with: pasteboard), let image = NSImage(pasteboard: pasteboard) {
            return DragPayload(count: 1, icons: [image])
        }
        return nil
    }

    /// By kind, not by reading the file: until it's dropped the sandbox can't see it.
    private static func icon(for url: URL) -> NSImage {
        let type = url.hasDirectoryPath ? UTType.folder : (UTType(filenameExtension: url.pathExtension) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }

    private static func temporaryFolder() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Dropped-\(UUID().uuidString)", isDirectory: true)
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil ? folder : nil
    }
}

extension Notification.Name {
    static let shotputDidPin = Notification.Name("ShotputDidPin")
}

/// Where the Shotput icon sits in the menu bar, in screen coordinates. Set by the app delegate.
@MainActor
enum MenuBarAnchor {
    static var frame: () -> CGRect? = { nil }

    /// The point pins fly to: the icon, or the top centre of the screen when it is hidden.
    static func target(on screen: NSScreen?) -> CGRect {
        if let frame = frame(), frame.width > 0 { return frame }
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        return CGRect(x: screen.frame.midX - 11, y: screen.frame.maxY - 22, width: 22, height: 22)
    }
}

/// The island's canvas. Drags go to the catcher; clicks reach it only where the island rests or
/// is open, and it takes the keyboard only while the tray is clicked open, for Esc.
final class NotchWindow: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: NotchGeometry.canvas),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar, so the island can cover it, and a step above Clove's island, so
        // during a drag Shotput's is the one in front.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The island draws its own shadow, only once it's open; a window shadow would outline
        // the whole canvas.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }
}

/// The catcher's one view: hands every drag event to the controller.
private final class DropTargetView: NSView {
    weak var drop: NotchDrop?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drop?.dragEntered() ?? [] }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drop?.model.phase == .targeted ? .copy : [] }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { drop?.dragExited() }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        return MainActor.assumeIsolated { drop?.drop(pasteboard) ?? false }
    }
}

/// An invisible window over one of the resting island's hot spots. It hears the pointer arrive,
/// leave and click there, and nothing anywhere else.
private final class HotZone: NSPanel {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onClick: () -> Void = {}

    init(level: NSWindow.Level) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.level = level
        isOpaque = false
        // Fully clear windows let the pointer through. This one is clear to the eye only.
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = ZoneView()
        view.zone = self
        contentView = view
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L("Show pins"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private final class ZoneView: NSView {
        weak var zone: HotZone?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseEntered(with event: NSEvent) { zone?.onEnter() }
        override func mouseExited(with event: NSEvent) { zone?.onExit() }
        override func mouseDown(with event: NSEvent) { zone?.onClick() }
    }
}

import AppKit
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
    }

    var phase: Phase = .hidden
    var geometry: NotchGeometry?
    var payload = DragPayload()
    /// How many pins the tray holds, for "4 of 15".
    var total = 0

    var isHardware: Bool { geometry?.isHardware ?? true }
    var isMenuBar: Bool { geometry?.isMenuBar ?? false }
    var notchSize: CGSize { geometry?.size ?? CGSize(width: 190, height: 32) }

    var isPanel: Bool {
        switch phase {
        case .hidden, .armed: false
        default: true
        }
    }

    var isMoment: Bool {
        switch phase {
        case .pinned, .alreadyPinned, .failed: true
        default: false
        }
    }

    // MARK: Size

    static let shoulder: CGFloat = 10
    static let earWidth: CGFloat = 34

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
        case .armed: body = CGSize(width: notch.width + Self.earWidth * 2, height: notch.height)
        case .near: body = CGSize(width: max(360, notch.width + 150), height: notch.height + 84)
        case .targeted: body = CGSize(width: max(388, notch.width + 178), height: notch.height + 96)
        case .pinned, .alreadyPinned, .failed: body = CGSize(width: max(340, notch.width + 130), height: notch.height + 60)
        }
        return CGSize(width: body.width + shoulderRadius(for: phase) * 2, height: body.height)
    }

    var size: CGSize { size(for: phase) }

    /// The card under the menu bar icon: a small pill while a drag is elsewhere, the well as it
    /// comes close.
    func cardSize(for phase: Phase) -> CGSize {
        switch phase {
        case .hidden: CGSize(width: 64, height: 30)
        case .armed: CGSize(width: 68, height: 30)
        case .near: CGSize(width: 360, height: 84)
        case .targeted: CGSize(width: 388, height: 96)
        case .pinned, .alreadyPinned, .failed: CGSize(width: 340, height: 60)
        }
    }

    var cardRadius: CGFloat {
        switch phase {
        case .hidden, .armed: 15
        default: 24
        }
    }

    func shoulderRadius(for phase: Phase) -> CGFloat {
        switch phase {
        case .hidden, .armed: 6
        default: Self.shoulder
        }
    }

    var shoulderRadius: CGFloat { shoulderRadius(for: phase) }

    var bottomRadius: CGFloat {
        switch phase {
        case .hidden, .armed: isHardware ? 10 : notchSize.height / 2
        case .pinned, .alreadyPinned, .failed: 22
        case .near, .targeted: 26
        }
    }
}

/// Puts a drop target in the notch while anything pinnable is dragged: a preview, or files from
/// Finder or any other app. The notch grows ears as the drag starts, opens into a well as it comes
/// close, and pins what's let go over it. The rest of the time there is nothing there, and no
/// click ever lands on it. With another notch app in charge of the notch, Settings can hang the
/// same well under the menu bar icon instead.
@MainActor
final class NotchDrop {
    static let shared = NotchDrop()

    let model = NotchDropModel()
    private let window = NotchWindow()
    /// Takes the drop. A window of its own, sized to the well, so the drawing canvas never
    /// catches a drag meant for the app beneath it.
    private let catcher: NSPanel
    private var monitors: [Any] = []

    /// The drag pasteboard's count when the mouse went down; a new count means a drag began.
    private var changeCountAtMouseDown = 0
    private var isWatchingForDrag = false
    private var poll: Timer?
    private var releaseTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var isDropping = false
    /// The drop has said how it went, and closes on its own once that's been read.
    private var hasOutcome = false
    /// Clove's island was open when the drag began, so Shotput waits, unseen, until the drag
    /// comes for the notch, and only then claims it and opens.
    private var isWaitingForCompanion = false

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
    }

    /// Listens for drags that start in other apps. A global mouse monitor needs no permission.
    func start() {
        guard monitors.isEmpty else { return }
        NotchApps.listen()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }) {
            monitors.append(monitor)
        }
    }

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            isWatchingForDrag = true
        case .leftMouseDragged:
            guard isWatchingForDrag, Settings.shared.pinsDraggedFiles else { return }
            let pasteboard = NSPasteboard(name: .drag)
            // The dragging app writes the pasteboard a moment into the drag, so keep looking.
            guard pasteboard.changeCount != changeCountAtMouseDown else { return }
            isWatchingForDrag = false
            if let payload = Self.payload(from: pasteboard) { arm(payload) }
        default:
            isWatchingForDrag = false
        }
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

        model.payload = payload
        model.total = PinStore.shared.pins.count
        if model.geometry != geometry || !window.isVisible {
            model.phase = .hidden
            model.geometry = geometry
            window.setFrame(geometry.windowFrame, display: true)
            window.appearance = geometry.isHardware ? NSAppearance(named: .darkAqua) : nil
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
            guard let self, self.model.phase == .hidden || self.model.isMoment else { return }
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
                guard let self, self.model.phase == .hidden else { return }
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
            self.model.phase = .hidden
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, self.model.phase == .hidden else { return }
            self.window.orderOut(nil)
            self.model.payload = DragPayload()
            NotchApps.release()
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

/// The island's canvas. It never takes a click or a drag: the catcher does.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { false }
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

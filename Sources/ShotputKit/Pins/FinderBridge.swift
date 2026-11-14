import AppKit
import Carbon.HIToolbox
import Combine

/// Shotput's two Finder keys, done with keystrokes Finder already understands, so nothing about
/// your files goes through Shotput but the ones you pin:
/// - ⌘X cuts. While Finder is in front Shotput holds ⌘X, presses ⌘C for you and remembers it was
///   a cut; the next ⌘V becomes ⌥⌘V, Finder's own Move Item Here. In a name being edited, ⌘X
///   still cuts the text.
/// - The pin shortcut copies the selection from the app in front, puts your clipboard back as it
///   was, and pins the files.
/// Pressing keys in another app needs Accessibility, asked for the first time either is used.
@MainActor
final class FinderBridge {
    static let shared = FinderBridge()

    private static let finder = "com.apple.finder"
    private let keys = HotKeyCenter(signature: 0x5348_4658)
    private var subscriptions = Set<AnyCancellable>()
    /// The clipboard's count right after a cut's copy. A later copy anywhere replaces the cut.
    private var cutChangeCount: Int?
    private var cutCount = 0

    func start() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.updateKeys() }
            .store(in: &subscriptions)
        Settings.shared.$cutsInFinder
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                if on, !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }
                self?.updateKeys()
            }
            .store(in: &subscriptions)
    }

    private var finderIsFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finder
    }

    private var isCutPending: Bool {
        cutChangeCount != nil && cutChangeCount == NSPasteboard.general.changeCount
    }

    /// ⌘X, and ⌘V while a cut waits, belong to Shotput only while Finder is in front. Everywhere
    /// else they're the app's own.
    private func updateKeys() {
        guard Settings.shared.cutsInFinder, finderIsFront else {
            keys.unregisterAll()
            return
        }
        var bindings: [(shortcut: Shortcut, action: () -> Void)] = [
            (Shortcut(keyCode: kVK_ANSI_X, .command), { MainActor.assumeIsolated { FinderBridge.shared.cut() } }),
        ]
        if isCutPending {
            bindings.append((Shortcut(keyCode: kVK_ANSI_V, .command), { MainActor.assumeIsolated { FinderBridge.shared.paste() } }))
        }
        keys.register(bindings)
    }

    // MARK: Cut and move

    private func cut() {
        guard ensureKeyAccess() else { return }
        let before = NSPasteboard.general.changeCount
        press(kVK_ANSI_C, .maskCommand)
        Task {
            guard await clipboardChanged(since: before) else { return }
            let files = Self.files(on: .general)
            if files.isEmpty {
                // Editing a name: the text was copied, so take it out to make it a cut.
                press(kVK_Delete, [])
                cutChangeCount = nil
            } else {
                cutChangeCount = NSPasteboard.general.changeCount
                cutCount = files.count
                HUD.show(files.count == 1 ? "Cut \(files[0].lastPathComponent). ⌘V moves it." : "Cut \(files.count) items. ⌘V moves them.", icon: .scissors)
            }
            updateKeys()
        }
    }

    private func paste() {
        let moving = isCutPending
        // Let go of ⌘V first, so the keystroke sent below isn't caught by Shotput again.
        cutChangeCount = nil
        keys.unregisterAll()
        if moving {
            press(kVK_ANSI_V, [.maskCommand, .maskAlternate])
            HUD.show(cutCount == 1 ? "Moved 1 item" : "Moved \(cutCount) items", icon: .move)
        } else {
            press(kVK_ANSI_V, .maskCommand)
        }
        updateKeys()
    }

    // MARK: Pinning the selection

    /// Copies what's selected in the app in front, Finder or any file manager, and pins the files
    /// it hands over. The clipboard is put back as it was.
    func pinSelection() {
        guard ensureKeyAccess() else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let origin = Self.frontWindowCenter(of: front)
        let saved = Self.snapshot(.general)
        let before = NSPasteboard.general.changeCount
        press(kVK_ANSI_C, .maskCommand)
        Task {
            let changed = await clipboardChanged(since: before)
            let files = changed ? Self.files(on: .general) : []
            Self.restore(saved, to: .general)
            // The restored clipboard isn't a cut any more.
            cutChangeCount = nil
            guard !files.isEmpty else {
                HUD.show("Select files to pin first", icon: .pin)
                return
            }
            let icons = files.prefix(3).map { NSWorkspace.shared.icon(forFile: $0.path) }
            let count = await PinStore.shared.pin(files: files)
            guard count > 0 else {
                HUD.show("Couldn’t pin that", icon: .warning)
                return
            }
            PinFlight.fly(icons, from: origin) {
                NotchDrop.shared.announcePinned(count, icons: Array(icons))
            }
        }
    }

    // MARK: Keystrokes

    /// Asks once; until it's allowed, says where to allow it.
    private func ensureKeyAccess() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        CGRequestPostEventAccess()
        HUD.show("Allow Shotput in Accessibility, then try again", icon: .lock)
        return false
    }

    /// One key with exactly these modifiers, whatever is held down: the shortcut that got here
    /// may still have ⌃⌥ pressed.
    private func press(_ key: Int, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// The app answers a copy in a few milliseconds; a busy one gets up to half a second.
    private func clipboardChanged(since count: Int) async -> Bool {
        for _ in 0 ..< 25 {
            if NSPasteboard.general.changeCount != count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    // MARK: Clipboard

    static func files(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }

    /// Where the files fly from: the middle of the front app's front window, which is where the
    /// selection almost always is. Window bounds need no permission; only their contents would.
    private static func frontWindowCenter(of app: NSRunningApplication?) -> CGPoint {
        let fallback = NSEvent.mouseLocation
        guard let pid = app?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]],
              let window = windows.first(where: { ($0[kCGWindowOwnerPID] as? pid_t) == pid && ($0[kCGWindowLayer] as? Int) == 0 }),
              let bounds = window[kCGWindowBounds].flatMap({ CGRect(dictionaryRepresentation: $0 as! CFDictionary) }),
              let primary = NSScreen.screens.first else { return fallback }
        // Window bounds count down from the top of the main screen; AppKit counts up.
        return CGPoint(x: bounds.midX, y: primary.frame.maxY - bounds.midY)
    }
}

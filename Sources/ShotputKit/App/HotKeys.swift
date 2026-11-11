import AppKit
import Carbon.HIToolbox

/// A key plus modifiers. Stored in defaults and registered as a system-wide hotkey.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, limited to command, option, control, and shift.
    var modifiers: UInt

    static let none = Shortcut(keyCode: .max, modifiers: 0)
    static let allowedFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: Int, _ flags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt16(keyCode), modifiers: flags.intersection(Self.allowedFlags).rawValue)
    }

    var isSet: Bool { keyCode != .max }
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var display: String {
        guard isSet else { return "" }
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + keyName
    }

    var keyName: String {
        if let special = Self.specialKeys[Int(keyCode)] { return special }
        // Ask the current layout what this key prints, so the label is right on any keyboard.
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    /// Function keys make fine shortcuts on their own. Everything else needs a real modifier.
    var isAcceptable: Bool {
        let name = Self.specialKeys[Int(keyCode)] ?? ""
        let isFunctionKey = name.hasPrefix("F") && name.count > 1
        return isFunctionKey || !flags.isDisjoint(with: [.command, .option, .control])
    }
}

/// Things a shortcut, a mouse button, or a URL can trigger.
enum HotAction: String, CaseIterable, Identifiable {
    case area, areaAnnotate, window, screen, annotateLast, repeatArea, text, annotateClipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Capture area"
        case .areaAnnotate: "Capture area and annotate"
        case .window: "Capture window"
        case .screen: "Capture screen"
        case .annotateLast: "Annotate last capture"
        case .repeatArea: "Repeat last area"
        case .text: "Copy text from area"
        case .annotateClipboard: "Annotate clipboard image"
        }
    }

    var icon: Icon {
        switch self {
        case .area: .capture
        case .areaAnnotate: .annotate
        case .window: .window
        case .screen: .screen
        case .annotateLast: .clock
        case .repeatArea: .refresh
        case .text: .readText
        case .annotateClipboard: .clipboard
        }
    }

    /// One line on what the action does, for Settings and the welcome guide.
    var detail: String {
        switch self {
        case .area: "Drag an area. It is on the clipboard when you let go."
        case .areaAnnotate: "Same, then the editor opens where you captured."
        case .window: "Click a window to get it alone, with clean corners."
        case .screen: "The whole display under the pointer."
        case .annotateLast: "Opens the most recent capture in the editor."
        case .repeatArea: "Captures the same area as last time, with no selection."
        case .text: "Drag over any text and it is copied as text."
        case .annotateClipboard: "Opens the image on the clipboard in the editor."
        }
    }

    var defaultShortcut: Shortcut {
        let hyper: NSEvent.ModifierFlags = [.control, .option, .command]
        return switch self {
        case .area: Shortcut(keyCode: kVK_ANSI_A, hyper)
        case .areaAnnotate: Shortcut(keyCode: kVK_ANSI_D, hyper)
        case .window: Shortcut(keyCode: kVK_ANSI_W, hyper)
        case .screen: Shortcut(keyCode: kVK_ANSI_S, hyper)
        case .annotateLast: Shortcut(keyCode: kVK_ANSI_E, hyper)
        case .text: Shortcut(keyCode: kVK_ANSI_T, hyper)
        case .repeatArea, .annotateClipboard: .none
        }
    }

    @MainActor
    func perform() {
        let coordinator = CaptureCoordinator.shared
        switch self {
        case .area: coordinator.capture(.area)
        case .areaAnnotate: coordinator.capture(.area, annotate: true)
        case .window: coordinator.capture(.window)
        case .screen: coordinator.capture(.screen)
        case .annotateLast: coordinator.annotateLast()
        case .repeatArea: coordinator.repeatLastArea()
        case .text: coordinator.capture(.area, readText: true)
        case .annotateClipboard: coordinator.annotateClipboard()
        }
    }
}

/// System-wide hotkeys through Carbon. Event driven, needs no Accessibility permission, and costs
/// nothing while idle. Synthetic keystrokes from Logi Options+ arrive the same way as real ones.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var isInstalled = false

    func register(_ bindings: [(shortcut: Shortcut, action: () -> Void)]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, binding) in bindings.enumerated() where binding.shortcut.isSet {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.shortcut.keyCode), binding.shortcut.carbonModifiers,
                EventHotKeyID(signature: 0x5348_5054, id: id), GetEventDispatcherTarget(), 0, &reference
            )
            if status == noErr, let reference {
                references.append(reference)
                handlers[id] = binding.action
            }
        }
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr else { return status }
            Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().handlers[id.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Registers every action's current shortcut.
    @MainActor
    static func reload() {
        let shortcuts = Settings.shared.shortcuts
        shared.register(HotAction.allCases.map { action in
            (shortcuts[action] ?? action.defaultShortcut, { MainActor.assumeIsolated { action.perform() } })
        })
    }
}

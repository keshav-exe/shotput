import AppKit
import Combine

final class Settings: ObservableObject {
    enum Key {
        static let afterCapture = "afterCapture"
        static let previewCorner = "previewCorner"
        static let previewDuration = "previewDuration"
        static let copyAtPointSize = "copyAtPointSize"
        static let savesEveryCapture = "savesEveryCapture"
        static let saveFolder = "saveFolderBookmark"
        static let shortcuts = "shortcuts"
        static let overlayHints = "overlayHintsShown"
        static let hasLaunched = "hasLaunched"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let playsSound = "playsSound"
        static let allowsLinks = "allowsLinks"
        static let showsMagnifier = "showsMagnifier"
        static let snapsToEdges = "snapsToEdges"
        static let selectionHints = "selectionHints"
        static let showsPointer = "showsPointer"
        static let windowShadow = "windowShadow"
        static let windowBackground = "windowBackground"
        static let windowBackgroundColor = "windowBackgroundColor"
        static let windowPadding = "windowPadding"
        static let saveFormat = "saveFormat"
        static let jpegQuality = "jpegQuality"
        static let filenameTemplate = "filenameTemplate"
        static let ocrKeepsLineBreaks = "ocrKeepsLineBreaks"
        static let ocrLanguageCorrection = "ocrLanguageCorrection"
        static let editorClosesOnCopy = "editorClosesOnCopy"
        static let escapeInEditor = "escapeInEditor"
        static let recognizesShapes = "recognizesShapes"
        static let capturesOwnWindows = "capturesOwnWindows"
        static let macScreenshotFolder = "macScreenshotFolderBookmark"
        static let restoresMacThumbnail = "restoresMacThumbnail"
        static let shortcutsBeforeScreenshotKeys = "shortcutsBeforeScreenshotKeys"
    }

    enum AfterCapture: String, CaseIterable, Identifiable {
        case preview, editor, clipboard
        var id: String { rawValue }
        var title: String {
            switch self {
            case .preview: L("Show a preview")
            case .editor: L("Open the editor")
            case .clipboard: L("Copy quietly")
            }
        }
    }

    enum Corner: String, CaseIterable, Identifiable {
        case automatic, bottomLeft, bottomRight, topLeft, topRight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: L("Nearest the pointer")
            case .bottomLeft: L("Bottom left")
            case .bottomRight: L("Bottom right")
            case .topLeft: L("Top left")
            case .topRight: L("Top right")
            }
        }
    }

    enum Hints: String, CaseIterable, Identifiable {
        case firstFew, always, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .firstFew: L("First few captures")
            case .always: L("Always")
            case .never: L("Never")
            }
        }
    }

    enum WindowBackground: String, CaseIterable, Identifiable {
        case transparent, wallpaper, solid
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transparent: L("None")
            case .wallpaper: L("Wallpaper")
            case .solid: L("Solid colour")
            }
        }
    }

    enum SaveFormat: String, CaseIterable, Identifiable {
        case png, jpeg, heic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            }
        }
        var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
    }

    enum EscapeInEditor: String, CaseIterable, Identifiable {
        case discard, copy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .discard: L("Closes without copying")
            case .copy: L("Copies and closes")
            }
        }
    }

    static let defaultTemplate = "Shotput %Y-%m-%d at %H.%M.%S"

    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var afterCapture: AfterCapture { didSet { store(afterCapture.rawValue, Key.afterCapture) } }
    @Published var previewCorner: Corner { didSet { store(previewCorner.rawValue, Key.previewCorner) } }
    /// Seconds before the preview leaves on its own. Zero keeps it until dismissed.
    @Published var previewDuration: Double { didSet { store(previewDuration, Key.previewDuration) } }
    @Published var copyAtPointSize: Bool { didSet { store(copyAtPointSize, Key.copyAtPointSize) } }
    @Published var savesEveryCapture: Bool { didSet { store(savesEveryCapture, Key.savesEveryCapture) } }
    @Published private(set) var saveFolder: URL?
    /// The folder macOS saves screenshots to, when Shotput previews them. Nil when it doesn't.
    @Published private(set) var screenshotFolder: URL?
    @Published var shortcuts: [HotAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: Key.shortcuts)
        }
    }

    @Published var showsMenuBarIcon: Bool { didSet { store(showsMenuBarIcon, Key.showsMenuBarIcon) } }
    @Published var playsSound: Bool { didSet { store(playsSound, Key.playsSound) } }
    @Published var allowsLinks: Bool { didSet { store(allowsLinks, Key.allowsLinks) } }

    @Published var showsMagnifier: Bool { didSet { store(showsMagnifier, Key.showsMagnifier) } }
    @Published var snapsToEdges: Bool { didSet { store(snapsToEdges, Key.snapsToEdges) } }
    @Published var selectionHints: Hints { didSet { store(selectionHints.rawValue, Key.selectionHints) } }
    @Published var showsPointer: Bool { didSet { store(showsPointer, Key.showsPointer) } }
    /// Whether Settings, the editor, and the guide can be captured like any other app's windows.
    @Published var capturesOwnWindows: Bool { didSet { store(capturesOwnWindows, Key.capturesOwnWindows) } }

    @Published var windowShadow: Bool { didSet { store(windowShadow, Key.windowShadow) } }
    @Published var windowBackground: WindowBackground { didSet { store(windowBackground.rawValue, Key.windowBackground) } }
    @Published var windowBackgroundColor: NSColor {
        didSet {
            defaults.set(try? NSKeyedArchiver.archivedData(withRootObject: windowBackgroundColor, requiringSecureCoding: true),
                         forKey: Key.windowBackgroundColor)
        }
    }
    /// Points of background around a window capture, when the background is not transparent.
    @Published var windowPadding: Double { didSet { store(windowPadding, Key.windowPadding) } }

    @Published var saveFormat: SaveFormat { didSet { store(saveFormat.rawValue, Key.saveFormat) } }
    @Published var jpegQuality: Double { didSet { store(jpegQuality, Key.jpegQuality) } }
    @Published var filenameTemplate: String { didSet { store(filenameTemplate, Key.filenameTemplate) } }

    @Published var ocrKeepsLineBreaks: Bool { didSet { store(ocrKeepsLineBreaks, Key.ocrKeepsLineBreaks) } }
    @Published var ocrLanguageCorrection: Bool { didSet { store(ocrLanguageCorrection, Key.ocrLanguageCorrection) } }

    @Published var editorClosesOnCopy: Bool { didSet { store(editorClosesOnCopy, Key.editorClosesOnCopy) } }
    @Published var escapeInEditor: EscapeInEditor { didSet { store(escapeInEditor.rawValue, Key.escapeInEditor) } }
    @Published var recognizesShapes: Bool { didSet { store(recognizesShapes, Key.recognizesShapes) } }

    /// The backdrop window captures get, or nil to keep them on transparency.
    var windowBackdrop: Backdrop.Style? {
        switch windowBackground {
        case .transparent: nil
        case .wallpaper: Backdrop.Style(fill: .wallpaper, padding: windowPadding)
        case .solid: Backdrop.Style(fill: .color(windowBackgroundColor), padding: windowPadding)
        }
    }

    private static let registered: [String: Any] = [
        Key.previewDuration: 6.0,
        Key.showsMenuBarIcon: true,
        Key.playsSound: false,
        Key.allowsLinks: true,
        Key.showsMagnifier: true,
        Key.snapsToEdges: true,
        Key.windowShadow: false,
        Key.windowPadding: 48.0,
        Key.jpegQuality: 0.85,
        Key.filenameTemplate: defaultTemplate,
        Key.ocrKeepsLineBreaks: true,
        Key.ocrLanguageCorrection: true,
        Key.recognizesShapes: true,
    ]

    private init() {
        defaults.register(defaults: Self.registered)
        afterCapture = AfterCapture(rawValue: defaults.string(forKey: Key.afterCapture) ?? "") ?? .preview
        previewCorner = Corner(rawValue: defaults.string(forKey: Key.previewCorner) ?? "") ?? .automatic
        previewDuration = defaults.double(forKey: Key.previewDuration)
        copyAtPointSize = defaults.bool(forKey: Key.copyAtPointSize)
        savesEveryCapture = defaults.bool(forKey: Key.savesEveryCapture)

        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        playsSound = defaults.bool(forKey: Key.playsSound)
        allowsLinks = defaults.bool(forKey: Key.allowsLinks)
        showsMagnifier = defaults.bool(forKey: Key.showsMagnifier)
        snapsToEdges = defaults.bool(forKey: Key.snapsToEdges)
        selectionHints = Hints(rawValue: defaults.string(forKey: Key.selectionHints) ?? "") ?? .firstFew
        showsPointer = defaults.bool(forKey: Key.showsPointer)
        capturesOwnWindows = defaults.bool(forKey: Key.capturesOwnWindows)
        windowShadow = defaults.bool(forKey: Key.windowShadow)
        windowBackground = WindowBackground(rawValue: defaults.string(forKey: Key.windowBackground) ?? "") ?? .transparent
        windowBackgroundColor = defaults.data(forKey: Key.windowBackgroundColor)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }
            ?? NSColor(hex: 0xE9E6DF)
        windowPadding = defaults.double(forKey: Key.windowPadding)
        saveFormat = SaveFormat(rawValue: defaults.string(forKey: Key.saveFormat) ?? "") ?? .png
        jpegQuality = defaults.double(forKey: Key.jpegQuality)
        filenameTemplate = defaults.string(forKey: Key.filenameTemplate) ?? Self.defaultTemplate
        ocrKeepsLineBreaks = defaults.bool(forKey: Key.ocrKeepsLineBreaks)
        ocrLanguageCorrection = defaults.bool(forKey: Key.ocrLanguageCorrection)
        editorClosesOnCopy = defaults.bool(forKey: Key.editorClosesOnCopy)
        escapeInEditor = EscapeInEditor(rawValue: defaults.string(forKey: Key.escapeInEditor) ?? "") ?? .discard
        recognizesShapes = defaults.bool(forKey: Key.recognizesShapes)

        var loaded: [HotAction: Shortcut] = [:]
        if let data = defaults.data(forKey: Key.shortcuts),
           let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (name, shortcut) in stored {
                if let action = HotAction(rawValue: name) { loaded[action] = shortcut }
            }
        }
        for action in HotAction.allCases where loaded[action] == nil {
            loaded[action] = action.defaultShortcut
        }
        shortcuts = loaded
        saveFolder = Self.resolveBookmark(defaults.data(forKey: Key.saveFolder))
        screenshotFolder = Self.resolveBookmark(defaults.data(forKey: Key.macScreenshotFolder))
    }

    private func store(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    /// Puts every preference back to how it ships. The save folder and the welcome guide are kept.
    func resetToDefaults() {
        afterCapture = .preview
        previewCorner = .automatic
        previewDuration = 6
        copyAtPointSize = false
        savesEveryCapture = false
        shortcuts = Dictionary(uniqueKeysWithValues: HotAction.allCases.map { ($0, $0.defaultShortcut) })
        showsMenuBarIcon = true
        playsSound = false
        allowsLinks = true
        showsMagnifier = true
        snapsToEdges = true
        selectionHints = .firstFew
        showsPointer = false
        capturesOwnWindows = false
        windowShadow = false
        windowBackground = .transparent
        windowBackgroundColor = NSColor(hex: 0xE9E6DF)
        windowPadding = 48
        saveFormat = .png
        jpegQuality = 0.85
        filenameTemplate = Self.defaultTemplate
        ocrKeepsLineBreaks = true
        ocrLanguageCorrection = true
        editorClosesOnCopy = false
        escapeInEditor = .discard
        recognizesShapes = true
    }

    // MARK: Save folder

    /// The sandbox only lets Shotput write where you point it, so the choice is kept as a
    /// security-scoped bookmark.
    func setSaveFolder(_ url: URL?) {
        guard let url else {
            defaults.removeObject(forKey: Key.saveFolder)
            saveFolder = nil
            savesEveryCapture = false
            return
        }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        defaults.set(bookmark, forKey: Key.saveFolder)
        saveFolder = url
    }

    func resolvedSaveFolder() -> URL? { saveFolder }

    private static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    }

    // MARK: macOS screenshots

    func setScreenshotFolder(_ url: URL?) {
        guard let url, let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) else {
            defaults.removeObject(forKey: Key.macScreenshotFolder)
            screenshotFolder = nil
            return
        }
        defaults.set(bookmark, forKey: Key.macScreenshotFolder)
        screenshotFolder = url
    }

    /// Whether ⇧⌘3, ⇧⌘4 and ⇧⌘5 are Shotput's.
    var usesScreenshotKeys: Bool { ScreenshotKeys.isTaken(shortcuts) }

    /// Puts Shotput's screen, area, and annotate captures on the keys macOS uses for screenshots,
    /// and back to what they were before.
    func setUsesScreenshotKeys(_ on: Bool) {
        if on {
            let before = Dictionary(uniqueKeysWithValues: ScreenshotKeys.bindings.keys.map { ($0.rawValue, shortcuts[$0] ?? Shortcut.none) })
            defaults.set(try? JSONEncoder().encode(before), forKey: Key.shortcutsBeforeScreenshotKeys)
            var next = shortcuts
            // Anything else already on those keys lets go of them.
            for (action, shortcut) in next where ScreenshotKeys.bindings.values.contains(shortcut) { next[action] = Shortcut.none }
            for (action, shortcut) in ScreenshotKeys.bindings { next[action] = shortcut }
            shortcuts = next
        } else {
            var next = shortcuts
            let before = defaults.data(forKey: Key.shortcutsBeforeScreenshotKeys)
                .flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) } ?? [:]
            for action in ScreenshotKeys.bindings.keys {
                next[action] = before[action.rawValue] ?? action.defaultShortcut
            }
            shortcuts = next
            defaults.removeObject(forKey: Key.shortcutsBeforeScreenshotKeys)
        }
    }

    // MARK: First-run touches

    /// Whether the selection hint shows this time. By default it shows for the first few captures.
    func consumeOverlayHint() -> Bool {
        switch selectionHints {
        case .always: return true
        case .never: return false
        case .firstFew:
            let shown = defaults.integer(forKey: Key.overlayHints)
            guard shown < 4 else { return false }
            defaults.set(shown + 1, forKey: Key.overlayHints)
            return true
        }
    }

    func consumeFirstLaunch() -> Bool {
        guard !defaults.bool(forKey: Key.hasLaunched) else { return false }
        defaults.set(true, forKey: Key.hasLaunched)
        return true
    }
}

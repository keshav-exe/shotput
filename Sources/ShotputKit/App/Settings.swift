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
    }

    enum AfterCapture: String, CaseIterable, Identifiable {
        case preview, editor, clipboard
        var id: String { rawValue }
        var title: String {
            switch self {
            case .preview: "Show a preview"
            case .editor: "Open the editor"
            case .clipboard: "Copy quietly"
            }
        }
    }

    enum Corner: String, CaseIterable, Identifiable {
        case automatic, bottomLeft, bottomRight, topLeft, topRight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Nearest the pointer"
            case .bottomLeft: "Bottom left"
            case .bottomRight: "Bottom right"
            case .topLeft: "Top left"
            case .topRight: "Top right"
            }
        }
    }

    enum Hints: String, CaseIterable, Identifiable {
        case firstFew, always, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .firstFew: "First few captures"
            case .always: "Always"
            case .never: "Never"
            }
        }
    }

    enum WindowBackground: String, CaseIterable, Identifiable {
        case transparent, wallpaper, solid
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transparent: "None"
            case .wallpaper: "Wallpaper"
            case .solid: "Solid colour"
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
            case .discard: "Closes without copying"
            case .copy: "Copies and closes"
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

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

    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var afterCapture: AfterCapture { didSet { defaults.set(afterCapture.rawValue, forKey: Key.afterCapture) } }
    @Published var previewCorner: Corner { didSet { defaults.set(previewCorner.rawValue, forKey: Key.previewCorner) } }
    /// Seconds before the preview leaves on its own. Zero keeps it until dismissed.
    @Published var previewDuration: Double { didSet { defaults.set(previewDuration, forKey: Key.previewDuration) } }
    @Published var copyAtPointSize: Bool { didSet { defaults.set(copyAtPointSize, forKey: Key.copyAtPointSize) } }
    @Published var savesEveryCapture: Bool { didSet { defaults.set(savesEveryCapture, forKey: Key.savesEveryCapture) } }
    @Published private(set) var saveFolder: URL?
    @Published var shortcuts: [HotAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: Key.shortcuts)
        }
    }

    private init() {
        defaults.register(defaults: [Key.previewDuration: 6.0])
        afterCapture = AfterCapture(rawValue: defaults.string(forKey: Key.afterCapture) ?? "") ?? .preview
        previewCorner = Corner(rawValue: defaults.string(forKey: Key.previewCorner) ?? "") ?? .automatic
        previewDuration = defaults.double(forKey: Key.previewDuration)
        copyAtPointSize = defaults.bool(forKey: Key.copyAtPointSize)
        savesEveryCapture = defaults.bool(forKey: Key.savesEveryCapture)

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

    /// The selection hint shows for the first few captures, then stays out of the way.
    func consumeOverlayHint() -> Bool {
        let shown = defaults.integer(forKey: Key.overlayHints)
        guard shown < 4 else { return false }
        defaults.set(shown + 1, forKey: Key.overlayHints)
        return true
    }

    func consumeFirstLaunch() -> Bool {
        guard !defaults.bool(forKey: Key.hasLaunched) else { return false }
        defaults.set(true, forKey: Key.hasLaunched)
        return true
    }
}

import AppKit
import UniformTypeIdentifiers

/// One screenshot and where on screen it came from. Mutable state is guarded by a lock.
final class Capture: @unchecked Sendable {
    private(set) var image: CGImage
    /// Pixels per point.
    let scale: CGFloat
    /// Global Cocoa coordinates of the captured region, when it maps to one.
    let screenRect: CGRect?
    let screen: NSScreen?
    let date = Date()
    let id = UUID()
    /// The app that was in front when the capture was taken, for the file name template.
    var appName: String?
    /// Set when the capture was put on a backdrop as it was taken. The editor starts from it,
    /// so changing the background there replaces this one instead of framing it twice.
    var backdrop: (plain: CGImage, style: Backdrop.Style)?

    private let lock = NSLock()
    private var cachedPNG: (data: Data, scale: CGFloat)?
    private var cachedFile: URL?

    init(image: CGImage, scale: CGFloat, screenRect: CGRect? = nil, screen: NSScreen? = nil) {
        self.image = image
        self.scale = scale
        self.screenRect = screenRect
        self.screen = screen
    }

    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }

    /// Replaces the pixels, for example with the annotated result from the editor.
    func replaceImage(_ newImage: CGImage) {
        lock.lock()
        image = newImage
        cachedPNG = nil
        cachedFile = nil
        lock.unlock()
    }

    /// Encoded once and reused for the clipboard, saving, and dragging. Safe from any thread.
    func png() -> (data: Data, scale: CGFloat)? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPNG { return cachedPNG }
        cachedPNG = Output.encode(image, scale: scale)
        return cachedPNG
    }

    /// The name a saved file gets, from the template in Settings.
    func fileName(_ format: Settings.SaveFormat) -> String {
        let template = UserDefaults.standard.string(forKey: Settings.Key.filenameTemplate) ?? Settings.defaultTemplate
        return "\(ImageCoding.fileName(template: template, date: date, appName: appName)).\(format.fileExtension)"
    }

    /// The capture encoded for saving to disk, in the format chosen in Settings.
    func fileData() -> SavedImage? {
        let format = Settings.SaveFormat(rawValue: UserDefaults.standard.string(forKey: Settings.Key.saveFormat) ?? "") ?? .png
        if format == .png, let png = png() { return SavedImage(data: png.data, name: fileName(.png), type: .png) }
        lock.lock()
        let image = image
        lock.unlock()
        guard let data = Output.encode(image, scale: scale, format: format) else { return nil }
        return SavedImage(data: data, name: fileName(format), type: format.type)
    }

    /// A temporary file for drag and drop.
    func temporaryFile() -> URL? {
        if let cachedFile { return cachedFile }
        guard let png = png() else { return nil }
        let url = Output.temporaryDirectory.appendingPathComponent(fileName(.png))
        do {
            try FileManager.default.createDirectory(at: Output.temporaryDirectory, withIntermediateDirectories: true)
            try png.data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        cachedFile = url
        return url
    }
}

/// Encoded bytes ready to write, with the name and type they should be saved under.
struct SavedImage {
    let data: Data
    let name: String
    let type: UTType
}

extension Settings.SaveFormat {
    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }
}

enum Output {
    static let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Captures", isDirectory: true)

    /// Applies the 1x preference, then encodes.
    static func encode(_ image: CGImage, scale: CGFloat) -> (data: Data, scale: CGFloat)? {
        var output = image
        var outputScale = scale
        // Read from defaults directly: this runs off the main thread.
        if UserDefaults.standard.bool(forKey: Settings.Key.copyAtPointSize), scale > 1,
           let reduced = AnnotationRenderer().flatten(base: image, scale: scale, annotations: [], outputScale: 1) {
            output = reduced
            outputScale = 1
        }
        guard let data = ImageCoding.pngData(output, scale: outputScale) else { return nil }
        return (data, outputScale)
    }

    /// Encodes for a saved file. Same resolution rule as the clipboard.
    static func encode(_ image: CGImage, scale: CGFloat, format: Settings.SaveFormat) -> Data? {
        var output = image
        var outputScale = scale
        if UserDefaults.standard.bool(forKey: Settings.Key.copyAtPointSize), scale > 1,
           let reduced = AnnotationRenderer().flatten(base: image, scale: scale, annotations: [], outputScale: 1) {
            output = reduced
            outputScale = 1
        }
        let quality = format == .png ? nil : UserDefaults.standard.double(forKey: Settings.Key.jpegQuality)
        return ImageCoding.encode(output, scale: outputScale, type: format.type, quality: quality)
    }

    static func copyToClipboard(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    static func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Removes drag-and-drop leftovers from earlier sessions.
    static func purgeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Writes into the chosen folder, or asks where to save when none is set.
    static func save(_ file: SavedImage, relativeTo window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let name = file.name
        if let folder = Settings.shared.resolvedSaveFolder() {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            let url = uniqueURL(in: folder, name: name)
            do {
                try file.data.write(to: url, options: .atomic)
                completion(url)
                return
            } catch {
                // Fall through to the panel, for example when the folder was moved or deleted.
            }
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [file.type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return completion(nil) }
            do {
                try file.data.write(to: url, options: .atomic)
                completion(url)
            } catch {
                NSAlert(error: error).runModal()
                completion(nil)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: finish)
        }
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

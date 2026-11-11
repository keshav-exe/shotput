import AppKit

/// One screenshot and where on screen it came from. Mutable state is guarded by a lock.
final class Capture: @unchecked Sendable {
    private(set) var image: CGImage
    /// Pixels per point.
    let scale: CGFloat
    /// Global Cocoa coordinates of the captured region, when it maps to one.
    let screenRect: CGRect?
    let screen: NSScreen?
    let date = Date()

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

    /// A temporary file for drag and drop.
    func temporaryFile() -> URL? {
        if let cachedFile { return cachedFile }
        guard let png = png() else { return nil }
        let url = Output.temporaryDirectory.appendingPathComponent(ImageCoding.timestampedName(for: date))
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
    static func save(_ png: Data, named name: String, relativeTo window: NSWindow?, completion: @escaping (URL?) -> Void) {
        if let folder = Settings.shared.resolvedSaveFolder() {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            let url = uniqueURL(in: folder, name: name)
            do {
                try png.write(to: url, options: .atomic)
                completion(url)
                return
            } catch {
                // Fall through to the panel, for example when the folder was moved or deleted.
            }
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return completion(nil) }
            do {
                try png.write(to: url, options: .atomic)
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

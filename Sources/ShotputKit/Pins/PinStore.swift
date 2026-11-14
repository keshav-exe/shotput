import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// What's kept in the menu bar: the 15 most recent pins, newest first. A pin is a capture or any
/// file dropped on the notch, copied into Shotput's own container so it survives a relaunch and
/// the original being moved or deleted. Nothing here leaves the Mac.
@MainActor
final class PinStore {
    struct Pin: Codable, Identifiable, Equatable {
        let id: UUID
        let date: Date
        let appName: String?
        let scale: CGFloat
        /// A dropped file's own name. Nil for a capture, which is kept as a PNG.
        var name: String? = nil
        /// Where a dropped file came from, so dropping it again moves it to the front instead
        /// of pinning it twice.
        var source: String? = nil

        var isCapture: Bool { name == nil }

        var type: UTType {
            guard let name else { return .png }
            return UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        }

        /// Opens in the editor: a capture, or a dropped picture.
        var isImage: Bool { isCapture || type.conforms(to: .image) }
    }

    static let shared = PinStore()
    static let limit = 15
    static let didChange = Notification.Name("ShotputPinsDidChange")

    private(set) var pins: [Pin] = []
    private var thumbnails: [UUID: CGImage] = [:]
    private let directory: URL
    private let thumbnailDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Pins", isDirectory: true)
        thumbnailDirectory = directory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([Pin].self, from: data) {
            pins = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    /// A capture is a PNG named for its id. A file keeps its own name, in a folder of its own,
    /// so dragging it back out gives the name it came in with.
    func url(for pin: Pin) -> URL {
        guard let name = pin.name else { return directory.appendingPathComponent("\(pin.id.uuidString).png") }
        return directory.appendingPathComponent(pin.id.uuidString, isDirectory: true).appendingPathComponent(name)
    }

    private func thumbnailURL(for pin: Pin) -> URL {
        thumbnailDirectory.appendingPathComponent("\(pin.id.uuidString).png")
    }

    func contains(_ capture: Capture) -> Bool { pins.contains { $0.id == capture.id } }

    var isFull: Bool { pins.count >= Self.limit }

    // MARK: Pinning

    /// Adds the capture at the front. Past the limit, the oldest pin goes.
    @discardableResult
    func pin(_ capture: Capture) -> Bool {
        guard !contains(capture), let png = capture.png() else { return false }
        let pin = Pin(id: capture.id, date: capture.date, appName: capture.appName, scale: png.scale)
        do {
            try png.data.write(to: url(for: pin), options: .atomic)
        } catch {
            return false
        }
        insert([pin])
        return true
    }

    /// Copies dropped files in, newest at the front in the order they were dragged. On APFS the
    /// copy is a clone, so even a large file pins at once and takes no extra space; anything
    /// slower happens off the main thread. A file pinned before moves to the front.
    /// - Returns: How many were pinned.
    func pin(files: [URL]) async -> Int {
        let files = Array(files.prefix(Self.limit))
        let directory = directory
        let copied = await Task.detached(priority: .userInitiated) { () -> [Pin] in
            files.compactMap { source in
                let pin = Pin(
                    id: UUID(), date: Date(), appName: nil, scale: PinStore.scale(of: source),
                    name: source.lastPathComponent, source: source.path
                )
                let folder = directory.appendingPathComponent(pin.id.uuidString, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
                    return pin
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    return nil
                }
            }
        }.value
        guard !copied.isEmpty else { return 0 }
        let sources = Set(copied.compactMap(\.source))
        pins.filter { $0.source.map(sources.contains) ?? false }.forEach { remove($0, notify: false) }
        insert(copied)
        copied.forEach(makeThumbnail)
        return copied.count
    }

    /// A Retina screenshot saved by macOS says 144 dpi, so it opens in the editor at the size
    /// it was on screen rather than twice that.
    private nonisolated static func scale(of file: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 72 else { return 1 }
        return CGFloat((dpi / 72).rounded())
    }

    private func insert(_ new: [Pin]) {
        pins.insert(contentsOf: new, at: 0)
        while pins.count > Self.limit { remove(pins[pins.count - 1], notify: false) }
        save()
    }

    // MARK: Removing

    func remove(_ pin: Pin, notify: Bool = true) {
        let file = url(for: pin)
        try? FileManager.default.removeItem(at: pin.isCapture ? file : file.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: thumbnailURL(for: pin))
        pins.removeAll { $0.id == pin.id }
        thumbnails[pin.id] = nil
        if notify { save() }
    }

    func remove(_ some: [Pin]) {
        some.forEach { remove($0, notify: false) }
        save()
    }

    func removeAll() {
        pins.forEach { remove($0, notify: false) }
        save()
    }

    // MARK: Thumbnails

    /// Decoded at the size the tray shows it, not the file's. A full-screen Retina pin is
    /// about 24 MB decoded; this is about 0.3 MB. Files that aren't pictures get Quick Look's
    /// thumbnail, made once when pinned and kept beside the pins.
    func thumbnail(for pin: Pin) -> CGImage? {
        if let cached = thumbnails[pin.id] { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        // A picture is its own thumbnail. Any other file, or a picture ImageIO can't read,
        // uses the one Quick Look made.
        let sources = pin.isImage ? [url(for: pin), thumbnailURL(for: pin)] : [thumbnailURL(for: pin)]
        for source in sources {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { continue }
            thumbnails[pin.id] = image
            return image
        }
        return nil
    }

    /// The file's kind, for a pin whose thumbnail isn't ready or can't be made.
    func icon(for pin: Pin) -> NSImage {
        NSWorkspace.shared.icon(forFile: url(for: pin).path)
    }

    private func makeThumbnail(for pin: Pin) {
        guard !pin.isCapture, thumbnail(for: pin) == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url(for: pin), size: CGSize(width: 180, height: 180), scale: 2, representationTypes: .thumbnail
        )
        let destination = thumbnailURL(for: pin)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.cgImage,
                  let target = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(target, image, nil)
            guard CGImageDestinationFinalize(target) else { return }
            Task { @MainActor in
                guard PinStore.shared.pins.contains(where: { $0.id == pin.id }) else { return }
                NotificationCenter.default.post(name: PinStore.didChange, object: nil)
            }
        }
    }

    // MARK: Using

    func copy(_ pin: Pin) { copy([pin]) }

    /// Several pins at once, one clipboard item each, so apps that take more than one paste
    /// them all and the rest paste the first. A capture goes as its image; a file as the file,
    /// the way Finder copies it.
    func copy(_ some: [Pin]) {
        let items = some.compactMap { pin -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            if pin.isCapture {
                guard let data = try? Data(contentsOf: url(for: pin)) else { return nil }
                item.setData(data, forType: .png)
            } else {
                item.setString(url(for: pin).absoluteString, forType: .fileURL)
            }
            return item
        }
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
    }

    /// Pictures open in the editor; every other file in the app macOS picks for it.
    func open(_ pin: Pin) {
        if pin.isImage, let image = ImageCoding.load(url(for: pin)) {
            EditorManager.shared.open(Capture(image: image, scale: pin.scale))
        } else {
            NSWorkspace.shared.open(url(for: pin))
        }
    }

    private func save() {
        try? JSONEncoder().encode(pins).write(to: indexURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

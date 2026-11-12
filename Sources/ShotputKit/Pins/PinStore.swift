import AppKit

/// Captures kept in the menu bar: the 15 most recent pins, newest first, saved in Shotput's own
/// container so they survive a relaunch. Nothing here leaves the Mac.
@MainActor
final class PinStore {
    struct Pin: Codable, Identifiable, Equatable {
        let id: UUID
        let date: Date
        let appName: String?
        let scale: CGFloat
        var fileName: String { "\(id.uuidString).png" }
    }

    static let shared = PinStore()
    static let limit = 15
    static let didChange = Notification.Name("ShotputPinsDidChange")

    private(set) var pins: [Pin] = []
    private var thumbnails: [UUID: NSImage] = [:]
    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Pins", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([Pin].self, from: data) {
            pins = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    func url(for pin: Pin) -> URL { directory.appendingPathComponent(pin.fileName) }

    func contains(_ capture: Capture) -> Bool { pins.contains { $0.id == capture.id } }

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
        pins.insert(pin, at: 0)
        while pins.count > Self.limit { remove(pins[pins.count - 1], notify: false) }
        save()
        return true
    }

    func remove(_ pin: Pin, notify: Bool = true) {
        try? FileManager.default.removeItem(at: url(for: pin))
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

    func thumbnail(for pin: Pin) -> NSImage? {
        if let cached = thumbnails[pin.id] { return cached }
        guard let image = NSImage(contentsOf: url(for: pin)) else { return nil }
        thumbnails[pin.id] = image
        return image
    }

    func copy(_ pin: Pin) {
        guard let data = try? Data(contentsOf: url(for: pin)) else { return }
        Output.copyToClipboard(data)
    }

    /// Several pins at once, one clipboard item each, so apps that take more than one image
    /// paste them all and the rest paste the first.
    func copy(_ some: [Pin]) {
        let items = some.compactMap { pin -> NSPasteboardItem? in
            guard let data = try? Data(contentsOf: url(for: pin)) else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            return item
        }
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
    }

    func open(_ pin: Pin) {
        guard let image = ImageCoding.load(url(for: pin)) else { return }
        EditorManager.shared.open(Capture(image: image, scale: pin.scale))
    }

    private func save() {
        try? JSONEncoder().encode(pins).write(to: indexURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

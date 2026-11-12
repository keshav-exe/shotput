import AppKit
import Carbon.HIToolbox
import ImageIO

/// What macOS's own screenshot tool is set to. Shotput reads these through narrow sandbox
/// exceptions in its entitlements, and writes only the floating thumbnail setting.
enum SystemScreenshots {
    private static let domain = "com.apple.screencapture" as CFString

    /// The folder ⇧⌘3 and ⇧⌘4 save to: Desktop unless changed in the ⇧⌘5 Options menu.
    static var folder: URL {
        let home = URL(fileURLWithPath: realHome, isDirectory: true)
        guard let path = CFPreferencesCopyAppValue("location" as CFString, domain) as? String, !path.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        let expanded = path.hasPrefix("~") ? realHome + path.dropFirst() : path
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Whether screenshots go to the clipboard instead of a file, set in the ⇧⌘5 Options menu.
    static var savesToClipboard: Bool {
        (CFPreferencesCopyAppValue("target-screenshot" as CFString, domain) as? String) == "clipboard"
    }

    /// The thumbnail macOS floats in the corner. While it shows, the file isn't written, so
    /// Shotput's preview would wait behind it.
    static var showsThumbnail: Bool {
        get { (CFPreferencesCopyAppValue("show-thumbnail" as CFString, domain) as? Bool) ?? true }
        set {
            CFPreferencesSetAppValue("show-thumbnail" as CFString, newValue as CFBoolean, domain)
            CFPreferencesAppSynchronize(domain)
        }
    }

    /// Whether macOS still answers ⇧⌘3, ⇧⌘4 or ⇧⌘5 itself. Shotput only hears those keys once
    /// they're turned off under Keyboard Shortcuts → Screenshots.
    static var ownsScreenshotKeys: Bool {
        let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
            as? [String: Any] ?? [:]
        // 28 is ⇧⌘3, 30 is ⇧⌘4, 184 is ⇧⌘5. A missing entry means it is on, as it ships.
        return ["28", "30", "184"].contains { id in
            guard let entry = hotkeys[id] as? [String: Any] else { return true }
            return (entry["enabled"] as? Bool) ?? (entry["enabled"] as? Int).map { $0 != 0 } ?? true
        }
    }

    /// Other screenshot apps that are open and may hold the same keys.
    static var otherTools: [NSRunningApplication] {
        let names: Set<String> = ["Shottr", "CleanShot X", "Snagit", "Xnapper", "Monosnap", "Lightshot", "Skitch", "Shotbase", "Zappy", "Flameshot"]
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName else { return false }
            return names.contains(name) || name.hasPrefix("Snagit")
        }
    }

    static func openKeyboardShortcuts() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    /// The sandbox points NSHomeDirectory at Shotput's container. This is the real one.
    private static var realHome: String {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }
}

/// Shotput's own shortcuts on the keys macOS uses for screenshots.
enum ScreenshotKeys {
    static let bindings: [HotAction: Shortcut] = [
        .screen: Shortcut(keyCode: kVK_ANSI_3, [.shift, .command]),
        .area: Shortcut(keyCode: kVK_ANSI_4, [.shift, .command]),
        .areaAnnotate: Shortcut(keyCode: kVK_ANSI_5, [.shift, .command]),
    ]

    static func isTaken(_ shortcuts: [HotAction: Shortcut]) -> Bool {
        bindings.allSatisfy { shortcuts[$0.key] == $0.value }
    }
}

/// Watches the folder macOS saves screenshots to and gives each new one Shotput's preview, as if
/// Shotput had taken it. Event driven: the folder is watched with a vnode source, nothing polls.
@MainActor
final class MacScreenshotWatcher {
    static let shared = MacScreenshotWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var seen = Set<String>()
    private var since = Date()
    private var pendingScan: DispatchWorkItem?

    /// Starts watching the folder in the saved bookmark. Returns false when there is no
    /// bookmark yet or it no longer resolves.
    @discardableResult
    func start() -> Bool {
        stop()
        guard let folder = Settings.shared.screenshotFolder, folder.startAccessingSecurityScopedResource() else {
            return false
        }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            folder.stopAccessingSecurityScopedResource()
            return false
        }
        self.folder = folder
        since = Date()
        seen = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []))

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleScan() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingScan?.cancel()
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
    }

    /// Asks for the screenshot folder in an open panel, the only way the sandbox lets Shotput
    /// read it, then starts watching. Turns macOS's own thumbnail off so the file lands at once.
    @discardableResult
    func enable() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = SystemScreenshots.folder
        panel.message = "Shotput needs to see the folder macOS saves screenshots to, so it can preview them."
        panel.prompt = "Allow"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        Settings.shared.setScreenshotFolder(url)
        if SystemScreenshots.showsThumbnail {
            UserDefaults.standard.set(true, forKey: Settings.Key.restoresMacThumbnail)
            SystemScreenshots.showsThumbnail = false
        }
        return start()
    }

    func disable() {
        stop()
        if UserDefaults.standard.bool(forKey: Settings.Key.restoresMacThumbnail) {
            SystemScreenshots.showsThumbnail = true
            UserDefaults.standard.removeObject(forKey: Settings.Key.restoresMacThumbnail)
        }
        Settings.shared.setScreenshotFolder(nil)
    }

    // MARK: Scanning

    private func scheduleScan(after delay: TimeInterval = 0.15) {
        // Let the folder settle: a burst of events arrives for each file.
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scan() {
        guard let folder else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var screenshots: [URL] = []
        var waiting = false
        for name in names where !seen.contains(name) && !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            let created = Self.created(url)
            if created < since.addingTimeInterval(-1) {
                seen.insert(name)
            } else if Self.isScreenshot(url) {
                seen.insert(name)
                screenshots.append(url)
            } else if Date().timeIntervalSince(created) < 3 {
                // macOS writes the file, then tags it. Look again until it has been tagged or is
                // clearly some other file.
                waiting = true
            } else {
                seen.insert(name)
            }
        }
        if waiting { scheduleScan(after: 0.25) }
        guard let chosen = Self.pick(screenshots) else { return }
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        DispatchQueue.global(qos: .userInitiated).async {
            guard let capture = Self.load(chosen) else { return }
            capture.appName = appName
            DispatchQueue.main.async { CaptureCoordinator.shared.adoptMacScreenshot(capture) }
        }
    }

    /// ⇧⌘3 with two displays saves one file each. The preview shows the display under the
    /// pointer; otherwise the newest file.
    private static func pick(_ urls: [URL]) -> URL? {
        guard urls.count > 1 else { return urls.first }
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if let under = urls.first(where: { url in
            guard let rect = globalRect(of: url) else { return false }
            return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height).contains(mouse)
        }) {
            return under
        }
        return urls.max { created($0) < created($1) }
    }

    nonisolated private static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }

    /// macOS tags every screenshot it saves. Recordings get a different tag and are skipped.
    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    nonisolated static func load(_ url: URL) -> Capture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        var scale = max(CGFloat(dpi / 72).rounded(), 1)

        // Where on screen it was taken, so the preview keeps clear of it and the flash lines up.
        var rect: CGRect?
        var screen: NSScreen?
        if let global = globalRect(of: url) {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let cocoa = CGRect(x: global.minX, y: primaryHeight - global.maxY, width: global.width, height: global.height)
            rect = cocoa
            screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: cocoa.midX, y: cocoa.midY)) }
            if global.width > 0 { scale = max((CGFloat(image.width) / global.width).rounded(), 1) }
        }
        return Capture(image: image, scale: scale, screenRect: rect, screen: screen)
    }

    /// The area in global display coordinates, top left origin, that macOS stores with the file.
    nonisolated private static func globalRect(of url: URL) -> CGRect? {
        let name = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        guard read == size,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [NSNumber],
              values.count == 4 else { return nil }
        return CGRect(x: values[0].doubleValue, y: values[1].doubleValue, width: values[2].doubleValue, height: values[3].doubleValue)
    }
}

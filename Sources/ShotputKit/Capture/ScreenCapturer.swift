import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}

/// A still of one display.
struct DisplayShot {
    let screen: NSScreen
    let image: CGImage
    /// Pixels per point.
    let scale: CGFloat

    /// Crops a rect given in the screen's own bottom-left point coordinates.
    func crop(_ rect: CGRect) -> CGImage? {
        image.cropping(to: CGRect(
            x: rect.minX * scale,
            y: (screen.frame.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral)
    }
}

/// An on-screen window, in global Cocoa coordinates. Ordered front to back.
struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect
    var ownerName: String? = nil
}

@MainActor
enum ScreenCapturer {
    /// Asking ScreenCaptureKit what's on screen is the slowest part of starting a capture, often
    /// longer than taking the stills. Displays and Shotput's own app rarely change, so the answer
    /// is kept and refreshed in the background after each capture. Anything that needs the
    /// current window list (window captures, or Shotput's own windows) still asks afresh.
    private static var cached: (content: SCShareableContent, date: Date)?
    private static var refreshing: Task<SCShareableContent, Error>?
    private static var screensObserver: Any?

    static func shareableContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cached = (content, Date())
        return content
    }

    /// Content good enough for display stills: cached when it is recent and the displays match.
    static func displayContent() async throws -> SCShareableContent {
        observeScreensIfNeeded()
        if let cached, Date().timeIntervalSince(cached.date) < 120,
           Set(cached.content.displays.map(\.displayID)) == Set(NSScreen.screens.compactMap(\.displayID)) {
            return cached.content
        }
        if let refreshing { return try await refreshing.value }
        return try await shareableContent()
    }

    /// Fetches fresh content off the critical path, so the next capture starts at once.
    static func warmUp() {
        guard refreshing == nil, CGPreflightScreenCaptureAccess() else { return }
        observeScreensIfNeeded()
        refreshing = Task {
            defer { refreshing = nil }
            return try await shareableContent()
        }
    }

    private static func observeScreensIfNeeded() {
        guard screensObserver == nil else { return }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                cached = nil
                warmUp()
            }
        }
    }

    /// Stills of every display, or of one, taken at the same time. Shotput's own windows are left
    /// out, unless Settings asks for its normal windows; its previews, HUDs, and shelves are
    /// always left out.
    static func captureDisplays(_ content: SCShareableContent, only: NSScreen? = nil, showsCursor: Bool = false) async throws -> [DisplayShot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownPID }
        let includesOwn = Settings.shared.capturesOwnWindows
        let ownFloating = content.windows.filter { $0.owningApplication?.processID == ownPID && $0.windowLayer != 0 }
        var jobs: [(screen: NSScreen, filter: SCContentFilter, configuration: SCStreamConfiguration)] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }),
                  only == nil || only == screen else { continue }
            let filter = includesOwn
                ? SCContentFilter(display: display, excludingWindows: ownFloating)
                : SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            configuration.showsCursor = showsCursor
            configuration.captureResolution = .best
            configuration.colorSpaceName = CGColorSpace.sRGB
            jobs.append((screen, filter, configuration))
        }
        // Every display at once: with two or three screens, waiting on each in turn was most of
        // the delay between the shortcut and the selection.
        let images = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, job) in jobs.enumerated() {
                let filter = job.filter, configuration = job.configuration
                group.addTask {
                    (index, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration))
                }
            }
            var images: [Int: CGImage] = [:]
            for try await (index, image) in group { images[index] = image }
            return images
        }
        return jobs.enumerated().compactMap { index, job in
            guard let image = images[index] else { return nil }
            return DisplayShot(screen: job.screen, image: image, scale: CGFloat(image.width) / job.screen.frame.width)
        }
    }

    /// One window on its own, with transparent corners and nothing overlapping it.
    static func captureWindow(
        _ id: CGWindowID, in content: SCShareableContent, includesShadow: Bool = false
    ) async throws -> (image: CGImage, scale: CGFloat)? {
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = !includesShadow
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, scale)
    }

    /// Normal app windows, front to back. Used for snapping and for window capture.
    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let includesOwn = Settings.shared.capturesOwnWindows

        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  includesOwn || info[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40, bounds.height >= 40 else { return nil }
            // Core Graphics measures from the top of the primary display, Cocoa from its bottom.
            return WindowInfo(id: id, frame: CGRect(
                x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height
            ), ownerName: info[kCGWindowOwnerName as String] as? String)
        }
    }
}

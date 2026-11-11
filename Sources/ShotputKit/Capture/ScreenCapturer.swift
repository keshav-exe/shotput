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
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Stills of every display, or of one. Shotput's own windows are left out.
    static func captureDisplays(_ content: SCShareableContent, only: NSScreen? = nil, showsCursor: Bool = false) async throws -> [DisplayShot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownPID }
        var shots: [DisplayShot] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }),
                  only == nil || only == screen else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            configuration.showsCursor = showsCursor
            configuration.captureResolution = .best
            configuration.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            shots.append(DisplayShot(screen: screen, image: image, scale: CGFloat(image.width) / screen.frame.width))
        }
        return shots
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

        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowOwnerPID as String] as? pid_t != ownPID,
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

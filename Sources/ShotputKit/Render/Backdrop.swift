import AppKit
import ScreenCaptureKit

/// Puts a screenshot on a backdrop: the desktop wallpaper or a colour, with padding and a soft
/// shadow. Used for window captures and by the editor's Background control.
enum Backdrop {
    enum Fill: Equatable {
        case wallpaper
        case color(NSColor)
    }

    struct Style: Equatable {
        var fill: Fill
        /// Points of backdrop around the image.
        var padding: CGFloat
    }

    /// - Parameters:
    ///   - wallpaper: Required for `.wallpaper`; without it the fill falls back to a neutral colour.
    ///   - addsShadow: False when the image already carries the system's window shadow.
    static func compose(_ image: CGImage, scale: CGFloat, style: Style, wallpaper: CGImage?, addsShadow: Bool = true) -> CGImage {
        let padding = Int((style.padding * scale).rounded())
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        switch style.fill {
        case .wallpaper:
            if let wallpaper {
                context.interpolationQuality = .high
                context.draw(wallpaper, in: aspectFill(CGSize(width: wallpaper.width, height: wallpaper.height), in: canvas))
            } else {
                context.setFillColor(NSColor(hex: 0xE9E6DF).cgColor)
                context.fill(canvas)
            }
        case let .color(color):
            context.setFillColor((color.usingColorSpace(.sRGB) ?? .white).cgColor)
            context.fill(canvas)
        }

        let frame = CGRect(x: padding, y: padding, width: image.width, height: image.height)
        // Area captures are square-cornered and opaque; round them so they sit on the backdrop
        // like a window does. Window captures already have their own transparent corners.
        let rounds = hasOpaqueCorner(image)
        let radius = 10 * scale
        let shape = CGPath(roundedRect: frame, cornerWidth: rounds ? radius : 0, cornerHeight: rounds ? radius : 0, transform: nil)

        if addsShadow, padding > 0 {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 36 * scale, color: NSColor.black.withAlphaComponent(0.32).cgColor)
            if rounds {
                context.addPath(shape)
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
            } else {
                context.draw(image, in: frame)
            }
            context.restoreGState()
        }
        context.saveGState()
        if rounds {
            context.addPath(shape)
            context.clip()
        }
        context.draw(image, in: frame)
        context.restoreGState()
        return context.makeImage() ?? image
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let fill = max(rect.width / size.width, rect.height / size.height)
        let scaled = CGSize(width: size.width * fill, height: size.height * fill)
        return CGRect(x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2, width: scaled.width, height: scaled.height)
    }

    private static func hasOpaqueCorner(_ image: CGImage) -> Bool {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        // Draw so the image's top-left pixel lands on the single pixel of the context.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return pixel[3] > 200
    }

    // MARK: Wallpaper

    /// The wallpaper as it is on screen right now, dynamic wallpapers included: only the window
    /// layers below the desktop icons are captured. Falls back to the wallpaper file.
    @MainActor
    static func wallpaper(for screen: NSScreen?) async -> CGImage? {
        let screen = screen ?? NSScreen.underMouse ?? NSScreen.main
        guard let screen else { return nil }
        if let captured = try? await captureWallpaper(screen) { return captured }
        return NSWorkspace.shared.desktopImageURL(for: screen).flatMap(ImageCoding.load)
    }

    @MainActor
    private static func captureWallpaper(_ screen: NSScreen) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { return nil }
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let layers = content.windows.filter { $0.windowLayer < iconLevel && $0.frame.intersects(display.frame) }
        guard !layers.isEmpty else { return nil }
        let filter = SCContentFilter(display: display, including: layers)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

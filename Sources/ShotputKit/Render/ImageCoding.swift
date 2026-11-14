import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageCoding {
    /// PNG tagged with its density, so a 2x capture opens at its on-screen size.
    public static func pngData(_ image: CGImage, scale: CGFloat) -> Data? {
        encode(image, scale: scale, type: .png, quality: nil)
    }

    /// Any ImageIO format, tagged with its density. Quality applies to lossy formats only.
    static func encode(_ image: CGImage, scale: CGFloat, type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * scale
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        var source = image
        // JPEG has no alpha. Flatten onto white so transparent window corners do not turn black.
        if type == .jpeg, image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
           let opaque = flattenedOnWhite(image) {
            source = opaque
        }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func timestampedName(for date: Date = Date()) -> String {
        "\(fileName(template: Settings.defaultTemplate, date: date, appName: nil)).png"
    }

    /// Tokens accepted in the file name template, with what each one stands for.
    static let templateTokens: [(token: String, meaning: String)] = [
        ("%Y", L("Year, 2026")), ("%y", L("Year, 26")), ("%m", L("Month, 07")), ("%b", L("Month, Jul")),
        ("%B", L("Month, July")), ("%d", L("Day, 09")), ("%j", L("Day of year, 190")), ("%A", L("Weekday, Friday")),
        ("%a", L("Weekday, Fri")), ("%H", L("Hour, 17")), ("%I", L("Hour, 05")), ("%p", L("AM or PM")),
        ("%M", L("Minute, 08")), ("%S", L("Second, 04")), ("%n", L("App name")), ("%r", L("Random, k3qz")),
    ]

    /// Expands a template such as `Shotput %Y-%m-%d` into a file name without an extension.
    /// Characters macOS cannot put in a name are replaced, and an empty result falls back to the default.
    static func fileName(template: String, date: Date, appName: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        func format(_ pattern: String) -> String {
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }

        var result = ""
        var characters = template.makeIterator()
        while let character = characters.next() {
            guard character == "%" else {
                result.append(character)
                continue
            }
            guard let token = characters.next() else {
                result.append("%")
                break
            }
            switch token {
            case "Y": result += format("yyyy")
            case "y": result += format("yy")
            case "m": result += format("MM")
            case "b": result += format("MMM")
            case "B": result += format("MMMM")
            case "d": result += format("dd")
            case "j": result += format("DDD")
            case "A": result += format("EEEE")
            case "a": result += format("EEE")
            case "H": result += format("HH")
            case "I": result += format("hh")
            case "p": result += format("a")
            case "M": result += format("mm")
            case "S": result += format("ss")
            case "n": result += appName ?? "Screen"
            case "r": result += String((0..<4).map { _ in "abcdefghijkmnpqrstuvwxyz23456789".randomElement()! })
            case "%": result += "%"
            default: result += "%\(token)"
            }
        }

        let cleaned = result
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix(".") else {
            return template == Settings.defaultTemplate ? "Shotput" : fileName(template: Settings.defaultTemplate, date: date, appName: appName)
        }
        return cleaned
    }
}

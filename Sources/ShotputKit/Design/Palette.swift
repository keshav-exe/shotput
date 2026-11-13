import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(light: UInt, dark: UInt) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        }
    }

    var color: Color { Color(nsColor: self) }
}

/// The calm palette: warm neutrals and one accent.
enum Palette {
    static let background = NSColor.dynamic(light: 0xFBFBF9, dark: 0x191917)
    static let surface = NSColor.dynamic(light: 0xFFFFFF, dark: 0x222220)
    static let surfaceMuted = NSColor.dynamic(light: 0xF1F0ED, dark: 0x2B2A27)
    static let ink = NSColor.dynamic(light: 0x2B2A26, dark: 0xECEAE3)
    static let inkSecondary = NSColor.dynamic(light: 0x736F67, dark: 0x9D988D)
    static let inkTertiary = NSColor.dynamic(light: 0xA6A29A, dark: 0x6F6A60)
    static let accent = NSColor.dynamic(light: 0x1F6FE5, dark: 0x5AA0FF)
    static let hairline = NSColor.dynamic(light: 0xEBE9E4, dark: 0x33322D)
}

enum Metrics {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let chipRadius: CGFloat = 14
}

/// Annotation inks. Fixed values, since they are drawn onto screenshots rather than onto app chrome.
public enum InkColor: Int, CaseIterable {
    case red, orange, yellow, green, blue, violet, black, white

    var hex: UInt {
        switch self {
        case .red: 0xE5484D
        case .orange: 0xF76B15
        case .yellow: 0xFFC53D
        case .green: 0x30A46C
        case .blue: 0x1F6FE5
        case .violet: 0x8E4EC6
        case .black: 0x2B2A26
        case .white: 0xFFFFFF
        }
    }

    var name: String {
        switch self {
        case .red: L("Red")
        case .orange: L("Orange")
        case .yellow: L("Yellow")
        case .green: L("Green")
        case .blue: L("Blue")
        case .violet: L("Violet")
        case .black: L("Black")
        case .white: L("White")
        }
    }

    var nsColor: NSColor { NSColor(hex: hex) }
    var cgColor: CGColor { nsColor.cgColor }

    private var isLight: Bool { self == .yellow || self == .white }

    /// Text or glyph colour that stays legible on top of this ink.
    var onInk: NSColor { isLight ? NSColor(hex: 0x2B2A26) : .white }

    /// Thin outline that keeps the ink visible on a background of its own colour.
    var halo: CGColor {
        isLight ? NSColor(hex: 0x2B2A26, alpha: 0.5).cgColor : NSColor(hex: 0xFFFFFF, alpha: 0.92).cgColor
    }
}

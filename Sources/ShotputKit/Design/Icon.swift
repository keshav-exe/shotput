import AppKit
import SwiftUI

/// Every icon Shotput draws, as SF Symbols, so each glyph is named once and matches the system.
enum Icon: String {
    case arrow = "arrow.up.right"
    case line = "line.diagonal"
    case rectangle = "rectangle"
    case ellipse = "circle"
    case text = "textformat"
    case counter = "1.circle"
    case pen = "scribble"
    case highlighter = "highlighter"
    case redact = "checkerboard.rectangle"
    case crop = "crop"
    case readText = "text.viewfinder"
    case save = "square.and.arrow.down"
    case copy = "doc.on.doc"
    case undo = "arrow.uturn.backward"
    case redo = "arrow.uturn.forward"
    case fill = "square.fill"
    case unfilled = "square"
    case background = "photo.artframe"
    case annotate = "pencil.tip.crop.circle"
    case close = "xmark"
    case check = "checkmark.circle.fill"
    case checkmark = "checkmark"
    case pin = "pin"
    case settings = "gearshape"
    case capture = "viewfinder"
    case folder = "folder"
    case command = "command"
    case info = "info.circle"
    case window = "macwindow"
    case screen = "display"
    case clipboard = "clipboard"
    case textFound = "text.magnifyingglass"
    case refresh = "arrow.clockwise"
    case clock = "clock.arrow.circlepath"
    case returnKey = "return"
    case back = "arrow.left"
    case keyboard = "keyboard"
    case update = "arrow.down.circle"
    case power = "power"
    case lock = "lock"
    case warning = "exclamationmark.triangle.fill"
    case toolbar = "rectangle.bottomthird.inset.filled"
    case areaDashed = "rectangle.dashed"
    case scissors = "scissors"
    case move = "arrow.right.doc.on.clipboard"
    case select = "cursorarrow"
    case filledRectangle = "rectangle.fill"
    case spotlight = "flashlight.on.fill"
    case tinted = "square.fill.on.square"
    case curvedArrow = "arrow.turn.up.right"
    case doubleArrow = "arrow.left.and.right"
    case curve = "point.topleft.down.to.point.bottomright.curvepath"
    case textLabel = "character.textbox"
    case textOutlined = "character"
    case counterFilled = "1.circle.fill"
    case counterSquare = "1.square.fill"
    case options = "slider.horizontal.3"
    case blurSecure = "drop.halffull"
    case blurSmooth = "drop"
    case blackout = "rectangle.inset.filled"
    case rotateLeft = "rotate.left"
    case flipHorizontal = "arrow.left.and.right.righttriangle.left.righttriangle.right"
    case flipVertical = "arrow.up.and.down.righttriangle.up.righttriangle.down"

    /// The symbol at the size its surroundings choose, as toolbars, tabs, and menus expect.
    func plain(label: String? = nil) -> NSImage {
        NSImage(systemSymbolName: rawValue, accessibilityDescription: label) ?? NSImage()
    }

    /// - Parameters:
    ///   - size: The symbol's point size, as a font size.
    ///   - weight: Stroke weight.
    func image(size: CGFloat = 13, weight: NSFont.Weight = .regular, label: String? = nil) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: rawValue, accessibilityDescription: label)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// The symbol in a SwiftUI view, tinted by the foreground style.
    func view(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        Image(systemName: rawValue)
            .font(.system(size: size, weight: weight))
            .accessibilityHidden(true)
    }
}

extension Tool {
    var icon: Icon {
        switch self {
        case .select: .select
        case .rectangle: .rectangle
        case .filledRectangle: .filledRectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .text: .text
        case .redact: .redact
        case .spotlight: .spotlight
        case .counter: .counter
        case .pen: .pen
        case .highlight: .highlighter
        }
    }
}

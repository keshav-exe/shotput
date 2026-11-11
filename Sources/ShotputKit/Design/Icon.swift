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
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .pen: .pen
        case .highlight: .highlighter
        case .redact: .redact
        case .crop: .crop
        }
    }
}

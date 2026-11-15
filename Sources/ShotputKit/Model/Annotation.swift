import AppKit

/// The editor's drawing tools, in toolbar order.
public enum Tool: String, CaseIterable, Codable {
    case select, rectangle, filledRectangle, ellipse, line, arrow, text, redact, spotlight, counter, pen, highlight

    var title: String {
        switch self {
        case .select: L("Select")
        case .rectangle: L("Rectangle")
        case .filledRectangle: L("Filled rectangle")
        case .ellipse: L("Ellipse")
        case .line: L("Line")
        case .arrow: L("Arrow")
        case .text: L("Text")
        case .redact: L("Redact")
        case .spotlight: L("Spotlight")
        case .counter: L("Step number")
        case .pen: L("Pen")
        case .highlight: L("Highlighter")
        }
    }

    /// Single-key shortcut while the editor has focus. C enters crop, which is a mode, not a tool.
    var key: Character {
        switch self {
        case .select: "v"
        case .rectangle: "r"
        case .filledRectangle: "f"
        case .ellipse: "o"
        case .line: "l"
        case .arrow: "a"
        case .text: "t"
        case .redact: "b"
        case .spotlight: "s"
        case .counter: "n"
        case .pen: "p"
        case .highlight: "h"
        }
    }

    /// What the toolbar's size control means for this tool.
    var sizeKind: SizeKind {
        switch self {
        case .rectangle, .ellipse, .line, .arrow, .pen: .stroke
        case .text: .font
        case .counter: .counter
        case .redact: .strength
        case .select, .filledRectangle, .spotlight, .highlight: .none
        }
    }

    var supportsColor: Bool { ![.select, .spotlight].contains(self) }
}

public enum SizeKind {
    case stroke, font, counter, strength, none

    /// The sizes offered in the toolbar's menu, in points.
    var presets: [CGFloat] {
        switch self {
        case .stroke: [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]
        case .font: [12, 14, 16, 18, 20, 24, 28, 36, 48, 64, 72]
        case .counter: [18, 22, 26, 30, 36, 44, 56]
        case .strength: [4, 6, 8, 10, 14, 18, 24, 32]
        case .none: []
        }
    }
}

/// The four quick sizes the editor used to offer. Kept as presets for code that thinks in them.
public enum Weight: Int, CaseIterable {
    case light, regular, heavy, extraHeavy

    var stroke: CGFloat { [2.5, 4, 6.5, 10][rawValue] }
    var fontSize: CGFloat { [14, 19, 28, 40][rawValue] }
    var counterSize: CGFloat { [22, 28, 38, 52][rawValue] }
}

// MARK: Colour

/// A mark's colour: one of the palette's swatches or any colour from the colour picker.
public struct Ink: Hashable, Codable {
    /// 0xRRGGBB.
    public var hex: UInt

    public init(hex: UInt) { self.hex = hex & 0xFFFFFF }
    public init(_ preset: InkColor) { self.init(hex: preset.hex) }

    public init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> UInt { UInt((min(max(value, 0), 1) * 255).rounded()) }
        self.init(hex: channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8 | channel(rgb.blueComponent))
    }

    public static let red = Ink(InkColor.red)
    public static let orange = Ink(InkColor.orange)
    public static let yellow = Ink(InkColor.yellow)
    public static let green = Ink(InkColor.green)
    public static let blue = Ink(InkColor.blue)
    public static let violet = Ink(InkColor.violet)
    public static let black = Ink(InkColor.black)
    public static let white = Ink(InkColor.white)
    public static let teal = Ink(hex: 0x12A594)
    public static let pink = Ink(hex: 0xE93D82)

    /// The palette, in the order the number keys pick them: 1 to 9, then 0.
    public static let palette: [Ink] = [.red, .orange, .yellow, .green, .teal, .blue, .violet, .pink, .black, .white]

    var nsColor: NSColor { NSColor(hex: hex) }
    var cgColor: CGColor { nsColor.cgColor }

    var name: String {
        if let preset = InkColor.allCases.first(where: { $0.hex == hex }) { return preset.name }
        if self == .teal { return L("Teal") }
        if self == .pink { return L("Pink") }
        return String(format: "#%06X", hex)
    }

    private var luminance: CGFloat {
        let r = CGFloat((hex >> 16) & 0xFF) / 255, g = CGFloat((hex >> 8) & 0xFF) / 255, b = CGFloat(hex & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private var isLight: Bool { luminance > 0.62 }

    /// Text or glyph colour that stays legible on top of this ink.
    var onInk: NSColor { isLight ? NSColor(hex: 0x2B2A26) : .white }

    /// Thin outline that keeps the ink visible on a background of its own colour.
    var halo: CGColor {
        isLight ? NSColor(hex: 0x2B2A26, alpha: 0.5).cgColor : NSColor(hex: 0xFFFFFF, alpha: 0.92).cgColor
    }
}

// MARK: Style

/// How a rectangle or ellipse is painted.
public enum ShapeFill: String, Codable, CaseIterable {
    case outline, solid, tinted, striped, dotted

    var title: String {
        switch self {
        case .outline: L("Outline")
        case .solid: L("Fill")
        case .tinted: L("Fill and border")
        case .striped: L("Stripes and border")
        case .dotted: L("Dots and border")
        }
    }

    /// The SF Symbol for the fill menu.
    var symbol: String {
        switch self {
        case .outline: "square"
        case .solid: "square.fill"
        case .tinted: "square.inset.filled"
        case .striped: "square.split.diagonal.fill"
        case .dotted: "circle.grid.3x3"
        }
    }
}

public enum ArrowStyle: String, Codable, CaseIterable {
    case tapered, uniform, double

    var title: String {
        switch self {
        case .tapered: L("Tapered")
        case .uniform: L("Even")
        case .double: L("Double-headed")
        }
    }
}

public enum HeadSize: String, Codable, CaseIterable {
    case small, medium, large

    var factor: CGFloat {
        switch self {
        case .small: 0.7
        case .medium: 1
        case .large: 1.45
        }
    }

    var title: String {
        switch self {
        case .small: L("Small head")
        case .medium: L("Medium head")
        case .large: L("Large head")
        }
    }
}

public enum TextStyle: String, Codable, CaseIterable {
    case plain, outlined, pill

    var title: String {
        switch self {
        case .plain: L("Plain")
        case .outlined: L("Outlined")
        case .pill: L("Label")
        }
    }
}

public enum TextFont: String, Codable, CaseIterable {
    case system, rounded, serif, mono, marker

    var title: String {
        switch self {
        case .system: L("System")
        case .rounded: L("Rounded")
        case .serif: L("Serif")
        case .mono: L("Monospaced")
        case .marker: L("Marker")
        }
    }
}

public enum CounterStyle: String, Codable, CaseIterable {
    case filled, ring, square

    var title: String {
        switch self {
        case .filled: L("Filled circle")
        case .ring: L("Ring")
        case .square: L("Rounded square")
        }
    }
}

public enum RedactMode: String, Codable, CaseIterable {
    case pixelate, blurSecure, blurSmooth, blackout

    var title: String {
        switch self {
        case .pixelate: L("Pixelate")
        case .blurSecure: L("Blur (secure)")
        case .blurSmooth: L("Blur (smooth)")
        case .blackout: L("Black out")
        }
    }
}

/// Everything about how one mark looks. Each tool keeps its own, so a thick red arrow and a
/// small blue label can both be the default at once.
public struct MarkStyle: Equatable, Codable {
    public var color: Ink = .red
    /// Points. Stroke width, font size, step-number diameter, or redaction cell size, by tool.
    public var size: CGFloat = 4
    public var fill: ShapeFill = .outline
    public var cornerRadius: CGFloat = 6
    public var shadow = true
    /// The whole mark's opacity. For a spotlight, how dark the rest of the image goes.
    public var opacity: CGFloat = 1
    public var dashed = false
    public var arrow: ArrowStyle = .tapered
    /// New arrows and lines start with a bend.
    public var curved = false
    public var head: HeadSize = .medium
    public var text: TextStyle = .pill
    public var font: TextFont = .system
    public var bold = true
    public var counter: CounterStyle = .filled
    public var redaction: RedactMode = .pixelate

    public init() {}

    public static func defaults(for tool: Tool) -> MarkStyle {
        var style = MarkStyle()
        switch tool {
        case .rectangle, .ellipse, .pen: style.size = 4
        case .filledRectangle: style.fill = .solid
        case .line, .arrow: style.size = 5
        case .text: style.size = 20
        case .counter: style.size = 28
        case .redact: style.size = 10; style.color = .black; style.shadow = false
        case .spotlight: style.opacity = 0.55; style.shadow = false; style.cornerRadius = 8
        case .highlight: style.color = .yellow; style.shadow = false
        case .select: break
        }
        return style
    }

    // Decodes what it can and keeps the defaults for the rest, so an older saved style still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let base = MarkStyle()
        color = value(.color, base.color)
        size = value(.size, base.size)
        fill = value(.fill, base.fill)
        cornerRadius = value(.cornerRadius, base.cornerRadius)
        shadow = value(.shadow, base.shadow)
        opacity = value(.opacity, base.opacity)
        dashed = value(.dashed, base.dashed)
        arrow = value(.arrow, base.arrow)
        curved = value(.curved, base.curved)
        head = value(.head, base.head)
        text = value(.text, base.text)
        font = value(.font, base.font)
        bold = value(.bold, base.bold)
        counter = value(.counter, base.counter)
        redaction = value(.redaction, base.redaction)
    }
}

// MARK: Annotation

/// One mark on the screenshot. Coordinates are image points with a top-left origin.
public struct Annotation: Identifiable, Equatable {
    public enum Kind: Equatable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case text(origin: CGPoint, string: String)
        case counter(center: CGPoint, number: Int)
        case pen([CGPoint])
        case highlight(CGRect)
        case redact(CGRect)
        /// Dims everything outside this rect.
        case spotlight(CGRect)
    }

    public let id: UUID
    public var kind: Kind
    public var style: MarkStyle
    /// Lines and arrows: the control point of a quadratic curve. Nil keeps them straight.
    public var bend: CGPoint?

    public init(id: UUID = UUID(), kind: Kind, style: MarkStyle, bend: CGPoint? = nil) {
        self.id = id
        self.kind = kind
        self.style = style
        self.bend = bend
    }

    /// A mark in its tool's default style, at one of the four quick sizes.
    /// - Parameter filled: Shapes get a tinted interior, text a label pill, and redaction a solid block.
    public init(
        id: UUID = UUID(), kind: Kind, color: Ink = .red, weight: Weight = .regular, filled: Bool = false,
        bend: CGPoint? = nil
    ) {
        let tool = Annotation(id: id, kind: kind, style: MarkStyle()).tool
        var style = MarkStyle.defaults(for: tool)
        style.color = color
        switch tool.sizeKind {
        case .stroke: style.size = weight.stroke
        case .font: style.size = weight.fontSize
        case .counter: style.size = weight.counterSize
        default: break
        }
        switch kind {
        case .rectangle, .ellipse: style.fill = filled ? .tinted : .outline
        case .text: style.text = filled ? .pill : .outlined
        case .redact: style.redaction = filled ? .blackout : .pixelate
        default: break
        }
        self.init(id: id, kind: kind, style: style, bend: bend)
    }

    public var color: Ink {
        get { style.color }
        set { style.color = newValue }
    }
}

enum TextMetrics {
    static func font(_ style: MarkStyle) -> NSFont {
        let size = max(style.size, 4)
        let system = NSFont.systemFont(ofSize: size, weight: style.bold ? .semibold : .regular)
        switch style.font {
        case .system:
            return system
        case .rounded, .serif:
            let design: NSFontDescriptor.SystemDesign = style.font == .rounded ? .rounded : .serif
            guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
            return NSFont(descriptor: descriptor, size: size) ?? system
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: style.bold ? .semibold : .regular)
        case .marker:
            return NSFont(name: style.bold ? "MarkerFelt-Wide" : "MarkerFelt-Thin", size: size) ?? system
        }
    }

    static func padding(_ style: MarkStyle) -> CGSize {
        let size = max(style.size, 4)
        if style.text == .pill {
            return CGSize(width: (size * 0.5).rounded(), height: (size * 0.22).rounded())
        }
        // Room for the outline, so nothing is clipped at the frame's edge.
        return CGSize(width: (size * 0.12).rounded() + 2, height: (size * 0.06).rounded() + 1)
    }

    static func textSize(_ string: String, _ style: MarkStyle) -> CGSize {
        let measured = (string.isEmpty ? " " : string) as NSString
        let rect = measured.boundingRect(
            with: CGSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font(style)]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// The label's outer frame, padding included.
    static func frame(origin: CGPoint, string: String, style: MarkStyle) -> CGRect {
        let text = textSize(string, style)
        let pad = padding(style)
        return CGRect(x: origin.x, y: origin.y, width: text.width + pad.width * 2, height: text.height + pad.height * 2)
    }
}

extension Annotation {
    var tool: Tool {
        switch kind {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: style.fill == .solid ? .filledRectangle : .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .counter: .counter
        case .pen: .pen
        case .highlight: .highlight
        case .redact: .redact
        case .spotlight: .spotlight
        }
    }

    /// Stroke width in points, for marks drawn with a line.
    var lineWidth: CGFloat { tool.sizeKind == .stroke ? style.size : 4 }

    /// Points along a line or arrow, curved or straight. Nil for other kinds.
    func pathPoints(samples: Int = 24) -> [CGPoint]? {
        guard let ends = endpoints else { return nil }
        guard let c = bend else { return [ends.from, ends.to] }
        return (0 ... samples).map { quadPoint(ends.from, c, ends.to, CGFloat($0) / CGFloat(samples)) }
    }

    /// The point halfway along the curve, where its bend handle sits.
    var bendHandle: CGPoint? {
        guard let ends = endpoints else { return nil }
        guard let c = bend else { return (ends.from + ends.to) * 0.5 }
        return quadPoint(ends.from, c, ends.to, 0.5)
    }

    /// Bends the curve so it passes through `handle` halfway along. Close to straight, it snaps straight.
    func bent(through handle: CGPoint) -> Annotation {
        guard let ends = endpoints else { return self }
        var copy = self
        let mid = (ends.from + ends.to) * 0.5
        copy.bend = handle.distance(to: mid) < 4 ? nil : handle * 2 - mid
        return copy
    }

    /// A gentle arc, bowed to the left of the direction of travel, for the curved style.
    func withAutomaticBend() -> Annotation {
        guard let ends = endpoints else { return self }
        let delta = ends.to - ends.from
        guard delta.length > 1 else { return self }
        let normal = CGPoint(x: delta.y, y: -delta.x) * (1 / delta.length)
        return bent(through: (ends.from + ends.to) * 0.5 + normal * (delta.length * 0.22))
    }

    /// Geometric bounds, ignoring stroke width.
    var frame: CGRect {
        switch kind {
        case .arrow, .line:
            let points = pathPoints() ?? []
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case let .rectangle(r), let .ellipse(r), let .highlight(r), let .redact(r), let .spotlight(r):
            return r
        case let .text(origin, string):
            return TextMetrics.frame(origin: origin, string: string, style: style)
        case let .counter(center, _):
            let r = style.size / 2
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        case let .pen(points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        }
    }

    /// Rect-shaped kinds resize from their corners.
    var resizableRect: CGRect? {
        switch kind {
        case let .rectangle(r), let .ellipse(r), let .highlight(r), let .redact(r), let .spotlight(r): r
        default: nil
        }
    }

    var endpoints: (from: CGPoint, to: CGPoint)? {
        switch kind {
        case let .arrow(a, b), let .line(a, b): (a, b)
        default: nil
        }
    }

    func withRect(_ rect: CGRect) -> Annotation {
        var copy = self
        switch kind {
        case .rectangle: copy.kind = .rectangle(rect)
        case .ellipse: copy.kind = .ellipse(rect)
        case .highlight: copy.kind = .highlight(rect)
        case .redact: copy.kind = .redact(rect)
        case .spotlight: copy.kind = .spotlight(rect)
        default: break
        }
        return copy
    }

    func withEndpoints(from: CGPoint, to: CGPoint) -> Annotation {
        var copy = self
        // Dragging an end carries the curve along, so the bend keeps its character.
        if let bend, let ends = endpoints {
            copy.bend = bend + ((from - ends.from) + (to - ends.to)) * 0.5
        }
        switch kind {
        case .arrow: copy.kind = .arrow(from: from, to: to)
        case .line: copy.kind = .line(from: from, to: to)
        default: break
        }
        return copy
    }

    func translated(by d: CGPoint) -> Annotation {
        applying(CGAffineTransform(translationX: d.x, y: d.y))
    }

    /// The mark carried along by a crop, rotation, flip, or resize of the image under it. Text and
    /// step numbers stay upright. Sizes scale with the transform, so a resized image looks the same.
    func applying(_ t: CGAffineTransform) -> Annotation {
        var copy = self
        func p(_ point: CGPoint) -> CGPoint { point.applying(t) }
        func r(_ rect: CGRect) -> CGRect { rect.applying(t).standardized }
        let factor = sqrt(abs(t.a * t.d - t.b * t.c))
        if abs(factor - 1) > 0.001, tool.sizeKind != .none {
            copy.style.size = style.size * factor
        }
        switch kind {
        case let .arrow(a, b): copy.kind = .arrow(from: p(a), to: p(b))
        case let .line(a, b): copy.kind = .line(from: p(a), to: p(b))
        case let .rectangle(rect): copy.kind = .rectangle(r(rect))
        case let .ellipse(rect): copy.kind = .ellipse(r(rect))
        case let .highlight(rect): copy.kind = .highlight(r(rect))
        case let .redact(rect): copy.kind = .redact(r(rect))
        case let .spotlight(rect): copy.kind = .spotlight(r(rect))
        case let .counter(center, number): copy.kind = .counter(center: p(center), number: number)
        case let .pen(points): copy.kind = .pen(points.map(p))
        case let .text(origin, string):
            if t.b == 0, t.c == 0, t.a == 1, t.d == 1 {
                copy.kind = .text(origin: p(origin), string: string)
            } else {
                // Keep the label's centre where the transform puts it.
                let centre = p(frame.center)
                let size = TextMetrics.frame(origin: origin, string: string, style: copy.style).size
                copy.kind = .text(origin: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), string: string)
            }
        }
        copy.bend = bend.map(p)
        return copy
    }

    /// Marks whose whole interior is solid: highlights, redactions, spotlights, and filled shapes.
    var coversArea: Bool {
        switch kind {
        case .highlight, .redact, .spotlight: true
        case .rectangle, .ellipse: style.fill != .outline
        default: false
        }
    }

    /// Whether the point is on the mark's edge, as opposed to anywhere inside it.
    func hitsOutline(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        var outline = self
        outline.style.fill = .outline
        if let rect = resizableRect, tool != .ellipse {
            outline.kind = .rectangle(rect)
        }
        return outline.hitTest(p, tolerance: tolerance)
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = max(lineWidth / 2, tolerance)
        let filled = style.fill != .outline
        switch kind {
        case .arrow, .line:
            // The head is wider than the shaft, so give arrows a little more reach.
            let extra = tool == .arrow ? lineWidth * style.head.factor : 0
            let points = pathPoints() ?? []
            return zip(points, points.dropFirst()).contains { p.distance(toSegment: $0, $1) <= reach + extra }
        case let .rectangle(r):
            guard r.insetBy(dx: -reach, dy: -reach).contains(p) else { return false }
            return filled || !r.insetBy(dx: reach, dy: reach).contains(p)
        case let .ellipse(r):
            guard r.width > 0, r.height > 0 else { return false }
            let nx = (p.x - r.midX) / (r.width / 2)
            let ny = (p.y - r.midY) / (r.height / 2)
            let radial = hypot(nx, ny)
            let band = reach / (min(r.width, r.height) / 2)
            return filled ? radial <= 1 + band : abs(radial - 1) <= band
        case .text, .counter, .highlight, .redact, .spotlight:
            return frame.insetBy(dx: -2, dy: -2).contains(p)
        case let .pen(points):
            guard points.count > 1 else { return points.first.map { $0.distance(to: p) <= reach } ?? false }
            return zip(points, points.dropFirst()).contains { p.distance(toSegment: $0, $1) <= reach }
        }
    }
}

/// A point on the quadratic curve from `a` to `b` with control `c`.
func quadPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return a * (u * u) + c * (2 * u * t) + b * (t * t)
}

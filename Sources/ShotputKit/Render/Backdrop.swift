import AppKit
import CoreImage
import ImageIO
import ScreenCaptureKit

/// Puts a screenshot on a backdrop: a gradient, a colour, the desktop wallpaper or a picture, with
/// padding, rounded corners and a soft shadow, optionally in a fixed aspect ratio. Used for window
/// captures and by the editor's Background control. Every fill is drawn in code or comes from the
/// Mac itself, so Shotput ships no background images.
enum Backdrop {
    enum Fill: Equatable {
        /// The wallpaper of the screen the capture came from, as it is on screen right now.
        case wallpaper
        /// A picture on this Mac: one of the system's desktop pictures, or one you added.
        case picture(URL)
        case color(NSColor)
        case gradient(Gradient)
        /// Nothing behind the image: padding and shadow only, on transparency.
        case clear

        /// Fills drawn from a picture, which the caller loads and passes to `compose`.
        var needsPicture: Bool {
            switch self {
            case .wallpaper, .picture: true
            default: false
            }
        }
    }

    /// A linear gradient, as colours from one end to the other and the direction it runs.
    struct Gradient: Equatable, Hashable {
        var colors: [UInt]
        /// Degrees clockwise from pointing up: 90 runs left to right, 135 from top left to bottom right.
        var angle: CGFloat = 135

        var nsColors: [NSColor] { colors.map { NSColor(hex: $0) } }
    }

    enum Ratio: String, CaseIterable, Identifiable {
        case auto, square, fourThree, threeTwo, sixteenNine, fourFive, nineSixteen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: L("Auto")
            case .square: L("Square, 1:1")
            case .fourThree: "4:3"
            case .threeTwo: "3:2"
            case .sixteenNine: "16:9"
            case .fourFive: L("Portrait, 4:5")
            case .nineSixteen: L("Story, 9:16")
            }
        }

        /// Width over height, or nil to follow the image.
        var value: CGFloat? {
            switch self {
            case .auto: nil
            case .square: 1
            case .fourThree: 4.0 / 3
            case .threeTwo: 3.0 / 2
            case .sixteenNine: 16.0 / 9
            case .fourFive: 4.0 / 5
            case .nineSixteen: 9.0 / 16
            }
        }
    }

    /// Where the image sits when a fixed ratio leaves room around it. Row by row from top left.
    enum Alignment: Int, CaseIterable, Identifiable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

        var id: Int { rawValue }
        /// 0 for leading, 0.5 for centred, 1 for trailing, on each axis. Y runs down.
        var unit: CGPoint { CGPoint(x: CGFloat(rawValue % 3) / 2, y: CGFloat(rawValue / 3) / 2) }
    }

    struct Style: Equatable {
        var fill: Fill
        /// Points of backdrop around the image, at the least.
        var padding: CGFloat
        /// Points of the screenshot's own edge colour added around it, inside the rounded corners.
        var inset: CGFloat = 0
        /// Trims uneven margins of that edge colour, so the content sits evenly inside the inset.
        var autoBalance = false
        /// Points. Applies to area captures; window captures keep their own corners.
        var cornerRadius: CGFloat = 10
        /// 0 for none to 1 for a deep, soft shadow.
        var shadow: CGFloat = 0.65
        /// Softens a wallpaper or picture so the screenshot stands out from it.
        var blur = false
        var ratio: Ratio = .auto
        var alignment: Alignment = .center
    }

    // MARK: Layout

    /// The canvas and where the image sits on it, in pixels with a top-left origin.
    static func layout(imageSize: CGSize, scale: CGFloat, style: Style) -> (canvas: CGSize, frame: CGRect) {
        let padding = (style.padding * scale).rounded()
        var canvas = CGSize(width: imageSize.width + padding * 2, height: imageSize.height + padding * 2)
        if let ratio = style.ratio.value {
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        let room = CGSize(width: canvas.width - padding * 2 - imageSize.width, height: canvas.height - padding * 2 - imageSize.height)
        let unit = style.alignment.unit
        let origin = CGPoint(x: (padding + room.width * unit.x).rounded(), y: (padding + room.height * unit.y).rounded())
        return (canvas, CGRect(origin: origin, size: imageSize))
    }

    /// Where the original image's top-left pixel lands on the canvas, in points, so marks can
    /// move with it. Inset and auto-balance move it within the framed screenshot too.
    static func imageOrigin(of image: CGImage, scale: CGFloat, style: Style?) -> CGPoint {
        guard let style else { return .zero }
        let prepared = prepare(image, scale: scale, style: style)
        let frame = layout(imageSize: CGSize(width: prepared.image.width, height: prepared.image.height), scale: scale, style: style).frame
        return CGPoint(x: (frame.minX + prepared.offset.x) / scale, y: (frame.minY + prepared.offset.y) / scale)
    }

    // MARK: Inset

    /// The screenshot as it will sit on the backdrop: trimmed to its content when balancing, and
    /// grown by the inset in its own edge colour. `offset` is where the original's top-left pixel
    /// ends up, in pixels from the top left. Window captures, with their transparent corners and
    /// shadow, are left as they are.
    static func prepare(_ image: CGImage, scale: CGFloat, style: Style) -> (image: CGImage, offset: CGPoint) {
        guard hasOpaqueCorner(image) else {
            // A window: its corners, rounded to the radius asked for.
            return (roundedWindow(image, radius: style.cornerRadius * scale), .zero)
        }
        guard style.inset > 0 || style.autoBalance, let edge = edgeColor(of: image) else {
            return (image, .zero)
        }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let content = style.autoBalance ? contentBounds(of: image, edge: edge) ?? full : full
        let inset = Int((style.inset * scale).rounded())
        let width = Int(content.width) + inset * 2, height = Int(content.height) + inset * 2
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cropped = image.cropping(to: content) else { return (image, .zero) }
        context.setFillColor(edge)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cropped, in: CGRect(x: inset, y: inset, width: Int(content.width), height: Int(content.height)))
        guard let result = context.makeImage() else { return (image, .zero) }
        return (result, CGPoint(x: CGFloat(inset) - content.minX, y: CGFloat(inset) - content.minY))
    }

    private static var edgeCache: (key: ObjectIdentifier, color: CGColor?)?

    /// The colour most of the image's outermost pixels share, or nil when the border is busy.
    /// Worked out once per image, since slider drags ask on every step.
    private static func edgeColor(of image: CGImage) -> CGColor? {
        if let edgeCache, edgeCache.key == ObjectIdentifier(image) { return edgeCache.color }
        let color = findEdgeColor(of: image)
        edgeCache = (ObjectIdentifier(image), color)
        return color
    }

    private static func findEdgeColor(of image: CGImage) -> CGColor? {
        guard let pixels = Pixels(image) else { return nil }
        var counts: [UInt32: Int] = [:]
        let step = max(1, (pixels.width + pixels.height) / 400)
        var total = 0
        for x in stride(from: 0, to: pixels.width, by: step) {
            for y in [0, pixels.height - 1] { counts[pixels.key(x, y), default: 0] += 1; total += 1 }
        }
        for y in stride(from: 0, to: pixels.height, by: step) {
            for x in [0, pixels.width - 1] { counts[pixels.key(x, y), default: 0] += 1; total += 1 }
        }
        guard let (key, count) = counts.max(by: { $0.value < $1.value }), Double(count) / Double(max(total, 1)) > 0.45 else { return nil }
        return CGColor(srgbRed: CGFloat(key >> 24 & 0xFF) / 255, green: CGFloat(key >> 16 & 0xFF) / 255, blue: CGFloat(key >> 8 & 0xFF) / 255, alpha: 1)
    }

    private static var contentCache: (key: ObjectIdentifier, bounds: CGRect?)?

    /// The smallest rectangle holding everything that isn't the edge colour, in pixels from the top left.
    private static func contentBounds(of image: CGImage, edge: CGColor) -> CGRect? {
        if let contentCache, contentCache.key == ObjectIdentifier(image) { return contentCache.bounds }
        guard let pixels = Pixels(image), let c = edge.components, c.count >= 3 else { return nil }
        let target = (UInt8(c[0] * 255), UInt8(c[1] * 255), UInt8(c[2] * 255))
        func differs(_ x: Int, _ y: Int) -> Bool {
            let p = pixels.rgb(x, y)
            return abs(Int(p.0) - Int(target.0)) + abs(Int(p.1) - Int(target.1)) + abs(Int(p.2) - Int(target.2)) > 24
        }
        var minX = pixels.width, minY = pixels.height, maxX = -1, maxY = -1
        for y in 0 ..< pixels.height {
            for x in 0 ..< pixels.width where differs(x, y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let bounds = maxX < minX ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        contentCache = (ObjectIdentifier(image), bounds)
        return bounds
    }

    // MARK: Window corners

    /// A window capture's body: the opaque rectangle inside its shadow, in pixels from the top
    /// left, with the colours its four corners would have if they weren't rounded.
    private struct WindowBody {
        let rect: CGRect
        /// Top left, top right, bottom left, bottom right.
        let corners: [CGColor]
    }

    private static var bodyCache: (key: ObjectIdentifier, body: WindowBody?)?

    private static func windowBody(of image: CGImage) -> WindowBody? {
        if let bodyCache, bodyCache.key == ObjectIdentifier(image) { return bodyCache.body }
        let body = findWindowBody(of: image)
        bodyCache = (ObjectIdentifier(image), body)
        return body
    }

    private static func findWindowBody(of image: CGImage) -> WindowBody? {
        guard let pixels = Pixels(image) else { return nil }
        // The middle row and column cross the body at full opacity; walk out from the centre to
        // where opacity drops away into the shadow.
        let midX = pixels.width / 2, midY = pixels.height / 2
        guard pixels.alpha(midX, midY) > 250 else { return nil }
        var left = midX, right = midX, top = midY, bottom = midY
        while left > 0, pixels.alpha(left - 1, midY) > 250 { left -= 1 }
        while right < pixels.width - 1, pixels.alpha(right + 1, midY) > 250 { right += 1 }
        while top > 0, pixels.alpha(midX, top - 1) > 250 { top -= 1 }
        while bottom < pixels.height - 1, pixels.alpha(midX, bottom + 1) > 250 { bottom += 1 }
        let rect = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        guard rect.width > 40, rect.height > 40 else { return nil }
        // Each corner's colour, read just past where the window's own rounding ends.
        let reach = min(Int(rect.width) / 4, Int(rect.height) / 4, 48)
        func color(_ x: Int, _ y: Int) -> CGColor {
            let p = pixels.rgb(x, y)
            return CGColor(srgbRed: CGFloat(p.0) / 255, green: CGFloat(p.1) / 255, blue: CGFloat(p.2) / 255, alpha: 1)
        }
        let corners = [
            color(left + reach, top + 2), color(right - reach, top + 2),
            color(left + reach, bottom - 2), color(right - reach, bottom - 2),
        ]
        return WindowBody(rect: rect, corners: corners)
    }

    /// The window with corners of `radius` pixels. Its own rounding is filled in first with each
    /// corner's colour, so any radius works, square included. The shadow around it is kept.
    static func roundedWindow(_ image: CGImage, radius: CGFloat) -> CGImage {
        guard let body = windowBody(of: image) else { return image }
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        // CoreGraphics' origin is bottom left.
        let rect = CGRect(x: body.rect.minX, y: CGFloat(height) - body.rect.maxY, width: body.rect.width, height: body.rect.height)
        let r = min(max(radius, 0), min(rect.width, rect.height) / 2)
        let full = CGRect(x: 0, y: 0, width: width, height: height)

        // Outside the body: the shadow, untouched.
        context.saveGState()
        context.addRect(full)
        context.addRect(rect)
        context.clip(using: .evenOdd)
        context.draw(image, in: full)
        context.restoreGState()

        // The body, squared off with its corner colours, then cut to the new radius.
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        context.clip()
        let square = min(rect.width, rect.height) / 2
        let patches = [
            CGRect(x: rect.minX, y: rect.maxY - square, width: square, height: square),
            CGRect(x: rect.maxX - square, y: rect.maxY - square, width: square, height: square),
            CGRect(x: rect.minX, y: rect.minY, width: square, height: square),
            CGRect(x: rect.maxX - square, y: rect.minY, width: square, height: square),
        ]
        for (patch, color) in zip(patches, body.corners) {
            context.setFillColor(color)
            context.fill(patch)
        }
        context.draw(image, in: full)
        context.restoreGState()
        return context.makeImage() ?? image
    }

    /// The image's pixels as 8-bit sRGB, top row first.
    private struct Pixels {
        let width: Int, height: Int
        private let data: [UInt8]

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            data = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }

        func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * width + x) * 4
            return (data[i], data[i + 1], data[i + 2])
        }

        /// The pixel's colour, quantised a little so near-identical shades count together.
        func key(_ x: Int, _ y: Int) -> UInt32 {
            let p = rgb(x, y)
            return UInt32(p.0 & 0xFC) << 24 | UInt32(p.1 & 0xFC) << 16 | UInt32(p.2 & 0xFC) << 8
        }
    }

    // MARK: Drawing

    /// - Parameters:
    ///   - picture: The wallpaper or picture, for those fills. Without it they fall back to a neutral colour.
    ///   - addsShadow: False when the image already carries the system's window shadow.
    static func compose(_ original: CGImage, scale: CGFloat, style: Style, wallpaper picture: CGImage?, addsShadow: Bool = true) -> CGImage {
        let image = prepare(original, scale: scale, style: style).image
        let size = CGSize(width: image.width, height: image.height)
        let (canvasSize, topLeftFrame) = layout(imageSize: size, scale: scale, style: style)
        let width = Int(canvasSize.width), height = Int(canvasSize.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return original }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        guard context.width > 0 else { return original }

        if let fill = fillImage(style, picture: picture, scale: scale, size: canvasSize) {
            context.draw(fill, in: canvas)
        }

        // CoreGraphics' origin is bottom left.
        let frame = CGRect(x: topLeftFrame.minX, y: canvasSize.height - topLeftFrame.maxY, width: size.width, height: size.height)
        // Area captures are square-cornered and opaque; round them so they sit on the backdrop
        // like a window does. Windows were rounded to the same radius as they were prepared.
        let rounds = hasOpaqueCorner(image)
        let radius = min(max(style.cornerRadius, 0) * scale, min(frame.width, frame.height) / 2)
        let shape = CGPath(roundedRect: frame, cornerWidth: rounds ? radius : 0, cornerHeight: rounds ? radius : 0, transform: nil)

        let depth = min(max(style.shadow, 0), 1)
        if addsShadow, depth > 0, let shadow = softShadow(image, shape: rounds ? shape : nil, frame: frame, canvas: canvasSize, depth: depth, scale: scale) {
            context.draw(shadow, in: canvas)
        }
        context.saveGState()
        if rounds {
            context.addPath(shape)
            context.clip()
        }
        context.draw(image, in: frame)
        context.restoreGState()
        return context.makeImage() ?? original
    }

    /// The shadow on its own, at the canvas's size: drawn at a quarter of it, then scaled up on the
    /// GPU. It's a wide, soft blur, so nothing is lost, and slider drags stay smooth even on a
    /// full Retina screen.
    private static func softShadow(_ image: CGImage, shape: CGPath?, frame: CGRect, canvas: CGSize, depth: CGFloat, scale: CGFloat) -> CGImage? {
        let factor: CGFloat = 4
        let width = Int((canvas.width / factor).rounded(.up)), height = Int((canvas.height / factor).rounded(.up))
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        // Shadow offset and blur are in device pixels, which the scale below doesn't touch.
        context.setShadow(
            offset: CGSize(width: 0, height: -(3 + 11 * depth) * scale / factor),
            blur: (8 + 44 * depth) * scale / factor,
            color: NSColor.black.withAlphaComponent(0.12 + 0.32 * depth).cgColor
        )
        context.scaleBy(x: 1 / factor, y: 1 / factor)
        if let shape {
            context.addPath(shape)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
        } else {
            context.draw(image, in: frame)
        }
        guard let small = context.makeImage() else { return nil }
        let extent = CGRect(origin: .zero, size: canvas)
        let scaled = CIImage(cgImage: small)
            .transformed(by: CGAffineTransform(scaleX: canvas.width / CGFloat(width), y: canvas.height / CGFloat(height)))
            .cropped(to: extent)
        return imageContext.createCGImage(scaled, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    // MARK: Fills

    private struct FillKey: Equatable {
        let fill: Fill
        let blur: Bool
        let size: CGSize
        let picture: ObjectIdentifier?
    }

    /// The last fill drawn, reused while only corners, shadow or alignment change.
    private static var fillCache: (key: FillKey, image: CGImage)?

    /// The backdrop behind the screenshot, at the canvas's size. Nil for transparency.
    private static func fillImage(_ style: Style, picture: CGImage?, scale: CGFloat, size: CGSize) -> CGImage? {
        if case .clear = style.fill { return nil }
        let key = FillKey(fill: style.fill, blur: style.blur, size: size, picture: picture.map(ObjectIdentifier.init))
        if let fillCache, fillCache.key == key { return fillCache.image }
        let image: CGImage?
        if case let .gradient(gradient) = style.fill {
            image = gradientImage(gradient, size: size)
        } else {
            let width = Int(size.width), height = Int(size.height)
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            let canvas = CGRect(x: 0, y: 0, width: width, height: height)
            context.interpolationQuality = .high
            switch style.fill {
            case let .color(color):
                context.setFillColor((color.usingColorSpace(.sRGB) ?? .white).cgColor)
                context.fill(canvas)
            default:
                if let picture {
                    let source = style.blur ? blurred(picture, scale: scale) ?? picture : picture
                    context.draw(source, in: aspectFill(CGSize(width: source.width, height: source.height), in: canvas))
                } else {
                    context.setFillColor(NSColor(hex: 0xE9E6DF).cgColor)
                    context.fill(canvas)
                }
            }
            image = context.makeImage()
        }
        if let image { fillCache = (key, image) }
        return image
    }

    /// A gradient at full size: drawn small, since it's smooth, then scaled up and given a faint
    /// grain on the GPU so wide gradients don't band in an 8-bit image.
    private static func gradientImage(_ gradient: Gradient, size: CGSize) -> CGImage? {
        let factor: CGFloat = 4
        let small = CGSize(width: max((size.width / factor).rounded(.up), 2), height: max((size.height / factor).rounded(.up), 2))
        guard let context = CGContext(
            data: nil, width: Int(small.width), height: Int(small.height), bitsPerComponent: 16, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        drawGradient(gradient, in: CGRect(origin: .zero, size: small), context, grained: false)
        guard let smooth = context.makeImage() else { return nil }
        let extent = CGRect(origin: .zero, size: size)
        let scaled = CIImage(cgImage: smooth)
            .transformed(by: CGAffineTransform(scaleX: size.width / small.width, y: size.height / small.height))
            .cropped(to: extent)
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return imageContext.createCGImage(scaled, from: extent)
        }
        // Grey noise overlaid, then mixed back in at a twentieth: each pixel nudged a shade up or
        // down, as the grain was when drawn on the CPU.
        let grey = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]).cropped(to: extent)
        let overlaid = grey.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: scaled])
        let grained = overlaid.applyingFilter("CIMix", parameters: [kCIInputBackgroundImageKey: scaled, "inputAmount": 0.05])
        return imageContext.createCGImage(grained, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The gradient across the whole canvas at its angle, with a faint grain so wide, smooth
    /// gradients don't band in an 8-bit image.
    static func drawGradient(_ gradient: Gradient, in canvas: CGRect, _ context: CGContext, grained: Bool = true) {
        let colors = gradient.nsColors.map(\.cgColor) as CFArray
        guard let cg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) else { return }
        // A line through the centre at the angle, long enough to reach the corners.
        let radians = (gradient.angle - 90) * .pi / 180
        let direction = CGPoint(x: cos(radians), y: -sin(radians))
        let half = (abs(direction.x) * canvas.width + abs(direction.y) * canvas.height) / 2
        let start = CGPoint(x: canvas.midX - direction.x * half, y: canvas.midY - direction.y * half)
        let end = CGPoint(x: canvas.midX + direction.x * half, y: canvas.midY + direction.y * half)
        context.saveGState()
        context.clip(to: canvas)
        context.drawLinearGradient(cg, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        if grained, let grain {
            context.setBlendMode(.overlay)
            context.setAlpha(0.05)
            context.draw(grain, in: CGRect(origin: canvas.origin, size: CGSize(width: grain.width, height: grain.height)), byTiling: true)
        }
        context.restoreGState()
    }

    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    /// A tile of monochrome noise from Core Image, made once: no image files involved.
    private static let grain: CGImage? = {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        return imageContext.createCGImage(mono, from: CGRect(x: 0, y: 0, width: 256, height: 256))
    }()

    /// A softened copy of the picture, worked at a modest size since the blur hides the detail.
    private static var blurCache: (key: ObjectIdentifier, image: CGImage)?

    private static func blurred(_ picture: CGImage, scale: CGFloat) -> CGImage? {
        if let blurCache, blurCache.key == ObjectIdentifier(picture) { return blurCache.image }
        let input = CIImage(cgImage: picture)
        let longest = max(input.extent.width, input.extent.height)
        let shrink = min(1, 1600 / longest)
        let small = input.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        let radius = max(small.extent.width, small.extent.height) * 0.025
        let soft = small.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: small.extent)
        guard let result = imageContext.createCGImage(soft, from: small.extent) else { return nil }
        blurCache = (ObjectIdentifier(picture), result)
        return result
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let fill = max(rect.width / size.width, rect.height / size.height)
        let scaled = CGSize(width: size.width * fill, height: size.height * fill)
        return CGRect(x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2, width: scaled.width, height: scaled.height)
    }

    /// Whether the image's top-left pixel is opaque: area captures are, window captures aren't.
    static func hasOpaqueCorner(_ image: CGImage) -> Bool {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        // Draw so the image's top-left pixel lands on the single pixel of the context.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return pixel[3] > 200
    }

    // MARK: Pictures

    /// A picture file, decoded no larger than `maxPixels` on its long side.
    static func loadPicture(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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

// MARK: - Built-in fills

extension Backdrop.Gradient {
    /// Drawn from a handful of colours each, so they cost nothing to ship.
    static let presets: [Backdrop.Gradient] = [
        .init(colors: [0xFF5F6D, 0xFFC371]),
        .init(colors: [0xF857A6, 0xFF5858]),
        .init(colors: [0xFF9A9E, 0xFAD0C4, 0xFBC2EB]),
        .init(colors: [0xA18CD1, 0xFBC2EB]),
        .init(colors: [0xE0C3FC, 0x8EC5FC]),
        .init(colors: [0x7F00FF, 0xE100FF]),
        .init(colors: [0x8E2DE2, 0x4A00E0]),
        .init(colors: [0x4776E6, 0x8E54E9]),
        .init(colors: [0x36D1DC, 0x5B86E5]),
        .init(colors: [0x2E3192, 0x1BFFFF]),
        .init(colors: [0x43CEA2, 0x185A9D]),
        .init(colors: [0x11998E, 0x38EF7D]),
        .init(colors: [0xD4FC79, 0x96E6A1]),
        .init(colors: [0xF7971E, 0xFFD200]),
        .init(colors: [0xFFDEE9, 0xB5FFFC]),
        .init(colors: [0xFDFBFB, 0xEBEDEE]),
        .init(colors: [0xFC5C7D, 0x6A82FB]),
        .init(colors: [0x00C9FF, 0x92FE9D]),
        .init(colors: [0x0F2027, 0x203A43, 0x2C5364]),
        .init(colors: [0x232526, 0x414345]),
    ]
}

extension Backdrop {
    /// Plain colours in two rows: strong ones, then the same hues soft, each led by a neutral.
    static let colorPresets: [UInt] = [
        0x000000, 0xFFFFFF, 0xFF3B30, 0xFF9500, 0xFFB800, 0x28A745, 0x1C7CEB, 0x8E3FF0,
        0x3A3A3C, 0xE5E5EA, 0xFFB3AE, 0xFFC680, 0xFFE38A, 0xA8E6B8, 0xA9D2FF, 0xD5BEFF,
    ]
}

import AppKit

/// The shapes the crop box can be held to.
enum AspectRatio: Hashable, CaseIterable {
    case freeform, original, square, fourThree, threeTwo, sixteenNine, threeFour, twoThree, nineSixteen

    var title: String {
        switch self {
        case .freeform: L("Freeform")
        case .original: L("Original ratio")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        case .threeFour: "3:4"
        case .twoThree: "2:3"
        case .nineSixteen: "9:16"
        }
    }

    /// Width over height, or nil for freeform.
    func value(original: CGSize) -> CGFloat? {
        switch self {
        case .freeform: nil
        case .original: original.height > 0 ? original.width / original.height : nil
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        case .threeFour: 3 / 4
        case .twoThree: 2 / 3
        case .nineSixteen: 9 / 16
        }
    }
}

/// An open crop: the box being adjusted, its shape, and the size the result will be saved at.
struct CropState: Equatable {
    /// Image points.
    var rect: CGRect
    var aspect: AspectRatio = .freeform
    /// The result's size relative to the crop box, for scaling the image down as it is cropped.
    var outputScale: CGFloat = 1
}

/// Where the image has strong straight edges, such as a window border or a panel's side, so the
/// crop box can snap to them.
enum EdgeFinder {
    /// - Returns: Candidate x and y positions in image points.
    static func edges(in image: CGImage, scale: CGFloat) -> (xs: [CGFloat], ys: [CGFloat]) {
        // Work on a small greyscale copy: fast, and fine detail does not make a useful edge.
        let factor = min(1, 900 / CGFloat(max(image.width, image.height)))
        let width = max(Int(CGFloat(image.width) * factor), 2)
        let height = max(Int(CGFloat(image.height) * factor), 2)
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return ([], []) }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The bitmap's first row is the image's top, matching the editor's top-left origin.
        func lum(_ x: Int, _ y: Int) -> Int { Int(pixels[y * width + x]) }

        // Back to whole pixels of the full image, so a snapped crop lands exactly on the edge.
        func points(_ small: Int) -> CGFloat { (CGFloat(small) / factor).rounded() / scale }
        var xs: [CGFloat] = []
        for x in 1 ..< width {
            var run = 0, best = 0
            for y in 0 ..< height {
                if abs(lum(x, y) - lum(x - 1, y)) > 9 { run += 1; best = max(best, run) } else { run = 0 }
            }
            if best >= max(height / 6, 12) { xs.append(points(x)) }
        }
        var ys: [CGFloat] = []
        for y in 1 ..< height {
            var run = 0, best = 0
            for x in 0 ..< width {
                if abs(lum(x, y) - lum(x, y - 1)) > 9 { run += 1; best = max(best, run) } else { run = 0 }
            }
            if best >= max(width / 6, 12) { ys.append(points(y)) }
        }
        return (xs, ys)
    }

    /// The nearest candidate within `reach`, or the value itself.
    static func snap(_ value: CGFloat, to candidates: [CGFloat], reach: CGFloat) -> CGFloat {
        guard let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) <= reach else { return value }
        return nearest
    }
}

/// Pixel operations behind rotate, flip, and resize.
enum ImageOps {
    private static func context(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? sRGB
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// A quarter turn, clockwise or not.
    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        guard let ctx = context(width: image.height, height: image.width, like: image) else { return nil }
        // Core Graphics has a bottom-left origin, so its turns run the other way to the editor's.
        ctx.translateBy(x: CGFloat(image.height) / 2, y: CGFloat(image.width) / 2)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return ctx.makeImage()
    }

    static func flipped(_ image: CGImage, horizontally: Bool) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height, like: image) else { return nil }
        if horizontally {
            ctx.translateBy(x: CGFloat(image.width), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        } else {
            ctx.translateBy(x: 0, y: CGFloat(image.height))
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    static func resampled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let ctx = context(width: width, height: height, like: image) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

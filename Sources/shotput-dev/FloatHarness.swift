// Floats two screenshots on screen, checks how they size, resize and snap, and captures the
// screen with them up. The capture needs Screen Recording for the terminal that runs it.
import AppKit
@testable import ShotputKit

@MainActor
func floatHarness(to path: String) {
    var failures = 0
    func expect(_ condition: Bool, _ label: String) {
        print(condition ? "  ok    \(label)" : "  FAIL  \(label)")
        if !condition { failures += 1 }
    }
    _ = NSApplication.shared
    guard let screen = NSScreen.main,
          let source = NSImage(contentsOfFile: "docs/editor.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fatalError("needs docs/editor.png and a screen") }

    let visible = screen.visibleFrame
    let a = Capture(image: source, scale: 2, screenRect: CGRect(x: visible.minX + 80, y: visible.minY + 120, width: CGFloat(source.width) / 2, height: CGFloat(source.height) / 2), screen: screen)
    let b = Capture(image: source, scale: 2, screen: screen)
    FloatingShots.shared.float(a)
    FloatingShots.shared.float(b)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let panels = FloatingShots.shared.panels
    expect(panels.count == 2, "two floats are up")
    expect(FloatingShots.shared.panels.allSatisfy { $0.level == .floating && $0.isVisible }, "floats sit above normal windows")

    let first = panels[0], second = panels[1]
    let fits = a.pointSize.width <= visible.width * 0.7 && a.pointSize.height <= visible.height * 0.7
    if fits {
        expect(first.frame.origin == a.screenRect!.origin, "a float opens where it was taken")
    } else {
        expect(first.frame.width <= visible.width * 0.7 + 1, "a large float opens no wider than most of the screen")
    }
    expect(visible.contains(second.frame), "a float with no origin opens on screen")

    // Smaller, keeping its shape.
    first.resize(by: 0.5, about: first.frame.center)
    let ratio = a.pointSize.width / a.pointSize.height
    expect(abs(first.frame.width / first.frame.height - ratio) < 0.02, "resizing keeps the aspect ratio")
    second.resize(by: 0.4, about: second.frame.center)
    first.setActualSize()
    expect(abs(first.zoom - 1) < 0.01 || !fits, "actual size is 100%")
    first.resize(by: 0.45, about: first.frame.center)

    // Side by side: dropped 6pt shy of its neighbour's right edge, it snaps flush, tops aligned.
    let left = first.frame
    var near = second.frame
    near.origin = CGPoint(x: left.maxX + 6, y: left.maxY - near.height + 4)
    let snapped = FloatingShots.snap(near, to: [left], within: visible)
    expect(snapped.minX == left.maxX, "a float snaps flush beside another")
    expect(snapped.maxY == left.maxY, "and lines its top up with it")
    let far = FloatingShots.snap(near.offsetBy(dx: 60, dy: 0), to: [left], within: visible)
    expect(far.minX == near.minX + 60, "a float far from others stays where it's put")
    second.setFrameOrigin(CGPoint(x: snapped.minX + 12, y: snapped.minY))
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))

    let union = first.frame.union(second.frame).insetBy(dx: -30, dy: -30).intersection(screen.frame).integral
    let top = (NSScreen.screens.first?.frame.maxY ?? 0) - union.maxY
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-R", "\(Int(union.minX)),\(Int(top)),\(Int(union.width)),\(Int(union.height))", path]
    shot.standardError = FileHandle.nullDevice
    try? shot.run()
    shot.waitUntilExit()
    if !FileManager.default.fileExists(atPath: path) {
        // Without Screen Recording, draw each float's own layers where it sits, over a plain desk.
        let scale: CGFloat = 2
        let width = Int(union.width * scale), height = Int(union.height * scale)
        if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.setFillColor(NSColor(calibratedRed: 0.36, green: 0.4, blue: 0.5, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            for panel in [first, second] {
                guard let layer = panel.contentView?.layer else { continue }
                context.saveGState()
                context.translateBy(x: panel.frame.minX - union.minX, y: panel.frame.minY - union.minY)
                context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.45).cgColor)
                context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: panel.frame.size), cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
                context.restoreGState()
                context.saveGState()
                context.translateBy(x: panel.frame.minX - union.minX, y: panel.frame.minY - union.minY)
                layer.render(in: context)
                context.restoreGState()
            }
            if let image = context.makeImage() { try? ImageCoding.pngData(image, scale: scale)?.write(to: URL(fileURLWithPath: path)) }
        }
    }
    print("wrote \(path)")
    FloatingShots.shared.closeAll()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
    if failures > 0 { exit(1) }
}

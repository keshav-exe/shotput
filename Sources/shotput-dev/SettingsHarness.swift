// Renders every Settings tab and every welcome guide step offscreen, and checks that each fits
// comfortably on a small laptop screen. Also checks the file name template.
import AppKit
import SwiftUI
@testable import ShotputKit

@MainActor
func settingsHarness(to path: String) {
    var failures = 0
    func expect(_ condition: Bool, _ label: String) {
        print(condition ? "  ok    \(label)" : "  FAIL  \(label)")
        if !condition { failures += 1 }
    }

    let base = (path as NSString).deletingPathExtension
    // The smallest supported screen is 800pt tall. Below a 25pt menu bar, a pane of 690pt plus
    // the 28pt title bar and 52pt tab bar just fits.
    let tallest: CGFloat = 690

    func render(_ view: some View, name: String, width: CGFloat?, appearance: NSAppearance.Name) -> CGSize {
        let host = NSHostingView(rootView: AnyView(view))
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        var size = host.fittingSize
        if let width { size.width = width }
        window.setContentSize(size)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return size }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let image = rep.cgImage {
            let file = "\(base)-\(name)-\(appearance == .darkAqua ? "dark" : "light").png"
            try? ImageCoding.pngData(image, scale: 2)?.write(to: URL(fileURLWithPath: file))
            print("wrote \(file)")
        }
        return size
    }

    // Measure each tab at its tallest: a solid window background shows every optional row.
    let settings = Settings.shared
    let savedBackground = settings.windowBackground
    settings.windowBackground = .solid
    defer { settings.windowBackground = savedBackground }

    for pane in SettingsWindowController.Pane.allCases {
        let view = pane.view.frame(width: SettingsWindowController.width).fixedSize(horizontal: false, vertical: true)
        let size = render(view.background(Color(nsColor: .windowBackgroundColor)), name: "settings-\(pane.title.lowercased())",
                          width: SettingsWindowController.width, appearance: .darkAqua)
        expect(size.height <= tallest, "\(pane.title) tab is \(Int(size.height))pt tall")
    }

    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        _ = render(CaptureBarView(defaultMode: .area) { _ in }.background(Color.gray), name: "capture-bar", width: nil, appearance: appearance)
    }

    NotchApps.assumeInstalled = ["NotchNook"]
    for step in OnboardingWindowController.Step.allCases {
        let state = OnboardingState(step: step)
        _ = render(OnboardingView(state: state).background(Color(nsColor: Palette.background)),
                   name: "welcome-\(step.rawValue)", width: nil, appearance: step.rawValue % 2 == 0 ? .darkAqua : .aqua)
    }

    // Frames of the welcome film at its key moments.
    let film = NSHostingView(rootView: WelcomeFilm())
    let filmWindow = NSWindow(contentRect: CGRect(origin: .zero, size: WelcomeFilm.stage), styleMask: [.borderless], backing: .buffered, defer: false)
    filmWindow.contentView = film
    film.frame = CGRect(origin: .zero, size: WelcomeFilm.stage)
    var elapsed = 0.0
    for (index, moment) in [1.4, 2.9, 3.9, 5.0, 7.6].enumerated() {
        RunLoop.main.run(until: Date().addingTimeInterval(moment - elapsed))
        elapsed = moment
        if let rep = film.bitmapImageRepForCachingDisplay(in: film.bounds) {
            film.cacheDisplay(in: film.bounds, to: rep)
            if let image = rep.cgImage { write(image, scale: 2, to: "\(base)-film-\(index).png") }
        }
    }

    let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 9, hour: 17, minute: 8, second: 4).date!
    expect(ImageCoding.fileName(template: Settings.defaultTemplate, date: date, appName: nil) == "Shotput 2026-07-09 at 17.08.04",
           "default template matches the old file names")
    expect(ImageCoding.fileName(template: "%n/%b %d", date: date, appName: "Safari") == "Safari-Jul 09", "slashes are replaced")
    expect(ImageCoding.fileName(template: "100%% %q", date: date, appName: nil) == "100% %q", "literal and unknown tokens survive")
    expect(ImageCoding.fileName(template: "   ", date: date, appName: nil).hasPrefix("Shotput 2026"), "empty template falls back")

    // The pixel at (x, y) from the top left, through a context of its own.
    func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var value: [UInt8] = [0, 0, 0, 0]
        value.withUnsafeMutableBytes { bytes in
            let one = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            one.draw(image, in: CGRect(x: -x, y: 1 - image.height + y, width: image.width, height: image.height))
        }
        return value
    }
    // Backdrops: padding grows the image, marks keep their place on the screenshot, undo restores.
    let plain = bitmap(width: 200, height: 100) { $0.setFillColor(rgb(0x1F6FE5)); $0.fill(CGRect(x: 0, y: 0, width: 200, height: 100)) }
    let model = EditorModel(base: plain, scale: 2)
    model.perform { $0.append(Annotation(kind: .counter(center: CGPoint(x: 10, y: 10), number: 1), color: .red)) }
    let style = Backdrop.Style(fill: .color(.white), padding: 20)
    model.setBackdrop(style, wallpaper: nil)
    expect(model.base.width == 280 && model.base.height == 180, "backdrop pads the image by 20pt a side at 2x")
    let moved: CGPoint? = { if case let .counter(center, _) = model.annotations[0].kind { return center }; return nil }()
    expect(moved == CGPoint(x: 30, y: 30), "marks move with the screenshot inside the backdrop")
    model.setBackdrop(Backdrop.Style(fill: .wallpaper, padding: 40), wallpaper: nil)
    expect(model.base.width == 360, "changing the backdrop reframes the original, not the framed image")
    model.setBackdrop(nil, wallpaper: nil)
    expect(model.base.width == 200 && model.backdrop == nil, "removing the backdrop gives the original back")
    model.undo()
    expect(model.base.width == 360 && model.backdrop?.style.padding == 40, "undo brings the backdrop back")
    let framed = Backdrop.compose(plain, scale: 2, style: style, wallpaper: nil)
    expect(sample(framed, x: 40, y: 40)[0] > 150, "area captures get rounded corners on a backdrop (corner pixel is backdrop, not image)")
    write(framed, scale: 2, to: "\(base)-backdrop.png")

    // Ratio and alignment: the canvas takes the ratio, the screenshot moves within it, and marks follow.
    let square = Backdrop.Style(fill: .gradient(Backdrop.Gradient.presets[0]), padding: 20, ratio: .square, alignment: .bottomRight)
    let layout = Backdrop.layout(imageSize: CGSize(width: 200, height: 100), scale: 2, style: square)
    expect(layout.canvas == CGSize(width: 280, height: 280), "a square ratio makes a square canvas around the padded image")
    expect(layout.frame.origin == CGPoint(x: 40, y: 140), "bottom right puts the image in that corner, inside the padding")
    model.setBackdrop(square, wallpaper: nil)
    let shifted: CGPoint? = { if case let .counter(center, _) = model.annotations[0].kind { return center }; return nil }()
    expect(shifted == CGPoint(x: 30, y: 80), "marks follow the screenshot when the ratio moves it")
    expect(model.base.width == 280 && model.base.height == 280, "the editor shows the ratio's canvas")

    // Transparent backdrop: rounded corners are see-through, and the radius is the one asked for.
    let clear = Backdrop.compose(plain, scale: 2, style: Backdrop.Style(fill: .clear, padding: 20, cornerRadius: 16, shadow: 0), wallpaper: nil)
    expect(sample(clear, x: 41, y: 41)[3] < 40, "a transparent backdrop leaves rounded corners see-through")
    let sharp = Backdrop.compose(plain, scale: 2, style: Backdrop.Style(fill: .clear, padding: 20, cornerRadius: 0, shadow: 0), wallpaper: nil)
    expect(sample(sharp, x: 41, y: 41)[3] > 240, "a zero radius keeps square corners")

    // Highlighter ink multiplies: dark text under it stays dark, white under it turns the ink's colour.
    let page = bitmap(width: 40, height: 20) { ctx in
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        ctx.setFillColor(rgb(0x111111)); ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
    }
    let marker = Annotation(kind: .highlight([CGPoint(x: 0, y: 10), CGPoint(x: 40, y: 10)]), style: .defaults(for: .highlight))
    if let inked = AnnotationRenderer().flatten(base: page, scale: 1, annotations: [marker], outputScale: 1) {
        let onWhite = sample(inked, x: 8, y: 10), onDark = sample(inked, x: 30, y: 10)
        expect(onWhite[0] > 230 && onWhite[2] < 170, "highlighter turns white paper yellow")
        expect(onDark.prefix(3).allSatisfy { $0 < 30 }, "dark text under the highlighter stays dark")
    } else {
        expect(false, "highlighter renders")
    }

    print(failures == 0 ? "all checks passed" : "\(failures) checks failed")
    if failures > 0 { exit(1) }
}

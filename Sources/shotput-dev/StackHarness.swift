// Shows four previews stacked in the corner, then fanned out as if pointed at, and captures
// both, so the stack can be judged on a real screen.
import AppKit
@testable import ShotputKit

@MainActor
func stackHarness(to path: String) {
    let base = (path as NSString).deletingPathExtension
    guard let screen = NSScreen.screens.first else { return }
    let settings = Settings.shared
    let savedDuration = settings.previewDuration
    settings.previewDuration = 0
    defer { settings.previewDuration = savedDuration }

    let colors: [UInt] = [0x1F6FE5, 0xE5484D, 0x30A46C, 0x8E4EC6]
    let sizes = [CGSize(width: 800, height: 500), CGSize(width: 400, height: 400), CGSize(width: 1200, height: 600), CGSize(width: 600, height: 380)]
    for (color, size) in zip(colors, sizes) {
        let image = bitmap(width: Int(size.width), height: Int(size.height)) { ctx in
            ctx.setFillColor(rgb(color))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(rgb(0xFFFFFF, 0.85))
            ctx.fill(CGRect(x: 40, y: size.height - 90, width: size.width * 0.5, height: 40))
        }
        PreviewPanelController.shared.show(Capture(image: image, scale: 2, screen: screen))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
    let visible = screen.visibleFrame
    let top = screen.frame.maxY - visible.maxY
    let region = CGRect(x: visible.maxX - 420, y: top + visible.height - 760, width: 420, height: 760)
    // Drawn from the windows themselves, back to front, so it needs no Screen Recording.
    let area = CGRect(x: visible.maxX - 420, y: visible.minY, width: 420, height: 760)
    func shoot(_ name: String) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let scale: CGFloat = 2
        let image = bitmap(width: Int(area.width * scale), height: Int(area.height * scale)) { ctx in
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(rgb(0xD8D4CC))
            ctx.fill(CGRect(origin: .zero, size: area.size))
            // Smaller cards sit further back, so draw them first.
            let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible && $0.level == .floating }.sorted { $0.frame.width < $1.frame.width }
            for panel in panels {
                guard let layer = panel.contentView?.layer else { continue }
                ctx.saveGState()
                let origin = panel.frame.origin
                ctx.translateBy(x: origin.x - area.minX, y: origin.y - area.minY)
                ctx.setAlpha(panel.alphaValue)
                layer.render(in: ctx)
                ctx.restoreGState()
            }
        }
        write(image, scale: scale, to: "\(base)-\(name).png")
    }
    shoot("stacked")
    // Put the pointer on the front card, as if reaching for it.
    let saved = NSEvent.mouseLocation
    let primary = NSScreen.screens[0].frame.height
    CGWarpMouseCursorPosition(CGPoint(x: visible.maxX - 120, y: primary - (visible.minY + 90)))
    PreviewPanelController.shared.pointerEntered()
    shoot("spread")
    CGWarpMouseCursorPosition(CGPoint(x: saved.x, y: primary - saved.y))
    PreviewPanelController.shared.dismissAll()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
}

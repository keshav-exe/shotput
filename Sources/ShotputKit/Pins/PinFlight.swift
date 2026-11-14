import AppKit

/// Files pinned by shortcut fly from where they were to where pins are taken: the notch, or the
/// menu bar icon. They lift a little, arc over, shrink into the target, and the island says so.
@MainActor
enum PinFlight {
    private static var windows: [NSWindow] = []

    static func fly(_ icons: [NSImage], from origin: CGPoint, landed: @escaping () -> Void) {
        let target = destination()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !icons.isEmpty,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main else {
            landed()
            return
        }

        // One clear window over the whole screen, so the icons can travel anywhere on it.
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 6)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.animationBehavior = .none
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)

        let start = CGPoint(x: origin.x - screen.frame.minX, y: origin.y - screen.frame.minY)
        let end = CGPoint(x: target.x - screen.frame.minX, y: target.y - screen.frame.minY)
        let duration = 0.62
        let stagger = 0.06

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            window.orderOut(nil)
            windows.removeAll { $0 === window }
        }
        for (index, icon) in icons.prefix(3).enumerated() {
            let layer = CALayer()
            layer.contents = icon
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = screen.backingScaleFactor
            layer.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
            layer.position = end
            layer.opacity = 0
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: -3)
            view.layer?.addSublayer(layer)

            // Fanned a touch at the start, so several files read as several.
            let spread = CGFloat(index) - CGFloat(min(icons.count, 3) - 1) / 2
            let from = CGPoint(x: start.x + spread * 18, y: start.y - abs(spread) * 4)
            // The arc bows up and over, the way a thrown thing travels, toward the top edge.
            let control = CGPoint(x: (from.x + end.x) / 2, y: max(from.y, end.y) + 40)
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: end, control: control)

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.7, 0.25)

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.6, 1.12, 1, 0.22]
            scale.keyTimes = [0, 0.18, 0.4, 1]

            let rotate = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            rotate.values = [spread * 0.12, spread * 0.2 - 0.08, 0]
            rotate.keyTimes = [0, 0.4, 1]

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.85, 1]

            let group = CAAnimationGroup()
            group.animations = [move, scale, rotate, fade]
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + Double(index) * stagger
            group.fillMode = .backwards
            layer.add(group, forKey: "flight")
        }
        CATransaction.commit()

        // The island answers as the first icon lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.88) { landed() }
    }

    /// The middle of the notch, or of the menu bar icon.
    private static func destination() -> CGPoint {
        if Settings.shared.pinTarget == .menuBar {
            let icon = MenuBarAnchor.target(on: NSScreen.underMouse)
            return CGPoint(x: icon.midX, y: icon.midY)
        }
        let geometry = NotchGeometry.underPointer()
        let notch = geometry.map { $0.hangingRect($0.size) } ?? .zero
        return CGPoint(x: notch.midX, y: notch.midY)
    }
}

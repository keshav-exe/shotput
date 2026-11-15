import AppKit
import SwiftUI

/// Where the drop island hangs, and from how big a notch. Screens without a notch get a stand-in
/// the size of a small one, drawn in glass at the top centre of the menu bar. With pins set to
/// the menu bar, it hangs under Shotput's icon instead and the "notch" is just the menu bar's height.
struct NotchGeometry: Equatable {
    /// The screen's full frame, in global coordinates.
    let screenFrame: CGRect
    /// The notch's width and height. Height is the menu bar's on screens without one.
    let size: CGSize
    /// Horizontal centre of the notch, in global coordinates.
    let midX: CGFloat
    /// A real notch, so the island is drawn in the hardware's black to blend into it.
    let isHardware: Bool
    /// Hanging under the menu bar icon rather than from the notch.
    var isMenuBar = false

    init(screenFrame: CGRect, size: CGSize, midX: CGFloat, isHardware: Bool, isMenuBar: Bool = false) {
        self.screenFrame = screenFrame
        self.size = size
        self.midX = midX
        self.isHardware = isHardware
        self.isMenuBar = isMenuBar
    }

    /// Under Shotput's menu bar icon, kept far enough from the screen's edges for the widest card.
    @MainActor
    static func menuBar() -> NotchGeometry? {
        let anchor = MenuBarAnchor.target(on: NSScreen.underMouse)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return nil }
        let frame = screen.frame
        let band = max(frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let half: CGFloat = 212
        let midX = min(max(anchor.midX, frame.minX + half), frame.maxX - half)
        return NotchGeometry(screenFrame: frame, size: CGSize(width: anchor.width, height: band), midX: midX, isHardware: false, isMenuBar: true)
    }

    @MainActor
    init?(_ screen: NSScreen) {
        let frame = screen.frame
        screenFrame = frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            size = CGSize(width: width, height: top)
            midX = frame.minX + left.width + width / 2
            isHardware = true
        } else {
            let menuBar = max(frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            size = CGSize(width: 180, height: min(menuBar, 32))
            midX = frame.midX
            isHardware = false
        }
        guard size.width > 0, size.height > 0 else { return nil }
    }

    /// The screen the pointer is on: dragging on an external display uses its menu bar, not
    /// a notch a screen away.
    @MainActor
    static func underPointer() -> NotchGeometry? {
        (NSScreen.underMouse ?? NSScreen.screens.first).flatMap(NotchGeometry.init)
    }

    /// Where the island rests between drags: the screen with the notch, else the main one.
    @MainActor
    static func resting() -> NotchGeometry? {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }), let geometry = NotchGeometry(notched) {
            return geometry
        }
        return (NSScreen.main ?? screens.first).flatMap(NotchGeometry.init)
    }

    /// Whether the Mac's built-in display has a notch, for how Shotput talks about it.
    @MainActor
    static var hasHardwareNotch: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    /// The window is a fixed canvas the island grows inside, so it never resizes mid-animation.
    /// Wide and tall enough for the biggest state and its shadow.
    static let canvas = CGSize(width: 560, height: 240)

    var windowFrame: CGRect {
        CGRect(
            x: (midX - Self.canvas.width / 2).rounded(),
            y: screenFrame.maxY - Self.canvas.height,
            width: Self.canvas.width,
            height: Self.canvas.height
        )
    }

    /// The pins bubble hanging just under the notch, when Clove has the notch.
    func bubbleRect(_ size: CGSize, gap: CGFloat) -> CGRect {
        CGRect(x: midX - size.width / 2, y: screenFrame.maxY - self.size.height - gap - size.height, width: size.width, height: size.height)
    }

    /// A rect of `size`, hanging from the top edge of the screen, centred on the notch.
    func hangingRect(_ size: CGSize) -> CGRect {
        CGRect(x: midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}

/// The island's outline: flush with the top of the screen, flaring out into the menu bar at the
/// top corners the way the hardware notch does, and rounded at the bottom. Both radii animate,
/// so the island grows from a tight notch into a soft panel in one spring.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, (rect.width - top * 2) / 2, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // The left shoulder curves inward, so the island looks poured from the menu bar.
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

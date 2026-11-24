import AppKit
import SwiftUI

/// Where the drop island lives on a screen, and how big its resting shape is.
///
/// On a screen with a notch the island hangs from the top edge in the hardware's black. On one
/// without (an external display, or a Mac with no notch) it's a Dynamic Island: a black pill
/// floating in the menu bar, there only while it has something to show, growing into the same
/// panels as the notch. With pins set to the menu bar, it hangs under Shotput's icon instead and
/// the "notch" is just the menu bar's height.
struct NotchGeometry: Equatable {
    /// The screen's full frame, in global coordinates.
    let screenFrame: CGRect
    /// The resting shape: the notch's own size, or the pill's.
    let size: CGSize
    /// Horizontal centre of the island, in global coordinates.
    let midX: CGFloat
    /// A real notch, so the island is drawn flush with the hardware.
    let isHardware: Bool
    /// Hanging under the menu bar icon rather than from the notch.
    var isMenuBar = false
    /// The gap between the top of the screen and the island: none for a notch, a little for the
    /// floating pill so it sits inside the menu bar.
    var topInset: CGFloat = 0

    /// The floating pill on a screen without a notch.
    var isFloating: Bool { !isHardware && !isMenuBar }

    init(screenFrame: CGRect, size: CGSize, midX: CGFloat, isHardware: Bool, isMenuBar: Bool = false, topInset: CGFloat = 0) {
        self.screenFrame = screenFrame
        self.size = size
        self.midX = midX
        self.isHardware = isHardware
        self.isMenuBar = isMenuBar
        self.topInset = topInset
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

    /// The space the floating pill leaves between its ears, where a notch would be.
    static let pillGap: CGFloat = 8

    @MainActor
    init?(_ screen: NSScreen) {
        let frame = screen.frame
        screenFrame = frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The camera housing is the space between the two menu bar areas macOS leaves
            // either side of it.
            let width = frame.width - left.width - right.width
            size = CGSize(width: width, height: top)
            midX = frame.minX + left.width + width / 2
            isHardware = true
        } else {
            // A few points shorter than the menu bar, so it reads as an island inside it.
            let menuBar = max(frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let bar = min(max(menuBar, 22), 40)
            let height = max(bar - 4, 20)
            size = CGSize(width: Self.pillGap, height: height)
            midX = frame.midX
            isHardware = false
            topInset = ((bar - height) / 2).rounded()
        }
        guard size.width > 0, size.height > 0 else { return nil }
    }

    /// The screen the pointer is on: dragging on an external display uses its menu bar, not
    /// a notch a screen away.
    @MainActor
    static func underPointer() -> NotchGeometry? {
        (NSScreen.underMouse ?? NSScreen.screens.first).flatMap(NotchGeometry.init)
    }

    /// Where the island rests between drags. On the built-in display, its notch if it has one;
    /// or, if Settings says so, on whichever display holds the window you're working in.
    @MainActor
    static func resting() -> NotchGeometry? {
        let screens = NSScreen.screens
        if Settings.shared.islandPlacement == .active, let screen = NSScreen.main, let geometry = NotchGeometry(screen) {
            return geometry
        }
        if let notched = screens.first(where: \.hasNotch), let geometry = NotchGeometry(notched) {
            return geometry
        }
        let builtIn = screens.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
        return (builtIn ?? NSScreen.main ?? screens.first).flatMap(NotchGeometry.init)
    }

    /// Whether the Mac's built-in display has a notch, for how Shotput talks about it.
    @MainActor
    static var hasHardwareNotch: Bool {
        NSScreen.screens.contains(where: \.hasNotch)
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

    /// A rect of `size` at the island's top, centred on it: hanging from the screen's edge for a
    /// notch, a few points below it for the pill.
    func hangingRect(_ size: CGSize) -> CGRect {
        CGRect(x: midX - size.width / 2, y: screenFrame.maxY - topInset - size.height, width: size.width, height: size.height)
    }
}

/// The island's outline: flush with the top of the screen, flaring out into the menu bar at the
/// top corners the way the hardware notch does, and rounded at the bottom. Both radii animate,
/// so the island grows from a tight notch into a soft panel in one spring.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// The floating island: rounded all round, no shoulders.
    var isFloating = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isFloating {
            return RoundedRectangle(cornerRadius: min(bottomRadius, rect.height / 2, rect.width / 2), style: .continuous).path(in: rect)
        }
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

extension NSScreen {
    /// A camera housing at the top, which macOS reports as menu bar space either side of it.
    var hasNotch: Bool { safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil }
}

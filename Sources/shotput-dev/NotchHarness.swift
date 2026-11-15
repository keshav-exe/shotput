// Shows the notch drop island on screen in each of its states and captures the top of the screen,
// so the glass and its gradient render as they really do. That needs Screen Recording for the
// terminal that runs it; without it, each state is drawn offscreen instead.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
@testable import ShotputKit

@MainActor
func notchHarness(to path: String) {
    let base = (path as NSString).deletingPathExtension
    guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first,
          let geometry = NotchGeometry(screen) else { fatalError("No screen") }

    let model = NotchDropModel()
    model.geometry = geometry
    model.total = 4
    let window = NotchWindow()
    window.contentView = NotchDropHostingView(model: model)
    window.setFrame(geometry.windowFrame, display: true)
    window.appearance = geometry.isHardware ? NSAppearance(named: .darkAqua) : nil
    window.orderFrontRegardless()

    let files = ["pdf", "key", "zip"].map { NSWorkspace.shared.icon(for: UTType(filenameExtension: $0) ?? .data) }
    let states: [(String, NotchDropModel.Phase, DragPayload)] = [
        ("armed", .armed, DragPayload(count: 3, icons: files)),
        ("near", .near, DragPayload(count: 1, name: "Quarterly review final v2.pdf", icons: [files[0]])),
        ("targeted", .targeted, DragPayload(count: 3, icons: files)),
        ("pinned", .pinned(3), DragPayload(count: 3, icons: files)),
        ("already", .alreadyPinned, DragPayload(count: 1, icons: files)),
        ("badge", .badge, DragPayload()),
        ("tray", .tray, DragPayload()),
        ("bubble", .hidden, DragPayload()),
    ]
    let frame = geometry.windowFrame
    let top = (NSScreen.screens.first?.frame.maxY ?? frame.maxY) - frame.maxY
    for (name, phase, payload) in states {
        model.payload = payload
        model.showsBubble = name == "bubble"
        if phase == .tray { model.trayView = PinTray.shared.notchContent {} }
        model.phase = phase
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        let file = "\(base)-\(name).png"
        if !captureScreen(frame, top: top, to: file), let host = window.contentView,
           let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            // Without Screen Recording the island is drawn offscreen: layout and text are
            // right, but Liquid Glass draws as nothing.
            host.cacheDisplay(in: host.bounds, to: rep)
            if let image = rep.cgImage { try? ImageCoding.pngData(image, scale: 2)?.write(to: URL(fileURLWithPath: file)) }
        }
        print("wrote \(file)")
    }
    window.orderOut(nil)
}

private func captureScreen(_ frame: CGRect, top: CGFloat, to file: String) -> Bool {
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R", "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height) - 60)", file]
    capture.standardError = FileHandle.nullDevice
    try? capture.run()
    capture.waitUntilExit()
    return capture.terminationStatus == 0
}

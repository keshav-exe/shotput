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

    // Run from the package, the harness has no bundle icon; the ears should show Shotput's.
    if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { AppMark.image = icon }
    let model = NotchDropModel()
    model.geometry = geometry
    model.total = 4
    let window = NotchWindow()
    window.contentView = NotchDropHostingView(model: model)
    window.setFrame(geometry.windowFrame, display: true)
    window.appearance = geometry.isHardware ? NSAppearance(named: .darkAqua) : nil
    window.orderFrontRegardless()

    // A mix of kinds in the tray, so its filters show. Unpinned again at the end.
    let before = Set(PinStore.shared.pins.map(\.id))
    let samples = FileManager.default.temporaryDirectory.appendingPathComponent("shotput-tray-samples", isDirectory: true)
    try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
    var sampleFiles: [URL] = []
    for (name, data) in [("Release notes.txt", Data("Shotput".utf8)), ("Brief.pdf", pdfData()), ("Assets.zip", Data([0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0, count: 18)))] {
        let url = samples.appendingPathComponent(name)
        try? data.write(to: url)
        sampleFiles.append(url)
    }
    sampleFiles.append(URL(fileURLWithPath: "docs/editor.png"))
    let pinned = Task { await PinStore.shared.pin(files: sampleFiles) }
    while !pinned.isCancelled, PinStore.shared.pins.count < before.count + sampleFiles.count {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if PinStore.shared.pins.count >= before.count + sampleFiles.count { break }
    }
    if let source = NSImage(contentsOfFile: "docs/editor.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        PinStore.shared.pin(Capture(image: source, scale: 2))
    }
    defer {
        PinStore.shared.remove(PinStore.shared.pins.filter { !before.contains($0.id) })
        try? FileManager.default.removeItem(at: samples)
    }
    model.total = PinStore.shared.pins.count

    // Reordering keeps everything else in place and sticks.
    let order = PinStore.shared.pins.map(\.id)
    if order.count >= 3 {
        PinStore.shared.move([order[order.count - 1]], before: order[0])
        print(PinStore.shared.pins.map(\.id) == [order[order.count - 1]] + order.dropLast() ? "  ok    a pin moves to the front" : "  FAIL  a pin moves to the front")
        PinStore.shared.move([order[order.count - 1]], before: nil)
        print(PinStore.shared.pins.map(\.id) == order ? "  ok    and back to the end" : "  FAIL  and back to the end")
        PinStore.shared.move([order[0], order[1]], before: order[order.count - 1])
        let expected = Array(order.dropFirst(2).dropLast()) + [order[0], order[1], order[order.count - 1]]
        print(PinStore.shared.pins.map(\.id) == expected ? "  ok    several move together, in their order" : "  FAIL  several move together, in their order")
    }

    let files = ["pdf", "key", "zip"].map { NSWorkspace.shared.icon(for: UTType(filenameExtension: $0) ?? .data) }
    let states: [(String, NotchDropModel.Phase, DragPayload)] = [
        ("armed", .armed, DragPayload(count: 3, icons: files)),
        ("near", .near, DragPayload(count: 1, name: "Quarterly review final v2.pdf", icons: [files[0]])),
        ("targeted", .targeted, DragPayload(count: 3, icons: files)),
        ("pinned", .pinned(3), DragPayload(count: 3, icons: files)),
        ("already", .alreadyPinned, DragPayload(count: 1, icons: files)),
        ("badge", .badge, DragPayload()),
        ("tray", .tray, DragPayload()),
        ("side-bubble", .hidden, DragPayload()),
    ]
    let frame = geometry.windowFrame
    let top = (NSScreen.screens.first?.frame.maxY ?? frame.maxY) - frame.maxY
    for (name, phase, payload) in states {
        model.payload = payload
        model.showsSideBubble = name == "side-bubble"
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

/// A one-page PDF, for a document pin.
private func pdfData() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 200, height: 260)
    guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
    pdf.beginPDFPage(nil)
    pdf.setFillColor(CGColor(gray: 0.2, alpha: 1))
    pdf.fill(CGRect(x: 20, y: 200, width: 160, height: 12))
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

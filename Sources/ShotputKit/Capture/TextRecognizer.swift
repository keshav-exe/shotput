import AppKit
import SwiftUI
import Vision

/// Reads text in an image on this Mac, following the text recognition preferences.
enum TextRecognizer {
    /// Calls back on the main thread with the recognised text, or nil when there is none.
    static func recognize(_ image: CGImage, completion: @escaping @MainActor (_ text: String?, _ lines: Int) -> Void) {
        let keepsLineBreaks = Settings.shared.ocrKeepsLineBreaks
        let correction = Settings.shared.ocrLanguageCorrection
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = correction
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.isEmpty ? nil : lines.joined(separator: keepsLineBreaks ? "\n" : " ")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(text, lines.count) }
            }
        }
    }
}

/// A short message near the bottom of the screen, for results that have no window to show them in.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var dismissal: DispatchWorkItem?

    static func show(_ message: String, icon: Icon = .check) {
        dismissal?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: HUDView(message: message, icon: icon))
        let size = host.fittingSize
        let screen = NSScreen.underMouse ?? NSScreen.screens[0]
        let frame = CGRect(
            x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 64,
            width: size.width, height: size.height
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                     completionHandler: { panel.orderOut(nil) })
                if Self.panel === panel { Self.panel = nil }
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

private struct HUDView: View {
    let message: String
    let icon: Icon

    var body: some View {
        Label { Text(message) } icon: { icon.view(size: 14, weight: .medium) }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(12)
    }
}

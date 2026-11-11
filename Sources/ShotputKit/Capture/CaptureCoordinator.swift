import AppKit
import ScreenCaptureKit

/// Runs a capture from trigger to delivery: still, selection, clipboard, then preview or editor.
@MainActor
final class CaptureCoordinator {
    enum Mode { case area, window, screen }

    static let shared = CaptureCoordinator()

    private(set) var lastCapture: Capture?
    private var overlay: SelectionOverlay?
    private var isStarting = false

    /// - Parameter annotate: Open the editor afterwards, whatever the "after capture" preference says.
    func capture(_ mode: Mode, annotate: Bool = false) {
        // Pressing a capture shortcut while selecting backs out, so one mouse button can toggle.
        if let overlay {
            overlay.cancel()
            return
        }
        guard !isStarting, ScreenPermission.ensure() else { return }
        isStarting = true
        let previousApp = NSWorkspace.shared.frontmostApplication

        Task {
            defer { isStarting = false }
            do {
                let content = try await ScreenCapturer.shareableContent()
                if mode == .screen {
                    guard let shot = try await ScreenCapturer.captureDisplays(content, only: NSScreen.underMouse).first else { return }
                    deliver(Capture(image: shot.image, scale: shot.scale, screen: shot.screen), annotate: annotate)
                    return
                }

                let shots = try await ScreenCapturer.captureDisplays(content)
                guard !shots.isEmpty else { return }
                let overlay = SelectionOverlay(mode: mode == .window ? .window : .area)
                self.overlay = overlay
                overlay.present(shots: shots, windows: ScreenCapturer.onScreenWindows()) { outcome in
                    self.overlay = nil
                    self.finish(outcome, content: content, annotate: annotate, previousApp: previousApp)
                }
            } catch {
                ScreenPermission.explain()
            }
        }
    }

    private func finish(
        _ outcome: SelectionOverlay.Outcome, content: SCShareableContent, annotate: Bool, previousApp: NSRunningApplication?
    ) {
        // Hand focus back, so a paste lands where the user was working. The editor keeps it instead.
        let opensEditor = annotate || Settings.shared.afterCapture == .editor
        if case .cancelled = outcome {
            previousApp?.activate()
            return
        }
        if !opensEditor { previousApp?.activate() }

        switch outcome {
        case .cancelled:
            break
        case let .area(rect, shot):
            guard let image = shot.crop(rect) else { return }
            let origin = shot.screen.frame.origin
            deliver(
                Capture(image: image, scale: shot.scale, screenRect: rect.offsetBy(dx: origin.x, dy: origin.y), screen: shot.screen),
                annotate: annotate
            )
        case let .window(info, shot):
            Task {
                // Prefer the window on its own. Fall back to the still if it has gone away.
                if let result = try? await ScreenCapturer.captureWindow(info.id, in: content) {
                    deliver(Capture(image: result.image, scale: result.scale, screenRect: info.frame, screen: shot.screen), annotate: annotate)
                } else {
                    let origin = shot.screen.frame.origin
                    let local = info.frame.offsetBy(dx: -origin.x, dy: -origin.y).intersection(CGRect(origin: .zero, size: shot.screen.frame.size))
                    guard let image = shot.crop(local) else { return }
                    deliver(Capture(image: image, scale: shot.scale, screenRect: info.frame, screen: shot.screen), annotate: annotate)
                }
            }
        }
    }

    private func deliver(_ capture: Capture, annotate: Bool) {
        lastCapture = capture
        let settings = Settings.shared
        let after = annotate ? Settings.AfterCapture.editor : settings.afterCapture

        let savesToFolder = settings.savesEveryCapture && settings.resolvedSaveFolder() != nil

        // The clipboard is filled straight away in every mode, so pasting never waits on a choice.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let png = capture.png() else { return }
            DispatchQueue.main.async {
                Output.copyToClipboard(png.data)
                if savesToFolder {
                    Output.save(png.data, named: ImageCoding.timestampedName(for: capture.date), relativeTo: nil) { _ in }
                }
            }
        }

        switch after {
        case .preview: PreviewPanelController.shared.show(capture)
        case .editor: EditorManager.shared.open(capture)
        case .clipboard: break
        }
    }

    func annotateLast() {
        guard let lastCapture else {
            annotateClipboard()
            return
        }
        PreviewPanelController.shared.dismiss()
        EditorManager.shared.open(lastCapture)
    }

    /// Opens whatever image is on the clipboard, so screenshots from other tools can be marked up too.
    func annotateClipboard() {
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSSound.beep()
            return
        }
        open(image: image)
    }

    func open(file url: URL) {
        guard let image = ImageCoding.load(url) else {
            NSSound.beep()
            return
        }
        open(image: image)
    }

    private func open(image: CGImage) {
        // Images from elsewhere carry no reliable density, so treat them as this screen's.
        let scale = NSScreen.underMouse?.backingScaleFactor ?? 2
        let capture = Capture(image: image, scale: scale)
        lastCapture = capture
        EditorManager.shared.open(capture)
    }
}

enum ScreenPermission {
    /// True when captures can proceed. Otherwise starts the system prompt, or explains how to allow it.
    @MainActor
    static func ensure() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let askedBefore = UserDefaults.standard.bool(forKey: "askedForScreenRecording")
        UserDefaults.standard.set(true, forKey: "askedForScreenRecording")
        // The first request shows the system's own prompt. After that it is silent, so explain.
        if !CGRequestScreenCaptureAccess(), askedBefore { explain() }
        return false
    }

    @MainActor
    static func explain() {
        let alert = NSAlert()
        alert.messageText = "Shotput needs Screen Recording"
        alert.informativeText = "macOS only lets Shotput see your screen while you take a screenshot, and only once you allow it. Turn Shotput on under Screen & System Audio Recording, then reopen it."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
import ScreenCaptureKit

/// Runs a capture from trigger to delivery: still, selection, clipboard, then preview or editor.
@MainActor
final class CaptureCoordinator {
    enum Mode { case area, window, screen }

    static let shared = CaptureCoordinator()

    private(set) var lastCapture: Capture?
    /// The last area selected, in global Cocoa coordinates, for "Repeat last area".
    private var lastArea: CGRect?
    private var overlay: SelectionOverlay?
    private var isStarting = false

    /// - Parameters:
    ///   - annotate: Open the editor afterwards, whatever the "after capture" preference says.
    ///   - readText: Copy the text in the selected area instead of the image.
    func capture(_ mode: Mode, annotate: Bool = false, readText: Bool = false) {
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
                    guard let shot = try await ScreenCapturer.captureDisplays(
                        content, only: NSScreen.underMouse, showsCursor: Settings.shared.showsPointer
                    ).first else { return }
                    let capture = Capture(image: shot.image, scale: shot.scale, screen: shot.screen)
                    capture.appName = previousApp?.localizedName
                    deliver(capture, annotate: annotate)
                    return
                }

                let shots = try await ScreenCapturer.captureDisplays(content)
                guard !shots.isEmpty else { return }
                let overlay = SelectionOverlay(mode: mode == .window ? .window : .area)
                self.overlay = overlay
                overlay.present(shots: shots, windows: ScreenCapturer.onScreenWindows()) { outcome in
                    self.overlay = nil
                    self.finish(outcome, content: content, annotate: annotate, readText: readText, previousApp: previousApp)
                }
            } catch {
                ScreenPermission.explain()
            }
        }
    }

    private func finish(
        _ outcome: SelectionOverlay.Outcome, content: SCShareableContent, annotate: Bool, readText: Bool,
        previousApp: NSRunningApplication?
    ) {
        // Hand focus back, so a paste lands where the user was working. The editor keeps it instead.
        let opensEditor = !readText && (annotate || Settings.shared.afterCapture == .editor)
        if case .cancelled = outcome {
            previousApp?.activate()
            return
        }
        if !opensEditor { previousApp?.activate() }
        let appName = previousApp?.localizedName

        switch outcome {
        case .cancelled:
            break
        case let .area(rect, shot):
            guard let image = shot.crop(rect) else { return }
            let origin = shot.screen.frame.origin
            lastArea = rect.offsetBy(dx: origin.x, dy: origin.y)
            if readText {
                copyText(in: image)
                return
            }
            let capture = Capture(image: image, scale: shot.scale, screenRect: rect.offsetBy(dx: origin.x, dy: origin.y), screen: shot.screen)
            capture.appName = appName
            deliver(capture, annotate: annotate)
        case let .window(info, shot):
            Task {
                // Prefer the window on its own. Fall back to the still if it has gone away.
                let capture: Capture
                let settings = Settings.shared
                if let result = try? await ScreenCapturer.captureWindow(info.id, in: content, includesShadow: settings.windowShadow) {
                    if let style = settings.windowBackdrop {
                        let wallpaper = style.fill == .wallpaper ? await Backdrop.wallpaper(for: shot.screen) : nil
                        let framed = Backdrop.compose(
                            result.image, scale: result.scale, style: style, wallpaper: wallpaper, addsShadow: !settings.windowShadow
                        )
                        capture = Capture(image: framed, scale: result.scale, screenRect: info.frame, screen: shot.screen)
                        capture.backdrop = (result.image, style)
                    } else {
                        capture = Capture(image: result.image, scale: result.scale, screenRect: info.frame, screen: shot.screen)
                    }
                } else {
                    let origin = shot.screen.frame.origin
                    let local = info.frame.offsetBy(dx: -origin.x, dy: -origin.y).intersection(CGRect(origin: .zero, size: shot.screen.frame.size))
                    guard let image = shot.crop(local) else { return }
                    capture = Capture(image: image, scale: shot.scale, screenRect: info.frame, screen: shot.screen)
                }
                if readText {
                    copyText(in: capture.image)
                    return
                }
                capture.appName = info.ownerName ?? appName
                deliver(capture, annotate: annotate)
            }
        }
    }

    private func copyText(in image: CGImage) {
        TextRecognizer.recognize(image) { text, lines in
            guard let text else {
                HUD.show("No text found", icon: .textFound)
                return
            }
            Output.copyToClipboard(text: text)
            HUD.show(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
        }
    }

    private func deliver(_ capture: Capture, annotate: Bool) {
        lastCapture = capture
        let settings = Settings.shared
        let after = annotate ? Settings.AfterCapture.editor : settings.afterCapture

        let savesToFolder = settings.savesEveryCapture && settings.resolvedSaveFolder() != nil
        if settings.playsSound { CaptureSound.play() }
        if let rect = capture.screenRect { CaptureFlash.show(over: rect) }
        NotificationCenter.default.post(name: .shotputDidCapture, object: nil)

        // The clipboard is filled straight away in every mode, so pasting never waits on a choice.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let png = capture.png() else { return }
            let file = savesToFolder ? capture.fileData() : nil
            DispatchQueue.main.async {
                Output.copyToClipboard(png.data)
                if let file { Output.save(file, relativeTo: nil) { _ in } }
            }
        }

        switch after {
        case .preview: PreviewPanelController.shared.show(capture)
        case .editor: EditorManager.shared.open(capture)
        case .clipboard: break
        }
    }

    /// Captures the area chosen last time again, straight away. Starts a normal selection when
    /// there is no earlier area or its display has gone.
    func repeatLastArea() {
        guard overlay == nil, !isStarting else { return }
        guard let area = lastArea,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(area) }) else {
            capture(.area)
            return
        }
        guard ScreenPermission.ensure() else { return }
        isStarting = true
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            defer { isStarting = false }
            do {
                let content = try await ScreenCapturer.shareableContent()
                guard let shot = try await ScreenCapturer.captureDisplays(content, only: screen).first else { return }
                let local = area.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                    .intersection(CGRect(origin: .zero, size: screen.frame.size))
                guard !local.isEmpty, let image = shot.crop(local) else { return }
                let capture = Capture(image: image, scale: shot.scale, screenRect: area, screen: screen)
                capture.appName = appName
                deliver(capture, annotate: false)
            } catch {
                ScreenPermission.explain()
            }
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

extension Notification.Name {
    static let shotputDidCapture = Notification.Name("ShotputDidCapture")
}

/// A brief shutter over what was just captured, so the eye knows it landed. It runs after the
/// overlay has gone, in its own window, so it never delays the clipboard.
@MainActor
enum CaptureFlash {
    static func show(over rect: CGRect) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, rect.width > 8, rect.height > 8 else { return }
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        view.layer?.cornerRadius = 4
        panel.contentView = view
        panel.alphaValue = 0.32
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

/// The system's own screenshot sound, so Shotput sounds like the Mac it runs on.
enum CaptureSound {
    private static let sound: NSSound? = {
        let system = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: system, byReference: true) ?? NSSound(named: "Tink")
    }()

    static func play() {
        sound?.stop()
        sound?.play()
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

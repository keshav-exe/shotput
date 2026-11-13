import AppKit
import SwiftUI

/// A button that records the next key combination pressed.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { shortcut = $0 }
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = { shortcut = $0 }
        if button.shortcut != shortcut { button.shortcut = shortcut }
    }
}

final class RecorderButton: NSButton {
    var onChange: ((Shortcut) -> Void)?
    var shortcut = Shortcut.none { didSet { refreshTitle() } }

    private var monitor: Any?
    private var isRecording: Bool { monitor != nil }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshTitle() {
        if isRecording {
            title = L("Press shortcut")
        } else {
            title = shortcut.isSet ? shortcut.display : L("Record")
        }
        setAccessibilityLabel(shortcut.isSet ? String(format: L("Shortcut %@"), shortcut.display) : L("No shortcut"))
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        // Release the live hotkeys, otherwise pressing a current shortcut would fire it.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                self.stopRecording()
                return event
            }
            let flags = event.modifierFlags.intersection(Shortcut.allowedFlags)
            if flags.isEmpty, event.keyCode == 53 {
                self.stopRecording()
            } else if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
                self.commit(.none)
            } else {
                let candidate = Shortcut(keyCode: Int(event.keyCode), flags)
                if candidate.isAcceptable { self.commit(candidate) } else { NSSound.beep() }
            }
            return nil
        }
        refreshTitle()
    }

    private func commit(_ newShortcut: Shortcut) {
        shortcut = newShortcut
        onChange?(newShortcut)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refreshTitle()
        MainActor.assumeIsolated { HotKeyCenter.reload() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isRecording { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}

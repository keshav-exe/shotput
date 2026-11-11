import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canRecordScreen = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            if !canRecordScreen {
                Section {
                    LabeledContent {
                        Button("Allow") {
                            if !CGRequestScreenCaptureAccess() { ScreenPermission.openSettings() }
                        }
                    } label: {
                        Text("Screen Recording is off")
                        Text("Shotput needs it to take screenshots. Reopen Shotput after you turn it on.")
                    }
                }
            }

            Section {
                ForEach(HotAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(shortcut: Binding(
                            get: { settings.shortcuts[action] ?? .none },
                            set: { settings.shortcuts[action] = $0 }
                        ))
                        .frame(width: 150, height: 24)
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("To use a mouse button, open Logi Options+, pick the button, choose Keyboard shortcut, and press one of these.")
                    .foregroundStyle(.secondary)
            }

            Section("After a capture") {
                Picker("Then", selection: $settings.afterCapture) {
                    ForEach(Settings.AfterCapture.allCases) { Text($0.title).tag($0) }
                }
                Picker("Preview appears", selection: $settings.previewCorner) {
                    ForEach(Settings.Corner.allCases) { Text($0.title).tag($0) }
                }
                .disabled(settings.afterCapture != .preview)
                Picker("Preview stays", selection: $settings.previewDuration) {
                    Text("4 seconds").tag(4.0)
                    Text("6 seconds").tag(6.0)
                    Text("10 seconds").tag(10.0)
                    Text("Until dismissed").tag(0.0)
                }
                .disabled(settings.afterCapture != .preview)
            }

            Section {
                Toggle(isOn: $settings.copyAtPointSize) {
                    Text("Copy at standard resolution")
                    Text("Halves the pixel size on Retina displays. Smaller images are quicker for an agent to read.")
                }
                LabeledContent("Save folder") {
                    HStack(spacing: Metrics.spacingS) {
                        if let folder = settings.saveFolder {
                            Text(folder.lastPathComponent).foregroundStyle(.secondary)
                            Button("Clear") { settings.setSaveFolder(nil) }
                        }
                        Button(settings.saveFolder == nil ? "Choose" : "Change") { chooseFolder() }
                    }
                }
                Toggle("Save every capture there", isOn: $settings.savesEveryCapture)
                    .disabled(settings.saveFolder == nil)
            } header: {
                Text("Output")
            } footer: {
                Text("Every capture goes to the clipboard. Without a save folder, Save asks where to put the file.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open Shotput at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.shortcuts) { HotKeyCenter.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canRecordScreen = CGPreflightScreenCaptureAccess()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { settings.setSaveFolder(panel.url) }
    }
}

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
            title = "Press shortcut"
        } else {
            title = shortcut.isSet ? shortcut.display : "Record"
        }
        setAccessibilityLabel(shortcut.isSet ? "Shortcut \(shortcut.display)" : "No shortcut")
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

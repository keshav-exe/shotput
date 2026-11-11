import AppKit
import ServiceManagement
import SwiftUI

/// Settings, one tab per area, so no single page grows taller than the screen.
final class SettingsWindowController: NSWindowController {
    enum Pane: Int, CaseIterable {
        case general, capture, editor, output, shortcuts, about

        var title: String {
            switch self {
            case .general: "General"
            case .capture: "Capture"
            case .editor: "Editor"
            case .output: "Output"
            case .shortcuts: "Shortcuts"
            case .about: "About"
            }
        }

        var icon: Icon {
            switch self {
            case .general: .settings
            case .capture: .capture
            case .editor: .annotate
            case .output: .folder
            case .shortcuts: .command
            case .about: .info
            }
        }

        @MainActor
        var view: AnyView {
            switch self {
            case .general: AnyView(GeneralPane())
            case .capture: AnyView(CapturePane())
            case .editor: AnyView(EditorPane())
            case .output: AnyView(OutputPane())
            case .shortcuts: AnyView(ShortcutsPane())
            case .about: AnyView(AboutPane())
            }
        }
    }

    private let tabs = NSTabViewController()

    init() {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: pane.view.frame(width: Self.width).fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = pane.icon.plain(label: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static let width: CGFloat = 520

    func select(_ pane: Pane) { tabs.selectedTabViewItemIndex = pane.rawValue }
}

// MARK: General

struct GeneralPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canRecordScreen = CGPreflightScreenCaptureAccess()
    @State private var confirmsReset = false

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

            Section("Startup") {
                Toggle("Open Shotput at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(isOn: $settings.showsMenuBarIcon) {
                    Text("Show in the menu bar")
                    Text("When hidden, open Shotput again from Applications or Spotlight to get back here.")
                }
            }

            Section("Feedback") {
                Toggle("Play a sound on capture", isOn: $settings.playsSound)
            }

            Section {
                Toggle(isOn: $settings.allowsLinks) {
                    Text("Allow shotput:// links")
                    Text("Lets launchers and Logi Options+ Smart Actions start a capture.")
                }
            }

            Section {
                LabeledContent("Welcome guide") {
                    Button("Show Again") { (NSApp.delegate as? AppDelegate)?.showOnboarding(.welcome) }
                }
                LabeledContent("All settings") {
                    Button("Reset…") { confirmsReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canRecordScreen = CGPreflightScreenCaptureAccess()
        }
        .confirmationDialog("Reset every setting?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Shortcuts and preferences go back to how Shotput ships. Your save folder stays.")
        }
    }
}

// MARK: Capture

struct CapturePane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section("While selecting") {
                Toggle("Show the magnifier", isOn: $settings.showsMagnifier)
                Toggle(isOn: $settings.snapsToEdges) {
                    Text("Snap to window edges")
                    Text("Hold ⌘ to place freely either way.")
                }
                Picker("Show the hint", selection: $settings.selectionHints) {
                    ForEach(Settings.Hints.allCases) { Text($0.title).tag($0) }
                }
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

            Section("Windows") {
                Toggle("Keep the window's shadow", isOn: $settings.windowShadow)
                Picker("Background", selection: $settings.windowBackground) {
                    ForEach(Settings.WindowBackground.allCases) { Text($0.title).tag($0) }
                }
                if settings.windowBackground == .solid {
                    ColorPicker("Colour", selection: Binding(
                        get: { Color(nsColor: settings.windowBackgroundColor) },
                        set: { settings.windowBackgroundColor = NSColor($0) }
                    ), supportsOpacity: false)
                }
                if settings.windowBackground != .transparent {
                    LabeledContent("Padding") {
                        HStack {
                            Slider(value: $settings.windowPadding, in: 0...160, step: 8)
                                .frame(width: 160)
                            Text("\(Int(settings.windowPadding)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Screen") {
                Toggle("Include the pointer", isOn: $settings.showsPointer)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: Editor

struct EditorPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Picker("Esc", selection: $settings.escapeInEditor) {
                    ForEach(Settings.EscapeInEditor.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Copy (⌘C) also closes the editor", isOn: $settings.editorClosesOnCopy)
            } header: {
                Text("Closing")
            } footer: {
                Text("Return always copies and closes. Esc first clears a selection or crop, then closes.")
                    .foregroundStyle(.secondary)
            }

            Section("Text recognition") {
                Toggle(isOn: $settings.ocrKeepsLineBreaks) {
                    Text("Keep line breaks")
                    Text("Off joins every line into one, which suits pasting a paragraph.")
                }
                Toggle("Correct spelling while reading", isOn: $settings.ocrLanguageCorrection)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: Output

struct OutputPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var showsTokens = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.copyAtPointSize) {
                    Text("Use standard resolution")
                    Text("Halves the pixel size on Retina displays. Smaller images are quicker for an agent to read.")
                }
            } header: {
                Text("Clipboard and files")
            }

            Section {
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
                Picker("Format", selection: $settings.saveFormat) {
                    ForEach(Settings.SaveFormat.allCases) { Text($0.title).tag($0) }
                }
                if settings.saveFormat != .png {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $settings.jpegQuality, in: 0.4...1)
                                .frame(width: 160)
                            Text("\(Int((settings.jpegQuality * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Saving")
            } footer: {
                Text("The clipboard always gets a PNG. Without a save folder, Save asks where to put the file.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Template", text: $settings.filenameTemplate, prompt: Text(Settings.defaultTemplate))
                    .labelsHidden()
                    .font(.body.monospaced())
                LabeledContent("Example") {
                    Text(example)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Tokens") {
                    Button("Insert…") { showsTokens = true }
                        .popover(isPresented: $showsTokens, arrowEdge: .trailing) { tokenGrid }
                }
            } header: {
                HStack {
                    Text("File name")
                    Spacer()
                    if settings.filenameTemplate != Settings.defaultTemplate {
                        Button("Reset") { settings.filenameTemplate = Settings.defaultTemplate }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// Kept in a popover so the tab stays the same height whether or not you need it.
    private var tokenGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: Metrics.spacingM, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: ImageCoding.templateTokens.count, by: 2)), id: \.self) { index in
                GridRow {
                    tokenCell(ImageCoding.templateTokens[index])
                    if index + 1 < ImageCoding.templateTokens.count {
                        tokenCell(ImageCoding.templateTokens[index + 1])
                    }
                }
            }
        }
        .padding(Metrics.spacingM)
        .frame(width: 400)
    }

    private var example: String {
        "\(ImageCoding.fileName(template: settings.filenameTemplate, date: Date(), appName: "Safari")).\(settings.saveFormat.fileExtension)"
    }

    private func tokenCell(_ token: (token: String, meaning: String)) -> some View {
        Button {
            settings.filenameTemplate += token.token
        } label: {
            HStack(spacing: 6) {
                Text(token.token)
                    .font(.callout.monospaced().weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.accent.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(Palette.accent.color)
                Text(token.meaning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add \(token.token) to the template")
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

// MARK: Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                ForEach(HotAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(shortcut: Binding(
                            get: { settings.shortcuts[action] ?? .none },
                            set: { settings.shortcuts[action] = $0 }
                        ))
                        .frame(width: 150, height: 24)
                    } label: {
                        Text(action.title)
                            .help(action.detail)
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the new keys. Delete clears it, Esc keeps it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Show Me How") { (NSApp.delegate as? AppDelegate)?.showOnboarding(.mouse) }
                } label: {
                    Text("Use a mouse button")
                    Text("Logi Options+ can press any of these shortcuts for you.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: About

struct AboutPane: View {
    private static let repository = URL(string: "https://github.com/keshav-exe/shotput")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty || build == short ? short : "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: Metrics.spacingM) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            VStack(spacing: Metrics.spacingXS) {
                Text("Shotput").font(.title2.weight(.semibold))
                Text("Version \(version)").foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Free and open source under the MIT licence. Shotput has no network access, so it never checks for updates by itself.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Metrics.spacingS) {
                Button("Check for Updates") { NSWorkspace.shared.open(Self.repository.appendingPathComponent("releases/latest")) }
                    .buttonStyle(.borderedProminent)
                Button("Source Code") { NSWorkspace.shared.open(Self.repository) }
                Button("Report an Issue") { NSWorkspace.shared.open(Self.repository.appendingPathComponent("issues/new")) }
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, Metrics.spacingL)
        .frame(maxWidth: .infinity)
    }
}

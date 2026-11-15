import AppKit
import ServiceManagement
import SwiftUI

/// Settings, one tab per area, so no single page grows taller than the screen.
final class SettingsWindowController: NSWindowController {
    enum Pane: Int, CaseIterable {
        /// Numbered as they were added, so a remembered tab stays the same tab.
        case general = 0, capture = 1, editor = 2, output = 3, pins = 6, shortcuts = 4, about = 5

        var title: String {
            switch self {
            case .general: L("General")
            case .capture: L("Capture")
            case .editor: L("Editor")
            case .output: L("Output")
            case .pins: L("Pins")
            case .shortcuts: L("Shortcuts")
            case .about: L("About")
            }
        }

        var icon: Icon {
            switch self {
            case .general: .settings
            case .capture: .capture
            case .editor: .annotate
            case .output: .folder
            case .pins: .pin
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
            case .pins: AnyView(PinsPane())
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
            // The tab view controller titles the window from the selected pane's controller.
            host.title = pane.title
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

    func select(_ pane: Pane) { tabs.selectedTabViewItemIndex = Pane.allCases.firstIndex(of: pane) ?? 0 }
}

// MARK: General

struct GeneralPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canRecordScreen = CGPreflightScreenCaptureAccess()
    @State private var confirmsReset = false

    /// Why the menu bar icon is on, or what hiding it means, in step with where pins live.
    private var menuBarIconDetail: String {
        if settings.pinTarget == .menuBar {
            return L("Your pins live under it. To hide it, keep pins in the notch instead, under Pins.")
        }
        return L("Click it for pins, which open in the notch. When hidden, open Shotput again from Applications or Spotlight to get back here.")
    }

    var body: some View {
        Form {
            if !canRecordScreen {
                Section {
                    LabeledContent {
                        Button(L("Allow")) {
                            if !CGRequestScreenCaptureAccess() { ScreenPermission.openSettings() }
                        }
                    } label: {
                        Text(L("Screen Recording is off"))
                        Text(L("Shotput needs it to take screenshots. Reopen Shotput after you turn it on."))
                    }
                }
            }

            Section(L("Startup")) {
                Toggle(L("Open Shotput at login"), isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(isOn: $settings.showsMenuBarIcon) {
                    Text(L("Show in the menu bar"))
                    Text(menuBarIconDetail)
                }
                .disabled(settings.pinTarget == .menuBar)
            }

            Section(L("Feedback")) {
                Toggle(L("Play a sound on capture"), isOn: $settings.playsSound)
            }

            Section(L("macOS screenshots")) {
                Toggle(isOn: Binding(
                    get: { settings.screenshotFolder != nil },
                    set: { on in
                        if on { MacScreenshotWatcher.shared.enable() } else { MacScreenshotWatcher.shared.disable() }
                    }
                )) {
                    Text(L("Preview macOS screenshots"))
                    Text(macScreenshotsDetail)
                }
            }

            Section {
                Toggle(isOn: $settings.allowsLinks) {
                    Text(L("Allow shotput:// links"))
                    Text(L("Lets launchers and Logi Options+ Smart Actions start a capture."))
                }
            }

            Section {
                LabeledContent(L("All settings")) {
                    Button(L("Reset…")) { confirmsReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canRecordScreen = CGPreflightScreenCaptureAccess()
        }
        .confirmationDialog(L("Reset every setting?"), isPresented: $confirmsReset) {
            Button(L("Reset"), role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text(L("Shortcuts and preferences go back to how Shotput ships. Your save folder stays."))
        }
    }
}

// MARK: Capture

struct CapturePane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section(L("While selecting")) {
                Toggle(L("Show the magnifier"), isOn: $settings.showsMagnifier)
                Toggle(L("Snap to window edges"), isOn: $settings.snapsToEdges)
                    .help(L("Hold ⌘ while selecting to place freely either way."))
                Picker(L("Show the hint"), selection: $settings.selectionHints) {
                    ForEach(Settings.Hints.allCases) { Text($0.title).tag($0) }
                }
            }

            Section(L("After a capture")) {
                Picker(L("Then"), selection: $settings.afterCapture) {
                    ForEach(Settings.AfterCapture.allCases) { Text($0.title).tag($0) }
                }
                Picker(L("Preview appears"), selection: $settings.previewCorner) {
                    ForEach(Settings.Corner.allCases) { Text($0.title).tag($0) }
                }
                .disabled(settings.afterCapture != .preview)
                Picker(L("Preview stays"), selection: $settings.previewDuration) {
                    Text(L("4 seconds")).tag(4.0)
                    Text(L("6 seconds")).tag(6.0)
                    Text(L("10 seconds")).tag(10.0)
                    Text(L("Until dismissed")).tag(0.0)
                }
                .disabled(settings.afterCapture != .preview)
            }

            Section(L("Windows")) {
                Toggle(L("Keep the window’s shadow"), isOn: $settings.windowShadow)
                LabeledContent(L("Background")) {
                    HStack(spacing: 8) {
                        if settings.windowBackground == .solid {
                            ColorPicker(L("Colour"), selection: Binding(
                                get: { Color(nsColor: settings.windowBackgroundColor) },
                                set: { settings.windowBackgroundColor = NSColor($0) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                        Picker(L("Background"), selection: $settings.windowBackground) {
                            ForEach(Settings.WindowBackground.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if settings.windowBackground != .transparent {
                    LabeledContent(L("Padding")) {
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

            Section(L("In captures")) {
                Toggle(L("Include the pointer in screen captures"), isOn: $settings.showsPointer)
                Toggle(L("Include Shotput’s own windows"), isOn: $settings.capturesOwnWindows)
                    .help(L("Settings, the editor, and the guide show up in captures. Previews, the notch, and the selection are always left out."))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

extension GeneralPane {
    private var macScreenshotsDetail: String {
        guard settings.screenshotFolder != nil else {
            return L("Shots from ⇧⌘3 and ⇧⌘4 get Shotput’s preview and go on the clipboard.")
        }
        if SystemScreenshots.savesToClipboard {
            return L("macOS is set to copy screenshots, not save them. Choose a folder under ⇧⌘5 → Options.")
        }
        let folder = settings.screenshotFolder?.lastPathComponent ?? L("the folder")
        return String(format: MacScreenshotWatcher.shared.holdsThumbnailOff
            ? L("Watching %@. macOS’s thumbnail is off so ⇧⌘3 and ⇧⌘4 land at once.")
            : L("Watching %@. macOS keeps its thumbnail while ⇧⌘5 is its own, so recordings are untouched."), folder)
    }
}

// MARK: Editor

struct EditorPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Picker(L("Esc"), selection: $settings.escapeInEditor) {
                    ForEach(Settings.EscapeInEditor.allCases) { Text($0.title).tag($0) }
                }
                Toggle(L("Copy (⌘C) also closes the editor"), isOn: $settings.editorClosesOnCopy)
            } header: {
                Text(L("Closing"))
            } footer: {
                Text(L("Return always copies and closes. Esc first clears a selection or crop, then closes."))
                    .foregroundStyle(.secondary)
            }

            Section(L("Drawing")) {
                Toggle(isOn: $settings.recognizesShapes) {
                    Text(L("Turn sketches into shapes"))
                    Text(L("A pen stroke that looks like a line, arrow, rectangle, or circle becomes one. ⌘Z keeps the sketch."))
                }
            }

            Section(L("Text recognition")) {
                Toggle(isOn: $settings.ocrKeepsLineBreaks) {
                    Text(L("Keep line breaks"))
                    Text(L("Off joins every line into one, which suits pasting a paragraph."))
                }
                Toggle(L("Correct spelling while reading"), isOn: $settings.ocrLanguageCorrection)
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
                    Text(L("Use standard resolution"))
                    Text(L("Halves the pixel size on Retina displays. Smaller images are quicker for an agent to read."))
                }
            } header: {
                Text(L("Clipboard and files"))
            }

            Section {
                LabeledContent(L("Save folder")) {
                    HStack(spacing: Metrics.spacingS) {
                        if let folder = settings.saveFolder {
                            Text(folder.lastPathComponent).foregroundStyle(.secondary)
                            Button(L("Clear")) { settings.setSaveFolder(nil) }
                        }
                        Button(settings.saveFolder == nil ? L("Choose") : L("Change")) { chooseFolder() }
                    }
                }
                Toggle(L("Save every capture there"), isOn: $settings.savesEveryCapture)
                    .disabled(settings.saveFolder == nil)
                Picker(L("Format"), selection: $settings.saveFormat) {
                    ForEach(Settings.SaveFormat.allCases) { Text($0.title).tag($0) }
                }
                if settings.saveFormat != .png {
                    LabeledContent(L("Quality")) {
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
                Text(L("Saving"))
            } footer: {
                Text(L("The clipboard always gets a PNG. Without a save folder, Save asks where to put the file."))
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField(L("Template"), text: $settings.filenameTemplate, prompt: Text(Settings.defaultTemplate))
                    .labelsHidden()
                    .font(.body.monospaced())
                LabeledContent(L("Example")) {
                    Text(example)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(L("Tokens")) {
                    Button(L("Insert…")) { showsTokens = true }
                        .popover(isPresented: $showsTokens, arrowEdge: .trailing) { tokenGrid }
                }
            } header: {
                HStack {
                    Text(L("File name"))
                    Spacer()
                    if settings.filenameTemplate != Settings.defaultTemplate {
                        Button(L("Reset")) { settings.filenameTemplate = Settings.defaultTemplate }
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
        panel.prompt = L("Choose")
        if panel.runModal() == .OK { settings.setSaveFolder(panel.url) }
    }
}

// MARK: Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var systemOwnsKeys = false
    @State private var systemOwnsFive = false

    private func readSystemKeys() {
        systemOwnsKeys = SystemScreenshots.ownsScreenshotKeys
        systemOwnsFive = SystemScreenshots.answers(.toolbar)
    }

    private var keysToTurnOff: String {
        var keys: [String] = []
        if settings.usesScreenshotKeys && systemOwnsKeys { keys += ["⇧⌘3", "⇧⌘4"] }
        if settings.usesCaptureBar && systemOwnsFive { keys.append("⇧⌘5") }
        return keys.joined(separator: keys.count > 2 ? ", " : " and ")
    }

    var body: some View {
        Form {
            Section {
                // The pin shortcut lives with the rest of pinning, on the Pins tab.
                ForEach(HotAction.allCases.filter { $0 != .pinFiles }) { action in
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
                Text(L("Click a shortcut, then press the new keys. Delete clears it, Esc keeps it."))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: Binding(get: { settings.usesScreenshotKeys }, set: { settings.setUsesScreenshotKeys($0) })) {
                    Text(L("Use ⇧⌘3 and ⇧⌘4"))
                    Text(L("Screen and area, on the keys macOS uses for screenshots."))
                }
                Toggle(isOn: Binding(get: { settings.usesCaptureBar }, set: { settings.setUsesCaptureBar($0) })) {
                    Text("Open the capture bar with ⇧⌘5")
                    Text("Shotput’s captures beside macOS’s own recorder. Off leaves ⇧⌘5 to macOS.")
                }
                if (settings.usesScreenshotKeys && systemOwnsKeys) || (settings.usesCaptureBar && systemOwnsFive) {
                    LabeledContent {
                        Button(L("Open Keyboard Shortcuts")) { SystemScreenshots.openKeyboardShortcuts() }
                    } label: {
                        Text(L("macOS still answers these keys"))
                        Text(String(format: L("Under Screenshots, turn off %@."), keysToTurnOff))
                    }
                }
            }
            .onAppear(perform: readSystemKeys)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                readSystemKeys()
                HotKeyCenter.reload()
            }

            Section {
                LabeledContent {
                    Button(L("Show Me How")) { (NSApp.delegate as? AppDelegate)?.showOnboarding(.mouse) }
                } label: {
                    Text(L("Use a mouse button"))
                    Text(L("Logi Options+ can press any of these shortcuts for you."))
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: Pins

struct PinsPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var canPressKeys = CGPreflightPostEventAccess()

        /// Where a drag goes, and where pins open afterwards, so the notch and the menu bar icon
    /// never seem to be two different trays.
    private var pinsFooter: String {
        if settings.pinTarget == .menuBar {
            return L("Start a drag and a card drops out under Shotput’s menu bar icon to take it. Click the icon to see your pins. It stays in the menu bar while pins live there.")
        }
        let drag = NotchGeometry.hasHardwareNotch
            ? L("Start a drag and the notch grows a pin; bring it close and it opens to take the drop.")
            : L("Start a drag and the top of the screen grows a pin; bring it close and it opens to take the drop.")
        let open = settings.showsMenuBarIcon
            ? (NotchGeometry.hasHardwareNotch ? L("Click the notch, or Shotput’s menu bar icon, to see your pins.") : L("Click the top of the screen, or Shotput’s menu bar icon, to see your pins."))
            : (NotchGeometry.hasHardwareNotch ? L("Click the notch to see your pins.") : L("Click the top of the screen to see your pins."))
        return drag + " " + open
    }

    var body: some View {
        Form {
            Section {
                Picker(L("Drag to pin at"), selection: $settings.pinTarget) {
                    ForEach(Settings.PinTarget.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $settings.pinsDraggedFiles) {
                    Text(L("Take files dragged in any app"))
                    Text(L("Off, only previews open the drop target."))
                }
            } header: {
                Text(L("Dragging"))
            } footer: {
                Text(pinsFooter)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    ShortcutRecorder(shortcut: Binding(
                        get: { settings.shortcuts[.pinFiles] ?? .none },
                        set: { settings.shortcuts[.pinFiles] = $0 }
                    ))
                    .frame(width: 150, height: 24)
                } label: {
                    Text(HotAction.pinFiles.title)
                    Text(L("Select files in Finder, press it, and they fly to your pins."))
                }
                Toggle(isOn: $settings.cutsInFinder) {
                    Text(L("⌘X cuts files in Finder"))
                    Text(L("Then ⌘V moves them, with Finder’s own Move Item Here."))
                }
                if !canPressKeys && (settings.cutsInFinder || settings.shortcuts[.pinFiles]?.isSet == true) {
                    LabeledContent {
                        Button(L("Open Accessibility")) { CGRequestPostEventAccess(); SystemSettings.openAccessibility() }
                    } label: {
                        Text(L("Shotput can’t press keys yet"))
                        Text(L("Both press Copy in Finder for you. Turn Shotput on under Accessibility."))
                    }
                }
            } header: {
                Text(L("Finder"))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPressKeys = CGPreflightPostEventAccess()
        }
    }
}

/// Deep links into System Settings.
enum SystemSettings {
    static func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: About

struct AboutPane: View {
    @ObservedObject private var updates = Updates.shared
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
                Text(String(format: L("Version %@"), version)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(L("Free and open source under the MIT licence. Shotput itself has no network access. Updates come through a separate helper that only fetches signed releases from GitHub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L("Install updates automatically"), isOn: Binding(get: { updates.isAutomatic }, set: { updates.isAutomatic = $0 }))
                .toggleStyle(.checkbox)
            HStack(spacing: Metrics.spacingS) {
                Button(L("Check for Updates")) { updates.checkNow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.canCheck)
                Button(L("Source Code")) { NSWorkspace.shared.open(Self.repository) }
                Button(L("Report an Issue")) { NSWorkspace.shared.open(Self.repository.appendingPathComponent("issues/new")) }
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, Metrics.spacingL)
        .frame(maxWidth: .infinity)
    }
}

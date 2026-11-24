import AppKit
import ServiceManagement
import SwiftUI

/// Settings, in the window every Mac app uses for them: a toolbar of panes across the top, each
/// a grouped form of the same size.
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

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .capture: "camera.viewfinder"
            case .editor: "pencil.tip.crop.circle"
            case .output: "square.and.arrow.down"
            case .pins: "pin"
            case .shortcuts: "keyboard"
            case .about: "info.circle"
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
            let host = NSHostingController(rootView: pane.view)
            host.sizingOptions = .preferredContentSize
            // The tab view controller titles the window from the selected pane's controller.
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
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

    static let width = SettingsMetrics.width

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
        if !NotchGeometry.hasHardwareNotch {
            return L("Click it for pins, right-click for captures. It stays on this Mac, which has no notch to open pins from.")
        }
        return L("Click it for pins, right-click for captures. Hidden, open Shotput again to get back here.")
    }

    var body: some View {
        SettingsPage {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shotput")
                            .font(.title3.weight(.semibold))
                        if canRecordScreen {
                            StatusBadge(text: L("Ready to capture"))
                        } else {
                            StatusBadge(text: L("Screen Recording is off"), tint: Palette.Vivid.red)
                        }
                    }
                    Spacer()
                    if !canRecordScreen {
                        Button(L("Allow")) {
                            if !CGRequestScreenCaptureAccess() { ScreenPermission.openSettings() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                if !canRecordScreen {
                    Text(L("Shotput needs it to take screenshots. Reopen Shotput after you turn it on."))
                        .settingsFooter()
                }
            }

            Section(L("Startup")) {
                SettingsToggle(title: L("Open Shotput at login"), symbol: "power", tint: Palette.Vivid.green, isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                SettingsToggle(title: L("Show in the menu bar"), subtitle: menuBarIconDetail, symbol: "menubar.rectangle", tint: Palette.Vivid.blue, isOn: $settings.showsMenuBarIcon)
                    // Without a notch, the icon is how pins are opened at rest.
                    .disabled(settings.pinTarget == .menuBar || (!NotchGeometry.hasHardwareNotch && settings.showsMenuBarIcon))
            }

            Section(L("Feedback")) {
                SettingsToggle(title: L("Play a sound on capture"), symbol: "speaker.wave.2.fill", tint: Palette.Vivid.pink, isOn: $settings.playsSound)
                SettingsToggle(title: L("Flash what was captured"), subtitle: L("A brief shutter over the area, so you see it land"), symbol: "camera.aperture", tint: Palette.Vivid.yellow, isOn: $settings.showsFlash)
            }

            Section(L("macOS Screenshots")) {
                SettingsToggle(
                    title: L("Preview macOS screenshots"), subtitle: macScreenshotsDetail,
                    symbol: "macwindow.on.rectangle", tint: Palette.Vivid.violet,
                    isOn: Binding(
                        get: { settings.screenshotFolder != nil },
                        set: { on in
                            if on { MacScreenshotWatcher.shared.enable() } else { MacScreenshotWatcher.shared.disable() }
                        }
                    )
                )
            }

            Section(L("Automation")) {
                SettingsToggle(title: L("Allow shotput:// links"), subtitle: L("Lets launchers and Logi Options+ Smart Actions start a capture."), symbol: "link", tint: Palette.Vivid.cyan, isOn: $settings.allowsLinks)
            }

            Section {
                SettingsRow(title: L("All settings"), subtitle: L("Shortcuts and preferences go back to how Shotput ships."), symbol: "arrow.counterclockwise", tint: Palette.Vivid.gray) {
                    Button(L("Reset…")) { confirmsReset = true }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canRecordScreen = CGPreflightScreenCaptureAccess()
        }
        .confirmationDialog(L("Reset every setting?"), isPresented: $confirmsReset) {
            Button(L("Reset"), role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text(L("Shortcuts and preferences go back to how Shotput ships. Your save folder stays."))
        }
    }

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

// MARK: Capture

struct CapturePane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        SettingsPage {
            Section {
                AfterCapturePicker(selection: $settings.afterCapture)
            } header: {
                Text(L("After a Capture"))
            } footer: {
                Text(L("The clipboard always has the capture the moment you let go, whichever you pick."))
                    .settingsFooter()
            }

            if settings.afterCapture == .preview {
                Section {
                    CornerPicker(selection: $settings.previewCorner)
                    SettingsRow(title: L("Stays on screen"), subtitle: L("Pointing at a preview holds it there"), symbol: "timer", tint: Palette.Vivid.orange) {
                        SteppedSlider(values: Settings.previewDurations, value: $settings.previewDuration, label: Settings.durationTitle)
                    }
                } header: {
                    Text(L("Previews"))
                } footer: {
                    Text(L("Several captures stack in the corner. Point at the stack to fan it out; click one to bring it to the front, and the front one to annotate it."))
                        .settingsFooter()
                }
            }

            Section(L("While Selecting")) {
                SettingsToggle(title: L("Show the magnifier"), subtitle: L("Pixel-exact edges, right beside the pointer"), symbol: "plus.magnifyingglass", tint: Palette.Vivid.blue, isOn: $settings.showsMagnifier)
                SettingsToggle(title: L("Snap to window edges"), subtitle: L("Hold ⌘ while selecting to place freely either way."), symbol: "rectangle.dashed", tint: Palette.Vivid.orange, isOn: $settings.snapsToEdges)
                SettingsPicker(title: L("Show the hint"), symbol: "text.bubble", tint: Palette.Vivid.gray, options: Settings.Hints.allCases, label: \.title, selection: $settings.selectionHints)
            }

            Section(L("Windows")) {
                SettingsToggle(title: L("Keep the window’s shadow"), symbol: "shadow", tint: Palette.Vivid.gray, isOn: $settings.windowShadow)
                SettingsRow(title: L("Background"), subtitle: L("Behind a window you capture"), symbol: "photo", tint: Palette.Vivid.green) {
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
                    SettingsRow(title: L("Padding"), symbol: "square.dashed", tint: Palette.Vivid.cyan) {
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

            Section(L("In Captures")) {
                SettingsToggle(title: L("Include the pointer in screen captures"), symbol: "cursorarrow", tint: Palette.Vivid.gray, isOn: $settings.showsPointer)
                SettingsToggle(title: L("Include Shotput’s own windows"), subtitle: L("Settings, the editor, and the guide. Previews, the notch, and the selection are always left out."), symbol: "macwindow", tint: Palette.Vivid.violet, isOn: $settings.capturesOwnWindows)
            }
        }
    }
}

// MARK: Editor

struct EditorPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        SettingsPage {
            Section {
                SettingsPicker(title: L("Esc"), symbol: "escape", tint: Palette.Vivid.gray, options: Settings.EscapeInEditor.allCases, label: \.title, selection: $settings.escapeInEditor)
                SettingsToggle(title: L("Copy (⌘C) also closes the editor"), symbol: "doc.on.doc.fill", tint: Palette.Vivid.blue, isOn: $settings.editorClosesOnCopy)
            } header: {
                Text(L("Closing"))
            } footer: {
                Text(L("Return always copies and closes. Esc first clears a selection or crop, then closes."))
                    .settingsFooter()
            }

            Section(L("Drawing")) {
                SettingsToggle(title: L("Turn sketches into shapes"), subtitle: L("A pen stroke that looks like a line, arrow, rectangle, or circle becomes one. ⌘Z keeps the sketch."), symbol: "scribble.variable", tint: Palette.Vivid.pink, isOn: $settings.recognizesShapes)
            }

            Section(L("Text Recognition")) {
                SettingsToggle(title: L("Keep line breaks"), subtitle: L("Off joins every line into one, which suits pasting a paragraph."), symbol: "text.alignleft", tint: Palette.Vivid.green, isOn: $settings.ocrKeepsLineBreaks)
                SettingsToggle(title: L("Correct spelling while reading"), symbol: "textformat.abc", tint: Palette.Vivid.orange, isOn: $settings.ocrLanguageCorrection)
            }
        }
    }
}

// MARK: Output

struct OutputPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var showsTokens = false

    var body: some View {
        SettingsPage {
            Section {
                SettingsToggle(title: L("Use standard resolution"), subtitle: L("Halves the pixel size on Retina displays. Smaller images are quicker for an agent to read."), symbol: "arrow.down.right.and.arrow.up.left", tint: Palette.Vivid.blue, isOn: $settings.copyAtPointSize)
            } header: {
                Text(L("Clipboard and Files"))
            }

            Section {
                SettingsRow(title: L("Save folder"), subtitle: settings.saveFolder?.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"), symbol: "folder.fill", tint: Palette.Vivid.cyan) {
                    HStack(spacing: Metrics.spacingS) {
                        if settings.saveFolder != nil {
                            Button(L("Clear")) { settings.setSaveFolder(nil) }
                        }
                        Button(settings.saveFolder == nil ? L("Choose…") : L("Change…")) { chooseFolder() }
                    }
                }
                SettingsToggle(title: L("Save every capture there"), symbol: "tray.and.arrow.down.fill", tint: Palette.Vivid.green, isOn: $settings.savesEveryCapture)
                    .disabled(settings.saveFolder == nil)
                SettingsPicker(title: L("Format"), symbol: "photo.fill", tint: Palette.Vivid.violet, options: Settings.SaveFormat.allCases, label: \.title, selection: $settings.saveFormat)
                if settings.saveFormat != .png {
                    SettingsRow(title: L("Quality"), symbol: "slider.horizontal.3", tint: Palette.Vivid.orange) {
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
                    .settingsFooter()
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
                    Text(L("File Name"))
                    Spacer()
                    if settings.filenameTemplate != Settings.defaultTemplate {
                        Button(L("Reset")) { settings.filenameTemplate = Settings.defaultTemplate }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
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

extension HotAction {
    /// The action's icon in Settings.
    var settingsSymbol: (name: String, tint: Color) {
        switch self {
        case .area: ("rectangle.dashed", Palette.Vivid.blue)
        case .areaAnnotate: ("pencil.and.outline", Palette.Vivid.pink)
        case .window: ("macwindow", Palette.Vivid.violet)
        case .screen: ("display", Palette.Vivid.cyan)
        case .annotateLast: ("clock.arrow.circlepath", Palette.Vivid.orange)
        case .repeatArea: ("arrow.clockwise", Palette.Vivid.green)
        case .text: ("text.viewfinder", Palette.Vivid.yellow)
        case .annotateClipboard: ("doc.on.clipboard.fill", Palette.Vivid.gray)
        case .toolbar: ("menubar.dock.rectangle", Palette.Vivid.gray)
        case .pinFiles: ("pin.fill", Palette.Vivid.red)
        }
    }
}

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
        SettingsPage {
            Section {
                // The pin shortcut lives with the rest of pinning, on the Pins tab.
                ForEach(HotAction.allCases.filter { $0 != .pinFiles }) { action in
                    SettingsRow(title: action.title, subtitle: action.detail, symbol: action.settingsSymbol.name, tint: action.settingsSymbol.tint) {
                        ShortcutRecorder(shortcut: Binding(
                            get: { settings.shortcuts[action] ?? .none },
                            set: { settings.shortcuts[action] = $0 }
                        ))
                        .frame(width: 150, height: 24)
                    }
                }
            } footer: {
                Text(L("Click a shortcut, then press the new keys. Delete clears it, Esc keeps it. Pressing a capture shortcut again while selecting backs out."))
                    .settingsFooter()
            }

            Section(L("macOS Keys")) {
                SettingsToggle(title: L("Use ⇧⌘3 and ⇧⌘4"), subtitle: L("Screen and area, on the keys macOS uses for screenshots."), symbol: "command", tint: Palette.Vivid.blue,
                               isOn: Binding(get: { settings.usesScreenshotKeys }, set: { settings.setUsesScreenshotKeys($0) }))
                SettingsToggle(title: L("Open the capture bar with ⇧⌘5"), subtitle: L("Shotput’s captures beside macOS’s own recorder. Off leaves ⇧⌘5 to macOS."), symbol: "menubar.dock.rectangle", tint: Palette.Vivid.violet,
                               isOn: Binding(get: { settings.usesCaptureBar }, set: { settings.setUsesCaptureBar($0) }))
                if (settings.usesScreenshotKeys && systemOwnsKeys) || (settings.usesCaptureBar && systemOwnsFive) {
                    SettingsRow(title: L("macOS still answers these keys"), subtitle: String(format: L("Under Screenshots, turn off %@."), keysToTurnOff), symbol: "exclamationmark.triangle.fill", tint: Palette.Vivid.yellow) {
                        Button(L("Open Keyboard Shortcuts")) { SystemScreenshots.openKeyboardShortcuts() }
                    }
                }
            }
            .onAppear(perform: readSystemKeys)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                readSystemKeys()
                HotKeyCenter.reload()
            }

            Section {
                SettingsRow(title: L("Use a mouse button"), subtitle: L("Logi Options+ can press any of these shortcuts for you."), symbol: "computermouse.fill", tint: Palette.Vivid.green) {
                    Button(L("Show Me How")) { (NSApp.delegate as? AppDelegate)?.showOnboarding(.mouse) }
                }
            }
        }
    }
}

// MARK: Pins

struct PinsPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var canPressKeys = CGPreflightPostEventAccess()

    /// Where the island goes matters only with another display, or no notch at all.
    private var showsPlacement: Bool {
        NSScreen.screens.count > 1 || !NotchGeometry.hasHardwareNotch
    }

    /// Where a drag goes, and where pins open afterwards, so the notch and the menu bar icon
    /// never seem to be two different trays.
    private var pinsFooter: String {
        if settings.pinTarget == .menuBar {
            return L("Start a drag and a card drops out under Shotput’s menu bar icon to take it. Click the icon to see your pins. It stays in the menu bar while pins live there.")
        }
        let drag = L("Start a drag and the notch grows a pin; bring it close and it opens to take the drop.")
        let island = L("On a display without a notch, a Dynamic Island in the menu bar does the same: out of sight until it’s needed.")
        let open = settings.showsMenuBarIcon
            ? L("Click the notch, or Shotput’s menu bar icon, to see your pins.")
            : L("Click the notch to see your pins.")
        return [drag, open, showsPlacement ? island : nil].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        SettingsPage {
            Section {
                PinTargetPicker(selection: $settings.pinTarget)
            } header: {
                Text(L("Where Pins Live"))
            } footer: {
                Text(pinsFooter)
                    .settingsFooter()
            }

            if settings.pinTarget == .notch {
                Section(NotchGeometry.hasHardwareNotch ? L("Notch") : L("Dynamic Island")) {
                    if showsPlacement {
                        SettingsPicker(title: L("Show on"), subtitle: L("Displays without a notch get a Dynamic Island in the menu bar"), symbol: "display.2", tint: Palette.Vivid.blue,
                                       options: Settings.Placement.allCases, label: \.title, selection: $settings.islandPlacement)
                    }
                    if NotchGeometry.hasHardwareNotch {
                    SettingsToggle(title: L("Show pins beside the notch"), subtitle: L("Shotput’s icon and how many are waiting. Off, the notch stays bare until a drag."), symbol: "pin.fill", tint: Palette.Vivid.red, isOn: $settings.showsPinBadge)
                    }
                }
            }

            Section(L("Dragging")) {
                SettingsToggle(title: L("Take files dragged in any app"), subtitle: L("Off, only previews open the drop target."), symbol: "hand.draw.fill", tint: Palette.Vivid.orange, isOn: $settings.pinsDraggedFiles)
            }

            Section {
                SettingsRow(title: HotAction.pinFiles.title, subtitle: L("Select files in Finder, press it, and they fly to your pins."), symbol: "pin.fill", tint: Palette.Vivid.red) {
                    ShortcutRecorder(shortcut: Binding(
                        get: { settings.shortcuts[.pinFiles] ?? .none },
                        set: { settings.shortcuts[.pinFiles] = $0 }
                    ))
                    .frame(width: 150, height: 24)
                }
                SettingsToggle(title: L("⌘X cuts files in Finder"), subtitle: L("Then ⌘V moves them, with Finder’s own Move Item Here."), symbol: "scissors", tint: Palette.Vivid.gray, isOn: $settings.cutsInFinder)
                if !canPressKeys && (settings.cutsInFinder || settings.shortcuts[.pinFiles]?.isSet == true) {
                    SettingsRow(title: L("Shotput can’t press keys yet"), subtitle: L("Both press Copy in Finder for you. Turn Shotput on under Accessibility."), symbol: "exclamationmark.triangle.fill", tint: Palette.Vivid.yellow) {
                        Button(L("Open Accessibility")) { CGRequestPostEventAccess(); SystemSettings.openAccessibility() }
                    }
                }
            } header: {
                Text(L("Finder"))
            }
        }
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
        SettingsPage {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shotput")
                            .font(.title2.weight(.semibold))
                        Text(String(format: L("Version %@"), version))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(L("Press, drag, paste into your agent."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(L("Check for Updates")) { updates.checkNow() }
                        .disabled(!updates.canCheck)
                }
                .padding(.vertical, 6)
            }

            Section(L("Updates")) {
                SettingsToggle(
                    title: L("Install updates automatically"),
                    subtitle: L("Only signed releases, fetched by a separate helper. Shotput itself has no network access."),
                    symbol: "arrow.down.circle.fill", tint: Palette.Vivid.blue,
                    isOn: Binding(get: { updates.isAutomatic }, set: { updates.isAutomatic = $0 })
                )
            }

            Section(L("Open Source")) {
                SettingsRow(title: L("Source code"), subtitle: L("Free under the MIT licence"), symbol: "chevron.left.forwardslash.chevron.right", tint: Palette.Vivid.gray) {
                    Button(L("Open")) { NSWorkspace.shared.open(Self.repository) }
                }
                SettingsRow(title: L("Report an issue"), subtitle: L("Something broken, or something missing"), symbol: "ladybug.fill", tint: Palette.Vivid.red) {
                    Button(L("Open")) { NSWorkspace.shared.open(Self.repository.appendingPathComponent("issues/new")) }
                }
            }
        }
    }
}

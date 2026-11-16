import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pictures

/// The pictures a backdrop can use, all already on this Mac: the macOS desktop pictures that are
/// stored in full, and pictures you add. Only small thumbnails are kept in memory.
@MainActor
final class BackdropLibrary: ObservableObject {
    static let shared = BackdropLibrary()

    struct Picture: Identifiable, Equatable {
        let url: URL
        /// Added by you, kept as a bookmark; otherwise one of the system's.
        let isUser: Bool
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var system: [Picture] = []
    @Published private(set) var user: [Picture] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]

    private static let bookmarksKey = "backdrop.pictures"
    private static let systemFolder = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
    private static let limit = 12
    private var isLoaded = false

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        user = Self.storedBookmarks().compactMap { Self.resolve($0) }.map { Picture(url: $0, isUser: true) }
        Task.detached(priority: .utility) {
            // Only stills stored in full: dynamic wallpapers download on demand and leave a thumbnail.
            let files = (try? FileManager.default.contentsOfDirectory(at: Self.systemFolder, includingPropertiesForKeys: nil)) ?? []
            let stills = files
                .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            await MainActor.run { self.system = stills.map { Picture(url: $0, isUser: false) } }
        }
    }

    /// A small preview for a swatch, made once in the background.
    func thumbnail(for url: URL) -> NSImage? {
        if let image = thumbnails[url] { return image }
        thumbnails[url] = NSImage(size: .zero)
        let thumbnailFile = Self.systemFolder.appendingPathComponent(".thumbnails").appendingPathComponent(url.lastPathComponent)
        Task.detached(priority: .utility) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let source = FileManager.default.fileExists(atPath: thumbnailFile.path) ? thumbnailFile : url
            guard let cg = Backdrop.loadPicture(source, maxPixels: 160) else { return }
            let image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
            await MainActor.run { self.thumbnails[url] = image }
        }
        return nil
    }

    /// Asks for pictures to add. They stay where they are; Shotput keeps a bookmark to each.
    func add(over window: NSWindow?, then chosen: @escaping (Picture) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("Choose pictures to use as backgrounds")
        panel.prompt = L("Add")
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            let added = panel.urls.map { Picture(url: $0, isUser: true) }.filter { !self.user.contains($0) }
            self.user = Array((added + self.user).prefix(Self.limit))
            self.storeBookmarks()
            if let first = added.first ?? panel.urls.first.map({ Picture(url: $0, isUser: true) }) { chosen(first) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    func remove(_ picture: Picture) {
        user.removeAll { $0 == picture }
        thumbnails[picture.url] = nil
        storeBookmarks()
    }

    private func storeBookmarks() {
        let data = user.compactMap { try? $0.url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
        UserDefaults.standard.set(data, forKey: Self.bookmarksKey)
    }

    private static func storedBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
    }

    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - Controls

/// The Background sidebar's state. Every change applies at once; sliders fold each drag into one
/// undo step. The last settings are remembered for the next screenshot, and any can be kept as a
/// named preset.
@MainActor
final class BackdropControls: ObservableObject {
    /// Nil for no backdrop.
    @Published private(set) var fill: Backdrop.Fill?
    @Published var padding: Double
    @Published var inset: Double
    @Published var autoBalance: Bool
    @Published var cornerRadius: Double
    @Published var shadow: Double
    @Published private(set) var blur: Bool
    @Published var ratio: Backdrop.Ratio
    @Published var alignment: Backdrop.Alignment
    /// The custom colour's value, kept apart from the presets.
    @Published var customColor: NSColor
    /// The screenshot is a window capture, with its own edges and shadow, so Inset and
    /// Auto-balance don't apply to it.
    @Published var hasOwnCorners = false
    /// The live wallpaper of the screen the capture came from, for its swatches.
    @Published var desktopThumbnail: NSImage?
    @Published private(set) var presets: [Preset] = []

    /// Called with the style to apply, and whether it continues the previous change.
    var onChange: ((Backdrop.Style?, _ continuing: Bool) -> Void)?
    private var isSliding = false
    private static let savedKey = "editor.backdrop"
    private static let presetsKey = "editor.backdrop.presets"

    init(current: Backdrop.Style?) {
        let saved = Self.saved()
        fill = nil
        padding = saved?.padding ?? 48
        inset = saved?.inset ?? 0
        autoBalance = saved?.autoBalance ?? false
        cornerRadius = saved?.cornerRadius ?? 10
        shadow = saved?.shadow ?? 0.65
        blur = false
        ratio = saved?.ratio ?? .auto
        alignment = saved?.alignment ?? .center
        customColor = Settings.shared.windowBackgroundColor
        presets = Self.storedPresets()
        sync(current)
    }

    /// Matches the controls to the image, for example after an undo, without applying anything.
    func sync(_ current: Backdrop.Style?) {
        let callback = onChange
        onChange = nil
        defer { onChange = callback }
        fill = current?.fill
        guard let current else { return }
        padding = Double(current.padding)
        inset = Double(current.inset)
        autoBalance = current.autoBalance
        cornerRadius = Double(current.cornerRadius)
        shadow = Double(current.shadow)
        blur = current.blur
        ratio = current.ratio
        alignment = current.alignment
        if case let .color(color) = current.fill, !Backdrop.colorPresets.contains(color.hexValue) { customColor = color }
    }

    var style: Backdrop.Style? {
        fill.map {
            Backdrop.Style(
                fill: $0, padding: padding, inset: inset, autoBalance: autoBalance, cornerRadius: cornerRadius,
                shadow: shadow, blur: blur, ratio: ratio, alignment: alignment
            )
        }
    }

    func isChosen(_ fill: Backdrop.Fill, blurred: Bool = false) -> Bool {
        self.fill == fill && (!fill.needsPicture || blur == blurred)
    }

    func choose(_ fill: Backdrop.Fill?, blurred: Bool = false) {
        self.fill = fill
        blur = blurred
        apply()
    }

    func apply() {
        isSliding = false
        onChange?(style, false)
        save()
    }

    /// A slider moved: one undo step per drag.
    func sliding() {
        guard fill != nil else { return }
        onChange?(style, isSliding)
        isSliding = true
    }

    func endSlide() {
        isSliding = false
        save()
    }

    // MARK: Presets

    struct Preset: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        fileprivate var settings: Saved
    }

    var hasPrevious: Bool { Self.saved()?.fill != nil }

    /// Everything as it was last left, fill included.
    func applyPrevious() {
        guard let saved = Self.saved() else { return }
        load(saved)
    }

    func apply(_ preset: Preset) { load(preset.settings) }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, fill != nil else { return }
        presets.removeAll { $0.name == trimmed }
        presets.append(Preset(name: trimmed, settings: current()))
        storePresets()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0 == preset }
        storePresets()
    }

    private func load(_ saved: Saved) {
        padding = saved.padding
        inset = saved.inset ?? 0
        autoBalance = saved.autoBalance ?? false
        cornerRadius = saved.cornerRadius
        shadow = saved.shadow
        ratio = saved.ratio
        alignment = saved.alignment
        choose(saved.fill, blurred: saved.blur)
    }

    private func storePresets() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: Self.presetsKey) }
    }

    private static func storedPresets() -> [Preset] {
        UserDefaults.standard.data(forKey: presetsKey).flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []
    }

    // MARK: Remembering

    fileprivate struct Saved: Codable, Equatable {
        enum Kind: String, Codable { case wallpaper, picture, color, gradient, clear }
        var kind: Kind?
        var color: UInt?
        var gradient: [UInt]?
        var angle: CGFloat?
        var picture: String?
        var padding: Double
        var inset: Double?
        var autoBalance: Bool?
        var cornerRadius: Double
        var shadow: Double
        var blur: Bool
        var ratio: Backdrop.Ratio
        var alignment: Backdrop.Alignment

        var fill: Backdrop.Fill? {
            switch kind {
            case .wallpaper: .wallpaper
            case .picture: picture.map { .picture(URL(fileURLWithPath: $0)) }
            case .color: color.map { .color(NSColor(hex: $0)) }
            case .gradient: gradient.map { .gradient(Backdrop.Gradient(colors: $0, angle: angle ?? 135)) }
            case .clear: .clear
            case nil: nil
            }
        }
    }

    private func current() -> Saved {
        var saved = Saved(
            padding: padding, inset: inset, autoBalance: autoBalance, cornerRadius: cornerRadius,
            shadow: shadow, blur: blur, ratio: ratio, alignment: alignment
        )
        switch fill {
        case .wallpaper: saved.kind = .wallpaper
        case let .picture(url): saved.kind = .picture; saved.picture = url.path
        case let .color(color): saved.kind = .color; saved.color = color.hexValue
        case let .gradient(gradient): saved.kind = .gradient; saved.gradient = gradient.colors; saved.angle = gradient.angle
        case .clear: saved.kind = .clear
        case nil: break
        }
        return saved
    }

    /// Keeps the last fill through a None, so Previous Settings can bring it back.
    private func save() {
        var saved = current()
        if fill == nil, let previous = Self.saved() {
            saved.kind = previous.kind
            saved.color = previous.color
            saved.gradient = previous.gradient
            saved.angle = previous.angle
            saved.picture = previous.picture
            saved.blur = previous.blur
        }
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.savedKey) }
    }

    private static func saved() -> Saved? {
        UserDefaults.standard.data(forKey: savedKey).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }
}

extension Backdrop.Ratio: Codable {}
extension Backdrop.Alignment: Codable {}

extension NSColor {
    /// The colour as 0xRRGGBB in sRGB.
    var hexValue: UInt {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> UInt { UInt((min(max(value, 0), 1) * 255).rounded()) }
        return channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8 | channel(rgb.blueComponent)
    }
}

// MARK: - Sidebar

/// The Background sidebar, laid out like CleanShot X's so it feels familiar: presets, None, then
/// gradients, wallpapers, blurred wallpapers and plain colours, then how the screenshot sits.
/// Built from native controls, so the sliders, buttons and menus are Liquid Glass.
struct BackdropSidebar: View {
    static let width: CGFloat = 5 * SwatchMetrics.size + 4 * SwatchMetrics.spacing + 2 * 18

    @ObservedObject var controls: BackdropControls
    @ObservedObject var library = BackdropLibrary.shared
    /// Opens the panel to add pictures, from the editor's window.
    var addPictures: () -> Void

    @AppStorage("editor.backdrop.showsAllGradients") private var showsAllGradients = false
    @AppStorage("editor.backdrop.showsAllWallpapers") private var showsAllWallpapers = false
    @AppStorage("editor.backdrop.showsAllBlurred") private var showsAllBlurred = false
    @State private var isNamingPreset = false
    @State private var presetName = ""

    private let columns = Array(repeating: GridItem(.fixed(SwatchMetrics.size), spacing: SwatchMetrics.spacing), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 10) {
                    presetsRow
                    noneButton
                }
                gradients
                wallpapers
                blurred
                plainColors
                Divider()
                layoutControls
                    .disabled(controls.fill == nil)
                    .opacity(controls.fill == nil ? 0.4 : 1)
            }
            .padding(18)
        }
        .scrollIndicators(.never)
        .frame(width: Self.width)
        .onAppear { library.load() }
        .animation(.snappy(duration: 0.22), value: showsAllGradients)
        .animation(.snappy(duration: 0.22), value: showsAllWallpapers)
        .animation(.snappy(duration: 0.22), value: showsAllBlurred)
        .alert(L("Save as Preset"), isPresented: $isNamingPreset) {
            TextField(L("Name"), text: $presetName)
            Button(L("Save")) { controls.savePreset(named: presetName) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Keeps this background, padding, corners, shadow and ratio to use again."))
        }
    }

    // MARK: Top

    private var presetsRow: some View {
        HStack(spacing: 8) {
            Menu {
                if controls.hasPrevious {
                    Button(L("Apply Previous Settings")) { controls.applyPrevious() }
                }
                if !controls.presets.isEmpty {
                    Section {
                        ForEach(controls.presets) { preset in
                            Button(preset.name) { controls.apply(preset) }
                        }
                    }
                    Menu(L("Delete Preset")) {
                        ForEach(controls.presets) { preset in
                            Button(preset.name, role: .destructive) { controls.delete(preset) }
                        }
                    }
                }
                Section {
                    Button(L("Save as Preset…"), action: namePreset)
                        .disabled(controls.fill == nil)
                }
            } label: {
                Text(L("Presets…")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonSizing(.flexible)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button(action: namePreset) {
                Image(systemName: "plus")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(controls.fill == nil)
            .help(L("Save as Preset…"))
            .accessibilityLabel(L("Save as Preset…"))
        }
    }

    private func namePreset() {
        presetName = ""
        isNamingPreset = true
    }

    @ViewBuilder
    private var noneButton: some View {
        let isNone = controls.fill == nil
        if isNone {
            Button { controls.choose(nil) } label: { Text(L("None")).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        } else {
            Button { controls.choose(nil) } label: { Text(L("None")).frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    // MARK: Fills

    private var gradients: some View {
        let all = Backdrop.Gradient.presets
        let shown = showsAllGradients ? all : Array(all.prefix(10))
        return section(L("Gradients"), expanded: $showsAllGradients, canExpand: all.count > 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: SwatchMetrics.spacing) {
                ForEach(shown, id: \.self) { gradient in
                    Swatch(isSelected: controls.isChosen(.gradient(gradient)), help: L("Gradient")) {
                        controls.choose(.gradient(gradient))
                    } content: {
                        LinearGradient(colors: gradient.nsColors.map(Color.init(nsColor:)), startPoint: gradient.start, endPoint: gradient.end)
                    }
                }
            }
        }
    }

    private var pictures: [BackdropLibrary.Picture] { library.user + library.system }

    private var wallpapers: some View {
        // The desktop, then pictures, then Add; one row until expanded.
        let all = pictures
        let shown = showsAllWallpapers ? all : Array(all.prefix(3))
        return section(L("Wallpapers"), expanded: $showsAllWallpapers, canExpand: all.count > 3) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: SwatchMetrics.spacing) {
                desktopSwatch(blurred: false)
                ForEach(shown) { pictureSwatch($0, blurred: false) }
                Button(action: addPictures) {
                    RoundedRectangle(cornerRadius: SwatchMetrics.radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary))
                        .frame(width: SwatchMetrics.size, height: SwatchMetrics.size)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(L("Add pictures…"))
                .accessibilityLabel(L("Add pictures…"))
            }
        }
    }

    private var blurred: some View {
        let all = pictures
        let shown = showsAllBlurred ? all : Array(all.prefix(4))
        return section(L("Blurred"), expanded: $showsAllBlurred, canExpand: all.count > 4) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: SwatchMetrics.spacing) {
                desktopSwatch(blurred: true)
                ForEach(shown) { pictureSwatch($0, blurred: true) }
            }
        }
    }

    private func desktopSwatch(blurred: Bool) -> some View {
        Swatch(isSelected: controls.isChosen(.wallpaper, blurred: blurred), help: blurred ? L("Your desktop, blurred") : L("Your desktop, as it is now")) {
            controls.choose(.wallpaper, blurred: blurred)
        } content: {
            if let image = controls.desktopThumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: blurred ? 5 : 0, opaque: true)
            } else {
                Color.primary.opacity(0.06)
                    .overlay(Image(systemName: "menubar.dock.rectangle").font(.system(size: 15)).foregroundStyle(.secondary))
            }
        }
    }

    private func pictureSwatch(_ picture: BackdropLibrary.Picture, blurred: Bool) -> some View {
        Swatch(isSelected: controls.isChosen(.picture(picture.url), blurred: blurred), help: picture.name) {
            controls.choose(.picture(picture.url), blurred: blurred)
        } content: {
            if let image = library.thumbnail(for: picture.url), image.size != .zero {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: blurred ? 5 : 0, opaque: true)
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .contextMenu {
            if picture.isUser {
                Button(L("Remove"), role: .destructive) {
                    if controls.fill == .picture(picture.url) { controls.choose(nil) }
                    library.remove(picture)
                }
            }
        }
    }

    private var plainColors: some View {
        section(L("Plain colour")) {
            let rows = [Array(Backdrop.colorPresets.prefix(8)), Array(Backdrop.colorPresets.dropFirst(8))]
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0 ..< 2, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(rows[row], id: \.self) { hex in
                            Dot(isSelected: isColor(hex), help: L("Colour")) {
                                controls.choose(.color(NSColor(hex: hex)))
                            } content: {
                                Circle().fill(Color(nsColor: NSColor(hex: hex)))
                            }
                            Spacer(minLength: 0)
                        }
                        if row == 0 {
                            Dot(isSelected: controls.fill == .clear, help: L("Transparent")) {
                                controls.choose(.clear)
                            } content: {
                                Checkerboard().clipShape(.circle)
                            }
                        } else {
                            Dot(isSelected: isCustomColor, help: L("Custom colour")) {
                                ColorPanelBridge.shared.show(controls.customColor) { color in
                                    controls.customColor = color
                                    controls.choose(.color(color))
                                }
                            } content: {
                                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            }
                        }
                    }
                }
            }
        }
    }

    private func isColor(_ hex: UInt) -> Bool {
        if case let .color(color) = controls.fill { return color.hexValue == hex }
        return false
    }

    private var isCustomColor: Bool {
        if case let .color(color) = controls.fill { return !Backdrop.colorPresets.contains(color.hexValue) }
        return false
    }

    private func section(_ title: String, expanded: Binding<Bool>? = nil, canExpand: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let expanded, canExpand {
                    Button {
                        expanded.wrappedValue.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(expanded.wrappedValue ? L("Show less") : L("Show more"))
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(expanded.wrappedValue ? 0 : 180))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
    }

    // MARK: Layout

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            ValueSlider(title: L("Padding"), value: $controls.padding, range: 0 ... 200, step: 1, format: { "\(Int($0))" }, controls: controls)
            HStack(alignment: .bottom, spacing: 16) {
                ValueSlider(title: L("Inset"), value: $controls.inset, range: 0 ... 80, step: 1, format: { "\(Int($0))" }, controls: controls)
                Toggle(L("Auto-balance"), isOn: $controls.autoBalance)
                    .toggleStyle(.checkbox)
                    .help(L("Evens out the margins around what you captured"))
                    .onChange(of: controls.autoBalance) { controls.apply() }
                    .padding(.bottom, 1)
            }
            .disabled(controls.hasOwnCorners)
            HStack(alignment: .top, spacing: 16) {
                ValueSlider(title: L("Shadow"), value: $controls.shadow, range: 0 ... 1, step: 0.01, format: { "\(Int(($0 * 100).rounded()))" }, controls: controls)
                ValueSlider(title: L("Corners"), value: $controls.cornerRadius, range: 0 ... 40, step: 1, format: { "\(Int($0))" }, controls: controls)
            }
            if controls.hasOwnCorners {
                Text(L("A window keeps its own edges, so Inset and Auto-balance are off for it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Alignment")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    AlignmentGrid(selection: $controls.alignment) { controls.apply() }
                        .disabled(controls.ratio == .auto)
                        .opacity(controls.ratio == .auto ? 0.5 : 1)
                        .help(controls.ratio == .auto ? L("Pick a ratio to move the screenshot within it") : L("Where the screenshot sits"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Ratio")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Picker(L("Ratio"), selection: $controls.ratio) {
                        ForEach(Backdrop.Ratio.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .buttonStyle(.glass)
                    .buttonSizing(.flexible)
                    .frame(maxWidth: .infinity)
                    .onChange(of: controls.ratio) { controls.apply() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A titled slider that shows its value in a small badge while you drag it or point at it.
private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    @ObservedObject var controls: BackdropControls
    @State private var isEditing = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(format(value))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 5, style: .continuous))
                    .opacity(isEditing || isHovered ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isEditing || isHovered)
            }
            // Continuous: a step would draw tick marks under the track.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range) { editing in
                isEditing = editing
                if !editing { controls.endSlide() }
            }
            .controlSize(.small)
            .onChange(of: value) { controls.sliding() }
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
        }
        .onHover { isHovered = $0 }
    }
}

enum SwatchMetrics {
    static let size: CGFloat = 40
    static let radius: CGFloat = 11
    static let spacing: CGFloat = 10
}

/// One fill in a grid: a rounded square, lifted a little on hover, ringed when chosen.
private struct Swatch<Content: View>: View {
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SwatchMetrics.radius, style: .continuous)
        Button(action: action) {
            content
                .frame(width: SwatchMetrics.size, height: SwatchMetrics.size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 5 : 2, y: isHovered ? 2 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: SwatchMetrics.radius + 3.5, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .padding(-3.5)
                        .opacity(isSelected ? 1 : 0)
                )
                .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One plain colour: a small circle, ringed when chosen.
private struct Dot<Content: View>: View {
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3.5).opacity(isSelected ? 1 : 0))
                .scaleEffect(isHovered ? 1.1 : 1)
                .frame(width: 26, height: 26)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Opens the system colour panel and reports each colour picked in it.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var picked: ((NSColor) -> Void)?

    func show(_ color: NSColor, picked: @escaping (NSColor) -> Void) {
        self.picked = picked
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        picked?(panel.color)
    }
}

/// The transparent choice, drawn as the usual grey and white checks.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 5
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0 ..< Int(ceil(size.height / cell)) {
                for column in 0 ..< Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color(white: 0.78)))
                }
            }
        }
    }
}

/// Nine positions for the screenshot within a fixed ratio, each drawn as a frame with the
/// screenshot in that spot.
private struct AlignmentGrid: View {
    @Binding var selection: Backdrop.Alignment
    let changed: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0 ..< 3) { row in
                GridRow {
                    ForEach(0 ..< 3) { column in
                        let alignment = Backdrop.Alignment(rawValue: row * 3 + column) ?? .center
                        let isSelected = selection == alignment
                        Button {
                            selection = alignment
                            changed()
                        } label: {
                            let unit = alignment.unit
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.3), lineWidth: isSelected ? 1.6 : 1)
                                .frame(width: 24, height: 18)
                                .overlay(alignment: Alignment(horizontal: unit.x == 0 ? .leading : unit.x == 1 ? .trailing : .center,
                                                              vertical: unit.y == 0 ? .top : unit.y == 1 ? .bottom : .center)) {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(isSelected ? Color.primary : Color.primary.opacity(0.35))
                                        .frame(width: 10, height: 7)
                                        .padding(3)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(alignment.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private extension Backdrop.Alignment {
    var title: String {
        switch self {
        case .topLeft: L("Top left")
        case .top: L("Top")
        case .topRight: L("Top right")
        case .left: L("Middle left")
        case .center: L("Centre")
        case .right: L("Middle right")
        case .bottomLeft: L("Bottom left")
        case .bottom: L("Bottom")
        case .bottomRight: L("Bottom right")
        }
    }
}

private extension Backdrop.Gradient {
    /// The gradient's ends as SwiftUI unit points, matching `Backdrop.drawGradient`.
    var direction: CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: sin(radians), y: -cos(radians))
    }

    var start: UnitPoint { UnitPoint(x: 0.5 - direction.x / 2, y: 0.5 - direction.y / 2) }
    var end: UnitPoint { UnitPoint(x: 0.5 + direction.x / 2, y: 0.5 + direction.y / 2) }
}

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

/// The editor's Background panel state. Every change applies at once; sliders fold each drag
/// into one undo step. The last settings are remembered for the next screenshot.
@MainActor
final class BackdropControls: ObservableObject {
    /// Nil for no backdrop.
    @Published private(set) var fill: Backdrop.Fill?
    @Published var padding: Double
    @Published var cornerRadius: Double
    @Published var shadow: Double
    @Published var blur: Bool
    @Published var ratio: Backdrop.Ratio
    @Published var alignment: Backdrop.Alignment
    /// The custom colour well's value, kept apart from the presets.
    @Published var customColor: NSColor
    /// The screenshot brings its own corners (a window capture), so Corners doesn't apply.
    @Published var hasOwnCorners = false
    /// The live wallpaper of the screen the capture came from, for its swatch.
    @Published var desktopThumbnail: NSImage?

    /// Called with the style to apply, and whether it continues the previous change.
    var onChange: ((Backdrop.Style?, _ continuing: Bool) -> Void)?
    private var isSliding = false
    private static let savedKey = "editor.backdrop"

    init(current: Backdrop.Style?) {
        let saved = Self.saved()
        fill = nil
        padding = saved?.padding ?? 48
        cornerRadius = saved?.cornerRadius ?? 10
        shadow = saved?.shadow ?? 0.65
        blur = saved?.blur ?? false
        ratio = saved?.ratio ?? .auto
        alignment = saved?.alignment ?? .center
        customColor = Settings.shared.windowBackgroundColor
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
                fill: $0, padding: padding, cornerRadius: cornerRadius, shadow: shadow,
                blur: blur, ratio: ratio, alignment: alignment
            )
        }
    }

    func choose(_ fill: Backdrop.Fill?) {
        self.fill = fill
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

    // MARK: Remembering

    private struct Saved: Codable {
        enum Kind: String, Codable { case wallpaper, picture, color, gradient, clear }
        var kind: Kind?
        var color: UInt?
        var gradient: [UInt]?
        var angle: CGFloat?
        var picture: String?
        var padding: Double
        var cornerRadius: Double
        var shadow: Double
        var blur: Bool
        var ratio: Backdrop.Ratio
        var alignment: Backdrop.Alignment
    }

    private func save() {
        var saved = Saved(
            padding: padding, cornerRadius: cornerRadius, shadow: shadow, blur: blur, ratio: ratio, alignment: alignment
        )
        switch fill {
        case .wallpaper: saved.kind = .wallpaper
        case let .picture(url): saved.kind = .picture; saved.picture = url.path
        case let .color(color): saved.kind = .color; saved.color = color.hexValue
        case let .gradient(gradient): saved.kind = .gradient; saved.gradient = gradient.colors; saved.angle = gradient.angle
        case .clear: saved.kind = .clear
        case nil: saved.kind = Self.saved()?.kind
        }
        if fill == nil, let previous = Self.saved() {
            saved.color = previous.color
            saved.gradient = previous.gradient
            saved.angle = previous.angle
            saved.picture = previous.picture
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

// MARK: - Panel

/// The Background panel: gradients, pictures and colours to set the screenshot on, then how it
/// sits there. Nothing here is an image file Shotput ships; gradients are drawn from colours and
/// pictures come from this Mac.
struct BackdropPicker: View {
    @ObservedObject var controls: BackdropControls
    @ObservedObject var library = BackdropLibrary.shared
    /// Opens the panel to add pictures, from the editor's window.
    var addPictures: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(SwatchMetrics.size), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)
            // The fills scroll; how the screenshot sits stays in reach below them.
            ScrollView {
                fills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            layoutControls
                .padding(16)
                .disabled(controls.fill == nil)
                .opacity(controls.fill == nil ? 0.45 : 1)
        }
        .frame(width: 6 * SwatchMetrics.size + 5 * 8 + 32)
        .onAppear { library.load() }
        .animation(.snappy(duration: 0.2), value: controls.fill?.needsPicture)
        .animation(.snappy(duration: 0.2), value: controls.ratio == .auto)
    }

    private var fills: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(L("Gradients")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(Backdrop.Gradient.presets, id: \.self) { gradient in
                        Swatch(isSelected: controls.fill == .gradient(gradient), help: L("Gradient")) {
                            controls.choose(.gradient(gradient))
                        } content: {
                            LinearGradient(colors: gradient.nsColors.map(Color.init(nsColor:)), startPoint: gradient.start, endPoint: gradient.end)
                        }
                    }
                }
            }
            section(L("Pictures")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    Swatch(isSelected: controls.fill == .wallpaper, help: L("Your desktop, as it is now")) {
                        controls.choose(.wallpaper)
                    } content: {
                        if let image = controls.desktopThumbnail {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "menubar.dock.rectangle").font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(library.user + library.system) { picture in
                        Swatch(isSelected: controls.fill == .picture(picture.url), help: picture.name) {
                            controls.choose(.picture(picture.url))
                        } content: {
                            if let image = library.thumbnail(for: picture.url), image.size != .zero {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
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
                    Button(action: addPictures) {
                        RoundedRectangle(cornerRadius: SwatchMetrics.radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .overlay(Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary))
                            .frame(width: SwatchMetrics.size, height: SwatchMetrics.size)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(L("Add pictures…"))
                    .accessibilityLabel(L("Add pictures…"))
                }
                if controls.fill?.needsPicture == true {
                    Toggle(L("Blur"), isOn: $controls.blur)
                        .onChange(of: controls.blur) { controls.apply() }
                }
            }
            section(L("Colours")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    Swatch(isSelected: controls.fill == .clear, help: L("Transparent")) {
                        controls.choose(.clear)
                    } content: {
                        Checkerboard()
                    }
                    ForEach(Backdrop.colorPresets, id: \.self) { hex in
                        Swatch(isSelected: isColor(hex), help: L("Colour")) {
                            controls.choose(.color(NSColor(hex: hex)))
                        } content: {
                            Color(nsColor: NSColor(hex: hex))
                        }
                    }
                    ColorPicker(L("Custom colour"), selection: Binding(
                        get: { Color(nsColor: controls.customColor) },
                        set: {
                            controls.customColor = NSColor($0)
                            controls.choose(.color(controls.customColor))
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: SwatchMetrics.size, height: SwatchMetrics.size)
                    .help(L("Custom colour"))
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("Background")).font(.headline)
            Spacer()
            Button(L("None")) { controls.choose(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(controls.fill == nil)
        }
    }

    private func isColor(_ hex: UInt) -> Bool {
        if case let .color(color) = controls.fill { return color.hexValue == hex }
        return false
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider(L("Padding"), value: $controls.padding, in: 0 ... 200, step: 2, label: "\(Int(controls.padding)) pt")
            slider(L("Corners"), value: $controls.cornerRadius, in: 0 ... 40, step: 1, label: "\(Int(controls.cornerRadius)) pt")
                .disabled(controls.hasOwnCorners)
            if controls.hasOwnCorners {
                Text(L("Window captures keep their own corners."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            slider(L("Shadow"), value: $controls.shadow, in: 0 ... 1, step: 0.05, label: "\(Int((controls.shadow * 100).rounded()))%")

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Ratio"))
                    Picker(L("Ratio"), selection: $controls.ratio) {
                        ForEach(Backdrop.Ratio.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: controls.ratio) { controls.apply() }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Position"))
                    AlignmentGrid(selection: $controls.alignment) { controls.apply() }
                        .disabled(controls.ratio == .auto)
                        .opacity(controls.ratio == .auto ? 0.45 : 1)
                        .help(controls.ratio == .auto ? L("Pick a ratio to move the screenshot within it") : L("Where the screenshot sits"))
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 62, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in
                if !editing { controls.endSlide() }
            }
            .controlSize(.small)
            .onChange(of: value.wrappedValue) { controls.sliding() }
            Text(label)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// One choice in a grid: what it fills with, inside a rounded square, ringed when chosen.
private enum SwatchMetrics {
    static let size: CGFloat = 36
    static let radius: CGFloat = 9
}

private struct Swatch<Content: View>: View {
    private typealias Metrics = SwatchMetrics

    let isSelected: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        Button(action: action) {
            content
                .frame(width: Metrics.size, height: Metrics.size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .padding(isSelected ? 3 : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius + 3, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                )
                .frame(width: Metrics.size, height: Metrics.size)
                .scaleEffect(isHovered && !isSelected ? 1.06 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The transparent choice, drawn as the usual grey and white checks.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0 ..< Int(ceil(size.height / cell)) {
                for column in 0 ..< Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color(white: 0.82)))
                }
            }
        }
    }
}

/// Nine positions for the screenshot within a fixed ratio.
private struct AlignmentGrid: View {
    @Binding var selection: Backdrop.Alignment
    let changed: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0 ..< 3) { row in
                GridRow {
                    ForEach(0 ..< 3) { column in
                        let alignment = Backdrop.Alignment(rawValue: row * 3 + column) ?? .center
                        Button {
                            selection = alignment
                            changed()
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selection == alignment ? Color.accentColor : Color.primary.opacity(0.1))
                                .frame(width: 18, height: 14)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(alignment.title)
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

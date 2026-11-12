import AppKit
import Combine
import SwiftUI

/// Shotput lives in the menu bar. While an editor or the settings window is open it joins the
/// Dock and the app switcher, so those windows are easy to get back to.
final class AppPresence {
    static let shared = AppPresence()
    private var openWindows = 0

    func windowDidOpen() {
        openWindows += 1
        if openWindows == 1 { NSApp.setActivationPolicy(.regular) }
    }

    func windowDidClose() {
        openWindows = max(0, openWindows - 1)
        DispatchQueue.main.async { [self] in
            if openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var subscriptions = Set<AnyCancellable>()
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Output.purgeTemporaryFiles()
        NSApp.mainMenu = MainMenu.build()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Icon.capture.plain(label: "Shotput")
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        // Left click opens the pinned tray; right click, or Control-click, the menu.
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Shotput: click for pins, right-click for captures and settings"
        statusItem = item
        Settings.shared.$showsMenuBarIcon
            .sink { [weak item] visible in item?.isVisible = visible }
            .store(in: &subscriptions)
        // Covers every path that changes shortcuts, including Reset, wherever it happens.
        Settings.shared.$shortcuts
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in HotKeyCenter.reload() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .shotputDidCapture)
            .merge(with: NotificationCenter.default.publisher(for: .shotputDidPin))
            .sink { [weak self] _ in self?.pulseMenuBarIcon() }
            .store(in: &subscriptions)
        MenuBarAnchor.frame = { [weak item] in
            guard let button = item?.button, let window = button.window, item?.isVisible == true else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }

        HotKeyCenter.reload()
        Updates.shared.start()
        if Settings.shared.screenshotFolder != nil { MacScreenshotWatcher.shared.start() }

        if Settings.shared.consumeFirstLaunch() {
            OnboardingProgress.reset()
            OnboardingProgress.isFirstRun = true
            showOnboarding(.welcome)
        } else if let step = OnboardingProgress.unfinishedStep {
            OnboardingProgress.isFirstRun = true
            // Reopened before the guide was finished, usually after macOS quit Shotput to apply
            // Screen Recording.
            showOnboarding(step)
        }
    }

    /// The menu bar icon blinks like a shutter on each capture. It is the only feedback when
    /// Settings says to copy quietly.
    private func pulseMenuBarIcon() {
        guard let button = statusItem?.button, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        button.alphaValue = 0.25
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 1
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSettings(nil) }
        return true
    }

    // MARK: Opening files and links

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                CaptureCoordinator.shared.open(file: url)
            } else if url.scheme == "shotput" {
                handle(command: url.host ?? "")
            }
        }
    }

    /// `shotput://` links let launchers and Logi Options+ Smart Actions start a capture. Only
    /// commands that put interactive UI on screen are exposed. A silent full-screen capture is
    /// not, because any app can open a link and could use that to read the screen.
    private func handle(command: String) {
        guard Settings.shared.allowsLinks || command == "settings" else { return }
        switch command {
        case "area": HotAction.area.perform()
        case "annotate": HotAction.areaAnnotate.perform()
        case "window": HotAction.window.perform()
        case "last": HotAction.annotateLast.perform()
        case "text": HotAction.text.perform()
        case "clipboard": HotAction.annotateClipboard.perform()
        case "settings": showSettings(nil)
        default: break
        }
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcuts = Settings.shared.shortcuts


        func add(_ action: HotAction, _ selector: Selector) {
            let item = menu.addItem(withTitle: action.title, action: selector, keyEquivalent: "")
            item.target = self
            item.image = action.icon.plain()
            if let shortcut = shortcuts[action], shortcut.isSet, shortcut.keyName.count == 1 {
                item.keyEquivalent = shortcut.keyName.lowercased()
                item.keyEquivalentModifierMask = shortcut.flags
            }
        }

        add(.area, #selector(captureArea))
        add(.areaAnnotate, #selector(captureAreaAndAnnotate))
        add(.window, #selector(captureWindow))
        add(.screen, #selector(captureScreen))
        add(.repeatArea, #selector(repeatArea))
        add(.text, #selector(copyText))
        menu.addItem(.separator())
        add(.annotateLast, #selector(annotateLast))
        add(.annotateClipboard, #selector(annotateClipboard))
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        settings.image = Icon.settings.plain()
        let updates = menu.addItem(withTitle: "Check for Updates…", action: #selector(Updates.checkNow), keyEquivalent: "")
        updates.target = Updates.shared
        menu.addItem(withTitle: "Quit Shotput", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            PinTray.shared.close()
            showStatusMenu()
        } else {
            PinTray.shared.toggle(from: sender)
        }
    }

    private func showStatusMenu() {
        guard let statusItem, let statusMenu else { return }
        // Attached only while it shows, so a left click stays free for the tray.
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(annotateLast) { return CaptureCoordinator.shared.lastCapture != nil }
        if item.action == #selector(annotateClipboard) { return NSPasteboard.general.canReadObject(forClasses: [NSImage.self]) }
        return true
    }

    @objc private func captureArea() { HotAction.area.perform() }
    @objc private func captureAreaAndAnnotate() { HotAction.areaAnnotate.perform() }
    @objc private func captureWindow() { HotAction.window.perform() }
    @objc private func captureScreen() { HotAction.screen.perform() }
    @objc private func annotateLast() { HotAction.annotateLast.perform() }
    @objc private func repeatArea() { HotAction.repeatArea.perform() }
    @objc private func copyText() { HotAction.text.perform() }
    @objc private func annotateClipboard() { CaptureCoordinator.shared.annotateClipboard() }

    // MARK: Settings and the welcome guide

    @objc func showSettings(_ sender: Any?) {
        showSettings(pane: nil)
    }

    func showSettings(pane: SettingsWindowController.Pane?) {
        let controller = settingsController ?? {
            let controller = SettingsWindowController()
            controller.window?.delegate = self
            settingsController = controller
            return controller
        }()
        if let pane { controller.select(pane) }
        if controller.window?.isVisible == false { AppPresence.shared.windowDidOpen() }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding(_ step: OnboardingWindowController.Step) {
        let controller = onboarding ?? {
            let controller = OnboardingWindowController(start: step)
            controller.onClose = { [weak self] in
                DispatchQueue.main.async { self?.onboarding = nil }
            }
            onboarding = controller
            return controller
        }()
        controller.show(step)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsController?.window { AppPresence.shared.windowDidClose() }
    }
}

@MainActor
enum MainMenu {
    /// Shown while a Shotput window is open. Items with no target travel the responder chain, which
    /// is how ⌘C reaches the editor and text fields alike.
    static func build() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            build(menu)
            item.submenu = menu
            main.addItem(item)
        }

        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ flags: NSEvent.ModifierFlags = .command) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key).keyEquivalentModifierMask = flags
        }

        submenu("Shotput") { menu in
            item(menu, "About Shotput", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "")
            menu.addItem(.separator())
            item(menu, "Settings…", #selector(AppDelegate.showSettings(_:)), ",")
            menu.addItem(withTitle: "Check for Updates…", action: #selector(Updates.checkNow), keyEquivalent: "").target = Updates.shared
            menu.addItem(.separator())
            item(menu, "Hide Shotput", #selector(NSApplication.hide(_:)), "h")
            item(menu, "Quit Shotput", #selector(NSApplication.terminate(_:)), "q")
        }
        submenu("File") { menu in
            item(menu, "Save…", #selector(EditorWindowController.saveDocument(_:)), "s")
            item(menu, "Close", #selector(NSWindow.performClose(_:)), "w")
        }
        submenu("Edit") { menu in
            item(menu, "Undo", #selector(CanvasView.undo(_:)), "z")
            item(menu, "Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift])
            menu.addItem(.separator())
            item(menu, "Cut", #selector(NSText.cut(_:)), "x")
            item(menu, "Copy", #selector(NSText.copy(_:)), "c")
            item(menu, "Paste", #selector(NSText.paste(_:)), "v")
            item(menu, "Delete", #selector(NSText.delete(_:)), "")
            item(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        }
        submenu("View") { menu in
            item(menu, "Zoom In", #selector(EditorWindowController.zoomImageIn(_:)), "+")
            item(menu, "Zoom Out", #selector(EditorWindowController.zoomImageOut(_:)), "-")
            item(menu, "Actual Size", #selector(EditorWindowController.zoomImageToActualSize(_:)), "0")
            item(menu, "Zoom to Fit", #selector(EditorWindowController.zoomImageToFit(_:)), "9")
        }
        submenu("Window") { menu in
            item(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            NSApp.windowsMenu = menu
        }
        return main
    }
}

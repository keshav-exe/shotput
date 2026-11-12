import AppKit
import Combine
import Sparkle

/// Updates through Sparkle. Every update is checked against the public key in Info.plist before
/// it is installed, and the download happens in Sparkle's own service, so Shotput stays offline.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    @Published private(set) var canCheck = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }

    private var updater: SPUUpdater { controller.updater }

    /// Starts the updater. A development build from `swift run` has no bundle to update, so it
    /// stays off there.
    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            try updater.start()
        } catch {
            // Usually a bad feed URL or public key in Info.plist. Check for Updates stays disabled.
            NSLog("Shotput: updates are off: %@", error.localizedDescription)
            return
        }
        canCheck = updater.canCheckForUpdates
        observations = [updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheck = value }
        }]
    }

    /// Checking and installing on their own, as one choice: an update that is found is also
    /// downloaded, and goes in the next time Shotput quits.
    var isAutomatic: Bool {
        get { updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    @objc func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

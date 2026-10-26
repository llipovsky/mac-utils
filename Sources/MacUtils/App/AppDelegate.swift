import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences.shared
    lazy var awake = AwakeController(prefs: prefs)
    lazy var jiggler = Jiggler(prefs: prefs)
    let updater = Updater.shared

    private var statusMenu: StatusMenuController?
    private lazy var settingsWindow = SettingsWindowController(app: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateOtherInstance() {
            NSApp.terminate(nil)
            return
        }

        ScriptLibrary.shared.installExampleIfNeeded()
        statusMenu = StatusMenuController(app: self)
        awake.onStop = { [weak self] in
            if self?.jiggler.isRunning == false { UserActivity.end() }
        }
        jiggler.onStop = { [weak self] in
            if self?.awake.isActive == false { UserActivity.end() }
        }

        if prefs.activateOnLaunch && !awake.isActive {
            awake.start(minutes: prefs.defaultDurationMinutes)
        }
        if prefs.jiggleOnLaunch && !jiggler.isRunning {
            jiggler.start()
        }
        if !prefs.askedForAccessibility && !Permissions.accessibilityGranted {
            prefs.askedForAccessibility = true
            Permissions.requestAccessibility()
        }
        updater.startAutomaticChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        jiggler.stop()
        awake.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            URLCommands.handle(url, app: self)
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// Only one copy per user session; a second launch just hands over to the first.
    private func activateOtherInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != NSRunningApplication.current }
        return !others.isEmpty
    }
}

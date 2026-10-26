import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController {
    private unowned let app: AppDelegate
    private var window: NSWindow?
    private let model = SettingsModel()

    init(app: AppDelegate) {
        self.app = app
    }

    func show() {
        if window == nil {
            let view = SettingsView(prefs: app.prefs, jiggler: app.jiggler, updater: app.updater, model: model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "MacUtils Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// View state that isn't a preference. (A class instead of @State, which the Command Line
/// Tools SDK can't expand.)
@MainActor
final class SettingsModel: ObservableObject {
    @Published var accessibilityGranted = Permissions.accessibilityGranted
    @Published var patterns = ScriptLibrary.shared.allPatterns()
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var loginError: String?

    func refresh() {
        accessibilityGranted = Permissions.accessibilityGranted
        patterns = ScriptLibrary.shared.allPatterns()
        launchAtLogin = LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var jiggler: Jiggler
    @ObservedObject var updater: Updater
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            KeepAwakeSettings(prefs: prefs)
                .tabItem { Label("Keep Awake", systemImage: "cup.and.saucer") }
            JigglerSettings(prefs: prefs, jiggler: jiggler, model: model)
                .tabItem { Label("Jiggler", systemImage: "cursorarrow.motionlines") }
            GeneralSettings(prefs: prefs, updater: updater, model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(20)
        .frame(width: 540)
    }
}

private struct KeepAwakeSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Picker("Default session length", selection: $prefs.defaultDurationMinutes) {
                ForEach(Choices.durations, id: \.self) { Text(Choices.durationLabel($0)).tag($0) }
            }
            Toggle("Start a session when MacUtils launches", isOn: $prefs.activateOnLaunch)
            Toggle("Allow the display to sleep (keep only the Mac awake)", isOn: $prefs.allowDisplaySleep)
            Toggle("Stay shown as Active in chat apps (resets the idle timer)", isOn: $prefs.stayActive)
                .disabled(prefs.allowDisplaySleep)
            Toggle("Show remaining time in the menu bar", isOn: $prefs.showRemainingTime)
            HStack {
                Toggle("Stop when the battery drops to", isOn: $prefs.stopOnLowBattery)
                Stepper("\(prefs.lowBatteryThreshold)%", value: $prefs.lowBatteryThreshold, in: 5...90, step: 5)
                    .disabled(!prefs.stopOnLowBattery)
            }
            Text("Closing the lid still sleeps a laptop unless it's on power with an external display connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct JigglerSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var jiggler: Jiggler
    @ObservedObject var model: SettingsModel
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Toggle("Jiggle the mouse", isOn: Binding(get: { jiggler.isRunning }, set: { $0 ? jiggler.start() : jiggler.stop() }))
            Toggle("Start jiggling when MacUtils launches", isOn: $prefs.jiggleOnLaunch)
            Picker("Pattern", selection: $prefs.jigglePattern) {
                ForEach(model.patterns.filter { $0.error == nil }) { Text($0.name).tag($0.id) }
            }
            Picker("Every", selection: $prefs.jiggleInterval) {
                ForEach(Choices.jiggleIntervals, id: \.self) { Text(Choices.intervalLabel($0)).tag($0) }
            }
            Toggle("Vary the interval a little (±30%)", isOn: $prefs.jiggleRandomize)
            Toggle("Skip while I'm using the Mac", isOn: $prefs.jigglePauseWhenActive)
            HStack {
                Button("Run Pattern Now") { jiggler.runOnce() }
                Button("Open Scripts Folder") { ScriptLibrary.shared.revealFolder() }
                Button("Reload Scripts") { model.patterns = ScriptLibrary.shared.allPatterns() }
            }

            ForEach(model.patterns.filter { $0.error != nil }) { pattern in
                Label("\(pattern.name): \(pattern.error ?? "")", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Section("Accessibility") {
                if model.accessibilityGranted {
                    Label("Granted — the jiggler sends real mouse events.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not granted — the cursor still moves and the idle timer is reset, but some apps may not count it as activity.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Request Access") { Permissions.requestAccessibility() }
                        Button("Open Privacy Settings") { Permissions.openAccessibilitySettings() }
                    }
                    Text("Turning it on needs an admin password once; after that it works for every user on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(poll) { _ in model.accessibilityGranted = Permissions.accessibilityGranted }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: Updater
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Toggle("Open MacUtils at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            .disabled(!AppInfo.isBundled)
            if let loginError = model.loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $prefs.autoCheckUpdates)
                Toggle("Install updates automatically", isOn: $prefs.autoInstallUpdates)
                    .disabled(!prefs.autoCheckUpdates)
                HStack {
                    Button("Check Now") { Task { await updater.checkAndOfferInstall() } }
                        .disabled(!updater.isSupported || updater.isBusy)
                    Text(updateStatus).foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("Signature", value: CodeSignature.runningSignatureDescription)
                if let repository = AppInfo.repository, let url = URL(string: "https://github.com/\(repository)") {
                    LabeledContent("Source") { Link(repository, destination: url) }
                }
                LabeledContent("Installed at", value: Bundle.main.bundlePath)
            }
        }
    }

    private var updateStatus: String {
        switch updater.state {
        case .idle:
            if let last = prefs.lastUpdateCheck { return "Last checked \(last.formatted(.relative(presentation: .named)))" }
            return ""
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .available(let version): return "\(version) available"
        case .downloading: return "Downloading…"
        case .installing: return "Installing…"
        case .failed(let message): return message
        }
    }
}

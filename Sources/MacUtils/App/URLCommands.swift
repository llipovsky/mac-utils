import Foundation

/// Lets MacUtils be driven from Terminal or Shortcuts, e.g.
///   open -g "macutils://awake?minutes=90"
///   open -g "macutils://jiggle?state=on&pattern=circle&interval=30"
@MainActor
enum URLCommands {
    static func handle(_ url: URL, app: AppDelegate) {
        guard url.scheme?.lowercased() == "macutils" else { return }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
        // Accept both macutils://awake and macutils:awake.
        let command = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        switch command {
        case "awake", "start":
            if let minutes = query["minutes"].flatMap(Int.init) {
                app.awake.start(minutes: minutes)
            } else if let hours = query["hours"].flatMap(Double.init) {
                app.awake.start(minutes: Int(hours * 60))
            } else {
                app.awake.start(minutes: app.prefs.defaultDurationMinutes)
            }
        case "stop":
            app.awake.stop()
        case "toggle":
            app.awake.isActive ? app.awake.stop() : app.awake.start(minutes: app.prefs.defaultDurationMinutes)
        case "jiggle":
            if let pattern = query["pattern"], ScriptLibrary.shared.pattern(id: pattern) != nil {
                app.prefs.jigglePattern = pattern
            }
            if let interval = query["interval"].flatMap(Double.init), interval >= 5 {
                app.prefs.jiggleInterval = interval
            }
            switch query["state"]?.lowercased() {
            case "off", "0", "false": app.jiggler.stop()
            case "toggle": app.jiggler.toggle()
            case "once": app.jiggler.runOnce()
            default: app.jiggler.start()
            }
        case "settings":
            app.showSettings()
        case "status":
            writeStatus(app)
        case "update":
            if let zip = query["zip"], !zip.isEmpty {
                let url = URL(fileURLWithPath: (zip as NSString).expandingTildeInPath)
                Task { await app.updater.install(zipAt: url, interactive: false) }
            } else {
                Task { await app.updater.checkAndOfferInstall() }
            }
        default:
            NSLog("MacUtils: unknown URL command \(url.absoluteString)")
        }
    }

    /// Writes ~/Library/Application Support/MacUtils/status.json, for scripts and debugging.
    private static func writeStatus(_ app: AppDelegate) {
        var status: [String: Any] = [
            "version": AppInfo.version,
            "build": AppInfo.build,
            "path": Bundle.main.bundlePath,
            "awake": app.awake.isActive,
            "jiggling": app.jiggler.isRunning,
            "pattern": app.prefs.jigglePattern,
            "interval": app.prefs.jiggleInterval,
            "accessibility": Permissions.accessibilityGranted,
            "signature": CodeSignature.runningSignatureDescription,
            "updateState": String(describing: app.updater.state),
        ]
        if let remaining = app.awake.remaining { status["remainingSeconds"] = Int(remaining) }
        if let lastRun = app.jiggler.lastRun { status["lastJiggle"] = ISO8601DateFormatter().string(from: lastRun) }

        let url = AppInfo.supportDirectory.appendingPathComponent("status.json")
        try? FileManager.default.createDirectory(at: AppInfo.supportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

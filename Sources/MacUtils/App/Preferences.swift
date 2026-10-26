import Foundation

/// Per-user settings, stored in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // Keep awake
    @Published var allowDisplaySleep: Bool { didSet { defaults.set(allowDisplaySleep, forKey: Key.allowDisplaySleep) } }
    @Published var stayActive: Bool { didSet { defaults.set(stayActive, forKey: Key.stayActive) } }
    @Published var activateOnLaunch: Bool { didSet { defaults.set(activateOnLaunch, forKey: Key.activateOnLaunch) } }
    @Published var defaultDurationMinutes: Int { didSet { defaults.set(defaultDurationMinutes, forKey: Key.defaultDurationMinutes) } }
    @Published var showRemainingTime: Bool { didSet { defaults.set(showRemainingTime, forKey: Key.showRemainingTime) } }
    @Published var stopOnLowBattery: Bool { didSet { defaults.set(stopOnLowBattery, forKey: Key.stopOnLowBattery) } }
    @Published var lowBatteryThreshold: Int { didSet { defaults.set(lowBatteryThreshold, forKey: Key.lowBatteryThreshold) } }

    // Jiggler
    @Published var jigglePattern: String { didSet { defaults.set(jigglePattern, forKey: Key.jigglePattern) } }
    @Published var jiggleInterval: Double { didSet { defaults.set(jiggleInterval, forKey: Key.jiggleInterval) } }
    @Published var jiggleRandomize: Bool { didSet { defaults.set(jiggleRandomize, forKey: Key.jiggleRandomize) } }
    @Published var jigglePauseWhenActive: Bool { didSet { defaults.set(jigglePauseWhenActive, forKey: Key.jigglePauseWhenActive) } }
    @Published var jiggleOnLaunch: Bool { didSet { defaults.set(jiggleOnLaunch, forKey: Key.jiggleOnLaunch) } }

    // Updates
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) } }
    @Published var autoInstallUpdates: Bool { didSet { defaults.set(autoInstallUpdates, forKey: Key.autoInstallUpdates) } }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    var askedForAccessibility: Bool {
        get { defaults.bool(forKey: Key.askedForAccessibility) }
        set { defaults.set(newValue, forKey: Key.askedForAccessibility) }
    }

    private enum Key {
        static let allowDisplaySleep = "allowDisplaySleep"
        static let stayActive = "stayActive"
        static let activateOnLaunch = "activateOnLaunch"
        static let defaultDurationMinutes = "defaultDurationMinutes"
        static let showRemainingTime = "showRemainingTime"
        static let stopOnLowBattery = "stopOnLowBattery"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let jigglePattern = "jigglePattern"
        static let jiggleInterval = "jiggleInterval"
        static let jiggleRandomize = "jiggleRandomize"
        static let jigglePauseWhenActive = "jigglePauseWhenActive"
        static let jiggleOnLaunch = "jiggleOnLaunch"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let autoInstallUpdates = "autoInstallUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let askedForAccessibility = "askedForAccessibility"
    }

    private init() {
        defaults.register(defaults: [
            Key.allowDisplaySleep: false,
            Key.stayActive: true,
            Key.activateOnLaunch: false,
            Key.defaultDurationMinutes: 0,
            Key.showRemainingTime: true,
            Key.stopOnLowBattery: true,
            Key.lowBatteryThreshold: 10,
            Key.jigglePattern: "subtle",
            Key.jiggleInterval: 60.0,
            Key.jiggleRandomize: true,
            Key.jigglePauseWhenActive: true,
            Key.jiggleOnLaunch: false,
            Key.autoCheckUpdates: true,
            Key.autoInstallUpdates: false,
        ])
        allowDisplaySleep = defaults.bool(forKey: Key.allowDisplaySleep)
        stayActive = defaults.bool(forKey: Key.stayActive)
        activateOnLaunch = defaults.bool(forKey: Key.activateOnLaunch)
        defaultDurationMinutes = defaults.integer(forKey: Key.defaultDurationMinutes)
        showRemainingTime = defaults.bool(forKey: Key.showRemainingTime)
        stopOnLowBattery = defaults.bool(forKey: Key.stopOnLowBattery)
        lowBatteryThreshold = defaults.integer(forKey: Key.lowBatteryThreshold)
        jigglePattern = defaults.string(forKey: Key.jigglePattern) ?? "subtle"
        jiggleInterval = defaults.double(forKey: Key.jiggleInterval)
        jiggleRandomize = defaults.bool(forKey: Key.jiggleRandomize)
        jigglePauseWhenActive = defaults.bool(forKey: Key.jigglePauseWhenActive)
        jiggleOnLaunch = defaults.bool(forKey: Key.jiggleOnLaunch)
        autoCheckUpdates = defaults.bool(forKey: Key.autoCheckUpdates)
        autoInstallUpdates = defaults.bool(forKey: Key.autoInstallUpdates)
    }
}

/// Choices offered in menus and settings.
enum Choices {
    /// Session lengths in minutes; 0 means indefinitely.
    static let durations = [0, 5, 15, 30, 60, 120, 180, 240, 360, 480, 720]
    static let extensions = [15, 30, 60, 120]
    static let jiggleIntervals: [Double] = [10, 30, 60, 120, 180, 300, 600]

    static func durationLabel(_ minutes: Int) -> String {
        if minutes <= 0 { return "Indefinitely" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    static func intervalLabel(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) seconds" }
        return s == 60 ? "1 minute" : "\(s / 60) minutes"
    }

    static func remainingLabel(_ interval: TimeInterval, compact: Bool) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if compact {
            return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d", m, s)
        }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

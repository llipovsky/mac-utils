import Combine
import Foundation

/// Keep-awake sessions: indefinite or timed, with display / activity options.
@MainActor
final class AwakeController: ObservableObject {
    enum Session: Equatable {
        case off
        case indefinite
        case until(Date)
    }

    @Published private(set) var session: Session = .off
    @Published private(set) var lastStopReason: String?

    private let prefs: Preferences
    private let systemSleep = PowerAssertion(type: PowerAssertion.preventSystemSleep, name: "MacUtils keep-awake session")
    private let displaySleep = PowerAssertion(type: PowerAssertion.preventDisplaySleep, name: "MacUtils keep-awake session (display)")
    private var timer: Timer?
    private var lastActivityPing = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    /// Called after a session ends (the app uses it to drop the activity assertion).
    var onStop: (() -> Void)?

    init(prefs: Preferences) {
        self.prefs = prefs
        prefs.$allowDisplaySleep
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAssertions() }
            .store(in: &cancellables)
    }

    var isActive: Bool { session != .off }

    var endDate: Date? {
        if case .until(let date) = session { return date }
        return nil
    }

    var remaining: TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSinceNow) }
    }

    /// minutes <= 0 starts an indefinite session.
    func start(minutes: Int) {
        start(until: minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil)
    }

    func start(until date: Date?) {
        session = date.map(Session.until) ?? .indefinite
        lastStopReason = nil
        applyAssertions()
        lastActivityPing = .distantPast
        tick()
        timer?.invalidate()
        timer = .commonModes(interval: 1) { [weak self] in self?.tick() }
    }

    func extend(minutes: Int) {
        switch session {
        case .off: start(minutes: minutes)
        case .indefinite: break
        case .until(let date): session = .until(max(date, Date()).addingTimeInterval(TimeInterval(minutes * 60)))
        }
    }

    func stop(reason: String? = nil) {
        timer?.invalidate()
        timer = nil
        session = .off
        lastStopReason = reason
        applyAssertions()
        onStop?()
    }

    private func applyAssertions() {
        if isActive {
            systemSleep.acquire()
            prefs.allowDisplaySleep ? displaySleep.release() : displaySleep.acquire()
        } else {
            systemSleep.release()
            displaySleep.release()
        }
    }

    private func tick() {
        if let end = endDate, end <= Date() {
            stop(reason: "Session ended")
            return
        }
        if prefs.stopOnLowBattery, let battery = Battery.read(), !battery.onACPower, battery.percent <= prefs.lowBatteryThreshold {
            stop(reason: "Battery at \(battery.percent)%")
            return
        }
        // Declaring activity also wakes the display, so it only makes sense when the display stays on.
        if prefs.stayActive && !prefs.allowDisplaySleep && Date().timeIntervalSince(lastActivityPing) >= 30 {
            UserActivity.declare()
            lastActivityPing = Date()
        }
        objectWillChange.send()
    }
}

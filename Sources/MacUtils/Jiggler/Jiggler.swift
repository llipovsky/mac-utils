import Combine
import Foundation

/// Runs the selected pattern every interval, skipping turns while a person is using the Mac.
@MainActor
final class Jiggler: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastRun: Date?

    private let prefs: Preferences
    private var loop: Task<Void, Never>?
    private var current: Task<JiggleRunner.Outcome, Never>?
    /// When and where the last turn left the cursor, to tell our movement from a person's.
    private var lastTurn = Date()
    private var restingPoint: CGPoint?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences) {
        self.prefs = prefs
        prefs.$jiggleInterval
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.scheduleLoop()
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        markTurn()
        scheduleLoop()
    }

    func stop() {
        isRunning = false
        loop?.cancel()
        loop = nil
        current?.cancel()
        onStop?()
    }

    /// Called after jiggling stops (the app uses it to drop the activity assertion).
    var onStop: (() -> Void)?

    func toggle() {
        isRunning ? stop() : start()
    }

    /// Runs the pattern right away, e.g. to preview it.
    func runOnce() {
        Task { await runPattern() }
    }

    private func scheduleLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextDelay() else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                await self.turn()
            }
        }
    }

    private func nextDelay() -> Double {
        let base = max(5, prefs.jiggleInterval)
        return prefs.jiggleRandomize ? base * Double.random(in: 0.7...1.3) : base
    }

    private func turn() async {
        if prefs.jigglePauseWhenActive && personWasActive() {
            markTurn()
            return
        }
        await runPattern()
    }

    private func personWasActive() -> Bool {
        let sinceLastTurn = Date().timeIntervalSince(lastTurn)
        if MouseDriver.secondsSinceHumanInput < sinceLastTurn { return true }
        if let restingPoint, MouseDriver.location.distance(to: restingPoint) > 2 { return true }
        return false
    }

    private func runPattern() async {
        guard current == nil else { return }
        let pattern = ScriptLibrary.shared.pattern(id: prefs.jigglePattern) ?? ScriptLibrary.builtins[1]
        if !pattern.steps.isEmpty {
            let steps = pattern.steps
            let postEvents = Permissions.accessibilityGranted
            let task = Task.detached(priority: .userInitiated) {
                await JiggleRunner.run(steps, postEvents: postEvents)
            }
            current = task
            _ = await task.value
            current = nil
        }
        UserActivity.declare()
        lastRun = Date()
        markTurn()
    }

    private func markTurn() {
        lastTurn = Date()
        restingPoint = MouseDriver.location
    }
}

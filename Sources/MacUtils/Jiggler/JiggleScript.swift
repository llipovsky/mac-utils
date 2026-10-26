import CoreGraphics
import Foundation

// A tiny line-based language for mouse movement patterns. See ScriptLibrary.exampleScript
// for the reference that's copied into the user's Scripts folder.

indirect enum JiggleStep: Equatable {
    case move(dx: Double, dy: Double, duration: Double)
    case moveTo(x: Coordinate, y: Coordinate, duration: Double)
    case circle(radius: Double, duration: Double)
    case random(radius: Double, duration: Double)
    case back(duration: Double)
    case wait(min: Double, max: Double)
    case scroll(lines: Int32)
    case repeatBlock(count: Int, body: [JiggleStep])
}

enum Coordinate: Equatable {
    case points(Double)
    case percent(Double)

    func resolve(origin: CGFloat, length: CGFloat) -> CGFloat {
        switch self {
        case .points(let value): return origin + value
        case .percent(let value): return origin + length * value / 100
        }
    }
}

struct JiggleScriptError: LocalizedError {
    let line: Int
    let message: String
    var errorDescription: String? { "Line \(line): \(message)" }
}

enum JiggleScriptParser {
    static let defaultDuration = 0.25
    static let maxDuration = 30.0
    static let maxWait = 300.0
    static let maxDistance = 5000.0
    static let maxRepeat = 1000

    static func parse(_ source: String) throws -> [JiggleStep] {
        // Each open block: the repeat count, the line it started on and the steps collected so far.
        var stack: [(count: Int, line: Int, steps: [JiggleStep])] = [(1, 0, [])]

        for (index, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let code = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            var words = code.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            let command = words.removeFirst()

            func fail(_ message: String) -> JiggleScriptError {
                JiggleScriptError(line: lineNumber, message: message)
            }
            func expectArguments(_ count: Int, _ usage: String) throws {
                if words.count != count { throw fail("expected `\(usage)`") }
            }
            func number(_ word: String, _ what: String) throws -> Double {
                guard let value = Double(word), value.isFinite else { throw fail("\(what) must be a number, got `\(word)`") }
                return value
            }
            func seconds(_ word: String) throws -> Double {
                let trimmed = word.hasSuffix("s") ? String(word.dropLast()) : word
                guard let value = Double(trimmed), value >= 0 else { throw fail("`\(word)` is not a duration in seconds") }
                return value
            }
            func distance(_ word: String, _ what: String) throws -> Double {
                let value = try number(word, what)
                guard abs(value) <= maxDistance else { throw fail("\(what) must be within ±\(Int(maxDistance))") }
                return value
            }
            func coordinate(_ word: String) throws -> Coordinate {
                if word.hasSuffix("%") {
                    let value = try number(String(word.dropLast()), "percentage")
                    guard (0...100).contains(value) else { throw fail("percentages must be 0–100%") }
                    return .percent(value)
                }
                return .points(try distance(word, "coordinate"))
            }

            // Optional trailing "over SECONDS" for movement commands.
            var duration = defaultDuration
            if let overIndex = words.firstIndex(of: "over") {
                guard overIndex == words.count - 2 else { throw fail("`over SECONDS` must come last") }
                duration = try seconds(words[overIndex + 1])
                guard duration <= maxDuration else { throw fail("movements can take at most \(Int(maxDuration)) seconds") }
                words.removeSubrange(overIndex...)
                guard ["move", "moveto", "circle", "random", "back"].contains(command) else {
                    throw fail("`over` only works with movement commands")
                }
            }

            let step: JiggleStep
            switch command {
            case "move":
                try expectArguments(2, "move DX DY [over SECONDS]")
                step = .move(dx: try distance(words[0], "DX"), dy: try distance(words[1], "DY"), duration: duration)
            case "moveto":
                try expectArguments(2, "moveto X Y [over SECONDS]")
                step = .moveTo(x: try coordinate(words[0]), y: try coordinate(words[1]), duration: duration)
            case "circle":
                try expectArguments(1, "circle RADIUS [over SECONDS]")
                step = .circle(radius: abs(try distance(words[0], "RADIUS")), duration: duration)
            case "random":
                try expectArguments(1, "random RADIUS [over SECONDS]")
                step = .random(radius: abs(try distance(words[0], "RADIUS")), duration: duration)
            case "back":
                try expectArguments(0, "back [over SECONDS]")
                step = .back(duration: duration)
            case "wait":
                try expectArguments(1, "wait SECONDS  or  wait MIN-MAX")
                let range = words[0].split(separator: "-", maxSplits: 1).map(String.init)
                let low = try seconds(range[0])
                let high = range.count == 2 ? try seconds(range[1]) : low
                guard low <= high, high <= maxWait else { throw fail("wait must be between 0 and \(Int(maxWait)) seconds, MIN ≤ MAX") }
                step = .wait(min: low, max: high)
            case "scroll":
                try expectArguments(1, "scroll LINES")
                guard let lines = Int32(words[0]), abs(lines) <= 50 else { throw fail("LINES must be a whole number between -50 and 50") }
                step = .scroll(lines: lines)
            case "repeat":
                try expectArguments(1, "repeat COUNT")
                guard let count = Int(words[0]), (1...maxRepeat).contains(count) else { throw fail("COUNT must be 1–\(maxRepeat)") }
                stack.append((count, lineNumber, []))
                continue
            case "end":
                try expectArguments(0, "end")
                guard stack.count > 1 else { throw fail("`end` without a matching `repeat`") }
                let block = stack.removeLast()
                step = .repeatBlock(count: block.count, body: block.steps)
            default:
                throw fail("unknown command `\(command)`")
            }
            stack[stack.count - 1].steps.append(step)
        }

        if stack.count > 1 {
            throw JiggleScriptError(line: stack.last!.line, message: "`repeat` is missing its `end`")
        }
        return stack[0].steps
    }
}

/// Executes parsed steps. Stops early if the person grabs the mouse.
enum JiggleRunner {
    enum Outcome {
        case completed
        case interrupted
        case cancelled
    }

    /// A whole run is capped so a runaway script can't hold the cursor.
    static let maxRunTime: TimeInterval = 120
    private static let frame: TimeInterval = 1.0 / 60

    private final class Context {
        let origin: CGPoint
        let bounds: CGRect
        let postEvents: Bool
        let deadline: Date
        var expected: CGPoint
        var lastMove = Date.distantPast

        init(origin: CGPoint, postEvents: Bool) {
            self.origin = origin
            self.expected = origin
            self.bounds = MouseDriver.displayBounds(containing: origin)
            self.postEvents = postEvents
            self.deadline = Date().addingTimeInterval(JiggleRunner.maxRunTime)
        }
    }

    private struct Interrupted: Error {}

    static func run(_ steps: [JiggleStep], postEvents: Bool) async -> Outcome {
        let context = Context(origin: MouseDriver.location, postEvents: postEvents)
        do {
            try await execute(steps, context)
            return .completed
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .interrupted
        }
    }

    private static func execute(_ steps: [JiggleStep], _ context: Context) async throws {
        for step in steps {
            try Task.checkCancellation()
            if Date() > context.deadline { throw Interrupted() }

            switch step {
            case .move(let dx, let dy, let duration):
                let target = CGPoint(x: context.expected.x + dx, y: context.expected.y + dy)
                try await glide(to: target, over: duration, context)
            case .moveTo(let x, let y, let duration):
                let target = CGPoint(
                    x: x.resolve(origin: context.bounds.minX, length: context.bounds.width),
                    y: y.resolve(origin: context.bounds.minY, length: context.bounds.height)
                )
                try await glide(to: target, over: duration, context)
            case .circle(let radius, let duration):
                try await circle(radius: radius, over: duration, context)
            case .random(let radius, let duration):
                let angle = Double.random(in: 0..<(2 * .pi))
                let distance = Double.random(in: 0...radius)
                let target = CGPoint(x: context.origin.x + cos(angle) * distance, y: context.origin.y + sin(angle) * distance)
                try await glide(to: target, over: duration, context)
            case .back(let duration):
                try await glide(to: context.origin, over: duration, context)
            case .wait(let low, let high):
                try await sleep(Double.random(in: low...high))
                try checkForPerson(context)
            case .scroll(let lines):
                if context.postEvents { MouseDriver.scroll(lines: lines) }
            case .repeatBlock(let count, let body):
                for _ in 0..<count {
                    try await execute(body, context)
                }
            }
        }
    }

    private static func glide(to target: CGPoint, over duration: Double, _ context: Context) async throws {
        let start = context.expected
        try await animate(over: duration, context) { t in
            CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
        }
    }

    private static func circle(radius: Double, over duration: Double, _ context: Context) async throws {
        // Starts and ends at the current position, going round a centre to its left.
        let center = CGPoint(x: context.expected.x - radius, y: context.expected.y)
        try await animate(over: duration, context, easing: { $0 }) { t in
            let angle = t * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private static func animate(
        over duration: Double,
        _ context: Context,
        easing: (Double) -> Double = { t in t * t * (3 - 2 * t) },
        position: (Double) -> CGPoint
    ) async throws {
        let frames = max(1, Int((duration / frame).rounded()))
        for index in 1...frames {
            try Task.checkCancellation()
            try checkForPerson(context)
            let t = easing(Double(index) / Double(frames))
            context.expected = MouseDriver.move(to: position(t), within: context.bounds, postEvents: context.postEvents)
            context.lastMove = Date()
            if frames > 1 { try await sleep(frame) }
        }
    }

    /// Throws if the cursor isn't where we last put it, i.e. someone moved the mouse.
    private static func checkForPerson(_ context: Context) throws {
        // Give the previous move a moment to land before comparing.
        guard Date().timeIntervalSince(context.lastMove) >= 0.012 else { return }
        if MouseDriver.location.distance(to: context.expected) > 3 { throw Interrupted() }
    }

    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

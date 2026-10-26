import ApplicationServices
import CoreGraphics

/// Moves the cursor. With Accessibility it posts real mouse events; without it the cursor
/// is warped, which needs no permission but isn't seen as input by every app.
enum MouseDriver {
    private static let source: CGEventSource? = {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    /// Cursor position in global display coordinates (origin at the top-left of the main display).
    static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func displayBounds(containing point: CGPoint) -> CGRect {
        var display = CGDirectDisplayID(0)
        var count = UInt32(0)
        if CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 {
            return CGDisplayBounds(display)
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    /// Moves to `point`, clamped to `bounds`; returns where the cursor was put.
    @discardableResult
    static func move(to point: CGPoint, within bounds: CGRect, postEvents: Bool) -> CGPoint {
        let target = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
        if postEvents,
           let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        } else {
            CGWarpMouseCursorPosition(target)
        }
        return target
    }

    static func scroll(lines: Int32) {
        CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    /// Seconds since the last real key press or click. MacUtils never synthesizes either,
    /// so these tell us whether a person has been using the Mac.
    static var secondsSinceHumanInput: Double {
        let key = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let click = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
        let rightClick = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .rightMouseDown)
        return min(key, click, rightClick)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

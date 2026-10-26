import Foundation
import IOKit.pwr_mgt
import IOKit.ps

/// A power-management assertion (what `caffeinate` uses). Needs no special permission.
final class PowerAssertion {
    static let preventSystemSleep = "PreventUserIdleSystemSleep"
    static let preventDisplaySleep = "PreventUserIdleDisplaySleep"

    private let type: String
    private let name: String
    private var id = IOPMAssertionID(0)
    private(set) var isHeld = false

    init(type: String, name: String) {
        self.type = type
        self.name = name
    }

    func acquire() {
        guard !isHeld else { return }
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
        isHeld = result == kIOReturnSuccess
        if !isHeld { NSLog("MacUtils: failed to create \(type) assertion (\(result))") }
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        isHeld = false
    }

    deinit { release() }
}

/// Tells macOS the user is active: resets the idle timer that chat apps use for "Away".
enum UserActivity {
    private static var id = IOPMAssertionID(0)

    static func declare() {
        IOPMAssertionDeclareUserActivity("MacUtils activity" as CFString, kIOPMUserActiveLocal, &id)
    }

    /// Drops the assertion now instead of letting it time out.
    static func end() {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
}

struct BatteryStatus {
    let percent: Int
    let onACPower: Bool
}

enum Battery {
    /// nil on Macs without a battery.
    static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery",
                  let current = description["Current Capacity"] as? Int,
                  let max = description["Max Capacity"] as? Int, max > 0
            else { continue }
            let onAC = description["Power Source State"] as? String == "AC Power"
            return BatteryStatus(percent: current * 100 / max, onACPower: onAC)
        }
        return nil
    }
}

import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// False when run straight from `swift run` instead of a packaged .app.
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var repository: String? {
        Bundle.main.object(forInfoDictionaryKey: "MURepository") as? String
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacUtils", isDirectory: true)
    }
}

/// Dotted version numbers ("1.2.10" > "1.2.9"); a leading "v" is ignored.
struct Version: Comparable {
    let parts: [Int]

    init(_ string: String) {
        let trimmed = string.hasPrefix("v") || string.hasPrefix("V") ? String(string.dropFirst()) : string
        parts = trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

extension Timer {
    /// A repeating main-thread timer that keeps firing while menus or alerts are open.
    @MainActor
    static func commonModes(interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

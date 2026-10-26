import AppKit
import Foundation

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let htmlUrl: URL
    let body: String?
    let assets: [Asset]

    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
}

/// Checks GitHub Releases for a newer MacUtils.zip and swaps it into the installed app.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading
        case installing
        case failed(String)
    }

    static let shared = Updater()
    static let assetName = "MacUtils.zip"

    @Published private(set) var state: State = .idle
    private(set) var latest: GitHubRelease?
    private let prefs = Preferences.shared
    private var timer: Timer?

    var isSupported: Bool { AppInfo.isBundled && AppInfo.repository != nil }

    var isBusy: Bool {
        [.checking, .downloading, .installing].contains(state)
    }

    func startAutomaticChecks() {
        timer?.invalidate()
        timer = .commonModes(interval: 3600) { [weak self] in self?.automaticCheck() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.automaticCheck() }
    }

    private func automaticCheck() {
        guard isSupported, prefs.autoCheckUpdates, !isBusy else { return }
        if let last = prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        Task {
            await check()
            if case .available = state, prefs.autoInstallUpdates {
                await installLatest(interactive: false)
            }
        }
    }

    /// Menu / Settings action: check, then ask before installing.
    func checkAndOfferInstall() async {
        await check()
        switch state {
        case .available(let version):
            let alert = NSAlert()
            alert.messageText = "MacUtils \(version) is available"
            alert.informativeText = "You have \(AppInfo.version). MacUtils will restart after updating; permissions are kept."
            alert.addButton(withTitle: "Install and Restart")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                await installLatest()
            }
        case .upToDate:
            showAlert("You're up to date", "MacUtils \(AppInfo.version) is the latest version.")
        case .failed(let message):
            showAlert("Couldn't check for updates", message)
        default:
            break
        }
    }

    func check() async {
        guard let repository = AppInfo.repository, AppInfo.isBundled else {
            state = .failed("Updates only work in the installed app.")
            return
        }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacUtils/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status != 404 else { throw UpdateError("No releases published for \(repository) yet.") }
            guard status == 200 else { throw UpdateError("GitHub answered with HTTP \(status).") }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(GitHubRelease.self, from: data)
            latest = release
            prefs.lastUpdateCheck = Date()
            state = Version(release.version) > Version(AppInfo.version) ? .available(version: release.version) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func installLatest(interactive: Bool = true) async {
        guard let release = latest, let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
            state = .failed("The latest release has no \(Self.assetName).")
            return
        }
        state = .downloading
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed.") }
            let work = try UpdateInstaller.makeWorkDirectory(near: Bundle.main.bundleURL)
            let zip = work.appendingPathComponent(Self.assetName)
            try FileManager.default.moveItem(at: downloaded, to: zip)
            await install(zipAt: zip, interactive: interactive)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Installs a local MacUtils.zip (also used by `open "macutils://update?zip=PATH"`).
    /// Non-interactive installs report failures only through `state`, never a modal alert.
    func install(zipAt zip: URL, interactive: Bool = true) async {
        guard AppInfo.isBundled else {
            state = .failed("Updates only work in the installed app.")
            return
        }
        state = .installing
        let target = Bundle.main.bundleURL
        do {
            try await Task.detached(priority: .userInitiated) {
                let newApp = try UpdateInstaller.extractAndVerify(zip: zip, replacing: target)
                try UpdateInstaller.replaceContents(of: target, with: newApp)
            }.value
            UpdateInstaller.relaunch(target)
        } catch {
            state = .failed(error.localizedDescription)
            if interactive { showAlert("Update failed", error.localizedDescription) }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum UpdateInstaller {
    /// A temporary folder on the same volume as the app, so the final swap is a rename.
    static func makeWorkDirectory(near app: URL) throws -> URL {
        let fm = FileManager.default
        if let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true) {
            return dir
        }
        let dir = fm.temporaryDirectory.appendingPathComponent("MacUtils-update-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func extractAndVerify(zip: URL, replacing current: URL) throws -> URL {
        let fm = FileManager.default
        let extracted = zip.deletingLastPathComponent().appendingPathComponent("extracted-\(UUID().uuidString)")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])

        let items = try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("The update archive doesn't contain an app.")
        }
        guard let newInfo = Bundle(url: app)?.infoDictionary,
              newInfo["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier
        else {
            throw UpdateError("The update is a different app (bundle identifier mismatch).")
        }
        try CodeSignature.verify(appAt: app)
        // Never let a downloaded copy carry the quarantine flag.
        try? run("/usr/bin/xattr", ["-cr", app.path])
        return app
    }

    /// Swaps Contents/ inside the existing bundle. Only the bundle folder itself needs to be
    /// writable, which install.sh arranges for shared installs in /Applications.
    static func replaceContents(of app: URL, with newApp: URL) throws {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: app.path) else {
            throw UpdateError("No permission to update \(app.path). Run the installer again from an admin account.")
        }
        let contents = app.appendingPathComponent("Contents")
        let old = app.appendingPathComponent("Contents.old-\(UUID().uuidString)")
        try fm.moveItem(at: contents, to: old)
        do {
            try fm.moveItem(at: newApp.appendingPathComponent("Contents"), to: contents)
        } catch {
            try? fm.moveItem(at: old, to: contents)
            throw error
        }
        try? fm.removeItem(at: old)

        // Shared installs stay writable for every local user so anyone can update.
        if let perms = try? fm.attributesOfItem(atPath: app.path)[.posixPermissions] as? Int, perms & 0o020 != 0 {
            try? run("/bin/chmod", ["-R", "g+w", contents.path])
        }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
    }

    @MainActor
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError("\((tool as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

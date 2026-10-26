import Foundation
import Security

/// Updates are only installed if they're signed by the same certificate as the running app.
/// That same check is what lets macOS carry the Accessibility permission over to the new version.
enum CodeSignature {
    static func runningRequirement() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    static func text(of requirement: SecRequirement) -> String? {
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    /// Ad-hoc builds are identified by their exact hash, so every build looks like a new app.
    static var runningSignatureIsStable: Bool {
        guard let requirement = runningRequirement(), let text = text(of: requirement) else { return false }
        return !text.contains("cdhash")
    }

    static var runningSignatureDescription: String {
        guard let requirement = runningRequirement(), let text = text(of: requirement) else { return "Unsigned" }
        if text.contains("cdhash") { return "Ad-hoc (development build — permissions reset with every build)" }
        if let range = text.range(of: #"certificate leaf = H"[0-9a-f]+""#, options: .regularExpression) {
            let hash = text[range].dropFirst("certificate leaf = H\"".count).dropLast()
            return "Stable certificate (\(hash.prefix(12))…)"
        }
        return "Stable certificate"
    }

    static func verify(appAt url: URL) throws {
        guard let requirement = runningRequirement(), runningSignatureIsStable else {
            throw UpdateError("This copy of MacUtils isn't signed with a stable certificate, so it can't verify updates. Reinstall it with install.sh.")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError("Couldn't read the downloaded app's signature.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw UpdateError("The update isn't signed by the same certificate as this app (\(message)). Not installing it.")
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

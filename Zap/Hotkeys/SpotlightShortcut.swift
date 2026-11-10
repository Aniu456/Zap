import Foundation

/// macOS stores "Show Spotlight search" in symbolic hotkey 64. Read the
/// dictionary again for every edit so unrelated shortcut changes are retained.
struct SpotlightShortcut {
    let domain: String
    let applyChanges: () throws -> Void
    private let key = "AppleSymbolicHotKeys" as CFString

    static let system = SpotlightShortcut(domain: "com.apple.symbolichotkeys") {
        let process = Process()
        process.executableURL = URL(fileURLWithPath:
            "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        process.arguments = ["-u"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
    }

    private func read() throws -> [String: Any] {
        let domain = domain as CFString
        guard CFPreferencesAppSynchronize(domain) else { throw CocoaError(.fileReadUnknown) }
        guard let value = CFPreferencesCopyAppValue(key, domain) else { return [:] }
        guard let dictionary = value as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
        return dictionary
    }

    /// A missing preference uses the macOS default, Command-Space.
    func commandSpaceEntry(includingDisabled: Bool = false) throws -> [String: Any]? {
        let shortcuts = try read()
        guard let raw = shortcuts["64"] else {
            return ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 1048576]]]
        }
        guard let entry = raw as? [String: Any],
              let enabled = entry["enabled"] as? Bool else { throw CocoaError(.propertyListReadCorrupt) }
        guard enabled || includingDisabled else { return nil }
        if let value = entry["value"] {
            guard let info = value as? [String: Any], let parameters = info["parameters"] as? [Int],
                  parameters.count == 3 else { throw CocoaError(.propertyListReadCorrupt) }
            guard parameters[1] == 49, parameters[2] == 1048576 else { return nil }
        }
        return entry
    }

    func setEnabled(_ enabled: Bool, original: [String: Any]) throws {
        var shortcuts = try read()
        var disabled = original
        disabled["enabled"] = false
        let expected = enabled ? disabled : original
        let replacement = enabled ? original : disabled
        if let current = shortcuts["64"] as? NSDictionary {
            // Leave subsequent edits made in System Settings in place.
            guard current.isEqual(to: expected) else {
                guard enabled else { throw CocoaError(.fileWriteUnknown) }
                if current.isEqual(to: original) { try applyChanges() }
                return
            }
        } else if enabled {
            return
        }
        shortcuts["64"] = replacement
        CFPreferencesSetAppValue(key, shortcuts as CFDictionary, domain as CFString)
        guard CFPreferencesAppSynchronize(domain as CFString) else { throw CocoaError(.fileWriteUnknown) }
        try applyChanges()
    }
}

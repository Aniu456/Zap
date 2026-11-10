import XCTest
@testable import Zap

final class SpotlightShortcutTests: XCTestCase {
    func testTransferAndRestoreAcrossInstancesPreservesOtherShortcuts() throws {
        let domain = "ZapTests.Spotlight." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var activations = 0
        let spotlight = SpotlightShortcut(domain: domain) { activations += 1 }
        let original = try XCTUnwrap(spotlight.commandSpaceEntry())
        try spotlight.setEnabled(false, original: original)
        XCTAssertNil(try spotlight.commandSpaceEntry())

        var entries = try XCTUnwrap(defaults.dictionary(forKey: "AppleSymbolicHotKeys"))
        entries["65"] = ["enabled": false]
        defaults.set(entries, forKey: "AppleSymbolicHotKeys")
        defaults.synchronize()
        let restored = SpotlightShortcut(domain: domain) { activations += 1 }
        try restored.setEnabled(true, original: original)
        XCTAssertNotNil(try restored.commandSpaceEntry())
        XCTAssertEqual(activations, 2)
        XCTAssertNotNil(defaults.dictionary(forKey: "AppleSymbolicHotKeys")?["65"])
    }

    @MainActor
    func testRegistrationFailureRollsBackAndSuccessfulTransferSurvivesReload() throws {
        let domain = "ZapTests.Spotlight." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let spotlight = SpotlightShortcut(domain: domain) {}
        var accepted = false
        let store = SettingsStore(defaults: defaults, spotlight: spotlight) { _, _ in accepted }
        store.useCommandSpace()
        XCTAssertTrue(store.launcherWarning?.contains("⌘ 空格") == true)
        XCTAssertNil(store.previousLauncher)
        XCTAssertEqual(store.launcherHotkey, .launcherDefault)
        XCTAssertNotNil(try spotlight.commandSpaceEntry())

        accepted = true
        store.useCommandSpace()
        store.returnSpotlightOnQuit()
        XCTAssertNotNil(try spotlight.commandSpaceEntry())
        let restarted = SettingsStore(defaults: defaults, spotlight: spotlight) { _, _ in true }
        restarted.resumeSpotlightTransfer()
        XCTAssertEqual(restarted.launcherHotkey, .commandSpace)
        XCTAssertNil(try spotlight.commandSpaceEntry())
        restarted.setLauncherHotkey(try XCTUnwrap(restarted.previousLauncher))
        XCTAssertNil(restarted.previousLauncher)
        XCTAssertEqual(restarted.launcherHotkey, .launcherDefault)
        XCTAssertNotNil(try spotlight.commandSpaceEntry())
    }

    @MainActor
    func testQuitReturnsManuallyFreedCommandSpace() throws {
        let domain = "ZapTests.Spotlight." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let spotlight = SpotlightShortcut(domain: domain) {}
        try spotlight.setEnabled(false, original: XCTUnwrap(spotlight.commandSpaceEntry()))
        let store = SettingsStore(defaults: defaults, spotlight: spotlight) { _, _ in true }
        store.useCommandSpace()
        XCTAssertNil(try spotlight.commandSpaceEntry())
        store.returnSpotlightOnQuit()
        XCTAssertNotNil(try spotlight.commandSpaceEntry())
    }

    func testRestorePreservesCustomSpotlightBinding() throws {
        let domain = "ZapTests.Spotlight." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let spotlight = SpotlightShortcut(domain: domain) {}
        let original = try XCTUnwrap(spotlight.commandSpaceEntry())
        try spotlight.setEnabled(false, original: original)
        let custom: [String: Any] = ["enabled": true, "value": ["parameters": [32, 49, 524288]]]
        defaults.set(["64": custom], forKey: "AppleSymbolicHotKeys")
        defaults.synchronize()
        XCTAssertNil(try spotlight.commandSpaceEntry())
        try spotlight.setEnabled(true, original: original)
        let current = defaults.dictionary(forKey: "AppleSymbolicHotKeys")?["64"] as? NSDictionary
        XCTAssertEqual(current, custom as NSDictionary)
    }
}

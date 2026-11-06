import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var launcherHotkey: HotkeyChord
    @Published private(set) var clipboardHotkey: HotkeyChord
    @Published private(set) var captureHotkey: HotkeyChord
    @Published private(set) var launcherWarning: String?
    @Published private(set) var clipboardWarning: String?
    @Published private(set) var captureWarning: String?

    private let defaults: UserDefaults
    private let launcherKey = "zap.hotkey.launcher"
    private let clipboardKey = "zap.hotkey.clipboard"
    private let captureKey = "zap.hotkey.capture"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var launcher = Self.load(defaults, key: launcherKey) ?? .launcherDefault
        var clipboard = Self.load(defaults, key: clipboardKey) ?? .clipboardDefault
        var capture = Self.load(defaults, key: captureKey) ?? .captureDefault
        if launcher == clipboard {
            clipboard = .clipboardDefault
        }
        if capture == launcher || capture == clipboard {
            capture = .captureDefault
        }
        if capture == launcher || capture == clipboard {
            capture = .captureFallback
        }
        launcherHotkey = launcher
        clipboardHotkey = clipboard
        captureHotkey = capture
    }

    func setLauncherHotkey(_ chord: HotkeyChord) {
        guard !conflicts(chord, with: clipboardHotkey, captureHotkey) else {
            launcherWarning = L10n.hotkeyConflict
            return
        }
        guard HotkeyManager.shared.commit(launcher: chord, clipboard: clipboardHotkey, capture: captureHotkey) else {
            launcherWarning = L10n.hotkeyRejected
            return
        }
        launcherHotkey = chord
        launcherWarning = nil
        save()
    }

    func setClipboardHotkey(_ chord: HotkeyChord) {
        guard !conflicts(chord, with: launcherHotkey, captureHotkey) else {
            clipboardWarning = L10n.hotkeyConflict
            return
        }
        guard HotkeyManager.shared.commit(launcher: launcherHotkey, clipboard: chord, capture: captureHotkey) else {
            clipboardWarning = L10n.hotkeyRejected
            return
        }
        clipboardHotkey = chord
        clipboardWarning = nil
        save()
    }

    func setCaptureHotkey(_ chord: HotkeyChord) {
        guard !conflicts(chord, with: launcherHotkey, clipboardHotkey) else {
            captureWarning = L10n.hotkeyConflict
            return
        }
        guard HotkeyManager.shared.commit(launcher: launcherHotkey, clipboard: clipboardHotkey, capture: chord) else {
            captureWarning = L10n.hotkeyRejected
            return
        }
        captureHotkey = chord
        captureWarning = nil
        save()
    }

    func restoreDefaultHotkeys() {
        guard HotkeyManager.shared.commit(
            launcher: .launcherDefault,
            clipboard: .clipboardDefault,
            capture: .captureDefault
        ) else {
            launcherWarning = L10n.hotkeyRejected
            clipboardWarning = L10n.hotkeyRejected
            captureWarning = L10n.hotkeyRejected
            return
        }
        launcherHotkey = .launcherDefault
        clipboardHotkey = .clipboardDefault
        captureHotkey = .captureDefault
        launcherWarning = nil
        clipboardWarning = nil
        captureWarning = nil
        save()
    }

    func noteRegistration(launcherOK: Bool, clipboardOK: Bool, captureOK: Bool) {
        launcherWarning = registrationWarning(ok: launcherOK, current: launcherWarning)
        clipboardWarning = registrationWarning(ok: clipboardOK, current: clipboardWarning)
        captureWarning = registrationWarning(ok: captureOK, current: captureWarning)
    }

    private func conflicts(_ chord: HotkeyChord, with others: HotkeyChord...) -> Bool {
        others.contains(chord)
    }

    private func registrationWarning(ok: Bool, current: String?) -> String? {
        if !ok { return L10n.hotkeyRejected }
        if current == L10n.hotkeyRejected { return nil }
        return current
    }

    private func save() {
        save(launcherHotkey, key: launcherKey)
        save(clipboardHotkey, key: clipboardKey)
        save(captureHotkey, key: captureKey)
    }

    private func save(_ chord: HotkeyChord, key: String) {
        guard let data = try? JSONEncoder().encode(chord) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(_ defaults: UserDefaults, key: String) -> HotkeyChord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyChord.self, from: data)
    }
}

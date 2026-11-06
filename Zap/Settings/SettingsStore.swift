import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var launcherHotkey: HotkeyChord
    @Published private(set) var clipboardHotkey: HotkeyChord
    @Published private(set) var launcherWarning: String?
    @Published private(set) var clipboardWarning: String?

    private let defaults: UserDefaults
    private let launcherKey = "zap.hotkey.launcher"
    private let clipboardKey = "zap.hotkey.clipboard"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var launcher = Self.load(defaults, key: launcherKey) ?? .launcherDefault
        var clipboard = Self.load(defaults, key: clipboardKey) ?? .clipboardDefault
        if launcher == clipboard {
            clipboard = .clipboardDefault
        }
        launcherHotkey = launcher
        clipboardHotkey = clipboard
    }

    func setLauncherHotkey(_ chord: HotkeyChord) {
        guard chord != clipboardHotkey else {
            launcherWarning = L10n.hotkeyConflict
            return
        }
        guard HotkeyManager.shared.commit(launcher: chord, clipboard: clipboardHotkey) else {
            launcherWarning = L10n.hotkeyRejected
            return
        }
        launcherHotkey = chord
        launcherWarning = nil
        save()
    }

    func setClipboardHotkey(_ chord: HotkeyChord) {
        guard chord != launcherHotkey else {
            clipboardWarning = L10n.hotkeyConflict
            return
        }
        guard HotkeyManager.shared.commit(launcher: launcherHotkey, clipboard: chord) else {
            clipboardWarning = L10n.hotkeyRejected
            return
        }
        clipboardHotkey = chord
        clipboardWarning = nil
        save()
    }

    func restoreDefaultHotkeys() {
        guard HotkeyManager.shared.commit(launcher: .launcherDefault, clipboard: .clipboardDefault) else {
            launcherWarning = L10n.hotkeyRejected
            clipboardWarning = L10n.hotkeyRejected
            return
        }
        launcherHotkey = .launcherDefault
        clipboardHotkey = .clipboardDefault
        launcherWarning = nil
        clipboardWarning = nil
        save()
    }

    func noteRegistration(launcherOK: Bool, clipboardOK: Bool) {
        launcherWarning = registrationWarning(ok: launcherOK, current: launcherWarning)
        clipboardWarning = registrationWarning(ok: clipboardOK, current: clipboardWarning)
    }

    private func registrationWarning(ok: Bool, current: String?) -> String? {
        if !ok { return L10n.hotkeyRejected }
        if current == L10n.hotkeyRejected { return nil }
        return current
    }

    private func save() {
        save(launcherHotkey, key: launcherKey)
        save(clipboardHotkey, key: clipboardKey)
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

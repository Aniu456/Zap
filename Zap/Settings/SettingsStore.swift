import Foundation

struct AppShortcut: Codable, Identifiable {
    var id: String { app.id }
    let app: LaunchableApp
    var chord: HotkeyChord?
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var launcherHotkey: HotkeyChord
    @Published private(set) var clipboardHotkey: HotkeyChord
    @Published private(set) var captureHotkey: HotkeyChord
    @Published private(set) var launcherWarning: String?
    @Published private(set) var clipboardWarning: String?
    @Published private(set) var captureWarning: String?

    @Published private(set) var appShortcuts: [AppShortcut]
    @Published private(set) var appWarnings: [String: String] = [:]
    private let appShortcutsKey = "zap.hotkey.applications"

    @Published private(set) var previousLauncher: HotkeyChord?
    private let previousKey = "zap.spotlight.previousLauncher"
    private let spotlightEntryKey = "zap.spotlight.originalEntry"
    private let replaceLauncher: (HotkeyChord, HotkeyChord) -> Bool
    private let spotlight: SpotlightShortcut
    private let defaults: UserDefaults
    private let launcherKey = "zap.hotkey.launcher"
    private let clipboardKey = "zap.hotkey.clipboard"
    private let captureKey = "zap.hotkey.capture"

    init(defaults: UserDefaults = .standard, spotlight: SpotlightShortcut = .system,
         replaceLauncher: @escaping (HotkeyChord, HotkeyChord) -> Bool = HotkeyManager.shared.replaceLauncher) {
        self.replaceLauncher = replaceLauncher
        self.defaults = defaults
        self.spotlight = spotlight
        previousLauncher = Self.load(defaults, key: previousKey)
        let launcher = Self.load(defaults, key: launcherKey) ?? .launcherDefault
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
        appShortcuts = defaults.data(forKey: appShortcutsKey).flatMap {
            try? JSONDecoder().decode([AppShortcut].self, from: $0)
        } ?? []
        launcherHotkey = launcher
        clipboardHotkey = clipboard
        captureHotkey = capture
    }

    func addApplication(_ app: LaunchableApp) {
        guard !appShortcuts.contains(where: { $0.id == app.id }) else { return }
        appShortcuts.append(AppShortcut(app: app))
        saveApplications()
    }

    func removeApplication(_ id: String) {
        HotkeyManager.shared.unregisterApplication(id)
        appShortcuts.removeAll { $0.id == id }
        appWarnings[id] = nil
        saveApplications()
    }

    func setApplicationHotkey(_ chord: HotkeyChord, for id: String) {
        guard let index = appShortcuts.firstIndex(where: { $0.id == id }) else { return }
        if [launcherHotkey, clipboardHotkey, captureHotkey].contains(chord) ||
            appShortcuts.contains(where: { $0.id != id && $0.chord == chord }) {
            appWarnings[id] = L10n.hotkeyConflict
            return
        }
        let shortcut = appShortcuts[index]
        guard HotkeyManager.shared.replaceApplicationHotkey(chord, for: shortcut) else {
            appWarnings[id] = L10n.hotkeyRejected
            return
        }
        appShortcuts[index].chord = chord
        appWarnings[id] = nil
        saveApplications()
    }

    func noteApplicationRegistration(_ id: String, ok: Bool) {
        appWarnings[id] = registrationWarning(ok: ok, current: appWarnings[id])
    }

    private func saveApplications() {
        if let data = try? JSONEncoder().encode(appShortcuts) {
            defaults.set(data, forKey: appShortcutsKey)
        }
    }

    func useCommandSpace() {
        guard !conflicts(.commandSpace, with: clipboardHotkey, captureHotkey) else {
            launcherWarning = L10n.hotkeyConflict
            return
        }
        do {
            let entry = try spotlight.commandSpaceEntry(includingDisabled: true)
            if previousLauncher == nil {
                previousLauncher = launcherHotkey == .commandSpace ? .launcherDefault : launcherHotkey
                if let previousLauncher { save(previousLauncher, key: previousKey) }
            }
            if let entry, entry["enabled"] as? Bool == true {
                defaults.set(entry, forKey: spotlightEntryKey)
                try spotlight.setEnabled(false, original: entry)
            }
            setLauncherHotkey(.commandSpace)
            if launcherWarning != nil {
                launcherWarning = "未能注册 ⌘ 空格，请检查其他应用的全局快捷键。"
                finishSpotlightRestore()
            } else if var entry {
                // The user may already have freed Command-Space manually.
                entry["enabled"] = true
                defaults.set(entry, forKey: spotlightEntryKey)
            }
        } catch {
            launcherWarning = Self.spotlightError
            finishSpotlightRestore()
        }
    }

    func returnSpotlightOnQuit() {
        guard previousLauncher != nil, launcherHotkey == .commandSpace else { return }
        do {
            // Older versions left no snapshot if Spotlight was already disabled.
            var entry = defaults.dictionary(forKey: spotlightEntryKey)
            if entry == nil {
                entry = try spotlight.commandSpaceEntry(includingDisabled: true)
                entry?["enabled"] = true
            }
            if let entry { try spotlight.setEnabled(true, original: entry) }
        } catch {
            launcherWarning = Self.spotlightError
        }
    }

    func resumeSpotlightTransfer() {
        guard previousLauncher != nil, launcherHotkey == .commandSpace else { return }
        do {
            if let entry = try spotlight.commandSpaceEntry() {
                defaults.set(entry, forKey: spotlightEntryKey)
                try spotlight.setEnabled(false, original: entry)
            }
            setLauncherHotkey(.commandSpace)
            if launcherWarning != nil { returnSpotlightOnQuit() }
        } catch {
            returnSpotlightOnQuit()
            launcherWarning = Self.spotlightError
        }
    }

    private static let spotlightError = "无法应用聚焦快捷键设置。请在「系统设置 → 键盘 → 键盘快捷键 → 聚焦」中检查。"

    private func finishSpotlightRestore() {
        guard previousLauncher != nil else { return }
        do {
            if let entry = defaults.dictionary(forKey: spotlightEntryKey) {
                try spotlight.setEnabled(true, original: entry)
            }
            defaults.removeObject(forKey: spotlightEntryKey)
            defaults.removeObject(forKey: previousKey)
            previousLauncher = nil
        } catch {
            launcherWarning = Self.spotlightError
        }
    }

    func setLauncherHotkey(_ chord: HotkeyChord) {
        guard !conflicts(chord, with: clipboardHotkey, captureHotkey) else {
            launcherWarning = L10n.hotkeyConflict
            return
        }
        guard replaceLauncher(chord, launcherHotkey) else {
            launcherWarning = L10n.hotkeyRejected
            return
        }
        launcherHotkey = chord
        launcherWarning = nil
        save()
        if chord != .commandSpace { finishSpotlightRestore() }
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
        let assignedChords = Set(appShortcuts.compactMap(\.chord))
        if !assignedChords.isDisjoint(with: [.launcherDefault, .clipboardDefault, .captureDefault]) {
            if assignedChords.contains(.launcherDefault) { launcherWarning = L10n.hotkeyConflict }
            if assignedChords.contains(.clipboardDefault) { clipboardWarning = L10n.hotkeyConflict }
            if assignedChords.contains(.captureDefault) { captureWarning = L10n.hotkeyConflict }
            return
        }
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
        finishSpotlightRestore()
    }

    func noteRegistration(launcherOK: Bool, clipboardOK: Bool, captureOK: Bool) {
        launcherWarning = registrationWarning(ok: launcherOK, current: launcherWarning)
        clipboardWarning = registrationWarning(ok: clipboardOK, current: clipboardWarning)
        captureWarning = registrationWarning(ok: captureOK, current: captureWarning)
    }

    private func conflicts(_ chord: HotkeyChord, with others: HotkeyChord...) -> Bool {
        others.contains(chord) || appShortcuts.contains { $0.chord == chord }
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

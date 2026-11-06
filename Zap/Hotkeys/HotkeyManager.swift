import Carbon
import Foundation

/// Carbon hot keys swallow the chord, so Option-Space does not also type into the front app.
///
final class HotkeyManager {
    static let shared = HotkeyManager()

    static let launcherID: UInt32 = 1
    static let clipboardID: UInt32 = 2

    private let signature: OSType = 0x5A617031 // 'Zap1'
    private var handler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        installHandler()
        registerAll()
    }

    /// Drops the current chords while the settings recorder is listening, then puts them back.
    func setSuspended(_ suspended: Bool) {
        if suspended {
            unregisterAll()
        } else {
            registerAll()
        }
    }

    func registerAll() {
        let chords = currentChords()
        let result = install(launcher: chords.launcher, clipboard: chords.clipboard, capture: chords.capture)
        MainActor.assumeIsolated {
            SettingsStore.shared.noteRegistration(
                launcherOK: result.launcher,
                clipboardOK: result.clipboard,
                captureOK: result.capture
            )
        }
    }

    /// Registers all three chords. On failure the previously saved chords are put back
    /// and this returns false, so a rejected shortcut cannot replace a working one.
    func commit(launcher: HotkeyChord, clipboard: HotkeyChord, capture: HotkeyChord) -> Bool {
        let fallback = currentChords()
        let result = install(launcher: launcher, clipboard: clipboard, capture: capture)
        guard result.launcher, result.clipboard, result.capture else {
            _ = install(launcher: fallback.launcher, clipboard: fallback.clipboard, capture: fallback.capture)
            return false
        }
        return true
    }

    /// Copies the saved chords out of the main actor before Carbon registration.
    private func currentChords() -> (launcher: HotkeyChord, clipboard: HotkeyChord, capture: HotkeyChord) {
        MainActor.assumeIsolated {
            let settings = SettingsStore.shared
            return (settings.launcherHotkey, settings.clipboardHotkey, settings.captureHotkey)
        }
    }

    private func install(
        launcher: HotkeyChord,
        clipboard: HotkeyChord,
        capture: HotkeyChord
    ) -> (launcher: Bool, clipboard: Bool, capture: Bool) {
        unregisterAll()
        let launcherOK = register(launcher, id: Self.launcherID)
        let clipboardOK = register(clipboard, id: Self.clipboardID)
        let captureOK = register(capture, id: CaptureFeature.hotkeyID)
        return (launcherOK, clipboardOK, captureOK)
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status != noErr { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handle(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    private func handle(id: UInt32) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                HotkeyManager.perform(id)
            }
        } else {
            Task { @MainActor in
                HotkeyManager.perform(id)
            }
        }
    }

    @MainActor
    private static func perform(_ id: UInt32) {
        switch id {
        case launcherID, clipboardID:
            guard !CaptureController.shared.isActive else { return }
            if id == launcherID {
                PaletteController.shared.toggle(.launcher)
            } else {
                PaletteController.shared.toggle(.clipboard)
            }
        case CaptureFeature.hotkeyID:
            CaptureController.shared.toggle()
        default:
            break
        }
    }

    @discardableResult
    private func register(_ chord: HotkeyChord, id: UInt32) -> Bool {
        guard chord.carbonModifiers != 0 else { return false }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeys[id] = ref
        return true
    }

    private func unregisterAll() {
        for ref in hotKeys.values {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }
}

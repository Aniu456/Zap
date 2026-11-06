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
        unregisterAll()
        let settings = MainThread.run { SettingsStore.shared }
        let launcherOK = register(settings.launcherHotkey, id: Self.launcherID)
        let clipboardOK = register(settings.clipboardHotkey, id: Self.clipboardID)
        let captureOK = register(settings.captureHotkey, id: CaptureFeature.hotkeyID)
        MainThread.run {
            SettingsStore.shared.noteRegistration(
                launcherOK: launcherOK,
                clipboardOK: clipboardOK,
                captureOK: captureOK
            )
        }
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
        MainThread.run {
            switch id {
            case HotkeyManager.launcherID, HotkeyManager.clipboardID:
                guard !CaptureController.shared.isActive else { return }
                if id == HotkeyManager.launcherID {
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

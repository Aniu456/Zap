import AppKit

@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private(set) var isActive = false
    private var isStarting = false
    private var generation = 0
    private var session: CaptureSession?
    private var pins: [PinWindowController] = []

    private init() {}

    func toggle() {
        if session != nil || isStarting {
            cancel()
            return
        }
        start()
    }

    /// Menu item always starts a shot. If one is already on screen, that one is cancelled first.
    func begin() {
        if session != nil || isStarting {
            cancel()
        }
        start()
    }

    private func start() {
        generation += 1
        let token = generation
        isStarting = true
        isActive = true
        PaletteController.shared.hide()
        ScreenRecordingPermission.shared.refresh()
        if !ScreenRecordingPermission.shared.isTrusted {
            ScreenRecordingPermission.shared.prompt()
            ScreenRecordingPermission.shared.refresh()
        }
        guard ScreenRecordingPermission.shared.isTrusted else {
            isStarting = false
            isActive = false
            ToastCenter.shared.show(L10n.screenRecordingNeeded)
            SettingsWindowController.shared.show()
            return
        }
        Task { @MainActor in
            defer {
                if token == self.generation {
                    self.isStarting = false
                }
            }
            do {
                let shots = try await ScreenGrabber.captureAll()
                guard token == self.generation else { return }
                guard !shots.isEmpty else {
                    self.isActive = false
                    ToastCenter.shared.show(L10n.captureFailed)
                    return
                }
                let session = CaptureSession(shots: shots) { [weak self] outcome in
                    self?.sessionEnded(outcome)
                }
                self.session = session
                session.begin()
            } catch {
                guard token == self.generation else { return }
                self.isActive = false
                ScreenRecordingPermission.shared.refresh()
                if ScreenRecordingPermission.shared.isTrusted {
                    ToastCenter.shared.show(L10n.captureFailed)
                } else {
                    ToastCenter.shared.show(L10n.screenRecordingNeeded)
                    SettingsWindowController.shared.show()
                }
            }
        }
    }

    func cancel() {
        generation += 1
        isStarting = false
        session?.cancel()
        if session == nil {
            isActive = false
        }
    }

    private func sessionEnded(_ outcome: CaptureSession.Outcome?) {
        session = nil
        isActive = false
        isStarting = false
        guard let outcome else { return }
        let stored = ClipboardStore.shared.publishCapturedPNG(outcome.png, caption: L10n.captureCaption)
        switch outcome.kind {
        case .copied:
            ToastCenter.shared.show(stored ? L10n.captureCopied : L10n.captureTooLarge)
            restorePreviousApp()
        case .pinned:
            let pin = PinWindowController(image: outcome.image, screenFrame: outcome.screenFrame)
            pin.onClose = { [weak self, weak pin] in
                guard let self, let pin else { return }
                self.pins.removeAll { $0 === pin }
            }
            pins.append(pin)
            ToastCenter.shared.show(stored ? L10n.capturePinned : L10n.captureTooLarge)
        }
    }

    private func restorePreviousApp() {
        guard let target = FrontmostTracker.shared.targetApp() else { return }
        NSApp.yieldActivation(to: target)
        _ = target.activate(from: .current, options: [])
    }
}

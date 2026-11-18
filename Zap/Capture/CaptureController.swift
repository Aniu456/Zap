import AppKit
import OSLog

@MainActor
final class CaptureController {
    static let shared = CaptureController()

    var isActive: Bool { coordinator.isActive }
    private var pins: [PinWindowController] = []
    private let logger = Logger(subsystem: "com.aniu456.Zap", category: "Capture")
    private enum StartupError: Error { case permissionDenied }

    private lazy var coordinator = CaptureCoordinator(
        prepare: {
            PaletteController.shared.hide()
            let permission = ScreenRecordingPermission.shared
            permission.refresh()
            if !permission.isTrusted {
                permission.prompt()
                permission.refresh()
            }
            guard permission.isTrusted else { throw StartupError.permissionDenied }
        },
        capture: { try await ScreenGrabber.captureAll() },
        makePresentation: { shots, completion in
            CaptureSession(shots: shots, onFinish: completion)
        },
        onOutcome: { [weak self] in self?.handle($0) },
        onFailure: { [weak self] in self?.handleFailure($0) }
    )

    private init() {}

    func toggle() { coordinator.toggle() }
    func begin() { coordinator.begin() }
    func cancel() { coordinator.cancel() }

    private func handleFailure(_ error: Error) {
        logger.error("Capture failed: \(String(describing: error), privacy: .public)")
        ScreenRecordingPermission.shared.refresh()
        if error is StartupError || !ScreenRecordingPermission.shared.isTrusted {
            ToastCenter.shared.show(L10n.screenRecordingNeeded)
            SettingsWindowController.shared.show()
        } else {
            ToastCenter.shared.show(L10n.captureFailed)
        }
    }

    private func handle(_ outcome: CaptureSession.Outcome) {
        switch outcome {
        case .copied(let data):
            let stored = ClipboardStore.shared.publishCapturedPNG(data, caption: L10n.captureCaption)
            if let message = CaptureCopyNotice.message(storedInHistory: stored) {
                ToastCenter.shared.show(message)
            }
            restorePreviousApp()
        case .colorCopied:
            restorePreviousApp()
        case .pinned(let image, let screenFrame):
            let pin = PinWindowController(image: image, screenFrame: screenFrame)
            pin.onClose = { [weak self, weak pin] in
                guard let self, let pin else { return }
                self.pins.removeAll { $0 === pin }
            }
            pins.append(pin)
        }
    }

    private func restorePreviousApp() {
        guard let target = FrontmostTracker.shared.targetApp() else { return }
        NSApp.yieldActivation(to: target)
        _ = target.activate(from: .current, options: [])
    }
}

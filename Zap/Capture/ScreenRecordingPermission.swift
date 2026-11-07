import AppKit
import CoreGraphics

@MainActor
final class ScreenRecordingPermission: ObservableObject {
    static let shared = ScreenRecordingPermission()

    @Published private(set) var isTrusted: Bool

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        isTrusted = CGPreflightScreenCaptureAccess()
    }

    func start() {
        refresh()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                ScreenRecordingPermission.shared.refresh()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeExternalChanges()
    }

    func refresh() {
        let trusted = CGPreflightScreenCaptureAccess()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Shows the system prompt. The switch often stays off until the user turns it on.
    func prompt() {
        let granted = CGRequestScreenCaptureAccess()
        isTrusted = granted || CGPreflightScreenCaptureAccess()
    }

    func openSystemSettings() {
        let raw = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeExternalChanges() {
        let refreshNow: (Notification) -> Void = { _ in
            Task { @MainActor in
                ScreenRecordingPermission.shared.refresh()
            }
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: refreshNow
            )
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main,
                using: refreshNow
            )
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main,
                using: refreshNow
            )
        )
    }
}

import AppKit
import CoreGraphics

@MainActor
final class ScreenRecordingPermission: ObservableObject {
    static let shared = ScreenRecordingPermission()

    @Published private(set) var isTrusted: Bool

    private var timer: Timer?

    private init() {
        isTrusted = CGPreflightScreenCaptureAccess()
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    ScreenRecordingPermission.shared.refresh()
                }
            } else {
                Task { @MainActor in
                    ScreenRecordingPermission.shared.refresh()
                }
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
}

import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission: ObservableObject {
    static let shared = AccessibilityPermission()

    @Published private(set) var isTrusted: Bool

    private var timer: Timer?

    private init() {
        isTrusted = AXIsProcessTrusted()
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                AccessibilityPermission.shared.refresh()
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Adds 一闪 to the Accessibility list and shows the system prompt when needed.
    func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openSystemSettings() {
        let raw = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

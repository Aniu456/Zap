import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermission: ObservableObject {
    static let shared = AccessibilityPermission()

    @Published private(set) var isTrusted: Bool

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        isTrusted = AXIsProcessTrusted()
    }

    func start() {
        refresh()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                AccessibilityPermission.shared.refresh()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeExternalChanges()
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

    private func observeExternalChanges() {
        let refreshNow: (Notification) -> Void = { _ in
            Task { @MainActor in
                AccessibilityPermission.shared.refresh()
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
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    Task { @MainActor in
                        AccessibilityPermission.shared.refresh()
                    }
                }
            }
        )
    }
}

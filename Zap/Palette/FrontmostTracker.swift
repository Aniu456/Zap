import AppKit

/// Remembers the last app that was not 一闪, so paste still has a target after the
/// status menu or the palette activates us.
@MainActor
final class FrontmostTracker: NSObject {
    static let shared = FrontmostTracker()

    private(set) var lastOtherApp: NSRunningApplication?

    private var observer: NSObjectProtocol?

    func start() {
        capture()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                FrontmostTracker.shared.capture()
            }
        }
    }

    func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, !Self.isZap(front) {
            return front
        }
        return lastOtherApp
    }

    func capture() {
        guard let app = NSWorkspace.shared.frontmostApplication, !Self.isZap(app) else { return }
        lastOtherApp = app
    }

    private static func isZap(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        if let bundleID = app.bundleIdentifier, bundleID == Bundle.main.bundleIdentifier { return true }
        return false
    }
}

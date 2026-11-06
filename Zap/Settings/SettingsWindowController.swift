import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        PaletteController.shared.hide()
        NSApp.activate()
        let window = ensureWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let host = NSHostingController(
            rootView: SettingsView()
                .environment(\.locale, Locale(identifier: "zh-Hans-SG"))
        )
        let window = NSWindow(contentViewController: host)
        window.title = L10n.settings.replacingOccurrences(of: "…", with: "")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 580, height: 640))
        window.minSize = NSSize(width: 520, height: 480)
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}

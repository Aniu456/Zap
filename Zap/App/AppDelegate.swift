import AppKit

/// A nib-less AppKit app does not install an `@main` delegate on its own.
/// `NSApplication.delegate` is weak, so this entry point retains the delegate.
@main
enum ZapMain {
    static func main() {
        // AppDelegate is main-actor isolated. Creating it here keeps the
        // nonisolated entry point from calling that initializer directly.
        // `app.run()` retains the local for the life of the process; the
        // application only keeps a weak reference.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrontmostTracker.shared.start()
        AccessibilityPermission.shared.start()
        ScreenRecordingPermission.shared.start()
        HotkeyManager.shared.start()
        AppIndex.shared.start()
        ClipboardStore.shared.load()
        ClipboardMonitor.shared.start()
        statusItem = StatusItemController()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AccessibilityPermission.shared.refresh()
        ScreenRecordingPermission.shared.refresh()
    }

    func applicationDidResignActive(_ notification: Notification) {
        PaletteController.shared.handleResign()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: L10n.appName)
        appItem.submenu = appMenu

        let about = NSMenuItem(title: L10n.aboutMenu, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)

        let settings = NSMenuItem(title: L10n.settings, action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)

        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)

        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

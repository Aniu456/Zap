import AppKit

@main
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
        HotkeyManager.shared.start()
        AppIndex.shared.start()
        ClipboardStore.shared.load()
        ClipboardMonitor.shared.start()
        statusItem = StatusItemController()
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

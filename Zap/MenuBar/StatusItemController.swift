import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = L10n.appName
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(shortcutItem(L10n.openLauncher, action: #selector(openLauncher), chord: SettingsStore.shared.launcherHotkey))
        menu.addItem(shortcutItem(L10n.openClipboard, action: #selector(openClipboard), chord: SettingsStore.shared.clipboardHotkey))
        menu.addItem(.separator())

        let trusted = AccessibilityPermission.shared.isTrusted
        let permission = NSMenuItem(
            title: trusted ? L10n.accessibilityGranted : L10n.accessibilityMissing,
            action: trusted ? nil : #selector(openSettings),
            keyEquivalent: ""
        )
        permission.target = self
        menu.addItem(permission)

        let settings = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func shortcutItem(_ title: String, action: Selector, chord: HotkeyChord) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        let equivalent = chord.keyEquivalent
        if equivalent.isEmpty {
            menuItem.title = "\(title)    \(chord.displayString)"
        } else {
            menuItem.keyEquivalent = equivalent
            menuItem.keyEquivalentModifierMask = chord.modifierFlags
        }
        return menuItem
    }

    @objc private func openLauncher() {
        PaletteController.shared.show(.launcher)
    }

    @objc private func openClipboard() {
        PaletteController.shared.show(.clipboard)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

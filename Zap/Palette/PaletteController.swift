import AppKit
import Carbon
import SwiftUI

enum PaletteMode: String, Equatable {
    case launcher
    case clipboard
}

@MainActor
final class PaletteController: ObservableObject {
    static let shared = PaletteController()

    @Published var mode: PaletteMode = .launcher
    @Published var query: String = "" {
        didSet {
            guard query != oldValue, selectedIndex != 0 else { return }
            selectedIndex = 0
        }
    }
    @Published var selectedIndex = 0
    @Published private(set) var isPresented = false

    private var panel: PalettePanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    private init() {}

    func toggle(_ mode: PaletteMode) {
        if isPresented && self.mode == mode {
            dismiss()
        } else {
            show(mode)
        }
    }

    func show(_ mode: PaletteMode) {
        self.mode = mode
        query = ""
        selectedIndex = 0
        let panel = ensurePanel()
        position(panel)
        isPresented = true
        NSApp.activate()
        panel.orderFrontRegardless()
        installKeyMonitor()
        installClickMonitor()
        AppIndex.shared.refreshIfStale()
        // makeKey on the same turn as installing the hosting view throws on newer AppKit.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard PaletteController.shared.isPresented else { return }
                PaletteController.shared.panel?.makeKey()
            }
        }
    }

    /// Esc, or the same hotkey again. Returns focus to the app the user was in.
    func dismiss() {
        let target = FrontmostTracker.shared.targetApp()
        hide()
        guard let target else { return }
        NSApp.yieldActivation(to: target)
        _ = target.activate(from: .current, options: [])
    }

    func hide() {
        isPresented = false
        query = ""
        panel?.orderOut(nil)
        removeKeyMonitor()
        removeClickMonitor()
    }

    /// Called when the user clicks another app. Order the panel out; resigning alone
    /// leaves a nonactivating window on screen when `hidesOnDeactivate` does not run.
    func handleResign() {
        guard isPresented else { return }
        hide()
    }

    func moveSelection(_ delta: Int) {
        let count = currentCount()
        guard count > 0 else { return }
        selectedIndex = min(max(0, selectedIndex + delta), count - 1)
    }

    func commitSelection() {
        switch mode {
        case .launcher:
            let rows = AppIndex.shared.ranked(matching: query)
            guard !rows.isEmpty else { return }
            let index = min(selectedIndex, rows.count - 1)
            let app = rows[index].app
            hide()
            AppIndex.shared.launch(app)
        case .clipboard:
            let rows = ClipboardStore.shared.ranked(matching: query)
            guard !rows.isEmpty else { return }
            let index = min(selectedIndex, rows.count - 1)
            let item = rows[index].item
            let target = FrontmostTracker.shared.targetApp()
            hide()
            paste(item, into: target)
        }
    }

    func deleteSelectedClipboardItem() {
        guard mode == .clipboard else { return }
        guard let item = selectedClipboardItem() else { return }
        ClipboardStore.shared.delete(item.id)
    }

    func togglePinSelected() {
        guard mode == .clipboard else { return }
        guard let item = selectedClipboardItem() else { return }
        ClipboardStore.shared.togglePin(item.id)
    }

    private func selectedClipboardItem() -> ClipboardItem? {
        let rows = ClipboardStore.shared.ranked(matching: query)
        guard !rows.isEmpty else { return nil }
        return rows[min(selectedIndex, rows.count - 1)].item
    }

    private func paste(_ item: ClipboardItem, into target: NSRunningApplication?) {
        if let target {
            NSApp.yieldActivation(to: target)
            _ = target.activate(from: .current, options: [])
        }
        let trusted = AccessibilityPermission.shared.isTrusted
        let pid = target?.processIdentifier
        let writeAndPaste = {
            MainActor.assumeIsolated {
                // Write immediately before Command-V. The activation delay must not
                // leave a newer clipboard value for the target app to paste.
                ClipboardStore.shared.placeOnPasteboard(item)
                guard trusted, let pid else {
                    ToastCenter.shared.show(L10n.pasteFallback)
                    return
                }
                PasteService.simulateCommandV(pid: pid)
            }
        }
        if target == nil || !trusted {
            writeAndPaste()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: writeAndPaste)
        }
    }

    private func currentCount() -> Int {
        switch mode {
        case .launcher:
            return AppIndex.shared.ranked(matching: query).count
        case .clipboard:
            return ClipboardStore.shared.ranked(matching: query).count
        }
    }

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let panel = PalettePanel()
        let host = NSHostingView(
            rootView: PaletteView()
                .environment(\.locale, Locale(identifier: "zh-Hans-SG"))
        )
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - min(120, visible.height * 0.14)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let consumed = MainActor.assumeIsolated {
                PaletteController.shared.handleKey(code: code, modifierRaw: modifiers)
            }
            return consumed ? nil : event
        }
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    PaletteController.shared.hideIfPointerOutsidePanel()
                }
            } else {
                Task { @MainActor in
                    PaletteController.shared.hideIfPointerOutsidePanel()
                }
            }
        }
    }

    private func hideIfPointerOutsidePanel() {
        guard isPresented, let panel else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            hide()
        }
    }

    /// Returns true when the palette consumed the key. The event itself stays outside the actor.
    private func handleKey(code: UInt16, modifierRaw: UInt) -> Bool {
        guard isPresented else { return false }
        // NSText no longer exposes composition state. The field editor is an NSTextInputClient.
        if let client = panel?.firstResponder as? any NSTextInputClient, client.hasMarkedText() {
            return false
        }
        let flags = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection([.command, .option, .control, .shift])
        if flags == .command && (code == UInt16(kVK_Delete) || code == UInt16(kVK_ForwardDelete)) {
            deleteSelectedClipboardItem()
            return true
        }
        if !flags.intersection([.command, .option, .control]).isEmpty { return false }
        switch Int(code) {
        case kVK_UpArrow:
            moveSelection(-1)
            return true
        case kVK_DownArrow:
            moveSelection(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commitSelection()
            return true
        case kVK_Escape:
            dismiss()
            return true
        default:
            return false
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        becomesKeyOnlyIfNeeded = false
    }
}

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
        panel.makeKey()
        installKeyMonitor()
        AppIndex.shared.refreshIfStale()
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
    }

    /// Called when the user clicks another app and the panel hides itself.
    func handleResign() {
        guard isPresented else { return }
        isPresented = false
        query = ""
        removeKeyMonitor()
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

    private func paste(_ item: ClipboardItem, into target: NSRunningApplication?) {
        if let target {
            NSApp.yieldActivation(to: target)
            _ = target.activate(from: .current, options: [])
        }
        ClipboardStore.shared.placeOnPasteboard(item)
        let trusted = AccessibilityPermission.shared.isTrusted
        let pid = target?.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard trusted, let pid else {
                ToastCenter.shared.show(L10n.pasteFallback)
                return
            }
            PasteService.simulateCommandV(pid: pid)
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
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
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
            MainThread.run {
                PaletteController.shared.handleKey(event)
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isPresented else { return event }
        // Let an in-progress IME composition (Pinyin, etc.) keep arrows and Return.
        if let text = panel?.firstResponder as? NSText, text.hasMarkedText() {
            return event
        }
        let blocked = event.modifierFlags.intersection([.command, .option, .control])
        if !blocked.isEmpty { return event }
        switch event.keyCode {
        case UInt16(kVK_UpArrow):
            moveSelection(-1)
            return nil
        case UInt16(kVK_DownArrow):
            moveSelection(1)
            return nil
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            commitSelection()
            return nil
        case UInt16(kVK_Escape):
            dismiss()
            return nil
        default:
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        WindowSpaces.apply(to: self)
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

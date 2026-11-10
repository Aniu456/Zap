import AppKit
import Carbon
import Combine
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
            guard query != oldValue else { return }
            closePreview()
            selectedIndex = 0
        }
    }
    let scrollRequests = PassthroughSubject<Int, Never>()
    @Published private(set) var selectedClipIDs: [UUID] = []
    @Published private(set) var previewID: UUID?
    @Published var editingClip = false
    private var selectionAnchorID: UUID?

    var orderedSelection: [ClipboardItem] {
        let items = ClipboardStore.shared.items
        return selectedClipIDs.compactMap { id in items.first { $0.id == id } }
    }

    private func closePreview() {
        previewID = nil
        editingClip = false
        clearSelection()
    }

    private func clearSelection() {
        selectedClipIDs.removeAll()
    }

    func selectAllClips() {
        let ids = ClipboardStore.shared.ranked(matching: query).map(\.id)
        guard !ids.isEmpty else { return }
        editingClip = false
        selectedClipIDs = ids
        if previewID == nil || !ids.contains(previewID!) { previewID = ids.first }
    }
    @Published var selectedIndex = 0
    @Published private(set) var isPresented = false
    /// Scroll results back to the top on every presentation.
    @Published private(set) var fieldToken = 0

    private var pasteTask: Task<Void, Never>?
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
        pasteTask?.cancel()
        closePreview()
        self.mode = mode
        let panel = ensurePanel()
        panel.searchField?.abortEditing()
        panel.searchField?.stringValue = ""
        query = ""
        selectedIndex = 0
        fieldToken &+= 1
        position(panel)
        isPresented = true
        NSApp.activate()
        panel.orderFrontRegardless()
        installKeyMonitor()
        installClickMonitor()
        AppIndex.shared.refreshIfStale()
        // makeKey on the same turn as installing the hosting view throws on newer AppKit.
        DispatchQueue.main.async { [weak self] in
            guard self?.isPresented == true else { return }
            panel.makeKey()
            panel.focusSearch()
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
        closePreview()
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
        clearSelection()
        selectedIndex = min(max(0, selectedIndex + delta), count - 1)
        if previewID != nil { previewID = ClipboardStore.shared.ranked(matching: query)[selectedIndex].id }
        scrollRequests.send(selectedIndex)
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
            if !selectedClipIDs.isEmpty {
                pasteInOrder(orderedSelection)
            } else if let item = selectedClipboardItem() {
                paste { ClipboardStore.shared.placeOnPasteboard(item) }
            }
        }
    }

    func clickClipboardRow(_ item: ClipboardItem, index: Int, modifiers: NSEvent.ModifierFlags) {
        selectedIndex = index
        editingClip = false
        let ids = ClipboardStore.shared.ranked(matching: query).map(\.id)
        if modifiers.contains(.shift) {
            // ⇧ and ⌘⇧ both select the contiguous run from the anchor; ⌘⇧ keeps what was already picked.
            let anchor = selectionAnchorID ?? previewID ?? item.id
            let run = ClipSelection.range(in: ids, from: anchor, to: item.id)
            selectedClipIDs = modifiers.contains(.command) ? ClipSelection.union(selectedClipIDs, run) : run
            previewID = item.id
            return
        }
        selectionAnchorID = item.id
        if modifiers.contains(.command) || !selectedClipIDs.isEmpty {
            // In multi-select a plain click toggles one row instead of dropping the whole selection.
            if selectedClipIDs.isEmpty, let previewID, previewID != item.id {
                selectedClipIDs.append(previewID)
            }
            selectedClipIDs = ClipSelection.toggle(item.id, in: selectedClipIDs)
            if selectedClipIDs.isEmpty {
                previewID = nil
            } else if !selectedClipIDs.contains(previewID ?? item.id) || selectedClipIDs.contains(item.id) {
                previewID = selectedClipIDs.contains(item.id) ? item.id : selectedClipIDs.last
            }
            return
        }
        previewID = previewID == item.id ? nil : item.id
    }

    /// Esc leaves editing or multi-select first; otherwise it closes the panel (an open preview closes with it).
    func escape() {
        if editingClip {
            editingClip = false
        } else if !selectedClipIDs.isEmpty {
            let keep = previewID
            clearSelection()
            previewID = keep
        } else {
            dismiss()
        }
    }

    func deleteSelectedClipboardItem() {
        guard mode == .clipboard else { return }
        guard let item = selectedClipboardItem() else { return }
        ClipboardStore.shared.delete(selectedClipIDs.isEmpty ? [item.id] : Set(selectedClipIDs))
        closePreview()
        selectedIndex = min(selectedIndex, max(0, currentCount() - 1))
    }

    func updateVisibleClips(_ ids: [UUID]) {
        if let previewID, !ids.contains(previewID) {
            editingClip = false
            self.previewID = nil
        }
        let remaining = selectedClipIDs.filter(ids.contains)
        if remaining != selectedClipIDs { selectedClipIDs = remaining }
        if previewID == nil { previewID = remaining.last }
        if let previewID, let index = ids.firstIndex(of: previewID) { selectedIndex = index }
    }

    private func selectedClipboardItem() -> ClipboardItem? {
        if let previewID { return ClipboardStore.shared.items.first { $0.id == previewID } }
        let rows = ClipboardStore.shared.ranked(matching: query)
        guard !rows.isEmpty else { return nil }
        return rows[min(selectedIndex, rows.count - 1)].item
    }

    /// Pastes into the previous app with a single ⌘V. Without Accessibility access the content
    /// simply stays on the clipboard, silently.
    private func paste(write: @escaping @MainActor () -> Bool) {
        let target = FrontmostTracker.shared.targetApp()
        hide()
        if let target {
            NSApp.yieldActivation(to: target)
            _ = target.activate(from: .current, options: [])
        }
        guard AccessibilityPermission.shared.isTrusted, let pid = target?.processIdentifier else {
            _ = write()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            MainActor.assumeIsolated {
                // Write immediately before Command-V so a newer clipboard value can't slip in between.
                if write() { _ = PasteService.simulateCommandV(pid: pid) }
            }
        }
    }

    private func pasteInOrder(_ selection: [ClipboardItem]) {
        guard !selection.isEmpty else { return }
        if let text = ClipboardItem.joinedText(selection) {
            paste { ClipboardStore.shared.placeTextOnPasteboard(text) }
            return
        }
        let target = FrontmostTracker.shared.targetApp()
        hide()
        if let target {
            NSApp.yieldActivation(to: target)
            _ = target.activate(from: .current, options: [])
        }
        let store = ClipboardStore.shared
        store.beginPasteBatch()
        guard AccessibilityPermission.shared.isTrusted, let pid = target?.processIdentifier else {
            // Manual paste keeps the last run (including all its consecutive image files).
            if let last = ClipboardItem.pasteSteps(selection, groupAdjacentImages: true).last {
                store.placeStepOnPasteboard(last)
            }
            return
        }
        let steps = ClipboardItem.pasteSteps(selection)
        let board = NSPasteboard.general
        pasteTask = Task {
            let startingCount = board.changeCount
            try? await Task.sleep(for: .milliseconds(120))
            guard board.changeCount == startingCount else { return }
            for step in steps {
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                var read = false
                guard store.placeStepOnPasteboard(step, onRead: { read = true }) else {
                    ToastCenter.shared.show(L10n.batchPasteFailed)
                    return
                }
                let count = board.changeCount
                guard PasteService.simulateCommandV(pid: pid) else {
                    ToastCenter.shared.show(L10n.batchPasteFailed)
                    return
                }
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(8))
                while !read {
                    guard !Task.isCancelled, board.changeCount == count else { return }
                    guard clock.now < deadline else {
                        ToastCenter.shared.show(L10n.batchPasteUnread)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(25))
                }
                // Reading a representation can precede the input's asynchronous attachment import.
                try? await Task.sleep(for: .milliseconds(300))
                guard board.changeCount == count else { return }
            }
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

    /// Prepare the first layout while the menu bar app is idle, without ordering the panel on screen.
    func prepareForFirstOpen() {
        guard panel == nil else { return }
        ensurePanel().contentView?.layoutSubtreeIfNeeded()
    }

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let panel = PalettePanel()
        let chrome = PaletteChrome(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        chrome.autoresizingMask = [.width, .height]
        let host = ClearHostingView(
            rootView: PaletteView()
                .environment(\.locale, Locale(identifier: "zh-Hans-SG"))
        )
        host.frame = chrome.bounds
        host.autoresizingMask = [.width, .height]
        chrome.addSubview(host)
        panel.contentView = chrome
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
        if editingClip {
            if flags.isEmpty && Int(code) == kVK_Escape {
                editingClip = false
                panel?.focusSearch()
                return true
            }
            return false
        }
        if mode == .clipboard && flags == .command && Int(code) == kVK_ANSI_A && query.isEmpty {
            selectAllClips()
            return true
        }
        if mode == .clipboard && flags == .command && (code == UInt16(kVK_Delete) || code == UInt16(kVK_ForwardDelete)) {
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
            if mode == .clipboard { escape() } else { dismiss() }
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

final class PaletteChrome: NSView {
    static let radius: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    weak var searchField: NSTextField?

    func focusSearch() {
        guard let searchField, searchField.window === self else { return }
        if let editor = searchField.currentEditor(), firstResponder === editor { return }
        makeFirstResponder(searchField)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = firstResponder as? NSTextView, editor.isEditable,
              !editor.hasMarkedText() else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case (.command, "a"): editor.selectAll(nil)
        case (.command, "c"): editor.copy(nil)
        case (.command, "x"): editor.cut(nil)
        case (.command, "v"): editor.paste(nil)
        case (.command, "z"): editor.undoManager?.undo()
        case ([.command, .shift], "z"): editor.undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
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

/// Pure selection helpers, kept outside the controller so they can be unit-tested.
enum ClipSelection {
    /// The contiguous run between `anchor` and `target` in list order. Falls back to the target alone.
    static func range(in ids: [UUID], from anchor: UUID, to target: UUID) -> [UUID] {
        guard let end = ids.firstIndex(of: target) else { return [] }
        guard let start = ids.firstIndex(of: anchor) else { return [target] }
        return Array(ids[min(start, end)...max(start, end)])
    }

    /// Adds `extra` after `base`, keeping the original pick order and dropping duplicates.
    static func union(_ base: [UUID], _ extra: [UUID]) -> [UUID] {
        base + extra.filter { !base.contains($0) }
    }

    static func toggle(_ id: UUID, in ids: [UUID]) -> [UUID] {
        ids.contains(id) ? ids.filter { $0 != id } : ids + [id]
    }
}

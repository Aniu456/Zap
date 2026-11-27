import AppKit

/// Main-thread pin window. Created from the capture controller after a shot is finished.
@MainActor
final class PinWindowController: NSObject, NSMenuDelegate {
    let window: PinWindow
    private let baseSize: NSSize
    private var scale: CGFloat = 1
    var onClose: (() -> Void)?

    private var snapshot: CaptureSession.PinSnapshot
    private var editor: CaptureSession?
    private lazy var optionsMenu = makeMenu()

    init(snapshot: CaptureSession.PinSnapshot, screenFrame: NSRect) {
        self.snapshot = snapshot
        baseSize = screenFrame.size
        let window = PinWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.window = window
        super.init()
        window.isFloatingPanel = true
        window.level = .floating
        WindowSpaces.apply(to: window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        showPin()
        window.setFrame(screenFrame, display: true)
        window.orderFrontRegardless()
    }

    private func showPin() {
        let view = PinContentView(image: snapshot.image)
        view.menu = optionsMenu
        window.isMovableByWindowBackground = true
        view.onClose = { [weak self] in self?.close() }
        window.acceptsMouseMovedEvents = true
        view.onScale = { [weak self] factor in self?.scale(by: factor) }
        view.onResetScale = { [weak self] in self?.scale(to: 1) }
        window.contentView = view
    }

    private func edit() -> CaptureSession {
        if let editor { return editor }
        (window.contentView as? PinContentView)?.loupe.hide()
        let shot = ScreenGrabber.Shot(displayID: 0, frame: window.frame, image: snapshot.base)
        let session = CaptureSession(shots: [shot]) { [weak self] outcome in
            guard let self else { return }
            if let exported = self.editor?.exportedPin { self.snapshot = exported }
            if case .pinned(let edited, _) = outcome {
                self.snapshot = edited
            } else if case .copied(let data) = outcome {
                _ = ClipboardStore.shared.publishCapturedPNG(data, caption: L10n.captureCaption)
            }
            self.editor = nil
            self.showPin()
        }
        editor = session
        window.isMovableByWindowBackground = false
        session.editPin(snapshot, in: window)
        window.contentView?.menu = optionsMenu
        return session
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }
        _ = add("放大", #selector(zoomIn))
        _ = add("缩小", #selector(zoomOut))
        _ = add("恢复原始大小（100%）", #selector(resetZoom))
        _ = add("取色器", #selector(pickColor))
        menu.addItem(.separator())
        let tools: [(String, CaptureTool)] = [
            (L10n.toolBox, .box), (L10n.toolArrow, .arrow),
            (L10n.toolText, .text), (L10n.toolMosaic, .mosaic)
        ]
        for (title, tool) in tools {
            add(title, #selector(selectTool(_:))).representedObject = tool
        }
        _ = add("完成标注", #selector(finishEditing))
        _ = add(L10n.undo, #selector(undoEdit))
        _ = add(L10n.redo, #selector(redoEdit))
        menu.addItem(.separator())
        _ = add(L10n.copyCapture, #selector(copyPin))
        _ = add(L10n.saveCapture, #selector(savePin))
        _ = add(L10n.closePin, #selector(close))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(undoEdit): item.isEnabled = editor?.canUndo ?? !snapshot.undo.isEmpty
            case #selector(redoEdit): item.isEnabled = editor?.canRedo ?? !snapshot.redo.isEmpty
            case #selector(finishEditing): item.isHidden = editor == nil
            case #selector(selectTool(_:)):
                item.state = editor?.tool == (item.representedObject as? CaptureTool) ? .on : .off
            case #selector(pickColor):
                item.state = (window.contentView as? PinContentView)?.picking == true ? .on : .off
            default: break
            }
        }
    }

    @objc private func selectTool(_ item: NSMenuItem) {
        if let tool = item.representedObject as? CaptureTool { edit().setTool(tool) }
    }

    @objc private func finishEditing() { editor?.commit(pin: true) }
    @objc private func undoEdit() { edit().undo() }
    @objc private func redoEdit() { edit().redo() }
    @objc private func copyPin() { edit().commit(pin: false) }
    @objc private func savePin() {
        let wasViewing = editor == nil
        edit().saveToFile()
        if wasViewing { editor?.cancel() }
    }
    @objc private func zoomIn() { finishEditing(); scale(by: 1.2) }
    @objc private func zoomOut() { finishEditing(); scale(by: 1 / 1.2) }
    @objc private func resetZoom() { finishEditing(); scale(to: 1) }

    @objc private func pickColor() {
        finishEditing()
        (window.contentView as? PinContentView)?.togglePicker()
    }

    @objc func close() {
        editor?.cancel()
        (window.contentView as? PinContentView)?.loupe.hide()
        window.orderOut(nil)
        window.contentView = nil
        onClose?()
    }

    private func scale(by factor: CGFloat) {
        scale(to: scale * factor)
    }

    private func scale(to next: CGFloat) {
        guard next.isFinite else { return }
        let clamped = min(4, max(0.25, next))
        guard abs(clamped - scale) > 0.001 else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let size = NSSize(width: baseSize.width * clamped, height: baseSize.height * clamped)
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        scale = clamped
        (window.contentView as? PinContentView)?.loupe.hide()
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

final class PinWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PinContentView: NSView {
    var onClose: (() -> Void)?
    let loupe = PixelLoupe()
    private(set) var picking = false
    private lazy var bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    var onScale: ((CGFloat) -> Void)?
    var onResetScale: (() -> Void)?

    private let image: NSImage
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        refreshTheme()
        closeButton.isBordered = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.closePin)
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.alphaValue = 0
        closeButton.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
        addSubview(closeButton)
        toolTip = "滚轮或双指捏合缩放 · 拖动移动 · 右键查看更多操作"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTheme()
    }

    private func refreshTheme() {
        let color = ZapSwatch.nsColor(.separator, appearance: effectiveAppearance)
        layer?.borderColor = color.cgColor
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: bounds.maxX - 26, y: bounds.maxY - 26, width: 20, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.alphaValue = 1
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0
        loupe.hide()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            super.rightMouseDown(with: event)
            return
        }
        window?.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            close()
            return
        }
        if !picking { window?.performDrag(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        // Do not keep resizing after a trackpad gesture has ended.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 2
        guard delta.isFinite, abs(delta) > 0.1 else { return }
        let factor = exp(min(20, max(-20, delta)) * 0.015)
        onScale?(factor)
    }

    override func magnify(with event: NSEvent) {
        guard event.magnification.isFinite else { return }
        onScale?(max(0.01, 1 + event.magnification))
    }

    @objc private func zoomIn() { onScale?(1.2) }
    @objc private func zoomOut() { onScale?(1 / 1.2) }
    @objc private func resetZoom() { onResetScale?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty || modifiers == .command || modifiers == .shift || modifiers == [.command, .shift] {
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoomIn(); return
            case "-": zoomOut(); return
            case "0": resetZoom(); return
            default: break
            }
        }
        if picking && loupe.copyColor(event) { return }
        super.keyDown(with: event)
    }

    func togglePicker() {
        picking.toggle()
        if picking {
            window?.makeKey()
            window?.makeFirstResponder(self)
            if let window { updateSample(window.mouseLocationOutsideOfEventStream) }
        } else {
            loupe.hide()
        }
    }

    override func mouseMoved(with event: NSEvent) { updateSample(event.locationInWindow) }

    private func updateSample(_ windowPoint: CGPoint) {
        guard picking, let bitmap else { return }
        loupe.update(image: bitmap, in: self, point: convert(windowPoint, from: nil))
    }

    override func flagsChanged(with event: NSEvent) {
        if picking { loupe.flagsChanged(event.modifierFlags) }
    }

    @objc private func close() {
        onClose?()
    }
}

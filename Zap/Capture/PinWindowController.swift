import AppKit

/// Main-thread pin window. Created from the capture controller after a shot is finished.
final class PinWindowController: NSObject {
    let window: PinWindow
    private let baseSize: NSSize
    private var scale: CGFloat = 1
    var onClose: (() -> Void)?

    init(image: NSImage, screenFrame: NSRect) {
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let view = PinContentView(image: image)
        view.onClose = { [weak self] in self?.close() }
        view.onResetScale = { [weak self] in self?.resetScale() }
        view.onScale = { [weak self] factor in self?.scale(by: factor) }
        window.contentView = view
        window.setFrame(screenFrame, display: true)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        onClose?()
    }

    private func resetScale() {
        scale(to: 1)
    }

    private func scale(by factor: CGFloat) {
        scale(to: scale * factor)
    }

    private func scale(to next: CGFloat) {
        let clamped = min(4, max(0.25, next))
        guard abs(clamped - scale) > 0.001 else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let size = NSSize(width: baseSize.width * clamped, height: baseSize.height * clamped)
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        scale = clamped
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

final class PinWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PinContentView: NSView {
    var onClose: (() -> Void)?
    var onResetScale: (() -> Void)?
    var onScale: ((CGFloat) -> Void)?

    private let image: NSImage
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        closeButton.isBordered = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.closePin)
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.alphaValue = 0
        closeButton.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
        addSubview(closeButton)
        menu = NSMenu()
        let item = NSMenuItem(title: L10n.closePin, action: #selector(close), keyEquivalent: "")
        item.target = self
        menu?.addItem(item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

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
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 {
            onResetScale?()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 2
        guard abs(delta) > 0.1 else { return }
        let factor = delta > 0 ? 1.04 : 0.96
        onScale?(factor)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    @objc private func close() {
        onClose?()
    }
}

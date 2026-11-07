import AppKit

/// Icon toolbar modeled on Snipaste's Mac annotation bar: a light rounded pill,
/// symbols only, tools on the left and actions on the right. Drag the bar to move it.
final class CaptureToolbar: NSView {
    var onTool: ((CaptureTool) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [CaptureTool: NSButton] = [:]
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private let colorDot = IgnoredHitView()
    private var dragGrab: CGPoint?
    private var dragMoved = false
    private var pressedButton: NSButton?
    private let gripWidth: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.965, alpha: 0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: 2)
        layer?.masksToBounds = false
        build()
        setTool(.arrow)
        setUndoEnabled(false)
        setRedoEnabled(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Clicks anywhere on the bar come here, so a drag can move it and a
        // tap can still fire the button underneath.
        super.hitTest(point) == nil ? nil : self
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(NSRect(x: 0, y: 0, width: gripWidth, height: bounds.height), cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor.black.withAlphaComponent(0.38)
        ink.setFill()
        let center = CGPoint(x: gripWidth / 2, y: bounds.midY)
        for row in -1...1 {
            for column in [-1, 1] {
                let rect = NSRect(
                    x: center.x + CGFloat(column) * 1.7 - 1,
                    y: center.y + CGFloat(row) * 3.4 - 1,
                    width: 2,
                    height: 2
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        let local = convert(event.locationInWindow, from: nil)
        let point = superview.convert(event.locationInWindow, from: nil)
        dragGrab = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        dragMoved = false
        if let button = button(at: local), button.isEnabled {
            pressedButton = button
            button.highlight(true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragGrab, let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let proposed = CGPoint(x: point.x - dragGrab.x, y: point.y - dragGrab.y)
        if !dragMoved, hypot(proposed.x - frame.minX, proposed.y - frame.minY) < 3 {
            return
        }
        if !dragMoved {
            dragMoved = true
            pressedButton?.highlight(false)
            pressedButton = nil
            NSCursor.closedHand.push()
        }
        frame.origin = CaptureGeometry.clampedToolbarOrigin(
            proposed,
            toolbarSize: frame.size,
            bounds: superview.bounds
        )
    }

    override func mouseUp(with event: NSEvent) {
        let button = pressedButton
        pressedButton = nil
        button?.highlight(false)
        if dragMoved {
            NSCursor.closedHand.pop()
        } else if let button, button.isEnabled,
                  button.frame.contains(convert(event.locationInWindow, from: nil)) {
            button.performClick(nil)
        }
        dragGrab = nil
        dragMoved = false
    }

    private func button(at local: CGPoint) -> NSButton? {
        for case let button as NSButton in subviews.reversed() where button.frame.contains(local) {
            return button
        }
        return nil
    }

    func setTool(_ tool: CaptureTool) {
        if let selected = toolButtons[tool] {
            colorDot.frame.origin.x = selected.frame.maxX - colorDot.frame.width
        }
        for (candidate, button) in toolButtons {
            style(button, selected: candidate == tool)
        }
    }

    func setUndoEnabled(_ enabled: Bool) {
        undoButton?.isEnabled = enabled
        undoButton?.alphaValue = enabled ? 1 : 0.35
    }

    func setRedoEnabled(_ enabled: Bool) {
        redoButton?.isEnabled = enabled
        redoButton?.alphaValue = enabled ? 1 : 0.35
    }

    private func style(_ button: NSButton, selected: Bool) {
        button.layer?.backgroundColor = (selected ? NSColor.black.withAlphaComponent(0.10) : NSColor.clear).cgColor
    }

    private func build() {
        let height: CGFloat = 32
        let buttonSide: CGFloat = 29
        var x = gripWidth
        let y = (height - buttonSide) / 2

        func place(_ button: NSButton) {
            button.frame = NSRect(x: x, y: y, width: buttonSide, height: buttonSide)
            addSubview(button)
            x += buttonSide + 1
        }

        let box = toolButton(.box, symbol: "rectangle.on.rectangle", tip: L10n.toolBox)
        place(box)
        colorDot.wantsLayer = true
        colorDot.layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.15, blue: 0.18, alpha: 1).cgColor
        colorDot.layer?.cornerRadius = 3
        let dotX = box.frame.midX + 6
        colorDot.frame = NSRect(x: dotX, y: height - 8, width: 6, height: 6)

        place(toolButton(.arrow, symbol: "arrow.up.right", tip: L10n.toolArrow))
        place(toolButton(.pencil, symbol: "pencil", tip: L10n.toolPencil))
        place(toolButton(.marker, symbol: "highlighter", tip: L10n.toolMarker))
        place(toolButton(.mosaic, symbol: "square.grid.2x2.fill", tip: L10n.toolMosaic))
        place(textButton())
        place(toolButton(.eraser, symbol: "eraser", tip: L10n.toolEraser))

        x += 3
        addSeparator(x: x, height: height)
        x += 8

        let undo = actionButton(symbol: "arrow.uturn.backward", tip: L10n.undo, action: #selector(undo(_:)))
        place(undo)
        undoButton = undo
        let redo = actionButton(symbol: "arrow.uturn.forward", tip: L10n.redo, action: #selector(redo(_:)))
        place(redo)
        redoButton = redo

        x += 3
        addSeparator(x: x, height: height)
        x += 8

        place(actionButton(symbol: "xmark", tip: L10n.cancel, action: #selector(cancelShot(_:))))
        place(actionButton(symbol: "pin", tip: L10n.pinCapture, action: #selector(pinShot(_:))))
        place(saveButton())
        place(actionButton(symbol: "doc.on.doc", tip: L10n.copyCapture, action: #selector(copyShot(_:))))

        addSubview(colorDot)
        frame = NSRect(x: 0, y: 0, width: x + 5, height: height)
    }

    private func addSeparator(x: CGFloat, height: CGFloat) {
        let line = IgnoredHitView(frame: NSRect(x: x, y: (height - 16) / 2, width: 1, height: 16))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        addSubview(line)
    }

    private func toolButton(_ tool: CaptureTool, symbol: String, tip: String) -> NSButton {
        let button = iconButton(symbol: symbol, tip: tip, action: #selector(pickTool(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(Self.name(for: tool))
        toolButtons[tool] = button
        return button
    }

    private func textButton() -> NSButton {
        let button = baseButton(tip: L10n.toolText, action: #selector(pickTool(_:)))
        button.identifier = NSUserInterfaceItemIdentifier("text")
        button.title = ""
        button.attributedTitle = NSAttributedString(
            string: "T",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1)
            ]
        )
        toolButtons[.text] = button
        return button
    }

    private func saveButton() -> NSButton {
        let button = baseButton(tip: L10n.saveCapture, action: #selector(saveShot(_:)))
        button.image = Self.floppyIcon
        button.imagePosition = .imageOnly
        return button
    }

    private func actionButton(symbol: String, tip: String, action: Selector) -> NSButton {
        iconButton(symbol: symbol, tip: tip, action: action)
    }

    private func iconButton(symbol: String, tip: String, action: Selector) -> NSButton {
        let button = baseButton(tip: tip, action: action)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1)
        return button
    }

    private func baseButton(tip: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = tip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.setButtonType(.momentaryChange)
        return button
    }

    private static func name(for tool: CaptureTool) -> String {
        switch tool {
        case .box: return "box"
        case .arrow: return "arrow"
        case .pencil: return "pencil"
        case .marker: return "marker"
        case .mosaic: return "mosaic"
        case .text: return "text"
        case .eraser: return "eraser"
        }
    }

    private static func tool(for name: String) -> CaptureTool? {
        switch name {
        case "box": return .box
        case "arrow": return .arrow
        case "pencil": return .pencil
        case "marker": return .marker
        case "mosaic": return .mosaic
        case "text": return .text
        case "eraser": return .eraser
        default: return nil
        }
    }

    private static let floppyIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let ink = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1)
            ink.setStroke()
            ink.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 2.2, y: 1.4, width: 11.6, height: 13.2), xRadius: 1.4, yRadius: 1.4)
            body.lineWidth = 1.15
            body.stroke()
            let shutter = NSBezierPath(rect: NSRect(x: 4.2, y: 8.2, width: 7.6, height: 5.2))
            shutter.lineWidth = 1.05
            shutter.stroke()
            NSBezierPath(rect: NSRect(x: 6.3, y: 2.5, width: 3.4, height: 2.6)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()

    @objc private func pickTool(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, let tool = Self.tool(for: name) else { return }
        setTool(tool)
        onTool?(tool)
    }

    @objc private func undo(_ sender: NSButton) { onUndo?() }
    @objc private func redo(_ sender: NSButton) { onRedo?() }
    @objc private func copyShot(_ sender: NSButton) { onCopy?() }
    @objc private func pinShot(_ sender: NSButton) { onPin?() }
    @objc private func saveShot(_ sender: NSButton) { onSave?() }
    @objc private func cancelShot(_ sender: NSButton) { onCancel?() }
}

private final class IgnoredHitView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

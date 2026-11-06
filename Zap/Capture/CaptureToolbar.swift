import AppKit

final class CaptureToolbar: NSView {
    static let preferredSize = NSSize(width: 548, height: 44)

    var onTool: ((CaptureTool) -> Void)?
    var onUndo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?
    var onCancel: (() -> Void)?

    private var toolButtons: [CaptureTool: NSButton] = [:]
    private var undoButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        build()
        setTool(.arrow)
        setUndoEnabled(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTool(_ tool: CaptureTool) {
        for (candidate, button) in toolButtons {
            style(button, selected: candidate == tool)
        }
    }

    private func style(_ button: NSButton, selected: Bool) {
        let color = selected ? NSColor.white : NSColor.labelColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        button.layer?.backgroundColor = (selected ? NSColor.controlAccentColor.cgColor : NSColor.clear).cgColor
    }

    func setUndoEnabled(_ enabled: Bool) {
        undoButton?.isEnabled = enabled
    }

    private func build() {
        let specs: [(String, Selector, String)] = [
            (L10n.toolArrow, #selector(pickTool(_:)), "arrow"),
            (L10n.toolBox, #selector(pickTool(_:)), "box"),
            (L10n.toolText, #selector(pickTool(_:)), "text"),
            (L10n.toolMosaic, #selector(pickTool(_:)), "mosaic"),
            (L10n.undo, #selector(undo(_:)), "undo"),
            (L10n.copyCapture, #selector(copyShot(_:)), "copy"),
            (L10n.pinCapture, #selector(pinShot(_:)), "pin"),
            (L10n.cancel, #selector(cancelShot(_:)), "cancel")
        ]
        var x: CGFloat = 8
        for (title, action, name) in specs {
            let width: CGFloat = title.count >= 3 ? 72 : 58
            let button = NSButton(title: title, target: self, action: action)
            button.frame = NSRect(x: x, y: 8, width: width, height: 28)
            button.isBordered = false
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.identifier = NSUserInterfaceItemIdentifier(name)
            style(button, selected: false)
            addSubview(button)
            if let tool = Self.tool(for: name) {
                toolButtons[tool] = button
            }
            if name == "undo" {
                undoButton = button
            }
            x += width + 6
        }
        frame.size.width = x + 2
    }

    private static func tool(for name: String) -> CaptureTool? {
        switch name {
        case "arrow": return .arrow
        case "box": return .box
        case "text": return .text
        case "mosaic": return .mosaic
        default: return nil
        }
    }

    @objc private func pickTool(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, let tool = Self.tool(for: name) else { return }
        setTool(tool)
        onTool?(tool)
    }

    @objc private func undo(_ sender: NSButton) { onUndo?() }
    @objc private func copyShot(_ sender: NSButton) { onCopy?() }
    @objc private func pinShot(_ sender: NSButton) { onPin?() }
    @objc private func cancelShot(_ sender: NSButton) { onCancel?() }
}

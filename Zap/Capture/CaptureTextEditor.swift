import AppKit

/// A separate grip moves the editor without stealing text selection or input focus.
final class CaptureTextEditor: NSView {
    let field = NSTextField()
    private let grip = Grip()
    private let movementBounds: CGRect

    init(frame: CGRect, movementBounds: CGRect) {
        self.movementBounds = movementBounds
        super.init(frame: frame)
        let gripWidth = min(20, frame.width / 3)
        grip.frame = CGRect(x: 0, y: 0, width: gripWidth, height: frame.height)
        grip.toolTip = "拖动调整文字位置"
        grip.onDrag = { [weak self] delta in self?.move(by: delta) }
        field.frame = CGRect(x: gripWidth, y: 0, width: frame.width - gripWidth, height: frame.height)
        addSubview(grip)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func move(by delta: CGPoint) {
        frame.origin = CGPoint(
            x: min(max(movementBounds.minX, frame.minX + delta.x), max(movementBounds.minX, movementBounds.maxX - frame.width)),
            y: min(max(movementBounds.minY, frame.minY + delta.y), max(movementBounds.minY, movementBounds.maxY - frame.height))
        )
    }

    private final class Grip: NSView {
        var onDrag: ((CGPoint) -> Void)?
        private var lastPoint: CGPoint?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
            NSColor.secondaryLabelColor.setFill()
            for y in [-4.0, 0, 4] {
                NSBezierPath(ovalIn: CGRect(x: bounds.midX - 1, y: bounds.midY + y - 1, width: 2, height: 2)).fill()
            }
        }
        override func mouseDown(with event: NSEvent) {
            lastPoint = event.locationInWindow
            NSCursor.closedHand.set()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let lastPoint else { return }
            let point = event.locationInWindow
            onDrag?(CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
            self.lastPoint = point
        }
        override func mouseUp(with event: NSEvent) {
            mouseDragged(with: event)
            lastPoint = nil
            NSCursor.openHand.set()
        }
    }
}

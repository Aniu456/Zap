import AppKit

final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct CaptureCanvasState {
    var background: CGImage
    var selection: CGRect?
    var preview: CGImage?
    var draft: CaptureMark?
    var cropSize: CGSize?
    var hint: String
}

final class CaptureOverlayView: NSView {
    let displayID: CGDirectDisplayID
    weak var session: CaptureSession?

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor = (session?.usesCrosshair(on: displayID) ?? true) ? .crosshair : .arrow
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let state = session?.canvasState(for: displayID) else {
            NSColor.black.setFill()
            bounds.fill()
            return
        }
        drawImage(state.background, in: bounds)
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill(using: .sourceOver)

        if let selection = state.selection, selection.width > 1, selection.height > 1 {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            if let preview = state.preview {
                drawImage(preview, in: selection)
            } else {
                drawImage(state.background, in: bounds)
            }
            NSGraphicsContext.current?.restoreGraphicsState()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()

            if let draft = state.draft, let cropSize = state.cropSize {
                drawDraft(draft, selection: selection, imageSize: cropSize)
            }
            drawSizeLabel(for: selection, preview: state.preview, cropSize: state.cropSize, background: state.background)
        }
        drawHint(state.hint)
    }

    override func mouseDown(with event: NSEvent) {
        session?.mouseDown(displayID: displayID, point: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        session?.mouseDragged(displayID: displayID, point: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        session?.mouseUp(displayID: displayID, point: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        session?.keyDown(event)
    }

    private func drawImage(_ image: CGImage, in rect: CGRect) {
        NSImage(cgImage: image, size: rect.size).draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private func drawDraft(_ mark: CaptureMark, selection: CGRect, imageSize: CGSize) {
        switch mark {
        case .arrow(let from, let to):
            let start = CaptureGeometry.viewPoint(fromCropPixel: from, selection: selection, imageSize: imageSize)
            let end = CaptureGeometry.viewPoint(fromCropPixel: to, selection: selection, imageSize: imageSize)
            NSColor.systemRed.setStroke()
            let line = NSBezierPath()
            line.move(to: start)
            line.line(to: end)
            line.lineWidth = 2
            line.lineCapStyle = .round
            line.stroke()
            if let head = ArrowGeometry.headPoints(from: start, to: end, length: 12) {
                let path = NSBezierPath()
                path.move(to: head.0)
                path.line(to: end)
                path.line(to: head.1)
                path.close()
                NSColor.systemRed.setFill()
                path.fill()
            }
        case .box(let rect), .mosaic(let rect):
            let viewRect = Self.viewRect(fromPixelRect: rect, selection: selection, imageSize: imageSize)
            let path = NSBezierPath(rect: viewRect)
            path.lineWidth = 2
            if case .mosaic = mark {
                path.setLineDash([5, 3], count: 2, phase: 0)
                NSColor.white.setStroke()
            } else {
                NSColor.systemRed.setStroke()
            }
            path.stroke()
        case .text:
            break
        }
    }

    private func drawSizeLabel(for selection: CGRect, preview: CGImage?, cropSize: CGSize?, background: CGImage) {
        let pixelSize: CGSize
        if let preview {
            pixelSize = CGSize(width: preview.width, height: preview.height)
        } else if let cropSize {
            pixelSize = cropSize
        } else {
            let pixels = CaptureGeometry.cropPixels(
                selection: selection,
                screenSize: bounds.size,
                imageSize: CGSize(width: background.width, height: background.height)
            )
            pixelSize = CGSize(width: pixels.width, height: pixels.height)
        }
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        let text = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let label = NSSize(width: textSize.width + 12, height: textSize.height + 6)
        var origin = NSPoint(x: selection.maxX - label.width, y: selection.minY - label.height - 6)
        if origin.y < 8 {
            origin.y = selection.minY + 6
        }
        if origin.x < 8 {
            origin.x = 8
        }
        let rect = NSRect(origin: origin, size: label)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 3), withAttributes: attributes)
    }

    private func drawHint(_ hint: String) {
        guard !hint.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = hint as NSString
        let textSize = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: (bounds.width - textSize.width) / 2 - 12,
            y: 18,
            width: textSize.width + 24,
            height: textSize.height + 10
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 5), withAttributes: attributes)
    }

    private static func viewRect(fromPixelRect rect: CGRect, selection: CGRect, imageSize: CGSize) -> CGRect {
        let rect = CaptureGeometry.normalized(rect)
        let topLeft = CaptureGeometry.viewPoint(
            fromCropPixel: CGPoint(x: rect.minX, y: rect.minY),
            selection: selection,
            imageSize: imageSize
        )
        let bottomRight = CaptureGeometry.viewPoint(
            fromCropPixel: CGPoint(x: rect.maxX, y: rect.maxY),
            selection: selection,
            imageSize: imageSize
        )
        return CaptureGeometry.normalized(
            CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        )
    }
}

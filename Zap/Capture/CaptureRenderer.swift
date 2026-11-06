import AppKit

enum CaptureRenderer {
    static func render(base: CGImage, marks: [CaptureMark]) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // User space matches the annotation model: origin at the top-left, y downward.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height))

        let lineWidth = max(2, CGFloat(min(width, height)) / 240)
        let markColor = Self.markColor
        for mark in marks {
            switch mark {
            case .mosaic(let rect):
                pixelate(context: context, imageWidth: width, imageHeight: height, rect: rect)
            case .box(let rect):
                strokeBox(rect, lineWidth: lineWidth, color: markColor, in: context)
            case .arrow(let from, let to):
                strokeArrow(from: from, to: to, lineWidth: lineWidth, color: markColor, in: context)
            case .text(let string, let origin, let fontSize):
                drawText(string, at: origin, fontSize: fontSize, color: markColor, in: context)
            }
        }
        context.restoreGState()
        return context.makeImage()
    }

    static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private static func pixelate(context: CGContext, imageWidth: Int, imageHeight: Int, rect: CGRect) {
        let topLeft = CaptureGeometry.pixelRect(from: rect, imageWidth: imageWidth, imageHeight: imageHeight)
        guard !topLeft.isEmpty, let data = context.data else { return }
        let bytesPerRow = context.bytesPerRow
        let count = bytesPerRow * imageHeight
        guard count > 0 else { return }
        var pixels = [UInt8](repeating: 0, count: count)
        pixels.withUnsafeMutableBytes { raw in
            raw.copyMemory(from: UnsafeRawBufferPointer(start: data, count: count))
        }
        // The bitmap's first row is the bottom of the image, even though user space is flipped.
        let bufferRect = CaptureGeometry.bottomUpRect(fromTopLeft: topLeft, imageHeight: imageHeight)
        let block = max(8, min(imageWidth, imageHeight) / 80)
        MosaicBuffer.pixelate(
            pixels: &pixels,
            width: imageWidth,
            height: imageHeight,
            bytesPerRow: bytesPerRow,
            rect: bufferRect,
            block: block
        )
        pixels.withUnsafeBytes { raw in
            UnsafeMutableRawBufferPointer(start: data, count: count).copyMemory(from: raw)
        }
    }

    private static let markColor = CGColor(red: 0.90, green: 0.15, blue: 0.18, alpha: 1)

    private static func strokeBox(_ rect: CGRect, lineWidth: CGFloat, color: CGColor, in context: CGContext) {
        let rect = CaptureGeometry.normalized(rect).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard rect.width > 0, rect.height > 0 else { return }
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.miter)
        context.stroke(rect)
    }

    private static func strokeArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, color: CGColor, in context: CGContext) {
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        let headLength = max(14, lineWidth * 5)
        guard let head = ArrowGeometry.headPoints(from: from, to: to, length: headLength) else { return }
        context.beginPath()
        context.move(to: head.0)
        context.addLine(to: to)
        context.addLine(to: head.1)
        context.closePath()
        context.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor, in context: CGContext) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: max(12, fontSize), weight: .semibold)
        let textColor = NSColor(cgColor: color) ?? NSColor(srgbRed: 0.90, green: 0.15, blue: 0.18, alpha: 1)
        let text = NSAttributedString(string: trimmed, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])
        context.saveGState()
        // Core Text draws upward. Flip around the baseline so the glyphs run down the image.
        context.translateBy(x: origin.x, y: origin.y + font.pointSize)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        text.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}

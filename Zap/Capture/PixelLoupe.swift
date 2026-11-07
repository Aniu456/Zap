import AppKit

/// Samples the frozen bitmap, independently of display zoom and the overlay's tint.
struct PixelSample {
    let x: Int
    let y: Int
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init?(image: CGImage, point: CGPoint, bounds: CGRect) {
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return nil }
        x = min(image.width - 1, Int((point.x - bounds.minX) * CGFloat(image.width) / bounds.width))
        y = min(image.height - 1, Int((bounds.maxY - point.y) * CGFloat(image.height) / bounds.height))
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.setBlendMode(.copy)
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgb = data.assumingMemoryBound(to: UInt8.self)
        let a = Int(rgb[3])
        func channel(_ index: Int) -> UInt8 {
            a == 0 ? 0 : UInt8(clamping: (Int(rgb[index]) * 255 + a / 2) / a)
        }
        alpha = rgb[3]
        red = channel(0)
        green = channel(1)
        blue = channel(2)
    }

    enum Format: Int, CaseIterable {
        case hex, rgb, rgba, flutterHex, flutterDecimal
    }

    func value(_ format: Format) -> String {
        switch format {
        case .hex: return String(format: "#%02X%02X%02X", red, green, blue)
        case .rgb: return "rgb(\(red), \(green), \(blue))"
        case .rgba: return "RGBA(\(red), \(green), \(blue), \(alpha))"
        case .flutterHex: return String(format: "Color(0x%02X%02X%02X%02X)", alpha, red, green, blue)
        case .flutterDecimal: return "Color.fromARGB(\(alpha), \(red), \(green), \(blue))"
        }
    }
}

final class PixelLoupe: NSView {
    private var sample: PixelSample?
    private var preview: CGImage?
    private var previewRect = CGRect.zero
    private var format: PixelSample.Format = .hex
    private var shiftDown = false
    private weak var host: NSWindow?
    private var panel: NSPanel?

    func update(image: CGImage, in view: NSView, point: CGPoint) {
        guard let window = view.window, let screen = window.screen,
              let next = PixelSample(image: image, point: point, bounds: view.bounds) else { hide(); return }
        sample = next
        let area = CGRect(x: next.x - 13, y: next.y - 4, width: 27, height: 9)
        let cropped = area.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        preview = image.cropping(to: cropped)
        previewRect = CGRect(x: (cropped.minX - area.minX) * 9, y: 47 + (area.maxY - cropped.maxY) * 9,
                             width: cropped.width * 9, height: cropped.height * 9)
        let popup: NSPanel
        if let panel { popup = panel } else {
            popup = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 243, height: 128),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            popup.ignoresMouseEvents = true
            popup.isReleasedWhenClosed = false
            popup.hidesOnDeactivate = false
            popup.contentView = self
            panel = popup
        }
        let cursor = window.convertPoint(toScreen: view.convert(point, to: nil))
        let size = popup.frame.size
        let region = screen.frame
        let x = cursor.x + 12 + size.width <= region.maxX ? cursor.x + 12 : cursor.x - size.width - 12
        let y = cursor.y - 12 - size.height >= region.minY ? cursor.y - 12 - size.height : cursor.y + 12
        popup.setFrameOrigin(CGPoint(x: max(region.minX, min(x, region.maxX - size.width)),
                                    y: max(region.minY, min(y, region.maxY - size.height))))
        if host !== window {
            host?.removeChildWindow(popup)
            popup.level = window.level
            window.addChildWindow(popup, ordered: .above)
            host = window
        }
        needsDisplay = true
    }

    func hide() {
        if let panel {
            host?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panel = nil
        host = nil
        sample = nil
        preview = nil
        shiftDown = false
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let down = flags.contains(.shift)
        if down && !shiftDown && sample != nil {
            let formats = PixelSample.Format.allCases
            format = formats[(format.rawValue + 1) % formats.count]
            needsDisplay = true
        }
        shiftDown = down
    }

    func copyColor(_ event: NSEvent) -> Bool {
        guard let sample, event.charactersIgnoringModifiers?.lowercased() == "c",
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sample.value(format), forType: .string)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        guard let sample, let preview, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(preview, in: previewRect)
        let center = CGRect(x: 117, y: 83, width: 9, height: 9)
        NSColor.white.setStroke()
        NSBezierPath(rect: center.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.black.setStroke()
        NSBezierPath(rect: center).stroke()
        let style: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]
        (sample.value(format) as NSString).draw(at: CGPoint(x: 6, y: 30), withAttributes: style)
        ("(\(sample.x), \(sample.y))" as NSString).draw(at: CGPoint(x: 6, y: 16), withAttributes: style)
        ("C 复制颜色 · Shift 切换格式" as NSString).draw(at: CGPoint(x: 6, y: 2), withAttributes: style)
    }
}

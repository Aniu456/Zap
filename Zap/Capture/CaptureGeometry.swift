import Foundation

/// Point and pixel math for a region capture. View space is AppKit: origin at the
/// bottom-left of the screen, y grows upward. Image space matches `CGImage`:
/// origin at the top-left, y grows downward.
enum CaptureGeometry {
    struct PixelRect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int

        var isEmpty: Bool { width <= 0 || height <= 0 }
    }

    static let minimumPoints: CGFloat = 8

    static func normalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(rect.origin.x, rect.origin.x + rect.size.width),
            y: min(rect.origin.y, rect.origin.y + rect.size.height),
            width: abs(rect.size.width),
            height: abs(rect.size.height)
        )
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        let rect = normalized(rect)
        return rect.width >= minimumPoints && rect.height >= minimumPoints
    }

    static func isDrag(from start: CGPoint, to end: CGPoint, minimum: CGFloat = 4) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= minimum
    }

    /// Maps a selection in screen points onto the captured image.
    /// `screenSize` and `selection` share one space. `imageSize` is the bitmap size.
    static func cropPixels(selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> PixelRect {
        let selection = normalized(selection)
        guard screenSize.width > 0, screenSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return PixelRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        let minX = Int(floor(selection.minX * scaleX))
        let maxX = Int(ceil(selection.maxX * scaleX))
        let top = screenSize.height - selection.maxY
        let minY = Int(floor(top * scaleY))
        let maxY = Int(ceil((top + selection.height) * scaleY))
        return clamped(
            PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            imageWidth: Int(imageSize.width.rounded()),
            imageHeight: Int(imageSize.height.rounded())
        )
    }

    static func clamped(_ rect: PixelRect, imageWidth: Int, imageHeight: Int) -> PixelRect {
        guard imageWidth > 0, imageHeight > 0 else {
            return PixelRect(x: 0, y: 0, width: 0, height: 0)
        }
        let normalized = PixelRect(
            x: min(rect.x, rect.x + rect.width),
            y: min(rect.y, rect.y + rect.height),
            width: abs(rect.width),
            height: abs(rect.height)
        )
        let x0 = max(0, min(normalized.x, imageWidth))
        let y0 = max(0, min(normalized.y, imageHeight))
        let x1 = max(0, min(normalized.x + normalized.width, imageWidth))
        let y1 = max(0, min(normalized.y + normalized.height, imageHeight))
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// CGBitmapContext stores the first row at the bottom. Annotation rects use the top.
    static func bottomUpRect(fromTopLeft rect: PixelRect, imageHeight: Int) -> PixelRect {
        PixelRect(
            x: rect.x,
            y: imageHeight - (rect.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    static func cropPixel(fromViewPoint point: CGPoint, selection: CGRect, imageSize: CGSize) -> CGPoint {
        let selection = normalized(selection)
        guard selection.width > 0, selection.height > 0 else { return .zero }
        let scaleX = imageSize.width / selection.width
        let scaleY = imageSize.height / selection.height
        let localX = point.x - selection.minX
        let localYFromTop = selection.maxY - point.y
        return CGPoint(x: localX * scaleX, y: localYFromTop * scaleY)
    }

    static func viewPoint(fromCropPixel pixel: CGPoint, selection: CGRect, imageSize: CGSize) -> CGPoint {
        let selection = normalized(selection)
        guard imageSize.width > 0, imageSize.height > 0 else { return selection.origin }
        let scaleX = selection.width / imageSize.width
        let scaleY = selection.height / imageSize.height
        return CGPoint(
            x: selection.minX + pixel.x * scaleX,
            y: selection.maxY - pixel.y * scaleY
        )
    }

    static func pixelRect(from rect: CGRect, imageWidth: Int, imageHeight: Int) -> PixelRect {
        let rect = normalized(rect)
        let x = Int(floor(rect.minX))
        let y = Int(floor(rect.minY))
        let width = Int(ceil(rect.maxX)) - x
        let height = Int(ceil(rect.maxY)) - y
        return clamped(PixelRect(x: x, y: y, width: width, height: height), imageWidth: imageWidth, imageHeight: imageHeight)
    }

    /// View rect covered by an integer crop of the frozen screenshot.
    /// Drawing that crop into this rect lines up with the full image drawn in `screenSize`.
    static func viewRect(forCrop pixels: PixelRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        guard screenSize.width > 0, screenSize.height > 0, imageSize.width > 0, imageSize.height > 0,
              pixels.width > 0, pixels.height > 0 else {
            return .zero
        }
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        let x = CGFloat(pixels.x) / scaleX
        let width = CGFloat(pixels.width) / scaleX
        let top = CGFloat(pixels.y) / scaleY
        let height = CGFloat(pixels.height) / scaleY
        let y = screenSize.height - top - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Default toolbar spot: to the right of the selection, vertically centered.
    /// If that side is off-screen, try the left, then below (right-aligned), then above.
    static func toolbarOrigin(selection: CGRect, toolbarSize: CGSize, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        let minX = bounds.minX + gap
        let maxX = bounds.maxX - gap - toolbarSize.width
        var x = selection.maxX + gap
        var y = selection.midY - toolbarSize.height / 2
        let fitsRight = x >= minX && x <= maxX
        if !fitsRight {
            let left = selection.minX - gap - toolbarSize.width
            if left >= minX {
                x = left
            } else {
                x = selection.maxX - toolbarSize.width
                y = selection.minY - gap - toolbarSize.height
                if y < bounds.minY + gap {
                    y = selection.maxY + gap
                }
            }
        }
        return clampedToolbarOrigin(CGPoint(x: x, y: y), toolbarSize: toolbarSize, bounds: bounds, gap: gap)
    }

    /// Pulls a dragged toolbar back on screen without moving it when it already fits.
    static func clampedToolbarOrigin(_ origin: CGPoint, toolbarSize: CGSize, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        let minX = bounds.minX + gap
        let minY = bounds.minY + gap
        let maxX = max(minX, bounds.maxX - gap - toolbarSize.width)
        let maxY = max(minY, bounds.maxY - gap - toolbarSize.height)
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}

enum ArrowGeometry {
    /// Returns the two base points of an arrow head. `to` is the tip.
    static func headPoints(from: CGPoint, to: CGPoint, length: CGFloat = 16, degrees: CGFloat = 28) -> (CGPoint, CGPoint)? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = hypot(dx, dy)
        guard distance > 0.5 else { return nil }
        let angle = atan2(dy, dx)
        let spread = degrees * .pi / 180
        let left = CGPoint(
            x: to.x - length * cos(angle - spread),
            y: to.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: to.x - length * cos(angle + spread),
            y: to.y - length * sin(angle + spread)
        )
        return (left, right)
    }
}

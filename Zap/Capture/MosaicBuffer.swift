import Foundation

/// Pixelates an RGBA8 buffer. Row 0 is the top of the image. `bytesPerRow` may include padding.
enum MosaicBuffer {
    static func pixelate(
        pixels: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        rect: CaptureGeometry.PixelRect,
        block: Int
    ) {
        guard width > 0, height > 0, block > 0, bytesPerRow >= width * 4 else { return }
        guard pixels.count >= bytesPerRow * height else { return }
        let area = CaptureGeometry.clamped(rect, imageWidth: width, imageHeight: height)
        guard !area.isEmpty else { return }

        var y = area.y
        while y < area.y + area.height {
            let blockHeight = min(block, area.y + area.height - y)
            var x = area.x
            while x < area.x + area.width {
                let blockWidth = min(block, area.x + area.width - x)
                var sum = [Int](repeating: 0, count: 4)
                var count = 0
                for row in y..<(y + blockHeight) {
                    let rowStart = row * bytesPerRow + x * 4
                    for column in 0..<blockWidth {
                        let index = rowStart + column * 4
                        sum[0] += Int(pixels[index])
                        sum[1] += Int(pixels[index + 1])
                        sum[2] += Int(pixels[index + 2])
                        sum[3] += Int(pixels[index + 3])
                        count += 1
                    }
                }
                guard count > 0 else { break }
                let average = sum.map { UInt8($0 / count) }
                for row in y..<(y + blockHeight) {
                    let rowStart = row * bytesPerRow + x * 4
                    for column in 0..<blockWidth {
                        let index = rowStart + column * 4
                        pixels[index] = average[0]
                        pixels[index + 1] = average[1]
                        pixels[index + 2] = average[2]
                        pixels[index + 3] = average[3]
                    }
                }
                x += blockWidth
            }
            y += blockHeight
        }
    }
}

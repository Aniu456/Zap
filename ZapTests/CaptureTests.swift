import CoreGraphics
import XCTest
@testable import Zap

final class WindowSpacesTests: XCTestCase {
    func testOverlayDoesNotUseTheMacOS26CrashCombination() {
        let behavior = WindowSpaces.overlay
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.stationary))
    }

    func testSanitizerDropsMoveToActiveSpaceWhenJoiningAllSpaces() {
        let behavior = WindowSpaces.sanitized([
            .canJoinAllSpaces,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ])
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.stationary))
    }
}

final class CaptureGeometryTests: XCTestCase {
    func testNormalizedRectIgnoresDragDirection() {
        let forward = CGRect(x: 10, y: 20, width: 30, height: 40)
        let backward = CGRect(x: 40, y: 60, width: -30, height: -40)
        XCTAssertEqual(CaptureGeometry.normalized(forward), CaptureGeometry.normalized(backward))
    }

    func testTinySelectionIsNotUsable() {
        XCTAssertFalse(CaptureGeometry.isUsable(CGRect(x: 0, y: 0, width: 7, height: 40)))
        XCTAssertTrue(CaptureGeometry.isUsable(CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    func testCropPixelsFlipsAppKitYAndScales() {
        let selection = CGRect(x: 10, y: 20, width: 30, height: 10)
        let pixels = CaptureGeometry.cropPixels(
            selection: selection,
            screenSize: CGSize(width: 100, height: 80),
            imageSize: CGSize(width: 200, height: 160)
        )
        XCTAssertEqual(pixels, CaptureGeometry.PixelRect(x: 20, y: 100, width: 60, height: 20))
    }

    func testCropPixelsClampsToTheImage() {
        let pixels = CaptureGeometry.cropPixels(
            selection: CGRect(x: -10, y: -10, width: 50, height: 40),
            screenSize: CGSize(width: 100, height: 80),
            imageSize: CGSize(width: 100, height: 80)
        )
        XCTAssertEqual(pixels.x, 0)
        XCTAssertGreaterThan(pixels.width, 0)
        XCTAssertLessThanOrEqual(pixels.x + pixels.width, 100)
        XCTAssertLessThanOrEqual(pixels.y + pixels.height, 80)
    }

    func testViewAndPixelRoundTrip() {
        let selection = CGRect(x: 10, y: 20, width: 40, height: 30)
        let imageSize = CGSize(width: 80, height: 60)
        let corners = [
            CGPoint(x: 10, y: 50),
            CGPoint(x: 50, y: 20),
            CGPoint(x: 30, y: 35)
        ]
        for point in corners {
            let pixel = CaptureGeometry.cropPixel(fromViewPoint: point, selection: selection, imageSize: imageSize)
            let back = CaptureGeometry.viewPoint(fromCropPixel: pixel, selection: selection, imageSize: imageSize)
            XCTAssertEqual(back.x, point.x, accuracy: 0.001)
            XCTAssertEqual(back.y, point.y, accuracy: 0.001)
        }
    }

    func testBottomUpRectMovesTheTopToTheBufferBottom() {
        let rect = CaptureGeometry.PixelRect(x: 2, y: 10, width: 4, height: 20)
        let flipped = CaptureGeometry.bottomUpRect(fromTopLeft: rect, imageHeight: 100)
        XCTAssertEqual(flipped, CaptureGeometry.PixelRect(x: 2, y: 70, width: 4, height: 20))
    }

    func testToolbarSitsOnTheBottomRightEdge() {
        let origin = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 40, y: 100, width: 200, height: 80),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(origin, CGPoint(x: 120, y: 49))
        XCTAssertEqual(origin.x + 120, 240, accuracy: 0.001)
        XCTAssertEqual(origin.y + 44 + 7, 100, accuracy: 0.001)
    }

    func testToolbarWiderThanTheSelectionStaysRightAligned() {
        let origin = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 100, y: 100, width: 50, height: 40),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(origin.x + 120, 150, accuracy: 0.001)
        XCTAssertEqual(origin.y + 44 + 7, 100, accuracy: 0.001)
    }

    func testBottomRightToolbarIsPulledBackOntoTheScreen() {
        let origin = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 40, y: 10, width: 200, height: 80),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(origin, CGPoint(x: 120, y: 97))
    }

    func testFullScreenSelectionKeepsToolbarInsideAndFlushRight() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 300)
        let size = CGSize(width: 410, height: 32)
        let origin = CaptureGeometry.toolbarOrigin(selection: bounds, toolbarSize: size, bounds: bounds)
        XCTAssertEqual(origin, CGPoint(x: 90, y: 7))
    }

    func testDraggedToolbarStaysPutUntilItWouldLeaveTheScreen() {
        let size = CGSize(width: 120, height: 44)
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let parked = CaptureGeometry.clampedToolbarOrigin(CGPoint(x: 40, y: 40), toolbarSize: size, bounds: bounds)
        XCTAssertEqual(parked, CGPoint(x: 40, y: 40))

        let clipped = CaptureGeometry.clampedToolbarOrigin(CGPoint(x: -40, y: 500), toolbarSize: size, bounds: bounds)
        XCTAssertEqual(clipped, CGPoint(x: 8, y: 248))
    }

    func testCropViewRectLinesUpWithAnAlignedSelection() {
        let selection = CGRect(x: 10, y: 20, width: 30, height: 10)
        let screen = CGSize(width: 100, height: 80)
        let image = CGSize(width: 200, height: 160)
        let pixels = CaptureGeometry.cropPixels(selection: selection, screenSize: screen, imageSize: image)
        let frame = CaptureGeometry.viewRect(forCrop: pixels, screenSize: screen, imageSize: image)
        XCTAssertEqual(frame.origin.x, selection.origin.x, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, selection.origin.y, accuracy: 0.001)
        XCTAssertEqual(frame.width, selection.width, accuracy: 0.001)
        XCTAssertEqual(frame.height, selection.height, accuracy: 0.001)
    }
}

final class ArrowGeometryTests: XCTestCase {
    func testHeadSitsBehindARightwardTip() {
        let head = ArrowGeometry.headPoints(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 0), length: 4, degrees: 28)
        XCTAssertNotNil(head)
        XCTAssertLessThan(head!.0.x, 10)
        XCTAssertLessThan(head!.1.x, 10)
        XCTAssertGreaterThan(head!.0.y, 0)
        XCTAssertLessThan(head!.1.y, 0)
        XCTAssertEqual(head!.0.y, -head!.1.y, accuracy: 0.001)
    }

    func testZeroLengthArrowHasNoHead() {
        XCTAssertNil(ArrowGeometry.headPoints(from: CGPoint(x: 3, y: 3), to: CGPoint(x: 3, y: 3)))
    }
}

final class MosaicBufferTests: XCTestCase {
    func testDirectBufferPreservesRowPadding() {
        var pixels: [UInt8] = [
            10, 20, 30, 255, 30, 40, 50, 255, 99, 98, 97, 96,
            50, 60, 70, 255, 70, 80, 90, 255, 95, 94, 93, 92
        ]
        pixels.withUnsafeMutableBufferPointer { buffer in
            MosaicBuffer.pixelate(
                pixels: buffer,
                width: 2,
                height: 2,
                bytesPerRow: 12,
                rect: CaptureGeometry.PixelRect(x: 0, y: 0, width: 2, height: 2),
                block: 2
            )
        }
        XCTAssertEqual(pixels, [
            40, 50, 60, 255, 40, 50, 60, 255, 99, 98, 97, 96,
            40, 50, 60, 255, 40, 50, 60, 255, 95, 94, 93, 92
        ])
    }

    func testBlockAverageFillsTheRect() {
        var pixels: [UInt8] = [
            255, 0, 0, 255, 0, 0, 255, 255,
            0, 0, 0, 255, 0, 255, 0, 255
        ]
        MosaicBuffer.pixelate(
            pixels: &pixels,
            width: 2,
            height: 2,
            bytesPerRow: 8,
            rect: CaptureGeometry.PixelRect(x: 0, y: 0, width: 2, height: 2),
            block: 2
        )
        let expected: [UInt8] = [63, 63, 63, 255]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            XCTAssertEqual(Array(pixels[index..<(index + 4)]), expected)
        }
    }

    func testPartialBlockLeavesPixelsOutsideTheRect() {
        var pixels = [UInt8](repeating: 0, count: 16)
        pixels[0] = 10
        pixels[1] = 20
        pixels[2] = 30
        pixels[3] = 255
        MosaicBuffer.pixelate(
            pixels: &pixels,
            width: 2,
            height: 2,
            bytesPerRow: 8,
            rect: CaptureGeometry.PixelRect(x: 0, y: 0, width: 1, height: 1),
            block: 4
        )
        XCTAssertEqual(Array(pixels[0..<4]), [10, 20, 30, 255])
        XCTAssertEqual(pixels[4], 0)
    }

    func testOutOfBoundsRectIsIgnored() {
        var pixels: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let original = pixels
        MosaicBuffer.pixelate(
            pixels: &pixels,
            width: 2,
            height: 1,
            bytesPerRow: 8,
            rect: CaptureGeometry.PixelRect(x: 9, y: 9, width: 2, height: 2),
            block: 2
        )
        XCTAssertEqual(pixels, original)
    }
}

final class CaptureRendererOrientationTests: XCTestCase {
    func testEmptyMarksKeepTheSameImage() {
        let image = makeImage(width: 2, height: 2) { _, _ in (10, 20, 30, 255) }
        let rendered = CaptureRenderer.render(base: image, marks: [])
        XCTAssertTrue(rendered === image)
    }

    func testAnnotationsDoNotFlipTheScreenshot() {
        let image = makeImage(width: 8, height: 8) { _, y in
            y == 0 ? (255, 0, 0, 255) : (0, 0, 255, 255)
        }
        let rendered = CaptureRenderer.render(
            base: image,
            marks: [.box(CGRect(x: 3, y: 3, width: 2, height: 2))]
        )
        let top = sample(rendered, x: 0, yFromTop: 0)
        let bottom = sample(rendered, x: 0, yFromTop: 7)
        XCTAssertNotNil(top)
        XCTAssertNotNil(bottom)
        XCTAssertGreaterThan(top!.0, 200)
        XCTAssertLessThan(top!.2, 40)
        XCTAssertLessThan(bottom!.0, 40)
        XCTAssertGreaterThan(bottom!.2, 200)
    }

    func testMosaicStaysInTheTopLeftOfAnUprightImage() {
        let image = makeImage(width: 8, height: 8) { x, y in
            (UInt8(x * 30), UInt8(y * 30), 0, 255)
        }
        let rendered = CaptureRenderer.render(
            base: image,
            marks: [.mosaic(CGRect(x: 0, y: 0, width: 4, height: 4))]
        )
        let topLeft = sample(rendered, x: 0, yFromTop: 0)
        let bottomLeft = sample(rendered, x: 0, yFromTop: 7)
        XCTAssertNotNil(topLeft)
        XCTAssertNotNil(bottomLeft)
        XCTAssertGreaterThan(Int(topLeft!.0) + Int(topLeft!.1), 0)
        XCTAssertEqual(bottomLeft!.0, 0)
        XCTAssertGreaterThan(bottomLeft!.1, 180)
    }

    private func makeImage(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = fill(x, y)
                let index = (y * width + x) * 4
                bytes[index] = pixel.0
                bytes[index + 1] = pixel.1
                bytes[index + 2] = pixel.2
                bytes[index + 3] = pixel.3
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func sample(_ image: CGImage?, x: Int, yFromTop: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let image, image.bitsPerPixel >= 32, let data = image.dataProvider?.data else { return nil }
        let length = CFDataGetLength(data)
        guard let pointer = CFDataGetBytePtr(data) else { return nil }
        let offset = yFromTop * image.bytesPerRow + x * 4
        guard offset >= 0, offset + 3 < length else { return nil }
        return (pointer[offset], pointer[offset + 1], pointer[offset + 2], pointer[offset + 3])
    }
}

final class PixelSampleTests: XCTestCase {
    func testSamplingScaledImageAndFormattingFlutterAlpha() throws {
        // Top-left pixel is half-transparent red. Bottom-left is opaque green.
        let bytes: [UInt8] = [128, 0, 0, 128, 0, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        let red = try XCTUnwrap(PixelSample(image: image, point: CGPoint(x: 1, y: 5), bounds: bounds))
        XCTAssertEqual(red.value(.hex), "#FF0000")
        XCTAssertEqual(red.value(.rgba), "RGBA(255, 0, 0, 128)")
        XCTAssertEqual(red.value(.flutterHex), "Color(0x80FF0000)")
        XCTAssertEqual(red.value(.flutterDecimal), "Color.fromARGB(128, 255, 0, 0)")
        let green = try XCTUnwrap(PixelSample(image: image, point: CGPoint(x: 1, y: 1), bounds: bounds))
        XCTAssertEqual(green.value(.rgb), "rgb(0, 255, 0)")
    }
}

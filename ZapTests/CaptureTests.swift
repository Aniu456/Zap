import XCTest
@testable import Zap

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

    func testToolbarPrefersTheSpaceBelowAndStaysOnScreen() {
        let below = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 20, y: 80, width: 100, height: 40),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(below, CGPoint(x: 20, y: 28))

        let above = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 20, y: 4, width: 100, height: 40),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertEqual(above.y, 52, accuracy: 0.001)

        let shifted = CaptureGeometry.toolbarOrigin(
            selection: CGRect(x: 360, y: 80, width: 30, height: 40),
            toolbarSize: CGSize(width: 120, height: 44),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertLessThanOrEqual(shifted.x + 120, 392)
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

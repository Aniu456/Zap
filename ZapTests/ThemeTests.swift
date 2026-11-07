import AppKit
import XCTest
@testable import Zap

final class ZapThemeTests: XCTestCase {
    func testMuseIsBlackWhiteWithABlueAccent() {
        let lightPage = ZapSwatch.muse(.background, dark: false)
        let darkPage = ZapSwatch.muse(.background, dark: true)
        XCTAssertGreaterThan(lightPage.r, 0.94)
        XCTAssertGreaterThan(lightPage.g, 0.94)
        XCTAssertGreaterThan(lightPage.b, 0.94)
        XCTAssertLessThan(darkPage.r, 0.12)
        XCTAssertLessThan(darkPage.g, 0.12)
        XCTAssertLessThan(darkPage.b, 0.12)
        for dark in [false, true] {
            let accent = ZapSwatch.muse(.accent, dark: dark)
            XCTAssertGreaterThan(accent.b, accent.r)
            XCTAssertGreaterThan(accent.b, accent.g)
            XCTAssertFalse(ZapSwatch.muse(.selection, dark: dark).isYellow)
            XCTAssertFalse(ZapSwatch.muse(.background, dark: dark).isYellow)
        }
    }
}

final class PaletteAppearanceTests: XCTestCase {
    @MainActor func testMuseWindowCorners() async throws {
        defer { PaletteController.shared.hide() }
        for mode in [PaletteMode.launcher, .clipboard] {
            PaletteController.shared.show(mode)
            try await Task.sleep(for: .milliseconds(200))
            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PalettePanel })
            let view = try XCTUnwrap(panel.contentView)
            let layer = try XCTUnwrap(view.layer)
            let scale = panel.backingScaleFactor
            let width = Int(view.bounds.width * scale)
            let height = Int(view.bounds.height * scale)
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            let image = try XCTUnwrap(context.makeImage())
            let bitmap = NSBitmapImageRep(cgImage: image)
            let alphas = [0, image.width - 1].flatMap { x in
                [0, image.height - 1].compactMap { bitmap.colorAt(x: x, y: $0)?.alphaComponent }
            }
            XCTAssertEqual(alphas, [0, 0, 0, 0])
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: image.width / 2, y: 10)).alphaComponent, 0.95)
            XCTAssertTrue(panel.firstResponder is NSTextView)
            PaletteController.shared.hide()
        }
    }
}

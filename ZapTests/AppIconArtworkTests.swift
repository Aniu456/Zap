import AppKit
import XCTest
@testable import Zap

final class AppIconArtworkTests: XCTestCase {
    func testBundledArtworkIsTheLightningIcon() throws {
        let image = try XCTUnwrap(AppIconArtwork.bundledImage())
        XCTAssertFalse(image.isTemplate)
        let rep = try XCTUnwrap(bitmap(of: image))
        XCTAssertGreaterThanOrEqual(rep.pixelsWide, 256)
        let center = try components(try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)))
        // Bright yellow bolt. The generic document glyph is white or empty here.
        XCTAssertGreaterThan(center.r, 0.75)
        XCTAssertGreaterThan(center.g, 0.55)
        XCTAssertLessThan(center.b, 0.5)
        XCTAssertGreaterThan(center.a, 0.9)
        let corner = try components(try XCTUnwrap(rep.colorAt(x: 1, y: 1)))
        XCTAssertLessThan(corner.r, 0.25)
        XCTAssertLessThan(corner.g, 0.25)
        XCTAssertLessThan(corner.b, 0.4)
        XCTAssertGreaterThan(corner.a, 0.9)
    }

    func testSettingsImageIsThatBitmap() throws {
        let bundled = try XCTUnwrap(AppIconArtwork.bundledImage())
        XCTAssertTrue(AppIconArtwork.image() === bundled)
    }

    @MainActor
    func testInstallReplacesTheAccessoryPlaceholder() throws {
        AppIconArtwork.install()
        let installed = try XCTUnwrap(NSApp.applicationIconImage)
        let rep = try XCTUnwrap(bitmap(of: installed))
        let center = try components(try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)))
        XCTAssertGreaterThan(center.r, 0.75)
        XCTAssertGreaterThan(center.g, 0.55)
        XCTAssertLessThan(center.b, 0.5)
    }

    private func bitmap(of image: NSImage) -> NSBitmapImageRep? {
        if let direct = image.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: { $0.pixelsWide < $1.pixelsWide }) {
            return direct
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private func components(_ color: NSColor) throws -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

import AppKit
import XCTest
@testable import Zap

@MainActor
final class PinEditingTests: XCTestCase {
    func testContextMenuCombinesPinControlsAndSelectedEditingActions() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let base = try XCTUnwrap(bitmap.cgImage)
        let mark = CaptureMark.box(CGRect(x: 12, y: 10, width: 16, height: 18))
        let frame = NSRect(x: 75, y: 90, width: 100, height: 50)
        let snapshot = CaptureSession.PinSnapshot(image: NSImage(cgImage: base, size: frame.size),
                                                  base: base, marks: [mark], undo: [[]], redo: [])
        let pin = PinWindowController(snapshot: snapshot, screenFrame: frame)
        defer { pin.close() }

        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
            location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
            windowNumber: pin.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(pin.window.contentView?.menu(for: event))
        func choose(_ title: String) throws {
            menu.delegate?.menuNeedsUpdate?(menu)
            let item = try XCTUnwrap(menu.item(withTitle: title))
            XCTAssertTrue(item.isEnabled)
            XCTAssertFalse(item.isHidden)
            menu.performActionForItem(at: menu.index(of: item))
        }
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }.map(\.title),
                       ["放大", "缩小", "恢复原始大小（100%）", "取色器", L10n.toolBox, L10n.toolArrow,
                        L10n.toolText, L10n.toolMosaic, L10n.undo, L10n.redo, L10n.copyCapture,
                        L10n.saveCapture, L10n.closePin])
        try choose(L10n.toolBox)
        let canvas = try XCTUnwrap(pin.window.contentView as? CaptureOverlayView)
        XCTAssertTrue(canvas.menu(for: event) === menu)
        XCTAssertFalse(canvas.subviews.contains { $0 is CaptureToolbar })
        XCTAssertFalse(pin.window.childWindows?.contains { $0.contentView is CaptureToolbar } ?? false)
        try choose(L10n.undo)
        XCTAssertEqual(canvas.session?.canvasState(for: canvas.displayID)?.marks, [])
        try choose("完成标注")
        XCTAssertTrue(pin.window.contentView is PinContentView)
        try choose(L10n.redo)
        let edited = try XCTUnwrap(pin.window.contentView as? CaptureOverlayView)
        XCTAssertEqual(edited.session?.canvasState(for: edited.displayID)?.marks, [mark])
        try choose("放大")
        XCTAssertGreaterThan(pin.window.frame.width, frame.width)
        XCTAssertTrue(pin.window.contentView is PinContentView)
        try choose("取色器")
        XCTAssertEqual((pin.window.contentView as? PinContentView)?.picking, true)
    }
}

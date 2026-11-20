import AppKit
import XCTest
@testable import Zap

@MainActor
final class CaptureTextMovementTests: XCTestCase {
    func testEditorMovementStaysInsideSelection() {
        let bounds = CGRect(x: 20, y: 30, width: 300, height: 200)
        let editor = CaptureTextEditor(frame: CGRect(x: 40, y: 50, width: 240, height: 28), movementBounds: bounds)
        editor.move(by: CGPoint(x: -1000, y: -1000))
        XCTAssertEqual(editor.frame.origin, bounds.origin)
        editor.move(by: CGPoint(x: 1000, y: 1000))
        XCTAssertEqual(editor.frame.maxX, bounds.maxX)
        XCTAssertEqual(editor.frame.maxY, bounds.maxY)
    }

    func testCommittedTextMovesInCropCoordinatesAndUndoRestoresIt() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 800, pixelsHigh: 500, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let shot = ScreenGrabber.Shot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 250),
                                      image: try XCTUnwrap(bitmap.cgImage))
        let session = CaptureSession(shots: [shot]) { _ in }
        session.begin()
        defer { session.cancel() }
        let presented = expectation(description: "presented")
        DispatchQueue.main.async { presented.fulfill() }
        await fulfillment(of: [presented], timeout: 2)
        session.mouseDown(displayID: 1, point: CGPoint(x: 20, y: 20))
        session.mouseUp(displayID: 1, point: CGPoint(x: 300, y: 200))
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        session.keyDown(try key("3", code: 20))
        session.mouseDown(displayID: 1, point: CGPoint(x: 80, y: 140))
        let view = try XCTUnwrap(NSApp.windows.compactMap { $0.contentView as? CaptureOverlayView }
            .first { $0.session === session })
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? CaptureTextEditor }.first)
        editor.field.stringValue = "测试 abc"
        let window = try XCTUnwrap(view.window)
        let responder = window.firstResponder
        let grip = try XCTUnwrap(editor.subviews.first { $0 !== editor.field })
        let gripPoint = grip.convert(CGPoint(x: grip.bounds.midX, y: grip.bounds.midY), to: nil)
        let originalFrame = editor.frame
        func mouse(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        window.sendEvent(try mouse(.leftMouseDown, gripPoint))
        let gripEnd = CGPoint(x: gripPoint.x, y: gripPoint.y - 10)
        window.sendEvent(try mouse(.leftMouseDragged, gripEnd))
        window.sendEvent(try mouse(.leftMouseUp, gripEnd))
        XCTAssertEqual(editor.frame.minY, originalFrame.minY - 10, accuracy: 0.01)
        XCTAssertTrue(window.firstResponder === responder)
        XCTAssertEqual(editor.field.stringValue, "测试 abc")
        let expectedTopLeft = editor.field.convert(CGPoint(x: 0, y: editor.field.bounds.maxY), to: view)
        XCTAssertTrue(session.control(editor.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let initial = try XCTUnwrap(session.canvasState(for: 1))
        let mark = try XCTUnwrap(initial.marks.first)
        guard case .text(_, let origin, _) = mark else { return XCTFail("Missing text") }
        let selection = try XCTUnwrap(initial.selection)
        let size = try XCTUnwrap(initial.cropSize)
        let topLeft = CaptureGeometry.viewPoint(fromCropPixel: origin, selection: selection, imageSize: size)
        XCTAssertEqual(topLeft.x, expectedTopLeft.x, accuracy: 0.01)
        XCTAssertEqual(topLeft.y, expectedTopLeft.y, accuracy: 0.01)
        let down = CGPoint(x: topLeft.x + 10, y: topLeft.y - 8)
        session.mouseDown(displayID: 1, point: down)
        session.mouseDragged(displayID: 1, point: CGPoint(x: down.x + 10, y: down.y - 5))
        session.mouseUp(displayID: 1, point: CGPoint(x: down.x + 25, y: down.y - 15))
        let moved = try XCTUnwrap(session.canvasState(for: 1)?.marks.first)
        guard case .text(_, let movedOrigin, _) = moved else { return XCTFail("Missing moved text") }
        XCTAssertEqual(movedOrigin.x, origin.x + 50, accuracy: 0.01)
        XCTAssertEqual(movedOrigin.y, origin.y + 30, accuracy: 0.01)
        session.keyDown(try key("z", code: 6, modifiers: .command))
        XCTAssertEqual(session.canvasState(for: 1)?.marks, initial.marks)
        session.keyDown(try key("z", code: 6, modifiers: [.command, .shift]))
        XCTAssertEqual(session.canvasState(for: 1)?.marks.first, moved)
    }
}

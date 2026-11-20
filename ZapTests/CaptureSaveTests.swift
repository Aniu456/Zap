import AppKit
import XCTest
@testable import Zap

@MainActor
final class CaptureSaveTests: XCTestCase {
    private func makeSession(choose: @escaping (String) -> URL?,
                             finish: @escaping (CaptureSession.Outcome?) -> Void) async throws -> (CaptureSession, NSWindow) {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let shot = ScreenGrabber.Shot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 320, height: 180),
                                      image: try XCTUnwrap(bitmap.cgImage))
        let session = CaptureSession(shots: [shot], chooseSaveURL: choose, onFinish: finish)
        session.begin()
        let presented = expectation(description: "presented")
        DispatchQueue.main.async { presented.fulfill() }
        await fulfillment(of: [presented], timeout: 2)
        let window = try XCTUnwrap(NSApp.windows.first { ($0.contentView as? CaptureOverlayView)?.session === session })
        session.mouseDown(displayID: 1, point: CGPoint(x: 20, y: 20))
        session.mouseUp(displayID: 1, point: CGPoint(x: 220, y: 140))
        return (session, window)
    }

    private func save(_ session: CaptureSession) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1))
        session.keyDown(event)
    }

    func testSuccessfulSaveWritesPNGAndClosesSessionOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        var saved = 0
        var calls = 0
        let (session, window) = try await makeSession(choose: { _ in calls += 1; return url }) {
            if case .saved? = $0 { saved += 1 }
        }
        defer { session.cancel() }
        try save(session)
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        XCTAssertEqual(image.pixelsWide, 200)
        XCTAssertEqual(image.pixelsHigh, 120)
        XCTAssertEqual(saved, 1)
        XCTAssertFalse(window.isVisible)
        try save(session)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(saved, 1)
    }

    func testCancelledSaveKeepsSelectionAndWindow() async throws {
        var completions = 0
        let (session, window) = try await makeSession(choose: { _ in nil }) { _ in completions += 1 }
        defer { session.cancel() }
        let selection = session.canvasState(for: 1)?.selection
        try save(session)
        XCTAssertEqual(completions, 0)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertEqual(session.canvasState(for: 1)?.selection, selection)
    }

    func testFailedSaveKeepsEditorAndAllowsRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("capture.png")
        defer { try? FileManager.default.removeItem(at: root) }
        var saved = 0
        let (session, window) = try await makeSession(choose: { _ in url }) {
            if case .saved? = $0 { saved += 1 }
        }
        defer { session.cancel() }
        try save(session)
        XCTAssertEqual(saved, 0)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.level, .screenSaver)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try save(session)
        XCTAssertEqual(saved, 1)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

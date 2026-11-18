import AppKit
import XCTest
@testable import Zap

@MainActor
final class CaptureLifecycleTests: XCTestCase {
    @MainActor
    private final class DeferredCapture {
        var pending: [CheckedContinuation<[ScreenGrabber.Shot], Error>] = []
        var onRequest: (() -> Void)?
        var onReturn: (() -> Void)?
        var observedCancellation = false

        func capture() async throws -> [ScreenGrabber.Shot] {
            defer {
                observedCancellation = Task.isCancelled
                onReturn?()
            }
            return try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                onRequest?()
            }
        }
    }

    @MainActor
    private final class Presentation: CapturePresenting {
        let completion: (CaptureSession.Outcome?) -> Void
        var begins = 0
        var cancels = 0
        var onBegin: (() -> Void)?
        init(completion: @escaping (CaptureSession.Outcome?) -> Void) { self.completion = completion }
        func begin() { begins += 1; onBegin?() }
        func cancel() { cancels += 1; completion(nil) }
    }

    @MainActor
    private final class Harness {
        let source = DeferredCapture()
        var sessions: [Presentation] = []
        var failures = 0
        var outcomes = 0
        var onPresent: (() -> Void)?
        var prepare: () throws -> Void = {}
        lazy var coordinator = CaptureCoordinator(
            prepare: { [unowned self] in try prepare() },
            capture: { [source] in try await source.capture() },
            makePresentation: { [unowned self] _, completion in
                let session = Presentation(completion: completion)
                session.onBegin = { [weak self] in self?.onPresent?() }
                sessions.append(session)
                return session
            },
            onOutcome: { [unowned self] _ in outcomes += 1 },
            onFailure: { [unowned self] _ in failures += 1 }
        )
    }

    private func shot() throws -> ScreenGrabber.Shot {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return ScreenGrabber.Shot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 40, height: 30),
                                  image: try XCTUnwrap(bitmap.cgImage))
    }

    private func start(_ harness: Harness) async {
        let requested = expectation(description: "capture requested")
        harness.source.onRequest = { requested.fulfill() }
        harness.coordinator.begin()
        await fulfillment(of: [requested], timeout: 2)
        harness.source.onRequest = nil
    }

    private func present(_ harness: Harness, request: Int = 0) async throws {
        let shown = expectation(description: "presentation begun")
        harness.onPresent = { shown.fulfill() }
        harness.source.pending[request].resume(returning: [try shot()])
        await fulfillment(of: [shown], timeout: 2)
        harness.onPresent = nil
    }

    func testRepeatedBeginJoinsAcquisitionAndVisibleSession() async throws {
        let h = Harness()
        await start(h)
        let state = h.coordinator.state
        h.coordinator.begin()
        XCTAssertEqual(h.coordinator.state, state)
        XCTAssertEqual(h.source.pending.count, 1)
        try await present(h)
        h.coordinator.begin()
        XCTAssertEqual(h.sessions.count, 1)
        XCTAssertEqual(h.sessions[0].begins, 1)
        h.coordinator.cancel()
        XCTAssertEqual(h.sessions[0].cancels, 1)
        XCTAssertEqual(h.coordinator.state, .idle)
    }

    func testCancelledAcquisitionCannotPresentOverNewSession() async throws {
        let h = Harness()
        await start(h)
        h.coordinator.cancel()
        await start(h)
        try await present(h, request: 1)
        let active = h.coordinator.state
        let returned = expectation(description: "old acquisition returned")
        h.source.onReturn = { returned.fulfill() }
        h.source.pending[0].resume(returning: [try shot()])
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertTrue(h.source.observedCancellation)
        XCTAssertEqual(h.coordinator.state, active)
        XCTAssertEqual(h.sessions.count, 1)
        XCTAssertEqual(h.failures, 0)
        h.coordinator.cancel()
    }

    func testOldFailureCannotResetNewAcquisition() async throws {
        let h = Harness()
        await start(h)
        h.coordinator.cancel()
        await start(h)
        let active = h.coordinator.state
        let returned = expectation(description: "old failure returned")
        h.source.onReturn = { returned.fulfill() }
        h.source.pending[0].resume(throwing: ScreenGrabber.CaptureError.noDisplays)
        await fulfillment(of: [returned], timeout: 2)
        h.source.onReturn = nil
        XCTAssertEqual(h.coordinator.state, active)
        XCTAssertEqual(h.failures, 0)
        try await present(h, request: 1)
        h.coordinator.cancel()
    }

    func testLateAndDuplicateSessionCompletionsCannotFinishNewSession() async throws {
        let h = Harness()
        await start(h)
        try await present(h)
        let retired = h.sessions[0]
        h.coordinator.cancel()
        await start(h)
        try await present(h, request: 1)
        let active = h.coordinator.state
        retired.completion(.colorCopied)
        retired.completion(nil)
        XCTAssertEqual(h.coordinator.state, active)
        XCTAssertEqual(h.outcomes, 0)
        h.sessions[1].completion(.colorCopied)
        h.sessions[1].completion(.colorCopied)
        XCTAssertEqual(h.outcomes, 1)
        XCTAssertEqual(h.coordinator.state, .idle)
    }

    func testPermissionFailureDoesNotStartAcquisition() {
        let h = Harness()
        h.prepare = { throw ScreenGrabber.CaptureError.noDisplays }
        h.coordinator.begin()
        XCTAssertEqual(h.coordinator.state, .idle)
        XCTAssertEqual(h.failures, 1)
        XCTAssertTrue(h.source.pending.isEmpty)
    }

    func testImmediateCancellationDoesNotStartCaptureService() async {
        let h = Harness()
        h.coordinator.begin()
        h.coordinator.cancel()
        let drained = expectation(description: "cancelled task scheduled")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(h.source.pending.isEmpty)
        XCTAssertEqual(h.failures, 0)
        XCTAssertEqual(h.coordinator.state, .idle)
    }

    func testEmptyAcquisitionReportsFailureWithoutShowingWindow() async {
        let h = Harness()
        await start(h)
        let returned = expectation(description: "empty acquisition returned")
        h.source.onReturn = { returned.fulfill() }
        h.source.pending[0].resume(returning: [])
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(h.coordinator.state, .idle)
        XCTAssertEqual(h.failures, 1)
        XCTAssertTrue(h.sessions.isEmpty)
    }

    func testCancelBeforeDeferredPresentationCannotResurrectWindows() async throws {
        var completions = 0
        let session = CaptureSession(shots: [try shot()]) { _ in completions += 1 }
        session.begin()
        let windows = NSApp.windows.filter { ($0.contentView as? CaptureOverlayView)?.session === session }
        XCTAssertEqual(windows.count, 1)
        XCTAssertFalse(windows[0].isVisible)
        session.cancel()
        session.begin()
        session.cancel()
        let drained = expectation(description: "presentation event drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible && $0.contentView == nil })
    }

    func testOldWindowCleanupDoesNotRemoveReplacementAndEscapeFinishesOnce() async throws {
        let old = CaptureSession(shots: [try shot()]) { _ in }
        old.begin()
        let retired = NSApp.windows.filter { ($0.contentView as? CaptureOverlayView)?.session === old }
        old.cancel()
        var completions = 0
        let replacement = CaptureSession(shots: [try shot()]) { _ in completions += 1 }
        replacement.begin()
        defer { replacement.cancel() }
        let presented = expectation(description: "replacement presented")
        DispatchQueue.main.async { presented.fulfill() }
        await fulfillment(of: [presented], timeout: 2)
        XCTAssertTrue(retired.allSatisfy { !$0.isVisible && $0.contentView == nil })
        let view = try XCTUnwrap(NSApp.windows.compactMap { $0.contentView as? CaptureOverlayView }
            .first { $0.session === replacement })
        let window = try XCTUnwrap(view.window)
        XCTAssertTrue(window.isVisible)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        window.sendEvent(escape)
        replacement.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(window.isVisible)
    }
}

import Foundation

@MainActor
protocol CapturePresenting: AnyObject {
    func begin()
    func cancel()
}

/// Owns one request from acquisition through presentation. UI and capture services
/// are injected so cancellation and late callbacks can be tested without the desktop.
@MainActor
final class CaptureCoordinator {
    enum State: Equatable {
        case idle
        case acquiring(UUID)
        case presenting(UUID)
    }

    private(set) var state: State = .idle
    var isActive: Bool { state != .idle }
    private var acquisition: Task<Void, Never>?
    private var presentation: (any CapturePresenting)?
    private let prepare: @MainActor () throws -> Void
    private let capture: @MainActor () async throws -> [ScreenGrabber.Shot]
    private let makePresentation: @MainActor ([ScreenGrabber.Shot], @escaping (CaptureSession.Outcome?) -> Void) -> any CapturePresenting
    private let onOutcome: @MainActor (CaptureSession.Outcome) -> Void
    private let onFailure: @MainActor (Error) -> Void

    init(prepare: @escaping @MainActor () throws -> Void,
         capture: @escaping @MainActor () async throws -> [ScreenGrabber.Shot],
         makePresentation: @escaping @MainActor ([ScreenGrabber.Shot], @escaping (CaptureSession.Outcome?) -> Void) -> any CapturePresenting,
         onOutcome: @escaping @MainActor (CaptureSession.Outcome) -> Void,
         onFailure: @escaping @MainActor (Error) -> Void) {
        self.prepare = prepare
        self.capture = capture
        self.makePresentation = makePresentation
        self.onOutcome = onOutcome
        self.onFailure = onFailure
    }

    /// Repeated start requests join the current operation instead of replacing it.
    func begin() {
        guard state == .idle else { return }
        let id = UUID()
        state = .acquiring(id)
        do {
            try prepare()
        } catch {
            guard state == .acquiring(id) else { return }
            state = .idle
            onFailure(error)
            return
        }
        guard state == .acquiring(id) else { return }
        acquisition = Task { @MainActor [weak self, capture] in
            do {
                try Task.checkCancellation()
                let shots = try await capture()
                try Task.checkCancellation()
                guard let self, self.state == .acquiring(id) else { return }
                guard !shots.isEmpty else { throw ScreenGrabber.CaptureError.noDisplays }
                self.acquisition = nil
                let session = self.makePresentation(shots) { [weak self] outcome in
                    self?.complete(id: id, outcome: outcome)
                }
                self.presentation = session
                self.state = .presenting(id)
                session.begin()
            } catch {
                guard let self, self.state == .acquiring(id) else { return }
                self.acquisition = nil
                self.state = .idle
                if !(error is CancellationError) { self.onFailure(error) }
            }
        }
    }

    func toggle() {
        if isActive { cancel() } else { begin() }
    }

    func cancel() {
        // Invalidate ownership before cancelling: cancellation may finish synchronously.
        state = .idle
        let task = acquisition
        let session = presentation
        acquisition = nil
        presentation = nil
        task?.cancel()
        session?.cancel()
    }

    private func complete(id: UUID, outcome: CaptureSession.Outcome?) {
        guard state == .presenting(id) else { return }
        state = .idle
        presentation = nil
        if let outcome { onOutcome(outcome) }
    }
}

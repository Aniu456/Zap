import AppKit
import ScreenCaptureKit
import OSLog

enum ScreenGrabber {
    private static let logger = Logger(subsystem: "com.aniu456.Zap", category: "Capture")
    struct Shot: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let image: CGImage

        static func == (lhs: Shot, rhs: Shot) -> Bool {
            lhs.displayID == rhs.displayID && lhs.frame == rhs.frame && lhs.image === rhs.image
        }
    }

    enum CaptureError: Error {
        case noDisplays
        case displayUnavailable(CGDirectDisplayID)
        case invalidImageSize(CGDirectDisplayID)
        case displayLayoutChanged
    }

    private struct ScreenRef: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let widthPx: Int
        let heightPx: Int
    }

    @MainActor
    private static func screenLayout() -> [ScreenRef] {
        NSScreen.screens.compactMap { screen in
            let screenNumber = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
            guard let number = screen.deviceDescription[screenNumber] as? NSNumber else {
                return nil
            }
            let scale = screen.backingScaleFactor
            return ScreenRef(
                displayID: CGDirectDisplayID(number.uint32Value),
                frame: screen.frame,
                widthPx: max(1, Int((screen.frame.width * scale).rounded())),
                heightPx: max(1, Int((screen.frame.height * scale).rounded()))
            )
        }
    }

    /// A capture is one transaction: all displays come from the same layout,
    /// or no overlay is presented. Cancellation never enters the fallback path.
    @MainActor
    static func captureAll() async throws -> [Shot] {
        try Task.checkCancellation()
        let screens = screenLayout()
        guard !screens.isEmpty else { throw CaptureError.noDisplays }
        var shots: [Shot] = []
        if #available(macOS 15.2, *) {
            // A display-space capture avoids enumerating every shareable window.
            shots = try await withThrowingTaskGroup(of: Shot?.self) { group in
                for screen in screens {
                    let rect = CGDisplayBounds(screen.displayID)
                    group.addTask {
                        try Task.checkCancellation()
                        do {
                            let image = try await SCScreenshotManager.captureImage(in: rect)
                            try Task.checkCancellation()
                            guard image.width == screen.widthPx, image.height == screen.heightPx else {
                                logger.notice("Display capture size mismatch; trying fallback; display=\(screen.displayID)")
                                return nil
                            }
                            return Shot(displayID: screen.displayID, frame: screen.frame, image: image)
                        } catch {
                            try Task.checkCancellation()
                            if error is CancellationError { throw error }
                            logger.error("Display capture failed; trying fallback; display=\(screen.displayID), error=\(String(describing: error), privacy: .public)")
                            return nil
                        }
                    }
                }
                var result: [Shot] = []
                for try await shot in group {
                    if let shot { result.append(shot) }
                }
                return result
            }
        }
        try Task.checkCancellation()
        let captured = Set(shots.map(\.displayID))
        let remaining = screens.filter { !captured.contains($0.displayID) }
        if !remaining.isEmpty {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            for screen in remaining {
                try Task.checkCancellation()
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
                    throw CaptureError.displayUnavailable(screen.displayID)
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = screen.widthPx
                config.height = screen.heightPx
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                try Task.checkCancellation()
                guard image.width == screen.widthPx, image.height == screen.heightPx else {
                    throw CaptureError.invalidImageSize(screen.displayID)
                }
                shots.append(Shot(displayID: screen.displayID, frame: screen.frame, image: image))
            }
        }
        try Task.checkCancellation()
        guard screenLayout() == screens else { throw CaptureError.displayLayoutChanged }
        return shots.sortedByDisplayOrder(screens.map(\.displayID))
    }
}

private extension Array where Element == ScreenGrabber.Shot {
    func sortedByDisplayOrder(_ ids: [CGDirectDisplayID]) -> Self {
        ids.compactMap { id in first { $0.displayID == id } }
    }
}

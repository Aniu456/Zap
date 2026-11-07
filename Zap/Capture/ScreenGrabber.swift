import AppKit
import ScreenCaptureKit

enum ScreenGrabber {
    struct Shot: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let image: CGImage

        static func == (lhs: Shot, rhs: Shot) -> Bool {
            lhs.displayID == rhs.displayID && lhs.frame == rhs.frame && lhs.image === rhs.image
        }
    }

    private struct ScreenRef {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let widthPx: Int
        let heightPx: Int
    }

    @MainActor
    static func captureAll() async throws -> [Shot] {
        let screens: [ScreenRef] = NSScreen.screens.compactMap { screen in
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
        var shots: [Shot] = []
        if #available(macOS 15.2, *) {
            // A display-space capture avoids enumerating every shareable window.
            shots = await withTaskGroup(of: Shot?.self) { group in
                for screen in screens {
                    let rect = CGDisplayBounds(screen.displayID)
                    group.addTask {
                        guard let image = try? await SCScreenshotManager.captureImage(in: rect),
                              image.width == screen.widthPx, image.height == screen.heightPx else { return nil }
                        return Shot(displayID: screen.displayID, frame: screen.frame, image: image)
                    }
                }
                var result: [Shot] = []
                for await shot in group {
                    if let shot { result.append(shot) }
                }
                return result
            }
        }
        let captured = Set(shots.map(\.displayID))
        let remaining = screens.filter { !captured.contains($0.displayID) }
        guard !remaining.isEmpty else { return shots.sortedByDisplayOrder(screens.map(\.displayID)) }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if shots.isEmpty { throw error }
            return shots.sortedByDisplayOrder(screens.map(\.displayID))
        }
        for screen in remaining {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = screen.widthPx
            config.height = screen.heightPx
            config.showsCursor = false
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                shots.append(Shot(displayID: screen.displayID, frame: screen.frame, image: image))
            } catch {
                continue
            }
        }
        return shots.sortedByDisplayOrder(screens.map(\.displayID))
    }
}

private extension Array where Element == ScreenGrabber.Shot {
    func sortedByDisplayOrder(_ ids: [CGDirectDisplayID]) -> Self {
        ids.compactMap { id in first { $0.displayID == id } }
    }
}

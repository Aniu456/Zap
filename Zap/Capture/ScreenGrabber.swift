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
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var shots: [Shot] = []
        for screen in screens {
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
        return shots
    }
}

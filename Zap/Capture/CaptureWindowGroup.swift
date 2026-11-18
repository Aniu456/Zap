import AppKit

/// A single-use set of capture windows. Preparation never makes windows visible;
/// presentation happens after the triggering menu/key event has finished.
@MainActor
final class CaptureWindowGroup {
    enum State { case prepared, visible, closed }
    private(set) var state: State = .prepared
    private(set) var windows: [CGDirectDisplayID: CaptureWindow] = [:]
    private(set) var views: [CGDirectDisplayID: CaptureOverlayView] = [:]
    private let displayOrder: [CGDirectDisplayID]
    private var mouseMonitor: Any?

    init(shots: [ScreenGrabber.Shot], session: CaptureSession) {
        displayOrder = shots.map(\.displayID)
        for shot in shots {
            let window = CaptureWindow(contentRect: shot.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
            window.setFrame(shot.frame, display: false)
            window.level = .screenSaver
            WindowSpaces.apply(to: window)
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.acceptsMouseMovedEvents = true
            let view = CaptureOverlayView(displayID: shot.displayID)
            view.frame = CGRect(origin: .zero, size: shot.frame.size)
            view.session = session
            window.contentView = view
            windows[shot.displayID] = window
            views[shot.displayID] = view
        }
    }

    func present(routeMouse: @escaping (NSEvent) -> Void) {
        guard state == .prepared else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .prepared else { return }
            // Prime every frozen canvas before exposing any display's window.
            for id in self.displayOrder {
                self.views[id]?.needsDisplay = true
                self.windows[id]?.displayIfNeeded()
            }
            self.state = .visible
            NSApp.activate()
            for id in self.displayOrder { self.windows[id]?.orderFrontRegardless() }
            let mouse = NSEvent.mouseLocation
            let key = self.displayOrder.compactMap { self.windows[$0] }
                .first { $0.frame.contains(mouse) } ?? self.displayOrder.first.flatMap { self.windows[$0] }
            key?.makeKeyAndOrderFront(nil)
            if let view = key?.contentView { key?.makeFirstResponder(view) }
            self.mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { event in
                MainActor.assumeIsolated { routeMouse(event) }
            }
            if key != nil { NSCursor.crosshair.set() }
        }
    }

    func close() {
        guard state != .closed else { return }
        state = .closed
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        let retired = Array(windows.values)
        windows.removeAll()
        views.removeAll()
        for window in retired { window.orderOut(nil) }
        // Release only this group's views after the input callback unwinds.
        DispatchQueue.main.async {
            for window in retired { window.contentView = nil }
        }
    }
}

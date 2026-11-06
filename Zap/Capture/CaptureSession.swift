import AppKit
import Carbon

/// Main-thread capture UI. Callers are already on the main actor.
final class CaptureSession: NSObject, NSTextFieldDelegate {
    struct Outcome {
        enum Kind {
            case copied
            case pinned
        }

        var kind: Kind
        var png: Data
        var image: NSImage
        var screenFrame: NSRect
    }

    private let shots: [ScreenGrabber.Shot]
    private let onFinish: (Outcome?) -> Void
    private var windows: [CGDirectDisplayID: CaptureWindow] = [:]
    private var views: [CGDirectDisplayID: CaptureOverlayView] = [:]
    private var phase: Phase = .selecting
    private var activeDisplay: CGDirectDisplayID?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var crop: CGImage?
    private var preview: CGImage?
    private var marks: [CaptureMark] = []
    private var draft: CaptureMark?
    private var tool: CaptureTool = .arrow
    private var textField: NSTextField?
    private var toolbar: CaptureToolbar?
    private var globalMouseMonitor: Any?
    private var finished = false

    private enum Phase {
        case selecting
        case editing
    }

    init(shots: [ScreenGrabber.Shot], onFinish: @escaping (Outcome?) -> Void) {
        self.shots = shots
        self.onFinish = onFinish
    }

    func begin() {
        for shot in shots {
            let window = CaptureWindow(
                contentRect: shot.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(shot.frame, display: false)
            window.level = .screenSaver
            WindowSpaces.apply(to: window)
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.acceptsMouseMovedEvents = true
            let view = CaptureOverlayView(displayID: shot.displayID)
            view.session = self
            window.contentView = view
            windows[shot.displayID] = window
            views[shot.displayID] = view
            window.orderFrontRegardless()
        }
        NSApp.activate()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self else { return }
            self.routeGlobal(event)
        }
        let mouse = NSEvent.mouseLocation
        let key = windows.values.first { $0.frame.contains(mouse) } ?? windows.values.first
        key?.makeKeyAndOrderFront(nil)
        if let view = key?.contentView {
            key?.makeFirstResponder(view)
        }
        redraw()
    }

    func cancel() {
        finish(nil)
    }

    func usesCrosshair(on _: CGDirectDisplayID) -> Bool {
        phase == .selecting
    }

    func canvasState(for displayID: CGDirectDisplayID) -> CaptureCanvasState? {
        guard let shot = shots.first(where: { $0.displayID == displayID }) else { return nil }
        let isActive = displayID == activeDisplay
        return CaptureCanvasState(
            background: shot.image,
            selection: isActive ? selection : nil,
            preview: isActive ? preview : nil,
            draft: isActive ? draft : nil,
            cropSize: isActive ? crop.map { CGSize(width: $0.width, height: $0.height) } : nil,
            hint: isActive || phase == .selecting ? hint : ""
        )
    }

    func mouseDown(displayID: CGDirectDisplayID, point: CGPoint) {
        guard textField == nil else { return }
        switch phase {
        case .selecting:
            activeDisplay = displayID
            dragStart = point
            selection = CGRect(origin: point, size: .zero)
            windows[displayID]?.makeKeyAndOrderFront(nil)
            if let view = views[displayID] {
                windows[displayID]?.makeFirstResponder(view)
            }
            redraw()
        case .editing:
            guard displayID == activeDisplay, let selection, selection.contains(point) else { return }
            if tool == .text {
                presentTextField(at: point)
                return
            }
            dragStart = point
            draft = nil
            redraw()
        }
    }

    func mouseDragged(displayID: CGDirectDisplayID, point: CGPoint) {
        guard textField == nil, let dragStart, let local = pointInActiveView(from: displayID, point: point) else { return }
        switch phase {
        case .selecting:
            guard let activeDisplay else { return }
            selection = rect(from: dragStart, to: local, displayID: activeDisplay)
            redraw()
        case .editing:
            guard let selection, selection.contains(dragStart) else { return }
            draft = mark(from: dragStart, to: local)
            redraw()
        }
    }

    func mouseUp(displayID: CGDirectDisplayID, point: CGPoint) {
        guard textField == nil, let dragStart, let local = pointInActiveView(from: displayID, point: point) else { return }
        let start = dragStart
        self.dragStart = nil
        switch phase {
        case .selecting:
            guard let activeDisplay else { return }
            let rect = rect(from: start, to: local, displayID: activeDisplay)
            selection = rect
            if CaptureGeometry.isUsable(rect) {
                enterEditing()
            } else {
                selection = nil
                redraw()
            }
        case .editing:
            guard let draft, CaptureGeometry.isDrag(from: start, to: local) else {
                self.draft = nil
                redraw()
                return
            }
            marks.append(draft)
            self.draft = nil
            refreshPreview()
            redraw()
        }
    }

    func keyDown(_ event: NSEvent) {
        if textField != nil { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
            return
        }
        guard phase == .editing else { return }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", !modifiers.contains(.shift) {
            undo()
            return
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            commit(pin: true)
            return
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            commit(pin: false)
            return
        }
        guard modifiers.isEmpty else { return }
        switch Int(event.keyCode) {
        case kVK_ANSI_1: setTool(.arrow)
        case kVK_ANSI_2: setTool(.box)
        case kVK_ANSI_3: setTool(.text)
        case kVK_ANSI_4: setTool(.mosaic)
        default: break
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            discardText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    private var hint: String {
        phase == .selecting ? L10n.captureSelectHint : L10n.captureEditHint
    }

    private func setTool(_ tool: CaptureTool) {
        self.tool = tool
        toolbar?.setTool(tool)
        makeOverlayFirstResponder()
    }

    private func undo() {
        guard !marks.isEmpty else {
            NSSound.beep()
            return
        }
        marks.removeLast()
        refreshPreview()
        redraw()
    }

    private func enterEditing() {
        guard let displayID = activeDisplay,
              let selection,
              let shot = shots.first(where: { $0.displayID == displayID }) else { return }
        let pixels = CaptureGeometry.cropPixels(
            selection: selection,
            screenSize: shot.frame.size,
            imageSize: CGSize(width: shot.image.width, height: shot.image.height)
        )
        guard !pixels.isEmpty,
              let cropped = shot.image.cropping(to: CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)) else {
            self.selection = nil
            redraw()
            return
        }
        crop = cropped
        phase = .editing
        refreshPreview()
        installToolbar()
        redraw()
        makeOverlayFirstResponder()
    }

    private func installToolbar() {
        guard let displayID = activeDisplay, let view = views[displayID], let selection,
              let shot = shots.first(where: { $0.displayID == displayID }) else { return }
        let toolbar = CaptureToolbar(frame: .zero)
        toolbar.onTool = { [weak self] tool in self?.setTool(tool) }
        toolbar.onUndo = { [weak self] in self?.undo() }
        toolbar.onCopy = { [weak self] in self?.commit(pin: false) }
        toolbar.onPin = { [weak self] in self?.commit(pin: true) }
        toolbar.onCancel = { [weak self] in self?.cancel() }
        toolbar.setTool(tool)
        let size = toolbar.frame.size
        let bounds = view.bounds.width > 1 ? view.bounds : CGRect(origin: .zero, size: shot.frame.size)
        let origin = CaptureGeometry.toolbarOrigin(selection: selection, toolbarSize: size, bounds: bounds)
        toolbar.frame.origin = origin
        view.addSubview(toolbar)
        self.toolbar = toolbar
    }

    private func presentTextField(at point: CGPoint) {
        guard let displayID = activeDisplay, let view = views[displayID], let selection else { return }
        commitText()
        var width = min(220, selection.maxX - point.x)
        var originX = point.x
        if width < 80 {
            width = min(220, selection.width)
            originX = max(selection.minX, selection.maxX - width)
        }
        var frame = NSRect(x: originX, y: point.y - 28, width: width, height: 28)
        if frame.minY < selection.minY {
            frame.origin.y = min(selection.maxY - frame.height, max(selection.minY, point.y))
        }
        let field = NSTextField(frame: frame)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        field.textColor = .systemRed
        field.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        field.focusRingType = .none
        field.delegate = self
        view.addSubview(field)
        textField = field
        windows[displayID]?.makeFirstResponder(field)
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let topLeft = CGPoint(x: field.frame.minX, y: field.frame.maxY)
        field.removeFromSuperview()
        if !string.isEmpty, let selection, let crop {
            let imageSize = CGSize(width: crop.width, height: crop.height)
            let origin = CaptureGeometry.cropPixel(fromViewPoint: topLeft, selection: selection, imageSize: imageSize)
            let fontPixels = 18 * imageSize.height / max(selection.height, 1)
            marks.append(.text(string, origin: origin, fontSize: fontPixels))
            refreshPreview()
        }
        redraw()
        makeOverlayFirstResponder()
    }

    private func discardText() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        field.removeFromSuperview()
        makeOverlayFirstResponder()
    }

    private func commit(pin: Bool) {
        guard let crop, let selection, let displayID = activeDisplay,
              let shot = shots.first(where: { $0.displayID == displayID }) else { return }
        let rendered = CaptureRenderer.render(base: crop, marks: marks) ?? crop
        guard let png = CaptureRenderer.pngData(from: rendered) else {
            ToastCenter.shared.show(L10n.captureFailed)
            return
        }
        let pointSize = NSSize(width: max(selection.width, 1), height: max(selection.height, 1))
        let image = NSImage(cgImage: rendered, size: pointSize)
        let screenFrame = NSRect(
            x: shot.frame.minX + selection.minX,
            y: shot.frame.minY + selection.minY,
            width: pointSize.width,
            height: pointSize.height
        )
        finish(Outcome(kind: pin ? .pinned : .copied, png: png, image: image, screenFrame: screenFrame))
    }

    private func refreshPreview() {
        guard let crop else {
            preview = nil
            return
        }
        preview = CaptureRenderer.render(base: crop, marks: marks) ?? crop
    }

    private func mark(from start: CGPoint, to end: CGPoint) -> CaptureMark? {
        guard let selection, let crop else { return nil }
        let imageSize = CGSize(width: crop.width, height: crop.height)
        let from = CaptureGeometry.cropPixel(fromViewPoint: start, selection: selection, imageSize: imageSize)
        let to = CaptureGeometry.cropPixel(fromViewPoint: end, selection: selection, imageSize: imageSize)
        switch tool {
        case .arrow:
            return .arrow(from: from, to: to)
        case .box:
            return .box(CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y))
        case .mosaic:
            return .mosaic(CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y))
        case .text:
            return nil
        }
    }

    private func routeGlobal(_ event: NSEvent) {
        guard dragStart != nil, let activeDisplay else { return }
        let screenPoint = NSEvent.mouseLocation
        guard let window = windows[activeDisplay], let view = views[activeDisplay] else { return }
        let windowPoint = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        let local = clamp(view.convert(windowPoint, from: nil), to: view.bounds)
        if event.type == .leftMouseDragged {
            mouseDragged(displayID: activeDisplay, point: local)
        } else if event.type == .leftMouseUp {
            mouseUp(displayID: activeDisplay, point: local)
        }
    }

    private func pointInActiveView(from displayID: CGDirectDisplayID, point: CGPoint) -> CGPoint? {
        guard let activeDisplay, let activeView = views[activeDisplay] else { return nil }
        if displayID == activeDisplay {
            return clamp(point, to: activeView.bounds)
        }
        guard let source = views[displayID], let sourceWindow = source.window, let activeWindow = activeView.window else {
            return nil
        }
        let sourceWindowPoint = source.convert(point, to: nil)
        let screenPoint = sourceWindow.convertToScreen(NSRect(origin: sourceWindowPoint, size: .zero)).origin
        let activeWindowPoint = activeWindow.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        return clamp(activeView.convert(activeWindowPoint, from: nil), to: activeView.bounds)
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func rect(from start: CGPoint, to end: CGPoint, displayID: CGDirectDisplayID) -> CGRect {
        let raw = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
        let bounds = views[displayID]?.bounds ?? .zero
        let intersection = CaptureGeometry.normalized(raw).intersection(bounds)
        if intersection.isNull || intersection.isEmpty { return .zero }
        return intersection
    }

    private func redraw() {
        toolbar?.setTool(tool)
        toolbar?.setUndoEnabled(!marks.isEmpty)
        for view in views.values {
            view.needsDisplay = true
            view.window?.invalidateCursorRects(for: view)
        }
    }

    private func makeOverlayFirstResponder() {
        guard let displayID = activeDisplay, let view = views[displayID] else { return }
        windows[displayID]?.makeFirstResponder(view)
    }

    private func finish(_ outcome: Outcome?) {
        guard !finished else { return }
        finished = true
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        textField?.delegate = nil
        textField = nil
        toolbar = nil
        let windows = Array(self.windows.values)
        self.windows.removeAll()
        views.removeAll()
        for window in windows {
            window.orderOut(nil)
        }
        // Drop the views on the next turn. The click or key that ended the shot
        // may still be on the call stack.
        DispatchQueue.main.async {
            for window in windows {
                window.contentView = nil
            }
        }
        onFinish(outcome)
    }
}

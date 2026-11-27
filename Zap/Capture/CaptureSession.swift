import AppKit
import Carbon
import UniformTypeIdentifiers
import OSLog

/// Selection and editing model; window ownership belongs to CaptureWindowGroup.
@MainActor
final class CaptureSession: NSObject, NSTextFieldDelegate, CapturePresenting {
    struct PinSnapshot {
        let image: NSImage
        let base: CGImage
        let marks: [CaptureMark]
        let undo: [[CaptureMark]]
        let redo: [[CaptureMark]]
    }

    private(set) var exportedPin: PinSnapshot?

    enum Outcome {
        case copied(Data)
        case colorCopied
        case saved
        case pinned(PinSnapshot, NSRect)
    }

    let loupe = PixelLoupe()
    private let shots: [ScreenGrabber.Shot]
    private let onFinish: (Outcome?) -> Void
    private let chooseSaveURL: (String) -> URL?
    private var isSaving = false
    private var windowGroup: CaptureWindowGroup?
    private weak var pinCanvas: CaptureOverlayView?
    private var windows: [CGDirectDisplayID: NSWindow] {
        if let pinCanvas, let window = pinCanvas.window { return [pinCanvas.displayID: window] }
        return windowGroup?.windows ?? [:]
    }
    private var views: [CGDirectDisplayID: CaptureOverlayView] {
        if let pinCanvas { return [pinCanvas.displayID: pinCanvas] }
        return windowGroup?.views ?? [:]
    }
    private var phase: Phase = .selecting
    private var activeDisplay: CGDirectDisplayID?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var crop: CGImage?
    private var preview: CGImage?
    private var marks: [CaptureMark] = []
    private var undoStack: [[CaptureMark]] = []
    private var redoStack: [[CaptureMark]] = []
    private var draft: CaptureMark?
    private(set) var tool: CaptureTool = .arrow
    private var textField: NSTextField?
    private var textEditor: CaptureTextEditor?
    private var movingText: (index: Int, before: [CaptureMark])?
    private var toolbar: CaptureToolbar?
    private var finished = false
    private let logger = Logger(subsystem: "com.aniu456.Zap", category: "Capture")
    private var eraserSnapshotTaken = false

    private enum Phase {
        case selecting
        case editing
    }

    init(shots: [ScreenGrabber.Shot], chooseSaveURL: ((String) -> URL?)? = nil,
         onFinish: @escaping (Outcome?) -> Void) {
        self.shots = shots
        self.onFinish = onFinish
        self.chooseSaveURL = chooseSaveURL ?? Self.presentSavePanel
    }

    func begin() {
        guard !finished, windowGroup == nil else { return }
        let group = CaptureWindowGroup(shots: shots, session: self)
        windowGroup = group
        group.present { [weak self] event in self?.routeGlobal(event) }
    }

    func editPin(_ snapshot: PinSnapshot, in window: NSWindow) {
        guard let shot = shots.first else { return }
        let view = CaptureOverlayView(displayID: shot.displayID)
        view.session = self
        window.contentView = view
        pinCanvas = view
        activeDisplay = shot.displayID
        selection = view.bounds
        crop = snapshot.base
        phase = .editing
        marks = snapshot.marks
        undoStack = snapshot.undo
        redoStack = snapshot.redo
        refreshPreview()
        redraw()
        window.makeKeyAndOrderFront(nil)
        makeOverlayFirstResponder()
    }

    func cancel() { cancel(reason: "controller") }

    func cancel(reason: String) {
        guard !finished else { return }
        logger.notice("Capture cancellation source: \(reason, privacy: .public)")
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
            marks: isActive ? marks : [],
            draft: isActive ? draft : nil,
            cropSize: isActive ? crop.map { CGSize(width: $0.width, height: $0.height) } : nil,
            hint: pinCanvas == nil && (isActive || phase == .selecting) ? hint : ""
        )
    }

    func mouseDown(displayID: CGDirectDisplayID, point: CGPoint) {
        guard !finished, textField == nil else { return }
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
                if let index = textMark(at: point) {
                    dragStart = point
                    movingText = (index, marks)
                    loupe.hide()
                    return
                }
                presentTextField(at: point)
                return
            }
            if tool == .eraser {
                dragStart = point
                eraserSnapshotTaken = false
                erase(at: point)
                return
            }
            dragStart = point
            draft = nil
            redraw()
        }
    }

    func mouseDragged(displayID: CGDirectDisplayID, point: CGPoint) {
        guard !finished, textField == nil, let dragStart, let local = pointInActiveView(from: displayID, point: point) else { return }
        switch phase {
        case .selecting:
            guard let activeDisplay else { return }
            selection = rect(from: dragStart, to: local, displayID: activeDisplay)
            redraw()
        case .editing:
            if movingText != nil {
                moveText(to: local, from: dragStart)
                return
            }
            guard let selection, selection.contains(dragStart) else { return }
            if tool == .eraser {
                erase(at: local)
                return
            }
            if tool == .pencil || tool == .marker {
                appendStroke(to: local, from: dragStart)
            } else {
                draft = mark(from: dragStart, to: local)
            }
            redraw()
        }
    }

    func mouseUp(displayID: CGDirectDisplayID, point: CGPoint) {
        guard !finished, textField == nil, let dragStart, let local = pointInActiveView(from: displayID, point: point) else { return }
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
            if let movingText {
                moveText(to: local, from: start)
                if marks != movingText.before {
                    undoStack.append(movingText.before)
                    if undoStack.count > 40 { undoStack.removeFirst() }
                    redoStack.removeAll()
                }
                self.movingText = nil
                redraw()
                return
            }
            if tool == .eraser {
                eraserSnapshotTaken = false
                self.dragStart = nil
                redraw()
                return
            }
            guard let draft else {
                redraw()
                return
            }
            let keep: Bool
            if case .stroke(let points, _, _) = draft {
                keep = points.count >= 2
            } else {
                keep = CaptureGeometry.isDrag(from: start, to: local)
            }
            guard keep else {
                self.draft = nil
                redraw()
                return
            }
            let committed = draft
            self.draft = nil
            commitMark(committed)
        }
    }

    func updateLoupe(in view: CaptureOverlayView, point: CGPoint) {
        guard pinCanvas == nil, !finished, textField == nil, movingText == nil, view.hitTest(point) === view,
              let shot = shots.first(where: { $0.displayID == view.displayID }) else {
            loupe.hide()
            return
        }
        loupe.update(image: shot.image, in: view, point: point)
    }

    func keyDown(_ event: NSEvent) {
        if finished || textField != nil { return }
        if loupe.copyColor(event) {
            finish(.colorCopied)
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.keyCode == UInt16(kVK_Escape) {
            cancel(reason: "escape")
            return
        }
        guard phase == .editing, movingText == nil else { return }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", !modifiers.contains(.shift) {
            undo()
            return
        }
        if modifiers.contains(.command), modifiers.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "z" {
            redo()
            return
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
            saveToFile()
            return
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            commit(pin: false)
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
        guard modifiers.isEmpty, pinCanvas == nil else { return }
        switch Int(event.keyCode) {
        case kVK_ANSI_1: setTool(.arrow)
        case kVK_ANSI_2: setTool(.box)
        case kVK_ANSI_3: setTool(.text)
        case kVK_ANSI_4: setTool(.mosaic)
        case kVK_ANSI_5: setTool(.pencil)
        case kVK_ANSI_6: setTool(.marker)
        case kVK_ANSI_7: setTool(.eraser)
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

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func setTool(_ tool: CaptureTool) {
        commitText()
        self.tool = tool
        toolbar?.setTool(tool)
        makeOverlayFirstResponder()
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            NSSound.beep()
            return
        }
        redoStack.append(marks)
        marks = previous
        draft = nil
        refreshPreview()
        redraw()
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            NSSound.beep()
            return
        }
        undoStack.append(marks)
        marks = next
        draft = nil
        refreshPreview()
        redraw()
    }

    private func commitMark(_ mark: CaptureMark) {
        undoStack.append(marks)
        if undoStack.count > 40 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        marks.append(mark)
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
        // Leave preview nil. The overlay keeps painting the frozen screenshot inside
        // the selection, so finishing the drag does not swap in a new bitmap.
        preview = nil
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
        toolbar.onRedo = { [weak self] in self?.redo() }
        toolbar.onCopy = { [weak self] in self?.commit(pin: false) }
        toolbar.onPin = { [weak self] in self?.commit(pin: true) }
        toolbar.onSave = { [weak self] in self?.saveToFile() }
        toolbar.onCancel = { [weak self] in self?.cancel(reason: "toolbar") }
        toolbar.setTool(tool)
        let size = toolbar.frame.size
        let bounds = view.bounds.width > 1 ? view.bounds : CGRect(origin: .zero, size: shot.frame.size)
        let origin = CaptureGeometry.toolbarOrigin(selection: selection, toolbarSize: size, bounds: bounds)
        toolbar.frame.origin = origin
        view.addSubview(toolbar)
        self.toolbar = toolbar
    }

    private func textBounds(_ mark: CaptureMark) -> CGRect? {
        guard case .text(let string, let origin, let fontSize) = mark,
              let selection, let crop else { return nil }
        let imageSize = CGSize(width: crop.width, height: crop.height)
        let topLeft = CaptureGeometry.viewPoint(fromCropPixel: origin, selection: selection, imageSize: imageSize)
        let font = NSFont.systemFont(ofSize: max(12, fontSize * selection.height / imageSize.height), weight: .semibold)
        let size = (string as NSString).size(withAttributes: [.font: font])
        return CGRect(x: topLeft.x, y: topLeft.y - font.ascender, width: size.width, height: size.height)
    }

    private func textMark(at point: CGPoint) -> Int? {
        marks.indices.reversed().first { index in
            textBounds(marks[index])?.insetBy(dx: -4, dy: -4).contains(point) == true
        }
    }

    private func moveText(to point: CGPoint, from start: CGPoint) {
        guard let movingText, let selection, let crop,
              case .text(let string, let origin, let fontSize) = movingText.before[movingText.index],
              let bounds = textBounds(movingText.before[movingText.index]) else { return }
        let x = min(max(bounds.minX + point.x - start.x, selection.minX), max(selection.minX, selection.maxX - bounds.width))
        let y = min(max(bounds.minY + point.y - start.y, selection.minY), max(selection.minY, selection.maxY - bounds.height))
        let moved = CGPoint(x: origin.x + (x - bounds.minX) * CGFloat(crop.width) / selection.width,
                            y: origin.y - (y - bounds.minY) * CGFloat(crop.height) / selection.height)
        marks[movingText.index] = .text(string, origin: moved, fontSize: fontSize)
        redraw()
    }

    private func presentTextField(at point: CGPoint) {
        guard let displayID = activeDisplay, let view = views[displayID], let selection else { return }
        commitText()
        let size = CGSize(width: min(240, selection.width), height: min(28, selection.height))
        let frame = CGRect(x: min(max(selection.minX, point.x), selection.maxX - size.width),
                           y: min(max(selection.minY, point.y - size.height), selection.maxY - size.height),
                           width: size.width, height: size.height)
        let editor = CaptureTextEditor(frame: frame, movementBounds: selection)
        let field = editor.field
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        field.textColor = .systemRed
        field.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        field.focusRingType = .none
        field.delegate = self
        view.addSubview(editor)
        textEditor = editor
        textField = field
        windows[displayID]?.makeFirstResponder(field)
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let topLeft = field.convert(CGPoint(x: field.bounds.minX, y: field.bounds.maxY), to: textEditor?.superview)
        textEditor?.removeFromSuperview()
        textEditor = nil
        if !string.isEmpty, let selection, let crop {
            let imageSize = CGSize(width: crop.width, height: crop.height)
            let origin = CaptureGeometry.cropPixel(fromViewPoint: topLeft, selection: selection, imageSize: imageSize)
            let fontPixels = 18 * imageSize.height / max(selection.height, 1)
            commitMark(.text(string, origin: origin, fontSize: fontPixels))
        } else {
            redraw()
        }
        makeOverlayFirstResponder()
    }

    private func discardText() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        textEditor?.removeFromSuperview()
        textEditor = nil
        makeOverlayFirstResponder()
    }

    func commit(pin: Bool) {
        commitText()
        guard let rendered = exportRender(), let crop else { return }
        if pin {
            finish(.pinned(pinSnapshot(rendered.image, size: rendered.screenFrame.size, base: crop), rendered.screenFrame))
        } else if let data = pngData(rendered.image) {
            if pinCanvas != nil {
                exportedPin = pinSnapshot(rendered.image, size: rendered.screenFrame.size, base: crop)
            }
            finish(.copied(data))
        }
    }

    private func pinSnapshot(_ image: CGImage, size: CGSize, base: CGImage) -> PinSnapshot {
        PinSnapshot(image: NSImage(cgImage: image, size: size), base: base, marks: marks, undo: undoStack, redo: redoStack)
    }

    func saveToFile() {
        commitText()
        guard !finished, !isSaving, let rendered = exportRender() else { return }
        isSaving = true
        defer { isSaving = false }
        let previousLevels = windows.mapValues(\.level)
        for window in windows.values {
            window.level = .floating
        }
        let url = chooseSaveURL(Self.defaultFileName())
        for (displayID, window) in windows {
            window.level = previousLevels[displayID] ?? .screenSaver
        }
        guard !finished, let url else { return }
        do {
            guard let data = pngData(rendered.image) else { return }
            try data.write(to: url, options: .atomic)
            if pinCanvas != nil, let crop {
                exportedPin = pinSnapshot(rendered.image, size: rendered.screenFrame.size, base: crop)
            }
            finish(.saved)
        } catch {
            logger.error("Saving capture failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func presentSavePanel(fileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportRender() -> (image: CGImage, screenFrame: NSRect)? {
        guard let crop, let selection, let displayID = activeDisplay,
              let shot = shots.first(where: { $0.displayID == displayID }) else { return nil }
        guard let rendered = CaptureRenderer.render(base: crop, marks: marks) else {
            logger.error("Capture rendering failed")
            return nil
        }
        let pointSize = NSSize(width: max(selection.width, 1), height: max(selection.height, 1))
        let screenFrame = NSRect(
            x: shot.frame.minX + selection.minX,
            y: shot.frame.minY + selection.minY,
            width: pointSize.width,
            height: pointSize.height
        )
        return (rendered, screenFrame)
    }

    private func pngData(_ image: CGImage) -> Data? {
        let data = CaptureRenderer.pngData(from: image)
        if data == nil { logger.error("Capture PNG encoding failed") }
        return data
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-SG")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "截图 \(formatter.string(from: Date())).png"
    }

    private func refreshPreview() {
        guard let crop else {
            preview = nil
            return
        }
        let mosaics = marks.filter { mark in
            if case .mosaic = mark { return true }
            return false
        }
        guard !mosaics.isEmpty else {
            preview = nil
            return
        }
        preview = CaptureRenderer.render(base: crop, marks: mosaics)
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
        case .pencil:
            return .stroke(points: [from, to], width: strokeWidth(2.4), alpha: 1)
        case .marker:
            return .stroke(points: [from, to], width: strokeWidth(14), alpha: 0.45)
        case .text, .eraser:
            return nil
        }
    }

    private func appendStroke(to viewPoint: CGPoint, from start: CGPoint) {
        guard let selection, let crop else { return }
        let imageSize = CGSize(width: crop.width, height: crop.height)
        let pixel = CaptureGeometry.cropPixel(fromViewPoint: viewPoint, selection: selection, imageSize: imageSize)
        if case .stroke(var points, let width, let alpha) = draft {
            if let last = points.last, hypot(last.x - pixel.x, last.y - pixel.y) < 0.8 { return }
            points.append(pixel)
            draft = .stroke(points: points, width: width, alpha: alpha)
            return
        }
        let origin = CaptureGeometry.cropPixel(fromViewPoint: start, selection: selection, imageSize: imageSize)
        switch tool {
        case .pencil:
            draft = .stroke(points: [origin, pixel], width: strokeWidth(2.4), alpha: 1)
        case .marker:
            draft = .stroke(points: [origin, pixel], width: strokeWidth(14), alpha: 0.45)
        default:
            break
        }
    }

    private func strokeWidth(_ points: CGFloat) -> CGFloat {
        guard let selection, let crop else { return points }
        return points * CGFloat(crop.height) / max(selection.height, 1)
    }

    private func erase(at viewPoint: CGPoint) {
        guard let selection, let crop else { return }
        let imageSize = CGSize(width: crop.width, height: crop.height)
        let pixel = CaptureGeometry.cropPixel(fromViewPoint: viewPoint, selection: selection, imageSize: imageSize)
        guard let index = marks.lastIndex(where: { markHits($0, point: pixel) }) else { return }
        if !eraserSnapshotTaken {
            undoStack.append(marks)
            if undoStack.count > 40 {
                undoStack.removeFirst()
            }
            redoStack.removeAll()
            eraserSnapshotTaken = true
        }
        marks.remove(at: index)
        refreshPreview()
        redraw()
    }

    private func markHits(_ mark: CaptureMark, point: CGPoint) -> Bool {
        switch mark {
        case .arrow(let from, let to):
            return distance(point, toSegmentFrom: from, to: to) < 14
        case .box(let rect), .mosaic(let rect):
            return CaptureGeometry.normalized(rect).insetBy(dx: -8, dy: -8).contains(point)
        case .text(let string, let origin, let fontSize):
            let width = max(fontSize, CGFloat(string.count) * fontSize * 0.9)
            return CGRect(x: origin.x - 4, y: origin.y - 4, width: width + 8, height: fontSize * 1.4 + 8).contains(point)
        case .stroke(let points, let width, _):
            guard points.count >= 2 else { return false }
            let limit = max(10, width)
            for index in 1..<points.count {
                if distance(point, toSegmentFrom: points[index - 1], to: points[index]) <= limit {
                    return true
                }
            }
            return false
        }
    }

    private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.01 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
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
        keepToolbarOnScreen()
        toolbar?.setTool(tool)
        toolbar?.setUndoEnabled(!undoStack.isEmpty)
        toolbar?.setRedoEnabled(!redoStack.isEmpty)
        for view in views.values {
            view.needsDisplay = true
            view.window?.invalidateCursorRects(for: view)
        }
    }

    /// A dragged toolbar stays where the user put it. Only an origin that would
    /// leave the screen is pulled back in.
    private func keepToolbarOnScreen() {
        guard let toolbar, let superview = toolbar.superview else { return }
        let origin = CaptureGeometry.clampedToolbarOrigin(
            toolbar.frame.origin,
            toolbarSize: toolbar.frame.size,
            bounds: superview.bounds, gap: 0
        )
        if origin != toolbar.frame.origin {
            toolbar.frame.origin = origin
        }
    }

    private func makeOverlayFirstResponder() {
        guard let displayID = activeDisplay, let view = views[displayID] else { return }
        windows[displayID]?.makeFirstResponder(view)
    }

    private func finish(_ outcome: Outcome?) {
        guard !finished else { return }
        finished = true
        let result: String
        switch outcome {
        case .copied: result = "copied"
        case .colorCopied: result = "color copied"
        case .saved: result = "saved"
        case .pinned: result = "pinned"
        case nil: result = "cancelled"
        }
        logger.notice("Capture session ended: \(result, privacy: .public)")
        loupe.hide()
        textField?.delegate = nil
        textField = nil
        textEditor = nil
        movingText = nil
        toolbar = nil
        windowGroup?.close()
        windowGroup = nil
        onFinish(outcome)
    }
}

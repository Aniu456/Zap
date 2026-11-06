import CoreGraphics

enum PasteService {
    /// Posts Command-V. A target pid keeps the keystroke out of 一闪's own search field.
    @discardableResult
    static func simulateCommandV(pid: pid_t?) -> Bool {
        let keyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}

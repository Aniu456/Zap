import AppKit
import Carbon

struct HotkeyChord: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    /// Raw value of the device-independent modifier flags that matter: command, option, shift, control.
    var modifiers: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .shift, .control])
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.displayToken(for: keyCode))
        return parts.joined()
    }

    /// Menu item key equivalent, or empty when AppKit has no single character for this key.
    var keyEquivalent: String {
        Self.keyEquivalent(for: keyCode)
    }

    static let launcherDefault = HotkeyChord(
        keyCode: UInt16(kVK_Space),
        modifiers: NSEvent.ModifierFlags.option.rawValue
    )

    static let clipboardDefault = HotkeyChord(
        keyCode: UInt16(kVK_Space),
        modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue
    )

    static func isModifierOnly(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
             kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }

    private static func displayToken(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌅"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return ansi[keyCode]?.uppercased() ?? "键\(keyCode)"
        }
    }

    private static func keyEquivalent(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return " "
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return "\r"
        case kVK_Tab:
            return "\t"
        case kVK_Delete:
            return functionKey(NSBackspaceCharacter)
        case kVK_ForwardDelete:
            return functionKey(NSDeleteCharacter)
        case kVK_LeftArrow:
            return functionKey(NSLeftArrowFunctionKey)
        case kVK_RightArrow:
            return functionKey(NSRightArrowFunctionKey)
        case kVK_UpArrow:
            return functionKey(NSUpArrowFunctionKey)
        case kVK_DownArrow:
            return functionKey(NSDownArrowFunctionKey)
        case kVK_F1:
            return functionKey(NSF1FunctionKey)
        case kVK_F2:
            return functionKey(NSF2FunctionKey)
        case kVK_F3:
            return functionKey(NSF3FunctionKey)
        case kVK_F4:
            return functionKey(NSF4FunctionKey)
        case kVK_F5:
            return functionKey(NSF5FunctionKey)
        case kVK_F6:
            return functionKey(NSF6FunctionKey)
        case kVK_F7:
            return functionKey(NSF7FunctionKey)
        case kVK_F8:
            return functionKey(NSF8FunctionKey)
        case kVK_F9:
            return functionKey(NSF9FunctionKey)
        case kVK_F10:
            return functionKey(NSF10FunctionKey)
        case kVK_F11:
            return functionKey(NSF11FunctionKey)
        case kVK_F12:
            return functionKey(NSF12FunctionKey)
        default:
            return ansi[keyCode] ?? ""
        }
    }

    private static func functionKey(_ value: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(value)) else { return "" }
        return String(scalar)
    }

    /// Unmodified ANSI characters for the ANSI virtual key codes. Menu equivalents stay lowercase.
    private static let ansi: [UInt16: String] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f",
        0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l",
        0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
        0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
        0x10: "y", 0x06: "z",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
        0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x2A: "\\",
        0x29: ";", 0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x32: "`"
    ]
}

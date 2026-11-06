import Foundation

enum ClipboardPolicy {
    static let maxItems = 200
    static let maxTextCharacters = 200_000
    static let maxImageBytes = 8 * 1024 * 1024

    static func acceptsText(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maxTextCharacters
    }

    static func acceptsImageByteCount(_ count: Int) -> Bool {
        count >= 32 && count <= maxImageBytes
    }
}

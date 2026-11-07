import Foundation

enum ClipboardPolicy {
    static let maxItems = 200
    /// Sum of each item's `byteCount`. Binary units, so the settings line shows 256 MB.
    static let maxDiskBytes = 256 * 1024 * 1024
    static let maxTextCharacters = 200_000
    static let maxImageBytes = 8 * 1024 * 1024
    /// Shorter text stays unlabeled in the history list. Images always show a size.
    static let minimumDisplayedTextBytes = 1_024

    static func acceptsText(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maxTextCharacters
    }

    static func acceptsImageByteCount(_ count: Int) -> Bool {
        count >= 32 && count <= maxImageBytes
    }

    static func showsStoredSize(of item: ClipboardItem) -> Bool {
        switch item.kind {
        case .image:
            return true
        case .text:
            return item.byteCount >= minimumDisplayedTextBytes
        }
    }
}

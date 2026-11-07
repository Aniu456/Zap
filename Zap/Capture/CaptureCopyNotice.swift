import Foundation

/// Toast after a capture is placed on the clipboard.
/// Success is silent. Only a history rejection is announced.
enum CaptureCopyNotice {
    static func message(storedInHistory: Bool) -> String? {
        storedInHistory ? nil : L10n.captureTooLarge
    }
}

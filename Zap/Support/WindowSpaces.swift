import AppKit

/// Spaces behavior that macOS 26 will actually accept.
///
/// `canJoinAllSpaces` cannot be combined with `moveToActiveSpace`. On macOS 26,
/// adding `fullScreenAuxiliary` or `stationary` to an all-spaces window also
/// fails `-[NSWindow _validateCollectionBehavior:]` and aborts the process.
enum WindowSpaces {
    static let overlay: NSWindow.CollectionBehavior = sanitized([.canJoinAllSpaces, .ignoresCycle])

    static func sanitized(_ behavior: NSWindow.CollectionBehavior) -> NSWindow.CollectionBehavior {
        var behavior = behavior
        if behavior.contains(.canJoinAllSpaces) {
            behavior.remove(.moveToActiveSpace)
            behavior.remove(.fullScreenAuxiliary)
            behavior.remove(.fullScreenPrimary)
            behavior.remove(.stationary)
        }
        return behavior
    }

    static func apply(to window: NSWindow) {
        window.collectionBehavior = overlay
    }
}

import AppKit
import Sparkle

/// Sparkle keeps a weak reference to this delegate, so `AppDelegate` retains it.
/// A menu-bar app is an accessory; Sparkle's alerts need a regular activation
/// policy for the update window to come forward.
final class UpdatePresenter: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        bringUpdateUIForward()
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        bringUpdateUIForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func bringUpdateUIForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

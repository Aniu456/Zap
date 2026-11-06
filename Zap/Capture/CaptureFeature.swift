import Foundation

/// Seam for the screenshot feature. v1 does not capture the screen.
///
/// A later version can register `reservedHotkeyID` with `HotkeyManager`, grab a
/// region, annotate (arrow, box, text, mosaic), and pin the result in its own
/// window. The PNG should be handed to `ClipboardStore.recordImageData(_:caption:)`,
/// or simply written to the general pasteboard: `ClipboardMonitor` already records
/// images. Doing both is safe; history deduplicates by content hash.
enum CaptureFeature {
    static let reservedHotkeyID: UInt32 = 3
}

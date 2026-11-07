import AppKit

/// Bitmap of the Zap icon for in-app UI.
///
/// The asset-catalog app icon is complete, but this accessory app cannot show
/// it through the usual lookups. `NSApp.applicationIconImage` stays the generic
/// document glyph: an `LSUIElement` app never gets a Dock tile, so AppKit leaves
/// that property on the placeholder in both Debug and Release. `Image("AppIcon")`
/// does not resolve either, because an appiconset is not a named image. Workspace
/// icons are IconServices representations, which SwiftUI draws as the same blank
/// page, and Xcode's DerivedData build is often missing from the icon cache.
/// `AppIconImage` is an ordinary imageset of the same artwork.
enum AppIconArtwork {
    static let assetName = "AppIconImage"

    static func bundledImage() -> NSImage? {
        guard let image = NSImage(named: assetName), hasPixels(image) else { return nil }
        image.isTemplate = false
        return image
    }

    /// Settings header image. Prefers the imageset, then a rasterized bundle icon.
    /// Never returns the raw Dock placeholder.
    static func image() -> NSImage {
        if let bundled = bundledImage() {
            return bundled
        }
        return rasterizedBundleIcon()
    }

    static func install() {
        // Hand the About panel its own image. The settings header keeps the
        // named bitmap; this copy is what replaces the accessory placeholder.
        let icon = (image().copy() as? NSImage) ?? image()
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    static func rasterizedBundleIcon() -> NSImage {
        rasterized(NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
    }

    static func rasterized(_ source: NSImage, side: CGFloat = 256) -> NSImage {
        let drawing = (source.copy() as? NSImage) ?? source
        if drawing.size.width < 1 || drawing.size.height < 1 {
            drawing.size = NSSize(width: side, height: side)
        }
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawing.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: drawing.size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func hasPixels(_ image: NSImage) -> Bool {
        guard image.isValid else { return false }
        if image.size.width > 1, image.size.height > 1 { return true }
        return image.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
    }
}

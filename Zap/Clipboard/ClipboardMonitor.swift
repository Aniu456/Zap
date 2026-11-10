import AppKit

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated {
                ClipboardMonitor.shared.poll()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if ClipboardStore.shared.isApplyingPasteboard { return }
        if ClipboardStore.shared.consumeIgnored(count) { return }
        ClipboardStore.shared.discardPasteFiles()
        ClipboardStore.shared.clearPasteboardSelection()
        ingest(pasteboard)
    }

    private func ingest(_ pasteboard: NSPasteboard) {
        if shouldSkip(pasteboard) { return }
        let source = pasteboard.string(forType: .init("org.nspasteboard.source"))
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let string = pasteboard.string(forType: .string)
        if let image = pngData(from: pasteboard) {
            let longText = (string?.count ?? 0) > 300
            let smallImage = image.count < 32_000
            if longText && smallImage {
                if let string { ClipboardStore.shared.recordText(string, source: source) }
                return
            }
            let caption: String?
            if let string, !string.isEmpty, string.count <= 300 {
                caption = string
            } else {
                caption = nil
            }
            ClipboardStore.shared.recordImageData(image, caption: caption, source: source)
            return
        }
        if let string, ClipboardPolicy.acceptsText(string) {
            ClipboardStore.shared.recordText(string, source: source)
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let text = urls.map { $0.isFileURL ? $0.path : $0.absoluteString }.joined(separator: "\n")
            ClipboardStore.shared.recordText(text, source: source)
        }
    }

    private func shouldSkip(_ pasteboard: NSPasteboard) -> Bool {
        let blocked: Set<NSPasteboard.PasteboardType> = [
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        ]
        return pasteboard.types?.contains(where: { blocked.contains($0) }) ?? false
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), ClipboardPolicy.acceptsImageByteCount(png.count) {
            return png
        }
        let jpeg = NSPasteboard.PasteboardType("public.jpeg")
        if let data = pasteboard.data(forType: jpeg),
           let image = NSImage(data: data),
           let png = Self.pngData(from: image),
           ClipboardPolicy.acceptsImageByteCount(png.count) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           ClipboardPolicy.acceptsImageByteCount(png.count) {
            return png
        }
        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

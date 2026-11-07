import AppKit
import CryptoKit
import ImageIO

struct RankedClip: Identifiable {
    var id: UUID { item.id }
    let item: ClipboardItem
    let match: FuzzyMatch
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet { cachedRanking = nil }
    }

    private var cachedRanking: (query: String, rows: [RankedClip])?
    private let persistence = ClipboardPersistence()

    private var directory: URL?
    private var ignoredChangeCounts: Set<Int> = []
    private let thumbnails = NSCache<NSString, NSImage>()
    private(set) var isApplyingPasteboard = false

    init(directory: URL? = nil) {
        self.directory = directory
        thumbnails.countLimit = 200
        thumbnails.totalCostLimit = 8 * 1024 * 1024
    }

    /// Store rooted at `directory`, for tests. The app uses `shared`.
    convenience init(testingDirectory directory: URL) {
        self.init(directory: directory)
    }

    /// Sum of each item's `byteCount`. Not a directory walk, and not the thumbnail cache.
    var totalByteCount: Int {
        ClipboardHistory.totalBytes(items)
    }

    var limitWarning: ClipboardLimitWarning? {
        ClipboardHistory.limitWarning(for: items)
    }

    var usageLine: String {
        DiskUsageFormat.historyLine(bytes: totalByteCount, count: items.count)
    }

    func load() {
        do {
            let directory = try directory ?? Self.prepareDirectories()
            load(from: directory)
        } catch {
            items = []
        }
    }

    /// Reads `history.json`, then drops oldest unpinned rows that exceed either cap and saves.
    func load(from directory: URL) {
        guard persistence.flush() else { return }
        self.directory = directory
        let url = directory.appendingPathComponent("history.json")
        do {
            let decoded: [ClipboardItem]
            do {
                let data = try Data(contentsOf: url)
                decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            } catch CocoaError.fileReadNoSuchFile {
                // The first PNG may have been written before the first index was saved.
                decoded = []
            }
            // Compare against the durable index before evicting any indexed rows.
            removeOrphanedImages(in: directory, referencedBy: decoded)
            let update = ClipboardHistory.applyingLimits(decoded)
            items = update.items
            guard !update.removed.isEmpty else { return }
            deleteFiles(for: update.removed)
            save()
            // Load-time eviction must hit disk immediately; delayed writes would
            // leave the old history.json and image files in place.
            _ = flush()
        } catch {
            items = []
        }
    }

    private func removeOrphanedImages(in directory: URL, referencedBy history: [ClipboardItem]) {
        let images = directory.appendingPathComponent("images", isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard (try? images.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let files = try? FileManager.default.contentsOfDirectory(
                at: images, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
              ) else { return }
        let retained = Set(history.compactMap { $0.imageFilename?.lowercased() })
        for file in files {
            let name = file.lastPathComponent
            guard file.pathExtension == "png",
                  UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  !retained.contains(name.lowercased()),
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink == false else { continue }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                NSLog("Zap orphan image cleanup failed: %@", error.localizedDescription)
            }
        }
    }

    func save() {
        guard let directory = directory ?? (try? Self.prepareDirectories()) else { return }
        self.directory = directory
        persistence.schedule(items: items, directory: directory)
    }

    /// Drain queued writes before the process exits.
    @discardableResult
    func flush() -> Bool {
        persistence.flush()
    }

    func recordText(_ text: String) {
        guard ClipboardPolicy.acceptsText(text) else { return }
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            text: text,
            imageFilename: nil,
            contentHash: Self.fingerprint(Data(text.utf8)),
            createdAt: Date(),
            byteCount: text.utf8.count
        )
        apply(item)
    }

    /// Puts a capture on the system pasteboard and into history.
    /// Returns false when the PNG is outside the history size limit; the pasteboard write still happens.
    @discardableResult
    func publishCapturedPNG(_ data: Data, caption: String) -> Bool {
        let pasteboard = NSPasteboard.general
        isApplyingPasteboard = true
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
        pasteboard.setData(data, forType: .png)
        ignoredChangeCounts.insert(pasteboard.changeCount)
        isApplyingPasteboard = false
        guard ClipboardPolicy.acceptsImageByteCount(data.count) else { return false }
        recordImageData(data, caption: caption)
        return true
    }

    /// `data` must be PNG bytes.
    func recordImageData(_ data: Data, caption: String?) {
        guard ClipboardPolicy.acceptsImageByteCount(data.count) else { return }
        let hash = Self.fingerprint(data)
        let storedCaption = caption.flatMap { ClipboardPolicy.acceptsText($0) ? $0 : nil }
        if items.contains(where: { $0.kind == .image && $0.contentHash == hash }) {
            let placeholder = ClipboardItem(
                id: UUID(),
                kind: .image,
                text: storedCaption,
                imageFilename: nil,
                contentHash: hash,
                createdAt: Date(),
                byteCount: data.count
            )
            apply(placeholder)
            return
        }
        guard let directory = directory ?? (try? Self.prepareDirectories()) else { return }
        self.directory = directory
        let filename = UUID().uuidString + ".png"
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        let item = ClipboardItem(
            id: UUID(),
            kind: .image,
            text: storedCaption,
            imageFilename: filename,
            contentHash: hash,
            createdAt: Date(),
            byteCount: data.count
        )
        apply(item)
    }

    func removeAll() {
        let removed = items
        items = []
        deleteFiles(for: removed)
        save()
    }

    func delete(_ ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        deleteFiles(for: removed)
        save()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].pinnedAt == nil {
            items[index].pinnedAt = Date()
        } else {
            items[index].pinnedAt = nil
        }
        save()
    }

    func ranked(matching query: String) -> [RankedClip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedRanking, cachedRanking.query == trimmed { return cachedRanking.rows }
        let rows = computeRanking(matching: trimmed)
        cachedRanking = (trimmed, rows)
        return rows
    }

    private func computeRanking(matching trimmed: String) -> [RankedClip] {
        if trimmed.isEmpty {
            return ClipboardHistory.sortedForDisplay(items).map {
                RankedClip(item: $0, match: FuzzyMatch(score: 0, indices: []))
            }
        }
        return items.compactMap { item in
            guard let match = FuzzyMatcher.match(query: trimmed, candidate: item.searchableText) else { return nil }
            return RankedClip(item: item, match: match)
        }
        .sorted { lhs, rhs in
            if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
            if (lhs.item.pinnedAt != nil) != (rhs.item.pinnedAt != nil) {
                return lhs.item.pinnedAt != nil
            }
            return lhs.item.createdAt > rhs.item.createdAt
        }
    }

    func thumbnail(for item: ClipboardItem, pointSize: CGFloat = 32, scale: CGFloat = 2) -> NSImage? {
        guard item.kind == .image, let name = item.imageFilename, let directory,
              pointSize.isFinite, scale.isFinite, pointSize > 0, scale > 0 else { return nil }
        let pixels = Int(min(512, ceil(pointSize * scale)))
        let key = "\(name):\(pixels)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        let representation = NSBitmapImageRep(cgImage: bitmap)
        let image = NSImage(size: NSSize(width: bitmap.width, height: bitmap.height))
        image.addRepresentation(representation)
        thumbnails.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }

    func placeOnPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        isApplyingPasteboard = true
        defer {
            ignoredChangeCounts.insert(pasteboard.changeCount)
            isApplyingPasteboard = false
        }
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = pngData(for: item) {
                if let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                }
                pasteboard.setData(data, forType: .png)
            } else if pasteboard.types?.isEmpty ?? true, let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    private func pngData(for item: ClipboardItem) -> Data? {
        guard let directory, let name = item.imageFilename else { return nil }
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    func consumeIgnored(_ changeCount: Int) -> Bool {
        ignoredChangeCounts.remove(changeCount) != nil
    }

    private func apply(_ item: ClipboardItem) {
        let update = ClipboardHistory.inserting(
            item,
            into: items,
            limit: ClipboardPolicy.maxItems,
            diskBudget: ClipboardPolicy.maxDiskBytes
        )
        items = update.items
        deleteFiles(for: update.removed)
        save()
    }

    private func deleteFiles(for removed: [ClipboardItem]) {
        let names = removed.compactMap(\.imageFilename)
        guard let directory, !names.isEmpty else { return }
        thumbnails.removeAllObjects()
        persistence.removeAfterSave(names, directory: directory)
    }

    private static func prepareDirectories() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Zap", isDirectory: true)
        let images = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        return directory
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// All mutable state belongs to the serial queue. Snapshots are immutable values.
final class ClipboardPersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Zap.clipboard.persistence", qos: .utility)
    private var pending: (items: [ClipboardItem], directory: URL)?
    private var obsoleteImages = Set<URL>()
    private var scheduled = false

    func schedule(items: [ClipboardItem], directory: URL) {
        queue.async {
            self.pending = (items, directory)
            guard !self.scheduled else { return }
            self.scheduled = true
            self.queue.asyncAfter(deadline: .now() + 0.25) {
                self.scheduled = false
                _ = self.writePending()
            }
        }
    }

    func removeAfterSave(_ names: [String], directory: URL) {
        let urls = names.map {
            directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent($0)
        }
        queue.async {
            self.obsoleteImages.formUnion(urls)
        }
    }

    @discardableResult
    func flush() -> Bool {
        queue.sync { writePending() }
    }

    private func writePending() -> Bool {
        guard let snapshot = pending else { return true }
        do {
            let data = try JSONEncoder().encode(snapshot.items)
            try data.write(to: snapshot.directory.appendingPathComponent("history.json"), options: .atomic)
            pending = nil
        } catch {
            // Keep the latest snapshot for the next mutation or termination flush.
            NSLog("Zap clipboard history save failed: %@", error.localizedDescription)
            return false
        }

        let retained = Set(snapshot.items.compactMap { item -> URL? in
            guard let name = item.imageFilename else { return nil }
            return snapshot.directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        })
        for url in obsoleteImages.subtracting(retained) {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                obsoleteImages.remove(url)
            } catch {
                NSLog("Zap clipboard image cleanup failed: %@", error.localizedDescription)
            }
        }
        return true
    }
}

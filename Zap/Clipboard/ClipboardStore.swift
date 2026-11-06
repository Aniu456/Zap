import AppKit
import CryptoKit

struct RankedClip: Identifiable {
    var id: UUID { item.id }
    let item: ClipboardItem
    let match: FuzzyMatch
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = []

    private var directory: URL?
    private var ignoredChangeCounts: Set<Int> = []
    private let thumbnails = NSCache<NSString, NSImage>()
    private(set) var isApplyingPasteboard = false

    private init() {
        thumbnails.countLimit = 40
    }

    func load() {
        do {
            let directory = try Self.prepareDirectories()
            self.directory = directory
            let url = directory.appendingPathComponent("history.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            items = []
        }
    }

    func save() {
        guard let directory = directory ?? (try? Self.prepareDirectories()) else { return }
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        let url = directory.appendingPathComponent("history.json")
        try? data.write(to: url, options: .atomic)
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

    /// Public entry for a future capture feature, and for images already on the pasteboard.
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

    func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        deleteFiles(for: [removed])
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

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let name = item.imageFilename else { return nil }
        if let cached = thumbnails.object(forKey: name as NSString) {
            return cached
        }
        guard let directory else { return nil }
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        guard let image = NSImage(contentsOf: url) else { return nil }
        thumbnails.setObject(image, forKey: name as NSString)
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
            if let image = image(for: item) {
                pasteboard.writeObjects([image])
            }
            if let data = pngData(for: item) {
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
        let update = ClipboardHistory.inserting(item, into: items, limit: ClipboardPolicy.maxItems)
        items = update.items
        deleteFiles(for: update.removed)
        save()
    }

    private func deleteFiles(for removed: [ClipboardItem]) {
        guard let directory else { return }
        let keep = Set(items.compactMap(\.imageFilename))
        for item in removed {
            guard let name = item.imageFilename, !keep.contains(name) else { continue }
            let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
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

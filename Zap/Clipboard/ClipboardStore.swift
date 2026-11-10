import AppKit
import CryptoKit
import ImageIO
import Vision
import CoreImage

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

    @Published private(set) var pasteboardItemID: UUID?
    private var indexingImages = false
    private var failedOCRFiles = Set<String>()
    private let pasteboard: NSPasteboard
    private var selectedChangeCount: Int?
    private var sources: [String: (name: String, icon: NSImage)] = [:]

    func sourceApp(_ bundleID: String) -> (name: String, icon: NSImage)? {
        if let source = sources[bundleID] { return source }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let source = (url.deletingPathExtension().lastPathComponent, NSWorkspace.shared.icon(forFile: url.path))
        sources[bundleID] = source
        return source
    }

    func clearPasteboardSelection() { pasteboardItemID = nil }

    private var cachedRanking: (query: String, rows: [RankedClip])?
    private let persistence = ClipboardPersistence()

    private var directory: URL?
    private var ignoredChangeCounts: Set<Int> = []
    private let thumbnails = NSCache<NSString, NSImage>()
    private(set) var isApplyingPasteboard = false
    /// Kept alive while their items are on the pasteboard.
    private var pasteProviders: [PasteDataProvider] = []

    init(directory: URL? = nil, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
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
        discardPasteFiles()
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
            indexImages()
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

    func recordText(_ text: String, source: String? = nil) {
        guard ClipboardPolicy.acceptsText(text) else { return }
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            text: text,
            imageFilename: nil,
            contentHash: Self.fingerprint(Data(text.utf8)),
            createdAt: Date(),
            byteCount: text.utf8.count, sourceBundleID: source
        )
        apply(item)
    }

    /// Puts a capture on the system pasteboard and into history.
    /// Returns false when the PNG is outside the history size limit; the pasteboard write still happens.
    @discardableResult
    func publishCapturedPNG(_ data: Data, caption: String) -> Bool {
        clearPasteboardSelection()
        isApplyingPasteboard = true
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
        pasteboard.setData(data, forType: .png)
        ignoredChangeCounts.insert(pasteboard.changeCount)
        isApplyingPasteboard = false
        guard ClipboardPolicy.acceptsImageByteCount(data.count) else { return false }
        recordImageData(data, caption: caption, source: Bundle.main.bundleIdentifier)
        return true
    }

    /// `data` must be PNG bytes.
    func recordImageData(_ data: Data, caption: String?, source: String? = nil) {
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
                byteCount: data.count, sourceBundleID: source
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
            byteCount: data.count, sourceBundleID: source
        )
        apply(item)
    }

    func removeAll() {
        let removed = items
        clearPasteboardSelection()
        items = []
        deleteFiles(for: removed)
        save()
    }

    func delete(_ ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        if let pasteboardItemID, ids.contains(pasteboardItemID) { clearPasteboardSelection() }
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
            let match = FuzzyMatcher.match(query: trimmed, candidate: item.searchableText)
            let ocrHit = match == nil && item.matchesRecognizedText(trimmed)
            guard let match = match ?? (ocrHit ? FuzzyMatch(score: 1, indices: []) : nil) else { return nil }
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
        let pixels = Int(min(1280, ceil(pointSize * scale)))
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

    @discardableResult
    func placeOnPasteboard(_ item: ClipboardItem) -> Bool {
        discardPasteFiles()
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            return writePasteboard(id: item.id) { $0.setString(text, forType: .string) }
        case .image:
            guard let data = pngData(for: item) else { return false }
            return writePasteboard(id: item.id) { board in
                if let image = NSImage(data: data) { board.writeObjects([image]) }
                return board.setData(data, forType: .png)
            }
        }
    }

    /// Writes one paste step. Data is handed out lazily so `onRead` fires the moment the target app
    /// actually reads it, which lets a multi-step paste move on without a fixed pause.
    @discardableResult
    func placeStepOnPasteboard(_ step: ClipboardItem.PasteStep, onRead: @escaping () -> Void = {}) -> Bool {
        var payloads: [[NSPasteboard.PasteboardType: Data]] = []
        switch step {
        case .text(let text):
            payloads = [[.string: Data(text.utf8)]]
        case .images(let items):
            if pasteFolder == nil { beginPasteBatch() }
            let folder = pasteFolder
            for item in items {
                guard let png = pngData(for: item) else { continue }
                var payload: [NSPasteboard.PasteboardType: Data] = [.png: png]
                if let folder {
                    pasteImageCount += 1
                    let url = folder.appendingPathComponent("image-\(String(format: "%04d", pasteImageCount)).png")
                    if (try? png.write(to: url)) != nil { payload[.fileURL] = Data(url.absoluteString.utf8) }
                }
                payloads.append(payload)
            }
        }
        guard !payloads.isEmpty else { return false }
        // Report once, after the target has read every item, so the next step never clears data still being pasted.
        var unread = payloads.count
        let providers = payloads.map { PasteDataProvider(payload: $0) {
            unread -= 1
            if unread == 0 { onRead() }
        } }
        pasteProviders = providers
        return writePasteboard(id: nil) { board in
            let items = providers.map { provider -> NSPasteboardItem in
                let item = NSPasteboardItem()
                item.setDataProvider(provider, forTypes: provider.types)
                return item
            }
            return board.writeObjects(items)
        }
    }

    private var pasteFolder: URL?
    private var pasteImageCount = 0

    /// Starts one batch of pasted image files. Names keep counting across the batch's steps,
    /// so inputs that dedupe attachments by file name never see the same name twice.
    func beginPasteBatch() {
        discardPasteFiles()
        let folder = Self.pasteRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        pasteFolder = (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil ? folder : nil
        pasteImageCount = 0
    }

    /// Pasted image files are only needed while their batch is on the clipboard. Called when the clipboard
    /// moves on (another paste from here, or a new copy anywhere), at launch, and at quit.
    func discardPasteFiles() {
        pasteProviders.removeAll()
        try? FileManager.default.removeItem(at: Self.pasteRoot)
        pasteFolder = nil
        pasteImageCount = 0
    }

    static var pasteRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ZapPaste", isDirectory: true)
    }

    func placeTextOnPasteboard(_ text: String) -> Bool {
        discardPasteFiles()
        return writePasteboard(id: nil) { $0.setString(text, forType: .string) }
    }

    private func writePasteboard(id: UUID?, write: (NSPasteboard) -> Bool) -> Bool {
        let board = pasteboard
        isApplyingPasteboard = true
        defer { isApplyingPasteboard = false }
        board.clearContents()
        let wrote = write(board)
        ignoredChangeCounts = [board.changeCount]
        selectedChangeCount = board.changeCount
        pasteboardItemID = wrote ? id : nil
        return wrote
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFilename else { return nil }
        return directory?.appendingPathComponent("images").appendingPathComponent(name)
    }

    // Index one image at a time. The file identity also guards edits or deletion during OCR.
    private func indexImages() {
        guard !indexingImages else { return }
        indexingImages = true
        Task {
            defer { indexingImages = false }
            while let item = items.first(where: {
                guard let name = $0.imageFilename else { return false }
                return $0.kind == .image && $0.recognizedText == nil && !failedOCRFiles.contains(name)
            }),
                  let url = imageURL(for: item) {
                let words = await Task.detached(priority: .utility) { () -> String? in
                    let request = VNRecognizeTextRequest()
                    request.revision = VNRecognizeTextRequestRevision3
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["zh-Hans", "en-US"]
                    do {
                        try VNImageRequestHandler(url: url).perform([request])
                        return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: "\n").prefix(16_000))
                    } catch { return nil }
                }.value
                guard let index = items.firstIndex(where: { $0.id == item.id && $0.imageFilename == item.imageFilename }) else { continue }
                guard let words else { failedOCRFiles.insert(url.lastPathComponent); continue }
                items[index].recognizedText = words
                save()
            }
        }
    }

    func edit(_ original: ClipboardItem, text: String? = nil, quarterTurns: Int = 0) -> Bool {
        guard var item = items.first(where: { $0.id == original.id && $0.contentHash == original.contentHash }) else { return false }
        let data: Data
        if item.kind == .text {
            guard let text, ClipboardPolicy.acceptsText(text) else { return false }
            data = Data(text.utf8)
            item.text = text
        } else {
            guard quarterTurns % 4 != 0 else { return true }
            guard let url = imageURL(for: item), let image = CIImage(contentsOf: url) else { return false }
            let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
            let rotated = image.oriented(orientations[quarterTurns % 4])
            guard let png = CIContext().pngRepresentation(of: rotated, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()),
                  ClipboardPolicy.acceptsImageByteCount(png.count) else { return false }
            data = png
        }
        item.contentHash = Self.fingerprint(data)
        guard !items.contains(where: { $0.id != item.id && $0.kind == item.kind && $0.contentHash == item.contentHash }) else { return false }
        if item.kind == .image {
            item.imageFilename = UUID().uuidString + ".png"
            item.recognizedText = nil
            guard let url = imageURL(for: item) else { return false }
            do { try data.write(to: url, options: .atomic) } catch { return false }
            deleteFiles(for: [original])
        }
        item.byteCount = data.count
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        items[index] = item
        let update = ClipboardHistory.applyingLimits(items)
        items = update.items
        deleteFiles(for: update.removed)
        save()
        if pasteboardItemID == item.id && selectedChangeCount == pasteboard.changeCount { placeOnPasteboard(item) }
        indexImages()
        return true
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
        selectedChangeCount = pasteboard.changeCount
        pasteboardItemID = items.first(where: { $0.contentHash == item.contentHash && $0.kind == item.kind })?.id
        deleteFiles(for: update.removed)
        save()
        if item.kind == .image { indexImages() }
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

/// Supplies one pasteboard item's data on demand and reports the first read.
final class PasteDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let payload: [NSPasteboard.PasteboardType: Data]
    var types: [NSPasteboard.PasteboardType] {
        var types = Array(payload.keys)
        if payload[.png] != nil { types.append(.tiff) }
        return types
    }
    private var onRead: (() -> Void)?

    init(payload: [NSPasteboard.PasteboardType: Data], onRead: @escaping () -> Void) {
        self.payload = payload
        self.onRead = onRead
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        let data: Data?
        if type == .tiff, let png = payload[.png] {
            data = NSImage(data: png)?.tiffRepresentation
        } else {
            data = payload[type]
        }
        guard let data, item.setData(data, forType: type) else { return }
        if let onRead {
            self.onRead = nil
            DispatchQueue.main.async(execute: onRead)
        }
    }
}

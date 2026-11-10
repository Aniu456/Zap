import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable {
        case text
        case image
    }

    var id: UUID
    var kind: Kind
    var text: String?
    var imageFilename: String?
    var contentHash: String
    var createdAt: Date
    var byteCount: Int
    /// Set while the item is pinned. Pinned rows stay at the top and are never auto-deleted.
    var pinnedAt: Date? = nil
    var sourceBundleID: String?
    var recognizedText: String?

    enum PasteSegment: Equatable {
        case text(String)
        case image(ClipboardItem)
    }

    /// Selection order is kept: consecutive text runs join with newlines, each image is its own step.
    static func pasteSegments(_ selection: [ClipboardItem]) -> [PasteSegment] {
        var segments: [PasteSegment] = []
        for item in selection {
            switch item.kind {
            case .text:
                guard let text = item.text else { continue }
                if case .text(let previous)? = segments.last {
                    segments[segments.count - 1] = .text(previous + "\n" + text)
                } else {
                    segments.append(.text(text))
                }
            case .image:
                segments.append(.image(item))
            }
        }
        return segments
    }

    /// One ⌘V each. Text runs join with newlines; consecutive images go together as several
    /// pasteboard items (file + PNG), the form chat apps and web inputs accept.
    enum PasteStep: Equatable {
        case text(String)
        case images([ClipboardItem])
    }

    static func pasteSteps(_ selection: [ClipboardItem]) -> [PasteStep] {
        var steps: [PasteStep] = []
        for segment in pasteSegments(selection) {
            switch segment {
            case .text(let text):
                steps.append(.text(text))
            case .image(let item):
                if case .images(let run)? = steps.last {
                    steps[steps.count - 1] = .images(run + [item])
                } else {
                    steps.append(.images([item]))
                }
            }
        }
        return steps
    }

    static func joinedText(_ selection: [ClipboardItem]) -> String? {
        guard !selection.isEmpty, selection.allSatisfy({ $0.kind == .text && $0.text != nil }) else { return nil }
        return selection.compactMap(\.text).joined(separator: "\n")
    }

    /// Single-line text used both for search and for the row title.
    var searchableText: String {
        switch kind {
        case .text:
            return Self.collapse(text ?? "")
        case .image:
            let caption = Self.collapse(text ?? "")
            return caption.isEmpty ? L10n.imageLabel : "\(L10n.imageLabel) \(caption)"
        }
    }

    var displayText: String {
        String(searchableText.prefix(180))
    }

    // OCR can misread one glyph even in otherwise legible screenshots.
    func matchesRecognizedText(_ query: String) -> Bool {
        guard let recognizedText, !recognizedText.isEmpty else { return false }
        if recognizedText.localizedCaseInsensitiveContains(query) { return true }
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard terms.contains(where: { $0.count >= 5 }) else { return false }
        let words = recognizedText.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard words.count >= terms.count else { return false }
        return (0...(words.count - terms.count)).contains { start in
            terms.enumerated().allSatisfy { offset, term in
                let word = words[start + offset]
                if word == term { return true }
                guard term.count >= 5, term.count <= 48, abs(word.count - term.count) <= 1 else { return false }
                if word.count == term.count {
                    return zip(word, term).filter { $0 != $1 }.count <= 1
                }
                return word.difference(from: term).count == 1
            }
        }
    }

    private static func collapse(_ text: String) -> String {
        let parts = text.split { $0.isWhitespace }
        return String(parts.joined(separator: " ").prefix(8_000))
    }
}

struct HistoryUpdate {
    var items: [ClipboardItem]
    var removed: [ClipboardItem]
}

enum ClipboardLimitWarning: Equatable {
    case pinnedOverDisk
    case pinnedOverCount
    case pinnedOverDiskAndCount
}

enum ClipboardHistory {
    /// Newest item stays at index 0. An identical hash moves to the front instead of duplicating.
    /// Both the item-count cap and the disk budget apply. Oldest unpinned rows go first.
    /// Pinned rows are never removed; if they alone still exceed a cap, they stay.
    static func inserting(
        _ item: ClipboardItem,
        into items: [ClipboardItem],
        limit: Int,
        diskBudget: Int = ClipboardPolicy.maxDiskBytes
    ) -> HistoryUpdate {
        var next = items
        if let index = next.firstIndex(where: { $0.kind == item.kind && $0.contentHash == item.contentHash }) {
            var existing = next.remove(at: index)
            existing.createdAt = item.createdAt
            existing.sourceBundleID = item.sourceBundleID
            next.insert(existing, at: 0)
        } else {
            next.insert(item, at: 0)
        }
        return applyingLimits(next, limit: limit, diskBudget: diskBudget)
    }

    /// Drops the oldest unpinned items until both caps hold. Storage order is newest-first,
    /// so the oldest unpinned row is the last one in the array.
    static func applyingLimits(
        _ items: [ClipboardItem],
        limit: Int = ClipboardPolicy.maxItems,
        diskBudget: Int = ClipboardPolicy.maxDiskBytes
    ) -> HistoryUpdate {
        var next = items
        var removed: [ClipboardItem] = []
        while next.count > limit || totalBytes(next) > diskBudget {
            guard let index = next.lastIndex(where: { $0.pinnedAt == nil }) else { break }
            removed.append(next.remove(at: index))
        }
        return HistoryUpdate(items: next, removed: removed)
    }

    static func totalBytes(_ items: [ClipboardItem]) -> Int {
        items.reduce(0) { $0 + max(0, $1.byteCount) }
    }

    /// Non-nil only when every remaining row is pinned and a cap is still exceeded.
    static func limitWarning(
        for items: [ClipboardItem],
        limit: Int = ClipboardPolicy.maxItems,
        diskBudget: Int = ClipboardPolicy.maxDiskBytes
    ) -> ClipboardLimitWarning? {
        let overDisk = totalBytes(items) > diskBudget
        let overCount = items.count > limit
        guard overDisk || overCount else { return nil }
        guard !items.contains(where: { $0.pinnedAt == nil }) else { return nil }
        if overDisk && overCount { return .pinnedOverDiskAndCount }
        if overDisk { return .pinnedOverDisk }
        return .pinnedOverCount
    }

    /// Pinned items first (most recently pinned), then everything else newest first.
    static func sortedForDisplay(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted { lhs, rhs in
            switch (lhs.pinnedAt, rhs.pinnedAt) {
            case let (left?, right?):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

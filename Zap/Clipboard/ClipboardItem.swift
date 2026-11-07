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

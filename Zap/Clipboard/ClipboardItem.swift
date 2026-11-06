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

enum ClipboardHistory {
    /// Newest item stays at index 0. An identical hash moves to the front instead of duplicating.
    static func inserting(_ item: ClipboardItem, into items: [ClipboardItem], limit: Int) -> HistoryUpdate {
        var next = items
        if let index = next.firstIndex(where: { $0.kind == item.kind && $0.contentHash == item.contentHash }) {
            var existing = next.remove(at: index)
            existing.createdAt = item.createdAt
            next.insert(existing, at: 0)
        } else {
            next.insert(item, at: 0)
        }
        var removed: [ClipboardItem] = []
        if next.count > limit {
            removed = Array(next.suffix(next.count - limit))
            next.removeLast(next.count - limit)
        }
        return HistoryUpdate(items: next, removed: removed)
    }
}

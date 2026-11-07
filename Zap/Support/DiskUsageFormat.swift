import Foundation

/// Binary byte counts for the history budget. The thumbnail cache is RAM and is not included.
enum DiskUsageFormat {
    static func bytes(_ count: Int) -> String {
        let safe = Int64(max(0, count))
        if safe == 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.locale = Locale(identifier: "zh-Hans-SG")
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.includesActualByteCount = false
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: safe)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    static func historyLine(
        bytes: Int,
        count: Int,
        maxBytes: Int = ClipboardPolicy.maxDiskBytes,
        maxItems: Int = ClipboardPolicy.maxItems
    ) -> String {
        "\(self.bytes(bytes)) / \(self.bytes(maxBytes)) · \(count) / \(maxItems) 条"
    }
}

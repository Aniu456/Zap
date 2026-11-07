import XCTest
@testable import Zap

private enum BudgetFixtures {
    static func item(
        hash: String,
        offset: Int,
        bytes: Int,
        kind: ClipboardItem.Kind = .text,
        filename: String? = nil,
        pinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            text: hash,
            imageFilename: filename,
            contentHash: hash,
            createdAt: Date(timeIntervalSince1970: TimeInterval(offset)),
            byteCount: bytes,
            pinnedAt: pinned ? Date(timeIntervalSince1970: TimeInterval(1_000 + offset)) : nil
        )
    }
}

final class ClipboardBudgetTests: XCTestCase {
    func testCountCapEvictsOldestUnpinned() {
        let pinned = BudgetFixtures.item(hash: "pinned", offset: 1, bytes: 8, pinned: true)
        let existing = [
            BudgetFixtures.item(hash: "fresh", offset: 4, bytes: 8),
            BudgetFixtures.item(hash: "mid", offset: 3, bytes: 8),
            BudgetFixtures.item(hash: "old", offset: 2, bytes: 8),
            pinned
        ]
        let update = ClipboardHistory.inserting(
            BudgetFixtures.item(hash: "new", offset: 9, bytes: 8),
            into: existing,
            limit: 4,
            diskBudget: ClipboardPolicy.maxDiskBytes
        )
        XCTAssertEqual(update.items.map(\.contentHash), ["new", "fresh", "mid", "pinned"])
        XCTAssertEqual(update.removed.map(\.contentHash), ["old"])
        XCTAssertTrue(update.items.contains(where: { $0.contentHash == "pinned" && $0.pinnedAt != nil }))
        XCTAssertNil(ClipboardHistory.limitWarning(for: update.items, limit: 4, diskBudget: ClipboardPolicy.maxDiskBytes))
    }

    func testCountCapStopsWhenOnlyPinsRemain() {
        let pins = (0..<4).map {
            BudgetFixtures.item(hash: "p\($0)", offset: $0, bytes: 8, pinned: true)
        }
        let update = ClipboardHistory.inserting(
            BudgetFixtures.item(hash: "new", offset: 20, bytes: 8),
            into: pins,
            limit: 3,
            diskBudget: 10_000
        )
        XCTAssertEqual(update.removed.map(\.contentHash), ["new"])
        XCTAssertEqual(update.items.map(\.contentHash), ["p0", "p1", "p2", "p3"])
        XCTAssertTrue(update.items.allSatisfy { $0.pinnedAt != nil })
        XCTAssertEqual(
            ClipboardHistory.limitWarning(for: update.items, limit: 3, diskBudget: 10_000),
            .pinnedOverCount
        )
    }

    func testDiskBudgetEvictsOldestUnpinnedWhileUnderTheCountCap() {
        let pinned = BudgetFixtures.item(hash: "pinned", offset: 1, bytes: 150, pinned: true)
        let existing = [
            BudgetFixtures.item(hash: "newer", offset: 3, bytes: 100),
            BudgetFixtures.item(hash: "older", offset: 2, bytes: 100),
            pinned
        ]
        let update = ClipboardHistory.inserting(
            BudgetFixtures.item(hash: "new", offset: 4, bytes: 100),
            into: existing,
            limit: 200,
            diskBudget: 300
        )
        XCTAssertLessThan(update.items.count, 200)
        XCTAssertEqual(update.items.map(\.contentHash), ["new", "pinned"])
        XCTAssertEqual(update.removed.map(\.contentHash), ["older", "newer"])
        XCTAssertLessThanOrEqual(ClipboardHistory.totalBytes(update.items), 300)
        XCTAssertNil(ClipboardHistory.limitWarning(for: update.items, limit: 200, diskBudget: 300))
    }

    func testPinnedItemsAreNeverAutoEvictedWhenDiskBudgetIsExceeded() {
        let pins = (0..<3).map {
            BudgetFixtures.item(hash: "p\($0)", offset: $0, bytes: 200, pinned: true)
        }
        let loose = BudgetFixtures.item(hash: "loose", offset: 10, bytes: 200)
        let update = ClipboardHistory.inserting(
            BudgetFixtures.item(hash: "new", offset: 11, bytes: 200),
            into: [loose] + pins,
            limit: 200,
            diskBudget: 300
        )
        XCTAssertEqual(update.items.map(\.contentHash), ["p0", "p1", "p2"])
        XCTAssertEqual(update.removed.map(\.contentHash), ["loose", "new"])
        XCTAssertTrue(update.items.allSatisfy { $0.pinnedAt != nil })
        XCTAssertGreaterThan(ClipboardHistory.totalBytes(update.items), 300)
        XCTAssertEqual(
            ClipboardHistory.limitWarning(for: update.items, limit: 200, diskBudget: 300),
            .pinnedOverDisk
        )
        let used = ClipboardHistory.totalBytes(update.items)
        let line = DiskUsageFormat.historyLine(bytes: used, count: update.items.count, maxBytes: 300, maxItems: 200)
        XCTAssertTrue(line.contains("3 / 200 条"))
        XCTAssertNotEqual(DiskUsageFormat.bytes(used), DiskUsageFormat.bytes(300))
        XCTAssertFalse(line.contains("内存"))
    }

    func testPinsThatExceedBothCapsStay() {
        let pins = (0..<3).map {
            BudgetFixtures.item(hash: "p\($0)", offset: $0, bytes: 200, pinned: true)
        }
        let update = ClipboardHistory.inserting(
            BudgetFixtures.item(hash: "new", offset: 9, bytes: 200),
            into: pins,
            limit: 2,
            diskBudget: 300
        )
        XCTAssertEqual(update.removed.map(\.contentHash), ["new"])
        XCTAssertEqual(update.items.count, 3)
        XCTAssertGreaterThan(update.items.count, 2)
        XCTAssertGreaterThan(ClipboardHistory.totalBytes(update.items), 300)
        XCTAssertEqual(
            ClipboardHistory.limitWarning(for: update.items, limit: 2, diskBudget: 300),
            .pinnedOverDiskAndCount
        )
    }

    func testUsageLineIncludesDiskAndCount() {
        XCTAssertEqual(ClipboardPolicy.maxItems, 200)
        XCTAssertEqual(ClipboardPolicy.maxDiskBytes, 256 * 1024 * 1024)
        let line = DiskUsageFormat.historyLine(bytes: 48 * 1024 * 1024, count: 37)
        XCTAssertEqual(
            line,
            "\(DiskUsageFormat.bytes(48 * 1024 * 1024)) / \(DiskUsageFormat.bytes(ClipboardPolicy.maxDiskBytes)) · 37 / 200 条"
        )
        let cap = DiskUsageFormat.bytes(ClipboardPolicy.maxDiskBytes)
        XCTAssertTrue(cap.contains("256"), cap)
        XCTAssertFalse(cap.contains("268"), cap)
        XCTAssertEqual(DiskUsageFormat.bytes(0), "0 KB")
        XCTAssertFalse(line.contains("内存"))
        XCTAssertEqual(L10n.diskUsage, "磁盘占用")
        XCTAssertTrue(L10n.pinnedOverDisk.contains("置顶内容已超过磁盘预算"))
        XCTAssertFalse(L10n.clipboardLimitWarning(.pinnedOverDisk).contains("内存"))
    }

    func testTinyTextHidesStoredSize() {
        let tiny = BudgetFixtures.item(hash: "tiny", offset: 1, bytes: ClipboardPolicy.minimumDisplayedTextBytes - 1)
        let long = BudgetFixtures.item(hash: "long", offset: 2, bytes: ClipboardPolicy.minimumDisplayedTextBytes)
        let image = BudgetFixtures.item(hash: "image", offset: 3, bytes: 40, kind: .image, filename: "a.png")
        XCTAssertFalse(ClipboardPolicy.showsStoredSize(of: tiny))
        XCTAssertTrue(ClipboardPolicy.showsStoredSize(of: long))
        XCTAssertTrue(ClipboardPolicy.showsStoredSize(of: image))
    }
}

final class ClipboardStoreBudgetTests: XCTestCase {
    @MainActor
    func testLoadTrimsOldestUnpinnedWhenDiskBudgetIsExceeded() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let budget = ClipboardPolicy.maxDiskBytes
        let pinned = BudgetFixtures.item(
            hash: "pinned",
            offset: 1,
            bytes: budget - 100,
            kind: .image,
            filename: "pinned.png",
            pinned: true
        )
        let older = BudgetFixtures.item(hash: "older", offset: 2, bytes: 80, kind: .image, filename: "older.png")
        let newer = BudgetFixtures.item(hash: "newer", offset: 3, bytes: 80, kind: .image, filename: "newer.png")
        try writeFile(named: "pinned.png", in: directory)
        try writeFile(named: "older.png", in: directory)
        try writeFile(named: "newer.png", in: directory)
        try writeHistory([newer, older, pinned], to: directory, pretty: false)

        let store = ClipboardStore(testingDirectory: directory)
        store.load(from: directory)

        XCTAssertEqual(store.items.map(\.contentHash), ["newer", "pinned"])
        XCTAssertLessThan(store.items.count, ClipboardPolicy.maxItems)
        XCTAssertLessThanOrEqual(store.totalByteCount, budget)
        XCTAssertNil(store.limitWarning)
        XCTAssertTrue(fileExists("pinned.png", in: directory))
        XCTAssertTrue(fileExists("newer.png", in: directory))
        XCTAssertFalse(fileExists("older.png", in: directory))
        let saved = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: historyURL(directory)))
        XCTAssertEqual(saved.map(\.contentHash), ["newer", "pinned"])
    }

    @MainActor
    func testLoadKeepsPinnedItemsThatStillExceedTheDiskBudget() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let budget = ClipboardPolicy.maxDiskBytes
        let pinned = BudgetFixtures.item(
            hash: "pinned",
            offset: 1,
            bytes: budget + 32 * 1024 * 1024,
            kind: .image,
            filename: "pinned.png",
            pinned: true
        )
        let older = BudgetFixtures.item(hash: "older", offset: 2, bytes: 1_024, kind: .image, filename: "older.png")
        try writeFile(named: "pinned.png", in: directory)
        try writeFile(named: "older.png", in: directory)
        try writeHistory([older, pinned], to: directory, pretty: true)

        let store = ClipboardStore(testingDirectory: directory)
        store.load(from: directory)

        XCTAssertEqual(store.items.map(\.contentHash), ["pinned"])
        XCTAssertGreaterThan(store.totalByteCount, budget)
        XCTAssertEqual(store.limitWarning, .pinnedOverDisk)
        XCTAssertTrue(store.usageLine.contains("1 / 200 条"))
        XCTAssertNotEqual(DiskUsageFormat.bytes(store.totalByteCount), DiskUsageFormat.bytes(budget))
        XCTAssertTrue(fileExists("pinned.png", in: directory))
        XCTAssertFalse(fileExists("older.png", in: directory))
        XCTAssertFalse(store.usageLine.contains("内存"))
    }

    @MainActor
    func testLoadTrimsOldestUnpinnedWhenCountCapIsExceeded() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unpinned = (0..<200).map {
            BudgetFixtures.item(hash: "u\($0)", offset: $0 + 1, bytes: 16)
        }
        let pinned = BudgetFixtures.item(hash: "pin", offset: 0, bytes: 16, pinned: true)
        try writeHistory(Array(unpinned.reversed()) + [pinned], to: directory, pretty: true)

        let store = ClipboardStore(testingDirectory: directory)
        store.load(from: directory)

        XCTAssertEqual(store.items.count, 200)
        XCTAssertTrue(store.items.contains(where: { $0.contentHash == "pin" && $0.pinnedAt != nil }))
        XCTAssertFalse(store.items.contains(where: { $0.contentHash == "u0" }))
        XCTAssertTrue(store.items.contains(where: { $0.contentHash == "u199" }))
        XCTAssertLessThanOrEqual(store.totalByteCount, ClipboardPolicy.maxDiskBytes)
        XCTAssertNil(store.limitWarning)
        let saved = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: historyURL(directory)))
        XCTAssertEqual(saved.map(\.contentHash), store.items.map(\.contentHash))
        XCTAssertFalse(saved.contains(where: { $0.contentHash == "u0" }))
    }

    @MainActor
    func testLoadDoesNotDeletePinsWhenTheyAlreadyExceedTheCountCap() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var pins = (0..<201).map {
            BudgetFixtures.item(hash: "p\($0)", offset: $0, bytes: 8, pinned: true)
        }
        pins[0].kind = .image
        pins[0].imageFilename = "keep.png"
        try writeFile(named: "keep.png", in: directory)
        try writeHistory(pins, to: directory, pretty: false)
        let before = try Data(contentsOf: historyURL(directory))

        let store = ClipboardStore(testingDirectory: directory)
        store.load(from: directory)

        XCTAssertEqual(store.items.count, 201)
        XCTAssertTrue(store.items.allSatisfy { $0.pinnedAt != nil })
        XCTAssertEqual(store.limitWarning, .pinnedOverCount)
        XCTAssertEqual(try Data(contentsOf: historyURL(directory)), before)
        XCTAssertTrue(fileExists("keep.png", in: directory))
        XCTAssertGreaterThan(store.items.count, ClipboardPolicy.maxItems)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zap-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func historyURL(_ directory: URL) -> URL {
        directory.appendingPathComponent("history.json")
    }

    private func writeHistory(_ items: [ClipboardItem], to directory: URL, pretty: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        try encoder.encode(items).write(to: historyURL(directory))
    }

    private func writeFile(named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        try Data([0x89, 0x50]).write(to: url)
    }

    private func fileExists(_ name: String, in directory: URL) -> Bool {
        let url = directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path)
    }
}

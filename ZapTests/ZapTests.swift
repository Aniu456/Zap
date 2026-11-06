import XCTest
@testable import Zap

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        let match = FuzzyMatcher.match(query: "   ", candidate: "Safari")
        XCTAssertEqual(match, FuzzyMatch(score: 0, indices: []))
    }

    func testRejectsNonSubsequence() {
        XCTAssertNil(FuzzyMatcher.match(query: "xyz", candidate: "Safari"))
        XCTAssertNil(FuzzyMatcher.match(query: "信微", candidate: "微信"))
    }

    func testCaseAndChinese() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "saf", candidate: "Safari"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "SAF", candidate: "Safari"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "微信", candidate: "微信"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "微", candidate: "微信"))
    }

    func testQuerySpacesAreIgnored() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "visual studio", candidate: "Visual Studio Code"))
    }

    func testTighterNameScoresHigher() {
        let notes = FuzzyMatcher.match(query: "note", candidate: "Notes")
        let notebook = FuzzyMatcher.match(query: "note", candidate: "Notebook")
        XCTAssertNotNil(notes)
        XCTAssertNotNil(notebook)
        XCTAssertGreaterThan(notes!.score, notebook!.score)
    }

    func testExactMatchBeatsPartial() {
        let exact = FuzzyMatcher.match(query: "mail", candidate: "Mail")
        let partial = FuzzyMatcher.match(query: "mail", candidate: "Mailbox")
        XCTAssertNotNil(exact)
        XCTAssertNotNil(partial)
        XCTAssertGreaterThan(exact!.score, partial!.score)
    }
}

final class ClipboardHistoryTests: XCTestCase {
    func testDuplicateMovesToFrontAndKeepsIdentity() {
        let older = makeItem(hash: "a", offset: 1)
        let other = makeItem(hash: "b", offset: 2)
        let again = makeItem(hash: "a", offset: 3)
        let update = ClipboardHistory.inserting(again, into: [other, older], limit: 10)
        XCTAssertEqual(update.items.map(\.contentHash), ["a", "b"])
        XCTAssertEqual(update.items[0].id, older.id)
        XCTAssertEqual(update.items[0].createdAt, again.createdAt)
        XCTAssertTrue(update.removed.isEmpty)
    }

    func testTrimDropsTheOldest() {
        let existing = (0..<5).map { makeItem(hash: "\($0)", offset: $0) }
        let update = ClipboardHistory.inserting(makeItem(hash: "new", offset: 9), into: existing, limit: 5)
        XCTAssertEqual(update.items.count, 5)
        XCTAssertEqual(update.items.first?.contentHash, "new")
        XCTAssertEqual(update.removed.map(\.contentHash), ["4"])
    }

    private func makeItem(hash: String, offset: Int) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            text: hash,
            imageFilename: nil,
            contentHash: hash,
            createdAt: Date(timeIntervalSince1970: TimeInterval(offset)),
            byteCount: hash.utf8.count
        )
    }
}

final class ClipboardPolicyTests: XCTestCase {
    func testTextBounds() {
        XCTAssertFalse(ClipboardPolicy.acceptsText(""))
        XCTAssertTrue(ClipboardPolicy.acceptsText("a"))
        let huge = String(repeating: "字", count: ClipboardPolicy.maxTextCharacters + 1)
        XCTAssertFalse(ClipboardPolicy.acceptsText(huge))
        XCTAssertTrue(ClipboardPolicy.acceptsText(String(repeating: "字", count: ClipboardPolicy.maxTextCharacters)))
    }

    func testImageBounds() {
        XCTAssertFalse(ClipboardPolicy.acceptsImageByteCount(10))
        XCTAssertTrue(ClipboardPolicy.acceptsImageByteCount(100))
        XCTAssertFalse(ClipboardPolicy.acceptsImageByteCount(ClipboardPolicy.maxImageBytes + 1))
        XCTAssertTrue(ClipboardPolicy.acceptsImageByteCount(ClipboardPolicy.maxImageBytes))
    }
}

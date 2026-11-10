import XCTest
import AppKit
@testable import Zap

final class FuzzyMatcherTests: XCTestCase {
    func testWholeNameDistanceTakesPriorityOverCloserSubstring() {
        XCTAssertEqual(
            FuzzyMatcher.match(query: "abcdefgh", candidate: "xbcdefghz"),
            FuzzyMatch(score: 61, indices: [])
        )
    }

    func testTypoInsideLongTextAndAtItsEdges() {
        let padding = String(repeating: "z", count: 4_000)
        for candidate in ["abcdfegh" + padding, padding + "abcdfegh", padding + "abcdfegh" + padding] {
            XCTAssertEqual(
                FuzzyMatcher.match(query: "abcdefgh", candidate: candidate),
                FuzzyMatch(score: 48, indices: [])
            )
        }
        XCTAssertNil(FuzzyMatcher.match(query: "abcdefgh", candidate: padding))
    }

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

    func testNearbyTypoStillMatches() {
        let typo = FuzzyMatcher.match(query: "Xocode", candidate: "Xcode")
        let exact = FuzzyMatcher.match(query: "Xcode", candidate: "Xcode")
        XCTAssertNotNil(typo)
        XCTAssertNotNil(exact)
        XCTAssertGreaterThan(exact!.score, typo!.score)
        XCTAssertNotNil(FuzzyMatcher.match(query: "xocode", candidate: "Xcode"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "xo code", candidate: "Xcode"))
        XCTAssertNotNil(FuzzyMatcher.match(query: "Xocde", candidate: "Xcode"))
        XCTAssertNil(FuzzyMatcher.match(query: "Xocode", candidate: "Safari"))
    }

    func testTypoOfTheWholeNameOutranksALongerWindow() {
        let direct = FuzzyMatcher.match(query: "Xocode", candidate: "Xcode")
        let buried = FuzzyMatcher.match(query: "Xocode", candidate: "Xcode Beta Tools")
        XCTAssertNotNil(direct)
        XCTAssertNotNil(buried)
        XCTAssertGreaterThan(direct!.score, buried!.score)
    }

    func testChineseSubstitution() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "微信开法", candidate: "微信开发"))
        XCTAssertNil(FuzzyMatcher.match(query: "完全不同", candidate: "微信开发"))
    }
}

final class LauncherSearchTests: XCTestCase {
    func testPinyinFromChineseDisplayAndFileNames() {
        let app = LaunchableApp(name: "网易有道词典", bundleName: "Dictionary",
                                path: "/Applications/词典.app", bundleIdentifier: nil)
        XCTAssertTrue(app.pinyinNames.contains("wangyiyoudaocidian"))
        XCTAssertTrue(app.pinyinNames.contains("cidian"))
        XCTAssertTrue(app.pinyinNames.contains { FuzzyMatcher.match(query: "youdao", candidate: $0) != nil })
    }

    @MainActor
    func testPaletteFocusAndEditingOnFirstKeyAfterOpenAndReopen() async throws {
        let palette = PaletteController.shared
        let board = NSPasteboard.general
        let savedItems = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            palette.hide()
            board.clearContents()
            board.writeObjects(savedItems)
        }

        for mode in [PaletteMode.launcher, .clipboard, .launcher] {
            palette.show(mode)
            // Allow the deferred makeKey and hosting-view attachment to finish.
            for _ in 0..<50 {
                if let panel = NSApp.keyWindow as? PalettePanel,
                   panel.searchField?.currentEditor() != nil { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let panel = try XCTUnwrap(NSApp.keyWindow as? PalettePanel)
            let editor = try XCTUnwrap(panel.searchField?.currentEditor() as? NSTextView)
            XCTAssertTrue(panel.firstResponder === editor)
            XCTAssertEqual(editor.string, "")
            func command(_ letter: String, code: UInt16) throws {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
                    context: nil, characters: letter, charactersIgnoringModifiers: letter,
                    isARepeat: false, keyCode: code))
                NSApp.sendEvent(event)
            }
            board.clearContents()
            board.setString("youdao", forType: .string)
            try command("v", code: 9)
            XCTAssertEqual(palette.query, "youdao")
            try command("a", code: 0)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6))
            board.clearContents()
            try command("c", code: 8)
            XCTAssertEqual(board.string(forType: .string), "youdao")
            palette.hide()
        }
    }
}

final class AppIndexStoreTests: XCTestCase {
    func testRoundTripKeepsNamesAndPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zap-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apps = [
            LaunchableApp(name: "Xcode", bundleName: "Xcode", path: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode"),
            LaunchableApp(name: "备忘录", bundleName: "Notes", path: "/System/Applications/Notes.app", bundleIdentifier: "com.apple.Notes")
        ]
        AppIndexStore.save(apps, to: directory)
        XCTAssertEqual(AppIndexStore.load(from: directory), apps)
    }

    func testMissingOrForeignSnapshotIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zap-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(AppIndexStore.load(from: directory))
        let url = directory.appendingPathComponent(AppIndexStore.fileName)
        try Data("{\"version\":2,\"apps\":[]}".utf8).write(to: url)
        XCTAssertNil(AppIndexStore.load(from: url.deletingLastPathComponent()))
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

    func testTrimKeepsPinnedItems() {
        var pinned = makeItem(hash: "pinned", offset: 0)
        pinned.pinnedAt = Date(timeIntervalSince1970: 1)
        let newer = (1..<5).map { makeItem(hash: "\($0)", offset: $0) }
        let existing = newer + [pinned]
        let update = ClipboardHistory.inserting(makeItem(hash: "new", offset: 9), into: existing, limit: 5)
        XCTAssertEqual(update.items.count, 5)
        XCTAssertTrue(update.items.contains(where: { $0.contentHash == "pinned" && $0.pinnedAt != nil }))
        XCTAssertFalse(update.removed.contains(where: { $0.contentHash == "pinned" }))
        XCTAssertEqual(update.removed.map(\.contentHash), ["4"])
    }

    func testDuplicateKeepsPin() {
        var older = makeItem(hash: "a", offset: 1)
        older.pinnedAt = Date(timeIntervalSince1970: 8)
        let update = ClipboardHistory.inserting(makeItem(hash: "a", offset: 3), into: [older], limit: 10)
        XCTAssertEqual(update.items[0].id, older.id)
        XCTAssertEqual(update.items[0].pinnedAt, older.pinnedAt)
    }

    func testDisplayOrderPinsFirst() {
        var pinned = makeItem(hash: "pinned", offset: 1)
        pinned.pinnedAt = Date(timeIntervalSince1970: 10)
        let fresh = makeItem(hash: "fresh", offset: 50)
        let ordered = ClipboardHistory.sortedForDisplay([fresh, pinned])
        XCTAssertEqual(ordered.map(\.contentHash), ["pinned", "fresh"])
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

final class ClipboardPersistenceTests: XCTestCase {
    func testScheduledWritePersistsWithoutExplicitFlush() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ClipboardPersistence()
        let latest = item("latest")
        writer.schedule(items: [item("older")], directory: directory)
        writer.schedule(items: [latest], directory: directory)
        let saved = expectation(description: "Scheduled history save")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent("history.json"))
                XCTAssertEqual(try JSONDecoder().decode([ClipboardItem].self, from: data), [latest])
            } catch {
                XCTFail("Scheduled write failed: \(error)")
            }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
    }

    private func item(_ value: String, image: String? = nil) -> ClipboardItem {
        ClipboardItem(id: UUID(), kind: image == nil ? .text : .image, text: value,
                      imageFilename: image, contentHash: value, createdAt: Date(), byteCount: value.utf8.count)
    }

    func testFlushWritesLatestSnapshotAndThenRemovesOldImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let old = item("old", image: "old.png")
        let kept = item("kept", image: "kept.png")
        try Data([1]).write(to: images.appendingPathComponent("old.png"))
        try Data([2]).write(to: images.appendingPathComponent("kept.png"))
        let writer = ClipboardPersistence()
        writer.schedule(items: [old, kept], directory: directory)
        XCTAssertTrue(writer.flush())
        writer.removeAfterSave(["old.png", "kept.png"], directory: directory)
        writer.schedule(items: [old], directory: directory)
        writer.schedule(items: [kept], directory: directory)
        XCTAssertTrue(writer.flush())
        let saved = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: directory.appendingPathComponent("history.json")))
        XCTAssertEqual(saved, [kept])
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.appendingPathComponent("old.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("kept.png").path))
    }

    func testFailedWriteKeepsSnapshotForRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let latest = item("latest")
        let writer = ClipboardPersistence()
        writer.schedule(items: [latest], directory: directory)
        XCTAssertFalse(writer.flush())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(writer.flush())
        let saved = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: directory.appendingPathComponent("history.json")))
        XCTAssertEqual(saved, [latest])
    }

    @MainActor
    func testRankingInvalidatesAfterPinDeleteAndInsertion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        store.recordText("first")
        let first = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.ranked(matching: "").map(\.id), [first.id])
        store.recordText("second")
        let second = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.ranked(matching: "").map(\.id), [second.id, first.id])
        store.togglePin(first.id)
        XCTAssertEqual(store.ranked(matching: "  ").map(\.id), [first.id, second.id])
        XCTAssertNotNil(store.ranked(matching: "first").first?.item.pinnedAt)
        store.delete([first.id])
        XCTAssertTrue(store.ranked(matching: "first").isEmpty)
        store.removeAll()
        XCTAssertTrue(store.ranked(matching: "").isEmpty)
        XCTAssertTrue(store.flush())
    }

    @MainActor
    func testThumbnailUsesRequestedPixelSizeAndLeavesOriginalIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 512, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let store = ClipboardStore(directory: directory)
        store.recordImageData(data, caption: nil)
        let clip = try XCTUnwrap(store.items.first)
        let small = try XCTUnwrap(store.thumbnail(for: clip, scale: 1))
        let retina = try XCTUnwrap(store.thumbnail(for: clip, scale: 2))
        XCTAssertEqual(small.representations.first?.pixelsWide, 32)
        XCTAssertEqual(retina.representations.first?.pixelsWide, 64)
        let preview = try XCTUnwrap(store.thumbnail(for: clip, pointSize: 608, scale: 1))
        XCTAssertEqual(preview.representations.first?.pixelsWide, 608)
        XCTAssertEqual(preview.representations.first?.pixelsHigh, 304)
        XCTAssertTrue(retina === store.thumbnail(for: clip, scale: 2))
        let original = directory.appendingPathComponent("images").appendingPathComponent(try XCTUnwrap(clip.imageFilename))
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertTrue(store.flush())
    }
}

final class AppShortcutTests: XCTestCase {
    @MainActor
    func testMultipleBindingsRejectConflictsAndSurviveReload() throws {
        let suite = "ZapTests.shortcuts." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let first = LaunchableApp(name: "One", bundleName: nil, path: "/test/One.app", bundleIdentifier: nil)
        let second = LaunchableApp(name: "Two", bundleName: nil, path: "/test/Two.app", bundleIdentifier: nil)
        defer {
            store.removeApplication(first.id)
            store.removeApplication(second.id)
        }

        store.addApplication(first)
        store.addApplication(second)
        store.addApplication(first)
        let flags = NSEvent.ModifierFlags([.control, .command, .option, .shift]).rawValue
        let firstChord = HotkeyChord(keyCode: 96, modifiers: flags)
        let secondChord = HotkeyChord(keyCode: 97, modifiers: flags)
        store.setApplicationHotkey(firstChord, for: first.id)
        store.setApplicationHotkey(secondChord, for: second.id)
        store.setApplicationHotkey(firstChord, for: second.id)
        XCTAssertEqual(store.appWarnings[second.id], L10n.hotkeyConflict)
        store.setApplicationHotkey(store.launcherHotkey, for: first.id)
        XCTAssertEqual(store.appWarnings[first.id], L10n.hotkeyConflict)
        store.setCaptureHotkey(secondChord)
        XCTAssertEqual(store.captureWarning, L10n.hotkeyConflict)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.appShortcuts.map(\.chord), [firstChord, secondChord])
        store.removeApplication(first.id)
        store.setApplicationHotkey(firstChord, for: second.id)
        XCTAssertNil(store.appWarnings[second.id])
        let remaining = SettingsStore(defaults: defaults).appShortcuts
        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertEqual(remaining.first?.chord, firstChord)
    }
}

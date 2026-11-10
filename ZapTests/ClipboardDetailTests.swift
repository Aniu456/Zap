import AppKit
import XCTest
@testable import Zap

@MainActor
final class ClipboardDetailTests: XCTestCase {
    func testOrderedPasteAndClipboardFeedback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(directory: dir, pasteboard: board)
        for value in ["first", "second", "third"] { store.recordText(value, source: "com.apple.Notes") }
        let order = [store.items[1], store.items[2], store.items[0]]
        let joined = try XCTUnwrap(ClipboardItem.joinedText(order))
        XCTAssertEqual(joined, "second\nfirst\nthird")
        XCTAssertTrue(store.placeOnPasteboard(order[0]))
        XCTAssertEqual(store.pasteboardItemID, order[0].id)
        XCTAssertTrue(store.placeTextOnPasteboard(joined))
        XCTAssertNil(store.pasteboardItemID)
        XCTAssertEqual(board.string(forType: .string), joined)
        XCTAssertTrue(store.placeOnPasteboard(order[1]))
        board.clearContents()
        board.setString("external copy", forType: .string)
        XCTAssertTrue(store.edit(order[1], text: "updated"))
        XCTAssertEqual(board.string(forType: .string), "external copy")
        XCTAssertTrue(store.flush())
        let restored = ClipboardStore(directory: dir, pasteboard: board)
        restored.load()
        XCTAssertEqual(restored.items.first { $0.id == order[1].id }?.sourceBundleID, "com.apple.Notes")
        XCTAssertEqual(restored.items.first { $0.id == order[1].id }?.text, "updated")
    }

    func testLegacyScreenshotIndexedAndSearchableAfterRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = dir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = NSImage(size: NSSize(width: 800, height: 160), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            ("Clipboard search example" as NSString).draw(at: CGPoint(x: 20, y: 30),
                withAttributes: [.font: NSFont.systemFont(ofSize: 50), .foregroundColor: NSColor.black])
            return true
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let name = UUID().uuidString + ".png"
        try png.write(to: images.appendingPathComponent(name))
        let item = ClipboardItem(id: UUID(), kind: .image, text: nil, imageFilename: name,
                                 contentHash: "old", createdAt: Date(), byteCount: png.count)
        try JSONEncoder().encode([item]).write(to: dir.appendingPathComponent("history.json"))
        let store = ClipboardStore(directory: dir)
        store.load()
        XCTAssertEqual(store.items.first?.id, item.id)
        for _ in 0..<900 where store.items.first?.recognizedText == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let recognized = try XCTUnwrap(store.items.first?.recognizedText, "OCR did not finish")
        XCTAssertFalse(recognized.isEmpty)
        XCTAssertEqual(store.ranked(matching: "Clipboard search").first?.id, item.id)
        XCTAssertNil(ClipboardItem.joinedText(store.items))
        XCTAssertTrue(store.flush())
        let restored = ClipboardStore(directory: dir)
        restored.load()
        XCTAssertEqual(restored.ranked(matching: "example").first?.id, item.id)
        XCTAssertNil(restored.items.first?.sourceBundleID)
    }

    func testShiftClickSelectsContiguousRangeInListOrder() {
        let ids = (0..<5).map { _ in UUID() }
        XCTAssertEqual(ClipSelection.range(in: ids, from: ids[1], to: ids[3]), Array(ids[1...3]))
        XCTAssertEqual(ClipSelection.range(in: ids, from: ids[3], to: ids[1]), Array(ids[1...3]))
        XCTAssertEqual(ClipSelection.range(in: ids, from: UUID(), to: ids[2]), [ids[2]])
        XCTAssertEqual(ClipSelection.range(in: ids, from: ids[0], to: UUID()), [])
    }

    func testDeselectingOneKeepsTheRestInOrder() {
        let ids = (0..<4).map { _ in UUID() }
        let picked = [ids[2], ids[0], ids[3]]
        XCTAssertEqual(ClipSelection.toggle(ids[0], in: picked), [ids[2], ids[3]])
        XCTAssertEqual(ClipSelection.toggle(ids[1], in: picked), picked + [ids[1]])
        XCTAssertEqual(ClipSelection.union([ids[3]], Array(ids[0...3])), [ids[3], ids[0], ids[1], ids[2]])
    }

    func testMixedSelectionPastesInPickOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(directory: dir, pasteboard: board)
        for value in ["a", "b", "c"] { store.recordText(value, source: nil) }
        let texts = store.items
        let image = ClipboardItem(id: UUID(), kind: .image, text: nil, imageFilename: nil, contentHash: "img", createdAt: Date(), byteCount: 0)
        let segments = ClipboardItem.pasteSegments([texts[0], texts[1], image, texts[2]])
        XCTAssertEqual(segments.count, 3)
        guard case .text(let first) = segments[0], case .image = segments[1], case .text(let last) = segments[2] else {
            return XCTFail("order lost: \(segments)")
        }
        XCTAssertEqual(first, (texts[0].text ?? "") + "\n" + (texts[1].text ?? ""))
        XCTAssertEqual(last, texts[2].text)
    }

    func testMixedSelectionPastesAsTextAndImageSteps() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = ClipboardStore(directory: dir, pasteboard: board)
        for size in [4, 6] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            store.recordImageData(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), caption: nil)
        }
        store.recordText("after")
        store.recordText("before")
        let before = try XCTUnwrap(store.items.first { $0.text == "before" })
        let after = try XCTUnwrap(store.items.first { $0.text == "after" })
        let images = store.items.filter { $0.kind == .image }
        XCTAssertEqual(images.count, 2)
        let steps = ClipboardItem.pasteSteps([before, images[0], images[1], after])
        XCTAssertEqual(steps, [.text("before"), .images([images[0]]), .images([images[1]]), .text("after")])
        // Model an input that only imports the first attachment for each ⌘V.
        var received: [Data] = []
        for step in steps {
            XCTAssertTrue(store.placeStepOnPasteboard(step))
            let entries = try XCTUnwrap(board.pasteboardItems)
            XCTAssertEqual(entries.count, 1)
            if let image = entries.first?.data(forType: .png) { received.append(image) }
        }
        XCTAssertEqual(received, try images.map { try Data(contentsOf: XCTUnwrap(store.imageURL(for: $0))) })

        let manual = ClipboardItem.pasteSteps([before, images[0], images[1], after], groupAdjacentImages: true)
        XCTAssertEqual(manual, [.text("before"), .images(images), .text("after")])
        var reads = 0
        XCTAssertTrue(store.placeStepOnPasteboard(manual[1]) { reads += 1 })
        let pasted = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(pasted.count, 2)
        for item in pasted {
            XCTAssertNotNil(item.data(forType: .png))
            let url = try XCTUnwrap(item.string(forType: .fileURL).flatMap(URL.init(string:)))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        let read = expectation(description: "read reported once")
        DispatchQueue.main.async { read.fulfill() }
        wait(for: [read], timeout: 1)
        XCTAssertEqual(reads, 1)

        // Image steps in one batch never reuse a file name.
        store.beginPasteBatch()
        var names: [String] = []
        for step in [ClipboardItem.PasteStep.images([images[0]]), .images([images[1]])] {
            XCTAssertTrue(store.placeStepOnPasteboard(step))
            for item in board.pasteboardItems ?? [] {
                names += [item.string(forType: .fileURL).flatMap(URL.init(string:))?.lastPathComponent].compactMap { $0 }
            }
        }
        XCTAssertEqual(names, ["image-0001.png", "image-0002.png"])

        // Once a single item replaces the batch on the clipboard, its files are gone.
        XCTAssertTrue(FileManager.default.fileExists(atPath: ClipboardStore.pasteRoot.path))
        XCTAssertTrue(store.placeOnPasteboard(before))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ClipboardStore.pasteRoot.path))
    }
}


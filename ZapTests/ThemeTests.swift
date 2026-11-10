import AppKit
import SwiftUI
import XCTest
@testable import Zap

final class ZapThemeTests: XCTestCase {
    func testMuseIsBlackWhiteWithABlueAccent() {
        let lightPage = ZapSwatch.muse(.background, dark: false)
        let darkPage = ZapSwatch.muse(.background, dark: true)
        XCTAssertGreaterThan(lightPage.r, 0.94)
        XCTAssertGreaterThan(lightPage.g, 0.94)
        XCTAssertGreaterThan(lightPage.b, 0.94)
        XCTAssertLessThan(darkPage.r, 0.12)
        XCTAssertLessThan(darkPage.g, 0.12)
        XCTAssertLessThan(darkPage.b, 0.12)
        for dark in [false, true] {
            let accent = ZapSwatch.muse(.accent, dark: dark)
            XCTAssertGreaterThan(accent.b, accent.r)
            XCTAssertGreaterThan(accent.b, accent.g)
            XCTAssertFalse(ZapSwatch.muse(.selection, dark: dark).isYellow)
            XCTAssertFalse(ZapSwatch.muse(.background, dark: dark).isYellow)
        }
    }
}

final class PaletteAppearanceTests: XCTestCase {
    @MainActor func testMuseWindowCorners() async throws {
        defer { PaletteController.shared.hide() }
        for mode in [PaletteMode.launcher, .clipboard] {
            PaletteController.shared.show(mode)
            try await Task.sleep(for: .milliseconds(200))
            let panel = try XCTUnwrap(NSApp.windows.first { $0 is PalettePanel })
            let view = try XCTUnwrap(panel.contentView)
            let layer = try XCTUnwrap(view.layer)
            let scale = panel.backingScaleFactor
            let width = Int(view.bounds.width * scale)
            let height = Int(view.bounds.height * scale)
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            let image = try XCTUnwrap(context.makeImage())
            let bitmap = NSBitmapImageRep(cgImage: image)
            let alphas = [0, image.width - 1].flatMap { x in
                [0, image.height - 1].compactMap { bitmap.colorAt(x: x, y: $0)?.alphaComponent }
            }
            XCTAssertEqual(alphas, [0, 0, 0, 0])
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: image.width / 2, y: 10)).alphaComponent, 0.95)
            XCTAssertTrue(panel.firstResponder is NSTextView)
            PaletteController.shared.hide()
        }
    }
}

@MainActor
final class ClipboardSplitAnimationTests: XCTestCase {
    private final class State: ObservableObject {
        @Published var expanded = false
    }

    private struct Fixture: View {
        @ObservedObject var state: State
        var body: some View {
            ClipboardSplitView(progress: state.expanded ? 1 : 0) {
                ScrollView {
                    LazyVStack {
                        HStack {
                            Spacer()
                            Color.green.frame(width: 16)
                        }
                        .frame(height: 60)
                        .background(alignment: .leading) { Color.red.frame(width: 640) }
                    }
                }
            } detail: {
                Color.blue
            }
            .animation(.linear(duration: 0.5), value: state.expanded)
            .frame(width: 640, height: 60)
        }
    }

    func testDividerTravelsBothWaysAndClipsOversizedRow() async throws {
        let state = State()
        let host = NSHostingView(rootView: Fixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        func listWidth() throws -> Int {
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                if let color = rep.colorAt(x: x, y: rep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
                   color.blueComponent > max(color.redComponent, color.greenComponent) + 0.25 {
                    let scale = rep.pixelsWide / 640
                    let trailingButton = try XCTUnwrap(rep.colorAt(x: x - 8 * scale, y: rep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
                    XCTAssertGreaterThan(trailingButton.greenComponent, trailingButton.redComponent)
                    return x * 640 / rep.pixelsWide
                }
            }
            return 640
        }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try listWidth(), 640)
        for expanded in [true, false] {
            state.expanded = expanded
            var intermediate = false
            for _ in 0..<14 {
                try await Task.sleep(for: .milliseconds(50))
                let width = try listWidth()
                intermediate = intermediate || (260..<635).contains(width)
            }
            XCTAssertTrue(intermediate, "Missing intermediate frame, expanded: \(expanded)")
            XCTAssertEqual(try listWidth(), expanded ? 256 : 640, accuracy: 3)
        }
    }
}

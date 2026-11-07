import XCTest
@testable import Zap

final class AppVersionTests: XCTestCase {
    func testSubtitleUsesTheBundleVersion() {
        XCTAssertEqual(AppVersion.display(short: "1.2.3", build: "1.2.3"), "1.2.3")
        XCTAssertEqual(AppVersion.display(short: "1.0", build: "1"), "1.0 (1)")
        XCTAssertEqual(AppVersion.subtitle(short: "1.0", build: "1"), "Zap · 1.0 (1)")
        XCTAssertEqual(AppVersion.subtitle(short: "  ", build: nil), "Zap")
        XCTAssertFalse(AppVersion.display(short: nil, build: nil).contains("1.0.0"))
    }
}

final class AboutCopyTests: XCTestCase {
    func testAboutCoversLauncherClipboardAndCapture() {
        let copy = [
            L10n.aboutIntro,
            L10n.aboutLauncher,
            L10n.aboutClipboard,
            L10n.aboutCapture,
            L10n.aboutPrivacy
        ].joined(separator: "\n")
        XCTAssertTrue(copy.contains("启动器"))
        XCTAssertTrue(copy.contains("剪贴板"))
        XCTAssertTrue(copy.contains("区域截图"))
        XCTAssertTrue(copy.contains("贴图"))
        XCTAssertTrue(copy.contains("不会上传"))
        XCTAssertEqual(L10n.aboutCopyright, "© 2026 Benny · MIT")
        XCTAssertEqual(L10n.githubURL, "https://github.com/Aniu456/Zap")
        XCTAssertFalse(copy.contains("1.0.0"))
    }
}

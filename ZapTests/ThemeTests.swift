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

    func testBlendStaysOnTheEndpoints() {
        let light = ZapSwatch.muse(.primary, dark: false)
        let dark = ZapSwatch.muse(.primary, dark: true)
        XCTAssertEqual(light.mixed(with: dark, 0).r, light.r, accuracy: 0.0001)
        XCTAssertEqual(light.mixed(with: dark, 1).r, dark.r, accuracy: 0.0001)
        let mid = light.mixed(with: dark, 0.5)
        XCTAssertGreaterThan(mid.r, dark.r)
        XCTAssertLessThan(mid.r, light.r)
    }

    @MainActor
    func testChoicePersistsAndSkipsTheTransitionWhenAsked() {
        let defaults = UserDefaults(suiteName: "zap-theme-\(UUID().uuidString)")!
        let controller = ThemeController(defaults: defaults)
        XCTAssertEqual(controller.theme, .muse)
        controller.setTheme(.spotlight, animated: false)
        XCTAssertEqual(controller.theme, .spotlight)
        XCTAssertNil(controller.blend)
        XCTAssertEqual(controller.vibrancyAmount(), 1, accuracy: 0.001)
        XCTAssertFalse(controller.colors(dark: true).searchIsPill)
        controller.setTheme(.muse, animated: false)
        XCTAssertEqual(controller.vibrancyAmount(), 0, accuracy: 0.001)
        XCTAssertTrue(controller.colors(dark: false).searchIsPill)
        let restored = ThemeController(defaults: defaults)
        XCTAssertEqual(restored.theme, .muse)
    }
}

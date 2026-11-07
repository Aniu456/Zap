import AppKit
import SwiftUI

/// One place owns the Muse / Spotlight choice. Colors are resolved from the
/// active theme and the current light or dark appearance, then blended for a
/// short transition. Reduce Motion commits the new theme on the next frame.
@MainActor
final class ThemeController: NSObject, ObservableObject {
    static let shared = ThemeController()

    @Published private(set) var theme: ZapTheme
    @Published private(set) var blend: Blend?

    struct Blend: Equatable {
        var from: ZapTheme
        var to: ZapTheme
        var fraction: CGFloat
        var startFraction: CGFloat
    }

    private let defaults: UserDefaults
    private let key = "zap.theme"
    private var displayLink: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private let duration: CFTimeInterval = 0.2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: key), let stored = ZapTheme(rawValue: raw) {
            theme = stored
        } else {
            theme = .muse
        }
        super.init()
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func setTheme(_ next: ZapTheme, animated: Bool? = nil) {
        let animate = animated ?? !reduceMotion
        if blend == nil, next == theme {
            return
        }
        if let blend, blend.to == next, theme == next {
            return
        }
        let displayedFrom = blend?.from ?? theme
        let displayedFraction = blend?.fraction ?? 1
        if let blend, blend.from == next {
            let start = 1 - displayedFraction
            self.blend = Blend(from: blend.to, to: next, fraction: start, startFraction: start)
        } else {
            self.blend = Blend(from: displayedFrom, to: next, fraction: 0, startFraction: 0)
        }
        theme = next
        defaults.set(next.rawValue, forKey: key)
        guard animate, self.blend != nil else {
            self.blend = nil
            finishFrame()
            return
        }
        animationStart = CACurrentMediaTime()
        startLink()
        finishFrame()
    }

    func colors(dark: Bool) -> ZapColors {
        let from = blend?.from ?? theme
        let to = blend?.to ?? theme
        let fraction = blend?.fraction ?? 1
        func color(_ token: ZapToken) -> Color {
            Color(nsColor: ZapSwatch.mixed(token, from: from, to: to, dark: dark, fraction: fraction).nsColor)
        }
        let vibrancy = Self.vibrancy(from: from, to: to, fraction: fraction)
        return ZapColors(
            background: color(.background),
            primary: color(.primary),
            secondary: color(.secondary),
            selection: color(.selection),
            accent: color(.accent),
            separator: color(.separator),
            keycap: color(.keycap),
            inputFill: color(.inputFill),
            inputStroke: color(.inputStroke),
            warning: color(.warning),
            vibrancy: vibrancy,
            searchIsPill: (1 - vibrancy) > 0.5
        )
    }

    func nsColor(_ token: ZapToken, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let from = blend?.from ?? theme
        let to = blend?.to ?? theme
        let fraction = blend?.fraction ?? 1
        return ZapSwatch.mixed(token, from: from, to: to, dark: dark, fraction: fraction).nsColor
    }

    func vibrancyAmount() -> CGFloat {
        Self.vibrancy(from: blend?.from ?? theme, to: blend?.to ?? theme, fraction: blend?.fraction ?? 1)
    }

    private static func vibrancy(from: ZapTheme, to: ZapTheme, fraction: CGFloat) -> CGFloat {
        let start: CGFloat = from == .spotlight ? 1 : 0
        let end: CGFloat = to == .spotlight ? 1 : 0
        return start + (end - start) * min(1, max(0, fraction))
    }

    private func startLink() {
        guard displayLink == nil else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            blend = nil
            finishFrame()
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - animationStart
        let raw = min(1, elapsed / duration)
        let eased = raw * raw * (3 - 2 * raw)
        if var current = blend {
            current.fraction = current.startFraction + (1 - current.startFraction) * eased
            blend = current
        }
        finishFrame()
        if raw >= 1 {
            blend = nil
            link.invalidate()
            displayLink = nil
            finishFrame()
        }
    }

    private func finishFrame() {
        NotificationCenter.default.post(name: .zapThemeChanged, object: nil)
    }
}

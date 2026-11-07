import AppKit
import SwiftUI

/// Muse is a solid black/white surface with one blue accent.
/// Spotlight uses system materials and semantic colors. Neither selection is yellow.
enum ZapTheme: String, CaseIterable, Identifiable {
    case muse
    case spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muse: return L10n.themeMuse
        case .spotlight: return L10n.themeSpotlight
        }
    }
}

enum ZapToken: CaseIterable {
    case background
    case chrome
    case primary
    case secondary
    case selection
    case accent
    case separator
    case keycap
    case inputFill
    case inputStroke
    case warning
}

struct ZapRGBA: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

    func mixed(with other: ZapRGBA, _ amount: CGFloat) -> ZapRGBA {
        let t = min(1, max(0, amount))
        return ZapRGBA(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Yellow is high red and green with a weak blue. Selection swatches must not look like that.
    var isYellow: Bool {
        r > 0.55 && g > 0.45 && b < 0.35 && r - b > 0.35
    }
}

enum ZapSwatch {
    static func muse(_ token: ZapToken, dark: Bool) -> ZapRGBA {
        switch token {
        case .background:
            return dark ? ZapRGBA(r: 0.07, g: 0.07, b: 0.075, a: 1) : ZapRGBA(r: 0.975, g: 0.975, b: 0.978, a: 1)
        case .chrome:
            return dark ? ZapRGBA(r: 0.09, g: 0.09, b: 0.095, a: 0.98) : ZapRGBA(r: 0.97, g: 0.97, b: 0.975, a: 0.98)
        case .primary:
            return dark ? ZapRGBA(r: 0.96, g: 0.96, b: 0.97, a: 1) : ZapRGBA(r: 0.08, g: 0.08, b: 0.09, a: 1)
        case .secondary:
            return dark ? ZapRGBA(r: 0.64, g: 0.64, b: 0.68, a: 1) : ZapRGBA(r: 0.42, g: 0.42, b: 0.46, a: 1)
        case .selection:
            return dark ? ZapRGBA(r: 0.20, g: 0.20, b: 0.215, a: 1) : ZapRGBA(r: 0.925, g: 0.925, b: 0.935, a: 1)
        case .accent:
            return dark ? ZapRGBA(r: 0.35, g: 0.62, b: 1, a: 1) : ZapRGBA(r: 0.12, g: 0.40, b: 1, a: 1)
        case .separator:
            return dark ? ZapRGBA(r: 1, g: 1, b: 1, a: 0.12) : ZapRGBA(r: 0, g: 0, b: 0, a: 0.10)
        case .keycap:
            return dark ? ZapRGBA(r: 1, g: 1, b: 1, a: 0.12) : ZapRGBA(r: 0, g: 0, b: 0, a: 0.06)
        case .inputFill:
            return dark ? ZapRGBA(r: 0.16, g: 0.16, b: 0.17, a: 1) : ZapRGBA(r: 0.94, g: 0.94, b: 0.95, a: 1)
        case .inputStroke:
            return dark ? ZapRGBA(r: 0.30, g: 0.32, b: 0.36, a: 1) : ZapRGBA(r: 0.78, g: 0.80, b: 0.84, a: 1)
        case .warning:
            return ZapRGBA(r: 0.92, g: 0.55, b: 0.15, a: 1)
        }
    }

    static func mixed(_ token: ZapToken, from: ZapTheme, to: ZapTheme, dark: Bool, fraction: CGFloat) -> ZapRGBA {
        rgba(token, theme: from, dark: dark).mixed(with: rgba(token, theme: to, dark: dark), fraction)
    }

    static func rgba(_ token: ZapToken, theme: ZapTheme, dark: Bool) -> ZapRGBA {
        switch theme {
        case .muse:
            return muse(token, dark: dark)
        case .spotlight:
            return rgba(spotlight(token, dark: dark))
        }
    }

    static func spotlight(_ token: ZapToken, dark: Bool) -> NSColor {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            switch token {
            case .background, .chrome:
                resolved = .windowBackgroundColor
            case .primary:
                resolved = .labelColor
            case .secondary:
                resolved = .secondaryLabelColor
            case .selection:
                resolved = .unemphasizedSelectedContentBackgroundColor
            case .accent:
                resolved = .controlAccentColor
            case .separator:
                resolved = .separatorColor
            case .keycap:
                resolved = .labelColor.withAlphaComponent(dark ? 0.16 : 0.08)
            case .inputFill:
                resolved = .controlBackgroundColor
            case .inputStroke:
                resolved = .separatorColor
            case .warning:
                resolved = .systemOrange
            }
        }
        return resolved
    }

    private static func rgba(_ color: NSColor) -> ZapRGBA {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return ZapRGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        }
        return ZapRGBA(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent, a: rgb.alphaComponent)
    }
}

struct ZapColors: Equatable {
    var background: Color
    var primary: Color
    var secondary: Color
    var selection: Color
    var accent: Color
    var separator: Color
    var keycap: Color
    var inputFill: Color
    var inputStroke: Color
    var warning: Color
    var vibrancy: CGFloat
    var searchIsPill: Bool

    var cover: CGFloat { 1 - vibrancy }
}

extension Notification.Name {
    static let zapThemeChanged = Notification.Name("zap.theme.changed")
}

import AppKit
import SwiftUI

enum ZapToken: CaseIterable {
    case background
    case chrome
    case primary
    case secondary
    case selection
    case accent
    case separator
    case keycap
    case warning
}

struct ZapRGBA: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

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
        case .warning:
            return ZapRGBA(r: 0.92, g: 0.55, b: 0.15, a: 1)
        }
    }

    static func nsColor(_ token: ZapToken, appearance: NSAppearance) -> NSColor {
        muse(token, dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua).nsColor
    }

    static func colors(dark: Bool) -> ZapColors {
        func color(_ token: ZapToken) -> Color { Color(nsColor: muse(token, dark: dark).nsColor) }
        return ZapColors(
            background: color(.background), primary: color(.primary), secondary: color(.secondary),
            selection: color(.selection), accent: color(.accent), separator: color(.separator),
            keycap: color(.keycap), warning: color(.warning)
        )
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
    var warning: Color
}

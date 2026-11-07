import Foundation

/// Marketing version and build from the app bundle. Nothing here is a fixed release number.
enum AppVersion {
    static func display(short: String?, build: String?) -> String {
        let marketing = cleaned(short)
        let bundleBuild = cleaned(build)
        switch (marketing, bundleBuild) {
        case let (marketing?, bundleBuild?) where marketing == bundleBuild:
            return marketing
        case let (marketing?, bundleBuild?):
            return "\(marketing) (\(bundleBuild))"
        case let (marketing?, nil):
            return marketing
        case let (nil, bundleBuild?):
            return bundleBuild
        default:
            return ""
        }
    }

    static func subtitle(short: String?, build: String?) -> String {
        let version = display(short: short, build: build)
        return version.isEmpty ? "Zap" : "Zap · \(version)"
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

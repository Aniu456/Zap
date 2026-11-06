import Foundation

enum AppIndexStore {
    static let fileName = "app-index.json"

    struct Snapshot: Codable, Equatable {
        var version: Int
        var apps: [LaunchableApp]
    }

    static func load(from directory: URL) -> [LaunchableApp]? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 1 else {
            return nil
        }
        let apps = snapshot.apps.filter { !$0.path.isEmpty && !$0.name.isEmpty }
        return apps.isEmpty ? nil : apps
    }

    static func save(_ apps: [LaunchableApp], to directory: URL) {
        let snapshot = Snapshot(version: 1, apps: apps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func supportDirectory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = base.appendingPathComponent("Zap", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

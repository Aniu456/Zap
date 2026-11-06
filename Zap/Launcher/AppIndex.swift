import AppKit

struct LaunchableApp: Identifiable, Hashable, Codable, Sendable {
    var id: String { path }
    let name: String
    let bundleName: String?
    let path: String
    let bundleIdentifier: String?

    var url: URL { URL(fileURLWithPath: path) }

    var fileName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct RankedApp: Identifiable {
    var id: String { app.id }
    let app: LaunchableApp
    let match: FuzzyMatch
}

@MainActor
final class AppIndex: ObservableObject {
    static let shared = AppIndex()

    @Published private(set) var apps: [LaunchableApp] = []
    @Published private(set) var isScanning = false

    private var lastScan = Date.distantPast
    private let recentKey = "zap.recentApps"
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var rescanWork: DispatchWorkItem?
    private var scanInFlight = false

    private init() {}

    func start() {
        if let directory = AppIndexStore.supportDirectory(),
           let cached = AppIndexStore.load(from: directory), !cached.isEmpty {
            apps = cached
        }
        watchInstallLocations()
        rescan()
    }

    /// Opening the launcher must not wait on a directory walk. A quiet rescan
    /// runs only when the cache is missing or old; unchanged results are not published.
    func refreshIfStale() {
        guard !scanInFlight else { return }
        if apps.isEmpty || Date().timeIntervalSince(lastScan) > 120 {
            rescan()
        }
    }

    func ranked(matching query: String) -> [RankedApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return orderedForEmptyQuery().map { RankedApp(app: $0, match: FuzzyMatch(score: 0, indices: [])) }
        }
        var ranked: [RankedApp] = []
        ranked.reserveCapacity(apps.count)
        for app in apps {
            let nameMatch = FuzzyMatcher.match(query: trimmed, candidate: app.name)
            let fileMatch = FuzzyMatcher.match(query: trimmed, candidate: app.fileName)
            let bundleMatch = app.bundleName.flatMap { FuzzyMatcher.match(query: trimmed, candidate: $0) }
            guard let best = [nameMatch?.score, fileMatch?.score, bundleMatch?.score].compactMap({ $0 }).max() else {
                continue
            }
            ranked.append(RankedApp(app: app, match: FuzzyMatch(score: best, indices: nameMatch?.indices ?? [])))
        }
        ranked.sort { lhs, rhs in
            if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }
        return ranked
    }

    func launch(_ app: LaunchableApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let launched = app
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            let failed = error != nil
            Task { @MainActor in
                if failed {
                    ToastCenter.shared.show(L10n.launchFailed)
                } else {
                    AppIndex.shared.remember(launched)
                }
            }
        }
    }

    private func scheduleRescan() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rescan()
        }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func rescan() {
        guard !scanInFlight else { return }
        scanInFlight = true
        if apps.isEmpty {
            isScanning = true
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppScanner.scan()
            Task { @MainActor in
                AppIndex.shared.apply(found)
            }
        }
    }

    private func apply(_ found: [LaunchableApp]) {
        scanInFlight = false
        if isScanning {
            isScanning = false
        }
        lastScan = Date()
        // A failed or empty walk must not replace a list the window is already showing.
        if found.isEmpty && !apps.isEmpty { return }
        guard !sameCatalog(found, apps) else { return }
        apps = found
        if let directory = AppIndexStore.supportDirectory() {
            AppIndexStore.save(found, to: directory)
        }
    }

    private func sameCatalog(_ lhs: [LaunchableApp], _ rhs: [LaunchableApp]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.path != right.path || left.name != right.name
                || left.bundleName != right.bundleName || left.bundleIdentifier != right.bundleIdentifier {
                return false
            }
        }
        return true
    }

    private func watchInstallLocations() {
        guard watchers.isEmpty else { return }
        for root in AppScanner.rootURLs() {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let fd = Darwin.open(root.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .link],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        AppIndex.shared.scheduleRescan()
                    }
                }
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            source.resume()
            watchers.append(source)
        }
    }

    private func orderedForEmptyQuery() -> [LaunchableApp] {
        let recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        let order = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ($1, $0) })
        return apps.sorted { lhs, rhs in
            let left = order[lhs.path] ?? Int.max
            let right = order[rhs.path] ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func remember(_ app: LaunchableApp) {
        var recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        recent.removeAll { $0 == app.path }
        recent.insert(app.path, at: 0)
        if recent.count > 12 {
            recent = Array(recent.prefix(12))
        }
        UserDefaults.standard.set(recent, forKey: recentKey)
    }
}

enum AppScanner {
    /// Directories that receive app installs. The index watches these so the
    /// launcher can refresh without scanning on every open.
    static func rootURLs() -> [URL] {
        let fileManager = FileManager.default
        var roots: [URL] = []
        roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .localDomainMask))
        roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .userDomainMask))
        roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .systemDomainMask))
        roots.append(URL(fileURLWithPath: "/Applications", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true))
        var seen = Set<String>()
        return roots.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    static func scan() -> [LaunchableApp] {
        let fileManager = FileManager.default
        var roots = rootURLs()
        roots.append(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))

        var seen = Set<String>()
        var apps: [LaunchableApp] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if root.pathExtension.lowercased() == "app" {
                if let app = makeApp(url: root, seen: &seen) {
                    apps.append(app)
                }
                continue
            }
            guard isDirectory.boolValue,
                  let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }
            let rootDepth = root.resolvingSymlinksInPath().pathComponents.count
            for case let url as URL in enumerator {
                if url.pathComponents.count - rootDepth > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                if let app = makeApp(url: url, seen: &seen) {
                    apps.append(app)
                }
            }
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return apps
    }

    private static func makeApp(url: URL, seen: inout Set<String>) -> LaunchableApp? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path
        if path.range(of: ".app/", options: .caseInsensitive) != nil { return nil }
        guard seen.insert(path).inserted else { return nil }
        let fallback = resolved.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: resolved)
        let localized = bundle?.localizedInfoDictionary
        let info = bundle?.infoDictionary
        let name = string(localized?["CFBundleDisplayName"])
            ?? string(info?["CFBundleDisplayName"])
            ?? string(localized?["CFBundleName"])
            ?? string(info?["CFBundleName"])
            ?? fallback
        guard !name.isEmpty else { return nil }
        return LaunchableApp(
            name: name,
            bundleName: string(info?["CFBundleName"]),
            path: path,
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

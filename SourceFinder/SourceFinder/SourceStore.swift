import Foundation
import CryptoKit
import SwiftUI

enum SourceFetcher {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Downloads and parses a source. Throws if it isn't a valid source.
    /// Successful downloads are saved so the app can open instantly next time.
    static func fetch(_ urlString: String, cache: Bool = true) async throws -> AltSource {
        guard let url = makeURL(urlString), url.scheme?.hasPrefix("http") == true else {
            throw FetchError.message("Not a valid http(s) URL.")
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.message("Server returned HTTP \(http.statusCode).")
        }
        let source = try parse(data, url: urlString)
        if cache { SourceCache.save(data, for: urlString) }
        return source
    }

    static func parse(_ data: Data, url: String) throws -> AltSource {
        do {
            return try JSONDecoder().decode(RawSource.self, from: data).toSource(url: url)
        } catch DecodingError.dataCorrupted(let ctx) {
            throw FetchError.message(ctx.debugDescription)
        } catch {
            throw FetchError.message("Not valid source JSON.")
        }
    }

    enum FetchError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let m): return m
            }
        }
    }
}

/// Saved copies of source JSON, so the app opens instantly and works offline.
enum SourceCache {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func file(for url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }

    static func save(_ data: Data, for url: String) {
        try? data.write(to: file(for: url), options: .atomic)
    }

    static func source(for url: String) -> AltSource? {
        guard let data = try? Data(contentsOf: file(for: url)) else { return nil }
        return try? SourceFetcher.parse(data, url: url)
    }

    /// Reads a saved copy off the main thread.
    static func loadSource(_ url: String) async -> AltSource? {
        SourceCache.source(for: url)
    }

    static func loadSources(_ urls: [String]) async -> [String: AltSource] {
        await withTaskGroup(of: (String, AltSource?).self) { group in
            for url in urls {
                group.addTask { (url, SourceCache.source(for: url)) }
            }
            var out: [String: AltSource] = [:]
            for await (url, cached) in group {
                if let cached { out[url] = cached }
            }
            return out
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

@MainActor
final class SourceStore: ObservableObject {
    enum LoadState {
        case loading
        case loaded(AltSource)
        case failed(String)
    }

    static let defaultSources: [String] = [
        "https://apps.altstore.io",
        "https://apps.sidestore.io/",
        "https://community-apps.sidestore.io/sidecommunity.json",
        "https://alt.getutm.app",
        "https://provenance-emu.com/apps.json",
        "https://flyinghead.github.io/flycast-builds/altstore.json",
        "https://altstore.oatmealdome.me",
        "https://xitrix.github.io/iTorrent/AltStore.json",
        "https://theodyssey.dev/altstore/odysseysource.json",
        "https://stikdebug.xyz/index.json",
        "https://raw.githubusercontent.com/khcrysalis/Feather/main/app-repo.json",
        "https://pokemmo.com/altstore/",
        "https://quarksources.github.io/dist/quantumsource.min.json",
    ]

    private static let defaultsKey = "savedSourceURLs"

    /// The user's sources, in their order.
    @Published private(set) var sourceURLs: [String]
    @Published private(set) var states: [String: LoadState] = [:]
    /// Refresh errors for sources that still show their saved copy.
    @Published private(set) var staleErrors: [String: String] = [:]
    /// Recommended sources that aren't in the user's list.
    @Published private(set) var previews: [String: LoadState] = [:]

    @Published private(set) var allApps: [AltApp] = []
    /// One entry per app (duplicates across sources merged), A to Z.
    @Published private(set) var groups: [SearchHit] = []
    @Published private(set) var recentGroups: [SearchHit] = []
    @Published private(set) var categories: [CategoryCount] = []
    /// Apps in recommended sources the user hasn't added.
    @Published private(set) var recommendedApps: [AltApp] = []

    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingPreviews = false
    @Published private(set) var loadedCount = 0
    /// Bumped whenever app data changes, so open searches re-run.
    @Published private(set) var dataVersion = 0

    private var didStart = false

    init() {
        sourceURLs = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? Self.defaultSources
    }

    // MARK: Reading

    var loadedSources: [AltSource] {
        sourceURLs.compactMap { if case .loaded(let s) = states[$0] { return s }; return nil }
    }

    func contains(_ url: String) -> Bool {
        let n = Self.normalize(url)
        return sourceURLs.contains { Self.normalize($0) == n }
    }

    /// A loaded source, whether it's in the user's list or a recommendation.
    func loadedSource(_ url: String) -> AltSource? {
        if case .loaded(let s) = states[url] { return s }
        if case .loaded(let s) = previews[url] { return s }
        return nil
    }

    func previewState(_ url: String) -> LoadState? {
        states[url] ?? previews[url]
    }

    /// The same app in other sources.
    func alternates(for app: AltApp) -> [AltApp] {
        (allApps + recommendedApps).filter { $0.groupKey == app.groupKey && $0.id != app.id }
    }

    // MARK: Loading

    /// Shows saved copies straight away, then refreshes from the network.
    func start() async {
        guard !didStart else { return }
        didStart = true
        let cached = await SourceCache.loadSources(sourceURLs)
        for (url, source) in cached where states[url] == nil {
            states[url] = .loaded(source)
        }
        rebuildApps()
        await refreshAll()
        await loadAllPreviews()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        loadedCount = 0
        defer { isRefreshing = false }
        let urls = sourceURLs
        for url in urls where states[url] == nil { states[url] = .loading }
        await withTaskGroup(of: (String, Result<AltSource, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let source = try await SourceFetcher.fetch(url)
                        return (url, .success(source))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            for await (url, result) in group {
                loadedCount += 1
                guard sourceURLs.contains(url) else { continue }
                switch result {
                case .success(let source):
                    states[url] = .loaded(source)
                    staleErrors[url] = nil
                case .failure(let error):
                    if Self.isLoaded(states[url]) {
                        staleErrors[url] = error.localizedDescription
                    } else {
                        states[url] = .failed(error.localizedDescription)
                    }
                }
                rebuildApps()
            }
        }
    }

    func retry(_ url: String) async {
        if !Self.isLoaded(states[url]) { states[url] = .loading }
        do {
            let source = try await SourceFetcher.fetch(url)
            guard sourceURLs.contains(url) else { return }
            states[url] = .loaded(source)
            staleErrors[url] = nil
        } catch {
            guard sourceURLs.contains(url) else { return }
            if Self.isLoaded(states[url]) {
                staleErrors[url] = error.localizedDescription
            } else {
                states[url] = .failed(error.localizedDescription)
            }
        }
        rebuildApps()
    }

    /// Loads a recommended source so it can be previewed and searched.
    func loadPreview(_ url: String) async {
        guard !contains(url) else { return }
        if Self.isLoaded(previews[url]) { return }
        if case .loading = previews[url] { return }
        previews[url] = .loading
        if let saved = await SourceCache.loadSource(url) {
            previews[url] = .loaded(saved)
            rebuildRecommended()
        }
        do {
            let source = try await SourceFetcher.fetch(url)
            previews[url] = .loaded(source)
        } catch {
            if !Self.isLoaded(previews[url]) {
                previews[url] = .failed(error.localizedDescription)
            }
        }
        rebuildRecommended()
    }

    func loadAllPreviews() async {
        isLoadingPreviews = true
        defer { isLoadingPreviews = false }
        await withTaskGroup(of: Void.self) { group in
            for rec in Recommendations.all where !contains(rec.url) {
                let url = rec.url
                group.addTask { await self.loadPreview(url) }
            }
        }
    }

    // MARK: Changing the list

    /// Checks the URL by fetching it, then saves it.
    @discardableResult
    func add(_ raw: String) async throws -> AltSource {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept links shared as sidestore://source?url=... or altstore://source?url=...
        if let comps = URLComponents(string: url),
           ["sidestore", "altstore"].contains(comps.scheme?.lowercased() ?? ""),
           let inner = comps.queryItems?.first(where: { $0.name == "url" })?.value {
            url = inner
        }
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        if contains(url) { throw SourceFetcher.FetchError.message("That source is already in your list.") }
        let source = try await SourceFetcher.fetch(url)
        add(loaded: source)
        return source
    }

    /// Adds a recommended source, using the preview if it's already loaded.
    func addRecommended(_ rec: RecommendedSource) async -> Bool {
        if contains(rec.url) { return true }
        if let source = loadedSource(rec.url) {
            add(loaded: source)
            return true
        }
        do {
            let source = try await SourceFetcher.fetch(rec.url)
            add(loaded: source)
            return true
        } catch {
            return false
        }
    }

    func add(loaded source: AltSource) {
        guard !contains(source.url) else { return }
        sourceURLs.append(source.url)
        states[source.url] = .loaded(source)
        previews[source.url] = nil
        save()
        rebuildApps()
    }

    func remove(_ url: String) {
        // Keep the data around so it still shows as a recommendation.
        if Self.isLoaded(states[url]) { previews[url] = states[url] }
        sourceURLs.removeAll { $0 == url }
        states[url] = nil
        staleErrors[url] = nil
        save()
        rebuildApps()
    }

    func move(from: IndexSet, to: Int) {
        sourceURLs.move(fromOffsets: from, toOffset: to)
        save()
        rebuildApps()
    }

    func resetToDefaults() async {
        let previous = states
        sourceURLs = Self.defaultSources
        states = [:]
        for url in sourceURLs {
            if let state = previous[url] { states[url] = state }
        }
        staleErrors = [:]
        save()
        rebuildApps()
        await refreshAll()
        await loadAllPreviews()
    }

    // MARK: Internals

    private func save() {
        UserDefaults.standard.set(sourceURLs, forKey: Self.defaultsKey)
    }

    private func rebuildApps() {
        allApps = loadedSources.flatMap(\.apps)
        groups = SearchEngine.groupAll(allApps)
        recentGroups = Array(
            groups.filter { $0.app.latestDate != nil }
                .sorted { ($0.app.latestDate ?? .distantPast) > ($1.app.latestDate ?? .distantPast) }
                .prefix(40)
        )
        categories = SearchEngine.categoryCounts(groups)
        rebuildRecommended()
    }

    private func rebuildRecommended() {
        var apps: [AltApp] = []
        for rec in Recommendations.all where !contains(rec.url) {
            if case .loaded(let source) = previews[rec.url] {
                apps.append(contentsOf: source.apps)
            }
        }
        recommendedApps = apps
        dataVersion &+= 1
    }

    private static func isLoaded(_ state: LoadState?) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func normalize(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }
}

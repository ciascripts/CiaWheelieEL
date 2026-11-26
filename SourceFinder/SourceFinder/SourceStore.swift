import Foundation
import SwiftUI

enum SourceFetcher {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: cfg)
    }()

    /// Downloads and parses a source. Throws if it isn't a valid source.
    static func fetch(_ urlString: String) async throws -> AltSource {
        guard let url = makeURL(urlString), url.scheme?.hasPrefix("http") == true else {
            throw FetchError.message("Not a valid http(s) URL.")
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.message("Server returned HTTP \(http.statusCode).")
        }
        do {
            let raw = try JSONDecoder().decode(RawSource.self, from: data)
            return raw.toSource(url: urlString)
        } catch DecodingError.dataCorrupted(let ctx) {
            throw FetchError.message(ctx.debugDescription)
        } catch {
            throw FetchError.message("Not valid source JSON.")
        }
    }

    enum FetchError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
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

    @Published private(set) var sourceURLs: [String]
    @Published private(set) var states: [String: LoadState] = [:]
    @Published private(set) var allApps: [AltApp] = []
    @Published private(set) var isRefreshing = false

    init() {
        sourceURLs = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? Self.defaultSources
    }

    var loadedSources: [AltSource] {
        sourceURLs.compactMap { if case .loaded(let s) = states[$0] { return s }; return nil }
    }

    func contains(_ url: String) -> Bool {
        sourceURLs.contains { normalize($0) == normalize(url) }
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        for u in sourceURLs where states[u] == nil { states[u] = .loading }
        await withTaskGroup(of: (String, LoadState).self) { group in
            for u in sourceURLs {
                group.addTask {
                    do {
                        let source = try await SourceFetcher.fetch(u)
                        return (u, LoadState.loaded(source))
                    } catch {
                        return (u, LoadState.failed(error.localizedDescription))
                    }
                }
            }
            for await (u, state) in group {
                states[u] = state
                rebuildApps()
            }
        }
    }

    /// Validates the URL by fetching it, then saves it.
    @discardableResult
    func add(_ raw: String) async throws -> AltSource {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept links shared as sidestore://source?url=... / altstore://source?url=...
        if let comps = URLComponents(string: url), ["sidestore", "altstore"].contains(comps.scheme?.lowercased() ?? ""),
           let inner = comps.queryItems?.first(where: { $0.name == "url" })?.value {
            url = inner
        }
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        if contains(url) { throw SourceFetcher.FetchError.message("That source is already in your list.") }
        let source = try await SourceFetcher.fetch(url)
        add(loaded: source)
        return source
    }

    func add(loaded source: AltSource) {
        guard !contains(source.url) else { return }
        sourceURLs.append(source.url)
        states[source.url] = .loaded(source)
        save()
        rebuildApps()
    }

    func remove(_ url: String) {
        sourceURLs.removeAll { $0 == url }
        states[url] = nil
        save()
        rebuildApps()
    }

    func move(from: IndexSet, to: Int) {
        sourceURLs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func resetToDefaults() async {
        sourceURLs = Self.defaultSources
        states = [:]
        save()
        rebuildApps()
        await refreshAll()
    }

    private func save() {
        UserDefaults.standard.set(sourceURLs, forKey: Self.defaultsKey)
    }

    private func rebuildApps() {
        allApps = loadedSources.flatMap(\.apps)
    }

    private func normalize(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }
}

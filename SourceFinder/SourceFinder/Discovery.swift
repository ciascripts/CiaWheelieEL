import Foundation

/// Finds new sources by searching public GitHub repositories, then probing
/// each repo for a JSON file that parses as an AltStore/SideStore source.
@MainActor
final class Discovery: ObservableObject {
    struct Found: Identifiable {
        var id: String { source.url }
        let repo: String
        let source: AltSource
    }

    static let presets = [
        "altstore source",
        "sidestore source",
        "topic:altstore-source",
        "topic:sidestore-source",
        "altstore repo",
        "ipa library",
    ]

    @Published private(set) var results: [Found] = []
    @Published private(set) var isSearching = false
    @Published private(set) var status: String?
    @Published private(set) var canLoadMore = false

    private var query = ""
    private var page = 1
    private var rateLimited = false
    private var searchTask: Task<Void, Never>?

    func search(_ q: String) {
        searchTask?.cancel()
        query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        page = 1
        results = []
        rateLimited = false
        searchTask = Task { await runPage() }
    }

    func loadMore() {
        guard !isSearching, canLoadMore else { return }
        page += 1
        searchTask = Task { await runPage() }
    }

    func cancel() {
        searchTask?.cancel()
        isSearching = false
    }

    private struct SearchResponse: Decodable {
        struct Repo: Decodable {
            let full_name: String
            let default_branch: String
        }
        let total_count: Int
        let items: [Repo]
    }

    private struct ContentItem: Decodable {
        let name: String
        let type: String
        let download_url: String?
    }

    private func runPage() async {
        isSearching = true
        defer { isSearching = false }
        status = "Searching GitHub…"

        var comps = URLComponents(string: "https://api.github.com/search/repositories")!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "sort", value: "updated"),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(page)),
        ]
        let repos: [SearchResponse.Repo]
        do {
            let (data, resp) = try await SourceFetcher.session.data(for: githubRequest(comps.url!))
            if let http = resp as? HTTPURLResponse, http.statusCode == 403 || http.statusCode == 429 {
                status = "GitHub's search limit was hit. Wait a minute and try again."
                return
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            repos = decoded.items
            canLoadMore = page * 30 < min(decoded.total_count, 1000)
        } catch {
            if !Task.isCancelled { status = "Search failed: \(error.localizedDescription)" }
            return
        }

        if repos.isEmpty {
            status = results.isEmpty ? "No repositories matched." : "No more results."
            return
        }

        var checked = 0
        status = "Checking \(repos.count) repositories…"
        await withTaskGroup(of: Found?.self) { group in
            for repo in repos {
                let name = repo.full_name, branch = repo.default_branch
                group.addTask { await SourceProbe.probe(name, branch: branch) }
            }
            for await found in group {
                checked += 1
                status = "Checked \(checked)/\(repos.count) repositories…"
                if let found, !results.contains(where: { $0.id == found.id }) {
                    results.append(found)
                }
            }
        }

        // Second pass: repos without a well-known file name - list their root
        // .json files through the GitHub API (rate limited, so best effort).
        let missing = repos.filter { r in !results.contains { $0.repo == r.full_name } }
        for repo in missing where !rateLimited && !Task.isCancelled {
            if let found = await probeViaContents(repo.full_name), !results.contains(where: { $0.id == found.id }) {
                results.append(found)
            }
        }

        if !Task.isCancelled {
            var msg = results.isEmpty ? "No sources found in these repositories." : "Found \(results.count) source\(results.count == 1 ? "" : "s")."
            if rateLimited { msg += " (GitHub API limit reached, some repos were skipped.)" }
            status = msg
        }
    }

    private func probeViaContents(_ repo: String) async -> Found? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/contents/") else { return nil }
        guard let response = try? await SourceFetcher.session.data(for: githubRequest(url)) else { return nil }
        let (data, resp) = response
        if let http = resp as? HTTPURLResponse, http.statusCode == 403 || http.statusCode == 429 {
            rateLimited = true
            return nil
        }
        guard let items = try? JSONDecoder().decode([ContentItem].self, from: data) else { return nil }
        let jsonFiles = items.filter {
            $0.type == "file" && $0.name.lowercased().hasSuffix(".json")
                && !SourceProbe.candidateFiles.contains($0.name)
                && !["package.json", "package-lock.json", "tsconfig.json", "renovate.json"].contains($0.name.lowercased())
        }
        for item in jsonFiles.prefix(5) {
            guard let dl = item.download_url else { continue }
            if let source = try? await SourceFetcher.fetch(dl), !source.apps.isEmpty {
                return Found(repo: repo, source: source)
            }
        }
        return nil
    }

    private func githubRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("SourceFinder-iOS", forHTTPHeaderField: "User-Agent")
        return req
    }
}

/// Checks a GitHub repo for a source file with a well-known name.
/// Kept outside the main-actor class so the checks run in parallel off the main thread.
enum SourceProbe {
    /// File names commonly used for sources, tried in order.
    static let candidateFiles = [
        "apps.json", "source.json", "altstore.json", "repo.json", "index.json",
        "sidestore.json", "app-repo.json", "altsource.json", "altstore-source.json", "apps.min.json",
    ]

    static func probe(_ repo: String, branch: String) async -> Discovery.Found? {
        for file in candidateFiles {
            if Task.isCancelled { return nil }
            let url = "https://raw.githubusercontent.com/\(repo)/\(branch)/\(file)"
            if let source = try? await SourceFetcher.fetch(url), !source.apps.isEmpty {
                return Discovery.Found(repo: repo, source: source)
            }
        }
        return nil
    }
}

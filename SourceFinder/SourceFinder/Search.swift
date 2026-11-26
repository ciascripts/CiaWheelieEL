import Foundation

// MARK: - Text normalizing

enum TextNormalizer {
    /// Lowercased, with accents and full-width characters folded ("Pokémon" -> "pokemon").
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Search words: folded, split on anything that isn't a letter or digit.
    static func words(_ s: String) -> [String] {
        fold(s).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Words plus camelCase and letter/digit pieces:
    /// "YTLitePlus" -> ytliteplus, yt, lite, plus. "EeveeSpotify" -> eeveespotify, eevee, spotify.
    static func tokens(_ s: String) -> [String] {
        var pieces: [String] = []
        for word in s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let chars = Array(word)
            var current = ""
            for i in chars.indices {
                let c = chars[i]
                if i > 0 && !current.isEmpty {
                    let p = chars[i - 1]
                    let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                    let lowerToUpper = p.isLowercase && c.isUppercase
                    let letterDigit = (p.isLetter && c.isNumber) || (p.isNumber && c.isLetter)
                    let acronymEnd = p.isUppercase && c.isUppercase && (next?.isLowercase ?? false)
                    if lowerToUpper || letterDigit || acronymEnd {
                        pieces.append(current)
                        current = ""
                    }
                }
                current.append(c)
            }
            if !current.isEmpty { pieces.append(current) }
        }
        var seen = Set<String>()
        var out: [String] = []
        for t in words(s) + pieces.map(fold) {
            if !t.isEmpty && !seen.contains(t) {
                seen.insert(t)
                out.append(t)
            }
        }
        return out
    }
}

/// Everything search looks at, normalized once when a source is parsed.
struct SearchFields {
    let name: String
    let compactName: String
    let nameTokens: [String]
    let developer: String
    let bundle: String
    /// "com.google.ios.youtube" -> com, google, ios, youtube
    let bundleParts: [String]
    let subtitle: String
    let subtitleWords: [String]
    let category: String
    let source: String
    let description: String
    let groupKey: String

    init(name: String, developer: String, bundle: String, subtitle: String?, category: String?,
         source: String, description: String?) {
        let folded = TextNormalizer.fold(name)
        let compact = folded.filter { $0.isLetter || $0.isNumber }
        let bundleID = bundle.lowercased()
        self.name = folded
        compactName = compact
        nameTokens = TextNormalizer.tokens(name)
        self.developer = TextNormalizer.fold(developer)
        self.bundle = bundleID
        bundleParts = bundleID.split(separator: ".").map(String.init)
        self.subtitle = TextNormalizer.fold(subtitle ?? "")
        subtitleWords = TextNormalizer.words(subtitle ?? "")
        self.category = TextNormalizer.fold(category ?? "")
        self.source = TextNormalizer.fold(source)
        self.description = TextNormalizer.fold(String((description ?? "").prefix(600)))
        groupKey = bundleID + "|" + compact
    }
}

// MARK: - Queries and results

enum SearchSort: String, CaseIterable, Identifiable {
    case relevance, name, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return "Best Match"
        case .name: return "Name"
        case .recent: return "Recently Updated"
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: return "star"
        case .name: return "textformat"
        case .recent: return "clock"
        }
    }
}

struct SearchQuery: Equatable {
    var text: String
    var category: String?
    var sourceURL: String?
    var sort: SearchSort
}

struct SearchHit: Identifiable, Hashable {
    let app: AltApp
    let score: Int
    /// How many other sources list the same app.
    let alsoIn: Int
    var id: String { app.id }
}

struct SearchResults {
    var hits: [SearchHit] = []
    /// Matches in recommended sources the user hasn't added yet.
    var recommendedHits: [SearchHit] = []
    static let empty = SearchResults()
}

struct CategoryCount: Identifiable, Hashable {
    let id: String
    let count: Int
}

// MARK: - Engine

enum SearchEngine {
    /// Runs off the main thread when awaited from the UI.
    static func run(_ query: SearchQuery, apps: [AltApp], recommendedApps: [AltApp]) async -> SearchResults {
        let words = TextNormalizer.words(query.text)
        let folded = TextNormalizer.fold(query.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let compact = words.joined()
        let hits = rank(apps, words: words, folded: folded, compact: compact,
                        category: query.category, sourceURL: query.sourceURL, sort: query.sort)
        guard !words.isEmpty, !Task.isCancelled else {
            return SearchResults(hits: hits, recommendedHits: [])
        }
        let mine = Set(hits.map { $0.app.groupKey })
        let recommended = rank(recommendedApps, words: words, folded: folded, compact: compact,
                               category: query.category, sourceURL: nil, sort: .relevance)
            .filter { !mine.contains($0.app.groupKey) }
        return SearchResults(hits: hits, recommendedHits: Array(recommended.prefix(25)))
    }

    /// Every app once (duplicates across sources merged), A to Z.
    static func groupAll(_ apps: [AltApp]) -> [SearchHit] {
        rank(apps, words: [], folded: "", compact: "", category: nil, sourceURL: nil, sort: .name)
    }

    static func categoryCounts(_ groups: [SearchHit]) -> [CategoryCount] {
        var counts: [String: Int] = [:]
        for g in groups where !g.app.search.category.isEmpty {
            counts[g.app.search.category, default: 0] += 1
        }
        return counts.map { CategoryCount(id: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }

    private struct Bucket {
        var app: AltApp
        var score: Int
        var count: Int
        let order: Int
    }

    static func rank(_ apps: [AltApp], words: [String], folded: String, compact: String,
                     category: String?, sourceURL: String?, sort: SearchSort) -> [SearchHit] {
        var buckets: [String: Bucket] = [:]
        var order = 0
        for app in apps {
            if let sourceURL, app.sourceURL != sourceURL { continue }
            if let category, app.search.category != category { continue }
            var points = 0
            if !words.isEmpty {
                guard let s = score(app.search, words: words, folded: folded, compact: compact) else { continue }
                points = s
            }
            let key = app.groupKey
            if var bucket = buckets[key] {
                bucket.count += 1
                // Keep the best match; on a tie keep the newest version.
                if points > bucket.score || (points == bucket.score && isNewer(app, than: bucket.app)) {
                    bucket.app = app
                    bucket.score = points
                }
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(app: app, score: points, count: 1, order: order)
                order += 1
            }
        }

        var list = Array(buckets.values)
        switch sort {
        case .relevance where !words.isEmpty:
            list.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.app.search.name < b.app.search.name
            }
        case .recent:
            list.sort { a, b in
                let da = a.app.latestDate ?? .distantPast
                let db = b.app.latestDate ?? .distantPast
                if da != db { return da > db }
                return a.app.search.name < b.app.search.name
            }
        default:
            list.sort { a, b in
                if a.app.search.name != b.app.search.name { return a.app.search.name < b.app.search.name }
                return a.order < b.order
            }
        }
        return list.map { SearchHit(app: $0.app, score: $0.score, alsoIn: $0.count - 1) }
    }

    /// Higher is better; nil when one of the words matches nothing.
    static func score(_ f: SearchFields, words: [String], folded: String, compact: String) -> Int? {
        var total = 0
        if f.name == folded || (!compact.isEmpty && f.compactName == compact) {
            total += 1000
        } else if f.name.hasPrefix(folded) || (!compact.isEmpty && f.compactName.hasPrefix(compact)) {
            total += 600
        } else if compact.count >= 3 && f.compactName.contains(compact) {
            total += 300
        }
        for word in words {
            let s = wordScore(f, word)
            if s == 0 { return nil }
            total += s
        }
        return total
    }

    private static func wordScore(_ f: SearchFields, _ w: String) -> Int {
        if f.nameTokens.contains(w) { return 300 }
        if f.nameTokens.contains(where: { $0.hasPrefix(w) }) { return 220 }
        if f.name.contains(w) { return 160 }
        if f.developer.contains(w) { return 110 }
        if f.subtitle.contains(w) { return 80 }
        if f.category == w { return 80 }
        if f.bundleParts.contains(where: { $0.hasPrefix(w) }) { return 70 }
        if f.source.contains(w) { return 40 }
        if w.count >= 3 && f.description.contains(w) { return 25 }

        // Typo tolerance: "dolpin" finds DolphiniOS, "spotfy" finds apps described as Spotify.
        let maxEdits = w.count >= 7 ? 2 : (w.count >= 4 ? 1 : 0)
        guard maxEdits > 0 else { return 0 }
        var best = Int.max
        for token in f.nameTokens {
            if abs(token.count - w.count) <= maxEdits {
                best = min(best, Fuzzy.distance(w, token, limit: maxEdits))
            }
            // A typo while still typing a longer word: compare with the word's start.
            if w.count >= 5 && token.count > w.count {
                for length in w.count...min(token.count, w.count + maxEdits) {
                    best = min(best, Fuzzy.distance(w, String(token.prefix(length)), limit: maxEdits))
                }
            }
        }
        if best <= maxEdits { return 120 - best * 30 }
        best = Int.max
        for token in f.subtitleWords where abs(token.count - w.count) <= maxEdits {
            best = min(best, Fuzzy.distance(w, token, limit: maxEdits))
        }
        return best <= maxEdits ? 70 - best * 20 : 0
    }

    private static func isNewer(_ a: AltApp, than b: AltApp) -> Bool {
        guard let da = a.latestDate else { return false }
        guard let db = b.latestDate else { return true }
        return da > db
    }
}

enum Fuzzy {
    /// Edit distance counting swapped neighbours as one edit.
    /// Stops early and returns `limit + 1` once the limit is passed.
    static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a.utf8), t = Array(b.utf8)
        let n = s.count, m = t.count
        if abs(n - m) > limit { return limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }
        var older = [Int](repeating: 0, count: m + 1)
        var previous = Array(0...m)
        var current = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            current[0] = i
            var rowMin = i
            for j in 1...m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1 && j > 1 && s[i - 1] == t[j - 2] && s[i - 2] == t[j - 1] {
                    value = min(value, older[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            (older, previous, current) = (previous, current, older)
        }
        return previous[m]
    }
}

import Foundation

// MARK: - Public models

/// One AltStore / SideStore source (a JSON file listing apps).
struct AltSource: Identifiable, Hashable {
    let url: String
    var id: String { url }
    let name: String
    let identifier: String?
    let subtitle: String?
    let iconURL: URL?
    let website: URL?
    let tintHex: String?
    let apps: [AltApp]

    /// The source's own icon, or its first app's icon when it has none.
    var displayIconURL: URL? { iconURL ?? apps.first?.iconURL }
    var displayTintHex: String? { tintHex ?? apps.first?.tintHex }
    var lastUpdated: Date? { apps.compactMap(\.latestDate).max() }

    static func == (lhs: AltSource, rhs: AltSource) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

struct AltApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let tintHex: String?
    let category: String?
    let screenshotURLs: [URL]
    let versions: [AltVersion]
    /// Sources mark test builds with "beta": true.
    let isBeta: Bool
    let sourceName: String
    let sourceURL: String
    /// Pre-normalized text so searching stays fast.
    let search: SearchFields

    var latest: AltVersion? { versions.first }
    var latestDate: Date? { latest?.parsedDate }
    var downloadURL: URL? { latest?.downloadURL }
    /// The same app listed by several sources shares this key.
    var groupKey: String { search.groupKey }

    static func == (lhs: AltApp, rhs: AltApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AltVersion: Hashable, Identifiable {
    var id: String { version + "|" + (date ?? "") + "|" + (downloadURL?.absoluteString ?? "") }
    let version: String
    let date: String?
    let parsedDate: Date?
    let downloadURL: URL?
    let size: Int?
    let notes: String?
    let minOSVersion: String?

    init(version: String, date: String?, downloadURL: URL?, size: Int?, notes: String?, minOSVersion: String?) {
        self.version = version
        self.date = date
        self.parsedDate = date.flatMap(DateParsing.parse)
        self.downloadURL = downloadURL
        self.size = size
        self.notes = notes
        self.minOSVersion = minOSVersion
    }
}

/// Sources write dates as "2024-05-01", "2024-05-01T10:00:00Z" or with fractional seconds.
enum DateParsing {
    private static let internet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-M-d"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = internet.date(from: s) ?? fractional.date(from: s) { return d }
        return day.date(from: String(s.prefix(10)))
    }
}

// MARK: - Lenient JSON decoding
// Sources in the wild are inconsistent (numbers as strings, missing fields,
// different screenshot layouts), so everything is decoded defensively and a
// single broken app never breaks the whole source.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where K == AnyKey {
    func string(_ key: String) -> String? {
        let k = AnyKey(key)
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s.isEmpty ? nil : s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return String(d) }
        return nil
    }

    func int(_ key: String) -> Int? {
        let k = AnyKey(key)
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Int(s) }
        return nil
    }

    func url(_ key: String) -> URL? { string(key).flatMap(makeURL) }

    func bool(_ key: String) -> Bool? {
        let k = AnyKey(key)
        if let b = try? decodeIfPresent(Bool.self, forKey: k) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return ["true", "yes", "1"].contains(s.lowercased()) }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i != 0 }
        return nil
    }
}

func makeURL(_ s: String) -> URL? {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let u = URL(string: trimmed), u.scheme != nil { return u }
    if let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
       let u = URL(string: enc), u.scheme != nil { return u }
    return nil
}

struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A screenshot entry can be a plain string or an object with `imageURL`.
private struct LooseScreenshot: Decodable {
    let url: URL?
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            url = makeURL(s)
        } else if let c = try? decoder.container(keyedBy: AnyKey.self) {
            url = c.url("imageURL") ?? c.url("url")
        } else {
            url = nil
        }
    }
}

private struct RawVersion: Decodable {
    let version: AltVersion?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let v = c.string("version") ?? c.string("buildVersion") else { version = nil; return }
        version = AltVersion(
            version: v,
            date: c.string("date"),
            downloadURL: c.url("downloadURL"),
            size: c.int("size"),
            notes: c.string("localizedDescription"),
            minOSVersion: c.string("minOSVersion")
        )
    }
}

struct RawApp: Decodable {
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let tintHex: String?
    let category: String?
    let screenshotURLs: [URL]
    let versions: [AltVersion]
    let isBeta: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let name = c.string("name") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "App without name"))
        }
        self.name = name
        bundleIdentifier = c.string("bundleIdentifier") ?? c.string("bundleID") ?? name
        developerName = c.string("developerName") ?? c.string("developer") ?? "Unknown developer"
        subtitle = c.string("subtitle")
        description = c.string("localizedDescription") ?? c.string("description")
        iconURL = c.url("iconURL") ?? c.url("icon")
        tintHex = c.string("tintColor")
        category = c.string("category")
        isBeta = c.bool("beta") ?? false

        var shots: [URL] = []
        for key in ["screenshots", "screenshotURLs"] where shots.isEmpty {
            let k = AnyKey(key)
            if let arr = try? c.decode([LooseScreenshot].self, forKey: k) {
                shots = arr.compactMap(\.url)
            } else if let nested = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: k) {
                for device in ["iphone", "ipad"] {
                    if let arr = try? nested.decode([LooseScreenshot].self, forKey: AnyKey(device)) {
                        shots += arr.compactMap(\.url)
                    }
                }
            }
        }
        screenshotURLs = shots

        var versions = ((try? c.decode([RawVersion].self, forKey: AnyKey("versions"))) ?? []).compactMap(\.version)
        if versions.isEmpty, let v = c.string("version") {
            // Legacy (pre-AltStore 2.0) flat layout.
            versions = [AltVersion(
                version: v,
                date: c.string("versionDate"),
                downloadURL: c.url("downloadURL"),
                size: c.int("size"),
                notes: c.string("versionDescription"),
                minOSVersion: c.string("minOSVersion")
            )]
        }
        self.versions = versions
    }
}

struct RawSource: Decodable {
    let name: String?
    let identifier: String?
    let subtitle: String?
    let iconURL: URL?
    let website: URL?
    let tintHex: String?
    let apps: [RawApp]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let apps = try? c.decode([Lenient<RawApp>].self, forKey: AnyKey("apps")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No \"apps\" list - this isn't an AltStore/SideStore source."))
        }
        self.apps = apps.compactMap(\.value)
        name = c.string("name")
        identifier = c.string("identifier")
        subtitle = c.string("subtitle") ?? c.string("description")
        iconURL = c.url("iconURL")
        website = c.url("website")
        tintHex = c.string("tintColor")
    }

    func toSource(url: String) -> AltSource {
        let sourceName = name ?? URL(string: url)?.host ?? url
        var mapped: [AltApp] = []
        mapped.reserveCapacity(apps.count)
        for (index, a) in apps.enumerated() {
            mapped.append(AltApp(
                id: "\(url)#\(a.bundleIdentifier)#\(index)",
                name: a.name,
                bundleIdentifier: a.bundleIdentifier,
                developerName: a.developerName,
                subtitle: a.subtitle,
                description: a.description,
                iconURL: a.iconURL,
                tintHex: a.tintHex,
                category: a.category,
                screenshotURLs: a.screenshotURLs,
                versions: a.versions,
                isBeta: a.isBeta,
                sourceName: sourceName,
                sourceURL: url,
                search: SearchFields(
                    name: a.name,
                    developer: a.developerName,
                    bundle: a.bundleIdentifier,
                    subtitle: a.subtitle,
                    category: a.category,
                    source: sourceName,
                    description: a.description
                )
            ))
        }
        return AltSource(url: url, name: sourceName, identifier: identifier, subtitle: subtitle,
                         iconURL: iconURL, website: website, tintHex: tintHex, apps: mapped)
    }
}

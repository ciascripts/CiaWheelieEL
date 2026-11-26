import SwiftUI

struct BridgeMessage: Identifiable, Decodable, Equatable {
    let id: Int
    let from: String      // "claude", "codex", "you", "system"
    let kind: String      // message, proposal, decision, work, review, done
    let text: String
    let ts: Double
    let assignee: String?
    let link: String?
    let auto: Bool?

    var date: Date { Date(timeIntervalSince1970: ts / 1000) }
}

struct BridgeTask: Decodable, Equatable {
    let title: String
    let repo: String?
    let details: String?
    let assignee: String?
    let status: String?
}

struct BridgeState: Decodable {
    let messages: [BridgeMessage]
    let lastId: Int
    let task: BridgeTask?
    let stopped: Bool
    let presence: [String: Double]?
}

/// Keeps the room in sync with the bridge server.
@MainActor
final class BridgeModel: ObservableObject {
    private static let urlKey = "bridgeURL"

    @Published var connectionURL: String {
        didSet {
            UserDefaults.standard.set(connectionURL, forKey: Self.urlKey)
            problem = nil
        }
    }
    @Published private(set) var messages: [BridgeMessage] = []
    @Published private(set) var task: BridgeTask?
    @Published private(set) var stopped = false
    @Published private(set) var presence: [String: Double] = [:]
    @Published private(set) var connected = false
    @Published private(set) var problem: String?

    private var lastId = 0

    init() {
        connectionURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
    }

    /// Accepts the MCP URL (https://host/mcp/KEY) or the API URL and returns https://host/api/KEY.
    /// Finds the bridge URL anywhere in the pasted text, so invisible characters,
    /// quotes or extra words copied along with it don't matter.
    var apiBase: URL? {
        let pattern = #"(https?)://([A-Za-z0-9.\-]+(?::[0-9]+)?)/(?:mcp|api)/([A-Za-z0-9_\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: connectionURL, range: NSRange(connectionURL.startIndex..., in: connectionURL)),
              let scheme = Range(match.range(at: 1), in: connectionURL),
              let host = Range(match.range(at: 2), in: connectionURL),
              let key = Range(match.range(at: 3), in: connectionURL) else { return nil }
        return URL(string: "\(connectionURL[scheme])://\(connectionURL[host])/api/\(connectionURL[key])")
    }

    var mcpURL: String? {
        guard let base = apiBase else { return nil }
        return base.absoluteString.replacingOccurrences(of: "/api/", with: "/mcp/")
    }

    func isOnline(_ agent: String) -> Bool {
        guard let last = presence[agent] else { return false }
        return Date().timeIntervalSince1970 * 1000 - last < 10 * 60 * 1000
    }

    // MARK: Actions

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        _ = await request("message", body: ["text": t])
        await refresh()
    }

    func setTask(title: String, repo: String, details: String) async {
        _ = await request("task", body: ["title": title, "repo": repo, "details": details])
        await refresh()
    }

    func setStopped(_ value: Bool) async {
        _ = await request(value ? "stop" : "resume", body: [:])
        await refresh()
    }

    func clear() async {
        _ = await request("clear", body: [:])
        messages = []
        lastId = 0
        await refresh()
    }

    func reload() async {
        messages = []
        lastId = 0
        await refresh()
    }

    func refresh() async {
        guard let data = await request("state?since=\(lastId)", body: nil),
              let state = try? JSONDecoder().decode(BridgeState.self, from: data) else { return }
        if state.lastId < lastId {
            // The room was cleared elsewhere; start over.
            messages = []
            lastId = 0
            return await refresh()
        }
        let known = Set(messages.map(\.id))
        let fresh = state.messages.filter { !known.contains($0.id) }
        if !fresh.isEmpty { messages.append(contentsOf: fresh) }
        if messages.count > 500 { messages.removeFirst(messages.count - 500) }
        lastId = max(lastId, state.lastId)
        task = state.task
        stopped = state.stopped
        presence = state.presence ?? [:]
    }

    func pollForever() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func request(_ path: String, body: [String: String]?) async -> Data? {
        guard let base = apiBase else {
            connected = false
            problem = "Add your bridge URL in Settings."
            return nil
        }
        guard let url = URL(string: base.absoluteString + "/" + path) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                connected = false
                problem = "The bridge didn't recognise this URL. Check the key in Settings."
                return nil
            }
            connected = true
            problem = nil
            return data
        } catch {
            connected = false
            problem = "Can't reach the bridge: \(error.localizedDescription)"
            return nil
        }
    }
}

enum StarterPrompts {
    static func prompt(for agent: String) -> String {
        let me = agent == "claude" ? "claude" : "codex"
        let other = agent == "claude" ? "Codex" : "Claude"
        return """
        Use the AI Bridge connector. Call bridge_join with agent "\(me)", read the task, then work through it with \(other) in the room:
        discuss who is better suited and post a proposal, agree on a decision, then either do the work on a new GitHub branch and open a pull request, or review the other agent's pull request.
        Between steps, keep calling bridge_wait (with the last message id you saw) until the other agent replies. Keep going until a "done" message, or until I say stop. Keep your room messages short.
        """
    }
}

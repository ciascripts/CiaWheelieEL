import SwiftUI
import UIKit

/// Talks to the iPad MCP server's Stop/Resume switch on the PC.
@MainActor
final class ControlModel: ObservableObject {
    private static let addressKey = "pcAddress"

    @Published var address: String {
        didSet { UserDefaults.standard.set(address, forKey: Self.addressKey) }
    }
    @Published private(set) var stopped = false
    @Published private(set) var connected = false
    @Published private(set) var lastAction = "Not connected yet"
    @Published private(set) var problem: String?

    let pip = PiPController()

    init() {
        address = UserDefaults.standard.string(forKey: Self.addressKey) ?? ""
        pip.onSetPlaying = { [weak self] playing in
            Task { @MainActor in
                guard let self else { return }
                if playing { await self.resume() } else { await self.stop() }
            }
        }
    }

    /// http://<address>:8765, adding the scheme and default port when missing.
    var baseURL: URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text) else { return nil }
        if url.port == nil, let withPort = URL(string: text + ":8765") { return withPort }
        return url
    }

    func stop() async {
        stopped = true  // show it straight away; the server confirms below
        updatePiP()
        await send("stop")
    }

    func resume() async {
        await send("resume")
    }

    func refresh() async {
        await send("status", method: "GET")
    }

    /// Checks the PC every 1.5 s while the app or its PiP window is alive.
    func pollForever() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private struct Status: Decodable {
        let stopped: Bool
        let last_action: String
    }

    private func send(_ path: String, method: String = "POST") async {
        guard let base = baseURL else {
            connected = false
            problem = "Enter your PC's address below."
            updatePiP()
            return
        }
        // Keep running long enough to deliver a Stop even if the app is in the background.
        let task = UIApplication.shared.beginBackgroundTask(withName: "control")
        defer { UIApplication.shared.endBackgroundTask(task) }

        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 4
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let status = try JSONDecoder().decode(Status.self, from: data)
            stopped = status.stopped
            lastAction = status.last_action
            connected = true
            problem = nil
        } catch {
            connected = false
            problem = "Can't reach the PC at \(base.absoluteString). Is the MCP server running, and are both on the same Wi-Fi?"
        }
        updatePiP()
    }

    private func updatePiP() {
        pip.render(stopped: stopped, connected: connected, detail: connected ? "Last: \(lastAction)" : (address.isEmpty ? "No PC address set" : "PC: \(address)"))
    }
}

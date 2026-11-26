import SwiftUI

@main
struct SourceFinderApp: App {
    @StateObject private var store = SourceStore()
    @StateObject private var discovery = Discovery()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(discovery)
                .task { await store.refreshAll() }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            AppSearchView()
                .tabItem { Label("Apps", systemImage: "magnifyingglass") }
            SourcesView()
                .tabItem { Label("My Sources", systemImage: "tray.full") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "globe") }
        }
    }
}

/// Builds sidestore:// and altstore:// links.
enum DeepLink {
    enum Store: String, CaseIterable, Identifiable {
        case sidestore, altstore
        var id: String { rawValue }
        var title: String { self == .sidestore ? "SideStore" : "AltStore" }
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    static func addSource(_ sourceURL: String, in store: Store) -> URL? {
        URL(string: "\(store.rawValue)://source?url=\(encode(sourceURL))")
    }

    static func install(_ ipaURL: URL, in store: Store) -> URL? {
        URL(string: "\(store.rawValue)://install?url=\(encode(ipaURL.absoluteString))")
    }
}

/// Opens a URL and shows an alert if no installed app handles it.
struct LinkOpener: ViewModifier {
    @Binding var failedTarget: String?
    func body(content: Content) -> some View {
        content.alert("Couldn't open link",
                      isPresented: Binding(get: { failedTarget != nil }, set: { if !$0 { failedTarget = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(failedTarget ?? "The app") doesn't seem to be installed on this device.")
        }
    }
}

struct IconView: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "app.dashed").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

func formatBytes(_ n: Int?) -> String? {
    guard let n, n > 0 else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

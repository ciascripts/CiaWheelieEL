import SwiftUI

@main
struct SourceFinderApp: App {
    @StateObject private var store = SourceStore()
    @StateObject private var discovery = Discovery()
    @StateObject private var router = Router()
    @StateObject private var toast = ToastCenter()
    @StateObject private var recents = RecentSearches()

    init() {
        // A bigger cache keeps icons and screenshots from reloading while scrolling.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024, directory: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(discovery)
                .environmentObject(router)
                .environmentObject(toast)
                .environmentObject(recents)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2.fill") }
                .tag(Router.Tab.browse)
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
                .tag(Router.Tab.discover)
            SourcesView()
                .tabItem { Label("Sources", systemImage: "tray.full.fill") }
                .tag(Router.Tab.sources)
        }
        .overlay(alignment: .top) { ToastOverlay() }
        .task { await store.start() }
    }
}

@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case browse, discover, sources }
    @Published var tab: Tab = .browse
    /// Set this to open Discover's GitHub search with the given text.
    @Published var pendingGitHubQuery: String?
}

@MainActor
final class RecentSearches: ObservableObject {
    private static let key = "recentSearches"
    @Published private(set) var items: [String]

    init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        items.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        items.insert(t, at: 0)
        if items.count > 8 { items = Array(items.prefix(8)) }
        UserDefaults.standard.set(items, forKey: Self.key)
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

enum Prefs {
    static let preferredStoreKey = "preferredStore"
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

/// Opens SideStore or AltStore, and says so when it isn't installed.
@MainActor
enum Installer {
    static func install(_ ipa: URL, with target: DeepLink.Store, openURL: OpenURLAction, toast: ToastCenter) {
        launch(DeepLink.install(ipa, in: target), target: target, openURL: openURL, toast: toast)
    }

    static func addSource(_ sourceURL: String, to target: DeepLink.Store, openURL: OpenURLAction, toast: ToastCenter) {
        launch(DeepLink.addSource(sourceURL, in: target), target: target, openURL: openURL, toast: toast)
    }

    private static func launch(_ link: URL?, target: DeepLink.Store, openURL: OpenURLAction, toast: ToastCenter) {
        guard let link else { return }
        openURL(link) { accepted in
            if accepted {
                Haptics.success()
            } else {
                toast.show("\(target.title) isn't installed", systemImage: "exclamationmark.triangle.fill")
            }
        }
    }
}

extension View {
    /// Navigation destinations shared by every tab. Register once per NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: AltApp.self) { AppDetailView(app: $0) }
            .navigationDestination(for: AltSource.self) { SourceDetailView(source: $0) }
            .navigationDestination(for: RecommendedSource.self) { RecommendedSourceView(rec: $0) }
            .navigationDestination(for: AppListRoute.self) { AppListView(route: $0) }
    }
}

import SwiftUI
import UIKit

struct SourcesView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var toast: ToastCenter
    @EnvironmentObject private var recents: RecentSearches
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.preferredStoreKey) private var preferred: DeepLink.Store = .sidestore
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.sourceURLs, id: \.self) { url in
                        MySourceRow(url: url)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.remove(url)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    UIPasteboard.general.string = url
                                    toast.show("Source URL copied", systemImage: "doc.on.doc.fill")
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Installer.addSource(url, to: preferred, openURL: openURL, toast: toast)
                                } label: {
                                    Label(preferred.title, systemImage: "plus.app")
                                }
                                .tint(.accentColor)
                            }
                    }
                    .onDelete { offsets in
                        let urls = offsets.map { store.sourceURLs[$0] }
                        for url in urls { store.remove(url) }
                    }
                    .onMove { from, to in store.move(from: from, to: to) }
                } header: {
                    Text("\(store.sourceURLs.count) sources · \(store.groups.count) apps")
                } footer: {
                    Text("Swipe right to add a source to \(preferred.title). Swipe left to copy or delete it. Sources higher in the list win when the same app is in several.")
                }

                let suggestions = Array(Recommendations.featured.filter { !store.contains($0.url) }.prefix(3))
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { rec in
                            NavigationLink(value: rec) { RecommendedRow(rec: rec) }
                        }
                        Button {
                            router.tab = .discover
                        } label: {
                            Label("See All Recommendations", systemImage: "sparkles")
                        }
                    } header: {
                        Text("Suggested")
                    }
                }
            }
            .refreshable { await store.refreshAll() }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            Label("Refresh All", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Divider()
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add source")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSourceSheet()
                    .environmentObject(store)
                    .environmentObject(toast)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(store)
                    .environmentObject(toast)
                    .environmentObject(recents)
            }
            .confirmationDialog("Replace your list with the default sources?", isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    Task { await store.resetToDefaults() }
                }
            }
            .appDestinations()
        }
    }
}

private struct MySourceRow: View {
    let url: String
    @EnvironmentObject private var store: SourceStore

    var body: some View {
        switch store.states[url] {
        case .loaded(let source):
            NavigationLink(value: source) {
                HStack(spacing: 12) {
                    IconView(url: source.displayIconURL, size: 44, tint: HexColor.color(source.displayTintHex))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(.headline).lineLimit(1)
                        Text(detail(for: source)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if store.staleErrors[url] != nil {
                        Spacer(minLength: 4)
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Couldn't refresh. Showing the saved copy.")
                    }
                }
                .padding(.vertical, 2)
            }
        case .failed(let message):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url).font(.subheadline).lineLimit(1)
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("Retry") {
                    Task { await store.retry(url) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            }
        case .loading, .none:
            HStack(spacing: 12) {
                ProgressView().frame(width: 44)
                Text(url).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func detail(for source: AltSource) -> String {
        var parts = ["\(source.apps.count) app\(source.apps.count == 1 ? "" : "s")"]
        if let d = source.lastUpdated {
            parts.append("updated " + d.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

struct SourceDetailView: View {
    let source: AltSource
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.preferredStoreKey) private var preferred: DeepLink.Store = .sidestore
    @State private var query = ""

    private var apps: [AltApp] {
        let words = TextNormalizer.words(query)
        guard !words.isEmpty else { return source.apps }
        return source.apps.filter { app in
            words.allSatisfy { w in
                app.search.name.contains(w) || app.search.developer.contains(w) || app.search.subtitle.contains(w)
            }
        }
    }

    private var statusLine: String {
        var parts = ["\(source.apps.count) app\(source.apps.count == 1 ? "" : "s")"]
        if let d = source.lastUpdated {
            parts.append("updated " + d.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let saved = store.contains(source.url)
        let tint = HexColor.color(source.displayTintHex) ?? Color.accentColor
        let list = apps
        let words = TextNormalizer.words(query)
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        IconView(url: source.displayIconURL, size: 68, tint: tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name).font(.title3.weight(.bold)).lineLimit(2)
                            Text(statusLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let subtitle = source.subtitle {
                        Text(subtitle).font(.callout)
                    }
                    HStack(spacing: 10) {
                        if saved {
                            Label("Saved", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        } else {
                            Button {
                                store.add(loaded: source)
                                Haptics.success()
                                toast.show("Added \(source.name)")
                            } label: {
                                Label("Save Source", systemImage: "plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button {
                            Installer.addSource(source.url, to: preferred, openURL: openURL, toast: toast)
                        } label: {
                            Label(preferred.title, systemImage: "plus.app").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        moreMenu(saved: saved)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(list) { app in
                    NavigationLink(value: app) {
                        AppRow(app: app, highlight: words, showSource: false)
                    }
                }
            } header: {
                Text("\(list.count) App\(list.count == 1 ? "" : "s")")
            }
        }
        .searchable(text: $query, prompt: "Search this source")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moreMenu(saved: Bool) -> some View {
        Menu {
            ForEach(DeepLink.Store.allCases.filter { $0 != preferred }) { other in
                Button {
                    Installer.addSource(source.url, to: other, openURL: openURL, toast: toast)
                } label: {
                    Label("Add to \(other.title)", systemImage: "plus.app")
                }
            }
            Button {
                UIPasteboard.general.string = source.url
                toast.show("Source URL copied", systemImage: "doc.on.doc.fill")
            } label: {
                Label("Copy Source URL", systemImage: "doc.on.doc")
            }
            if let link = URL(string: source.url) {
                ShareLink(item: link) {
                    Label("Share Source", systemImage: "square.and.arrow.up")
                }
            }
            if let site = source.website {
                Button {
                    openURL(site)
                } label: {
                    Label("Website", systemImage: "safari")
                }
            }
            if saved {
                Divider()
                Button(role: .destructive) {
                    store.remove(source.url)
                    toast.show("Removed \(source.name)", systemImage: "trash.fill")
                } label: {
                    Label("Remove Source", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 36, height: 30)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityLabel("More options")
    }
}

/// Loads a recommended source, then shows it like any other source.
struct RecommendedSourceView: View {
    let rec: RecommendedSource
    @EnvironmentObject private var store: SourceStore

    var body: some View {
        content
            .task { await store.loadPreview(rec.url) }
    }

    @ViewBuilder private var content: some View {
        switch store.previewState(rec.url) {
        case .loaded(let source):
            SourceDetailView(source: source)
        case .failed(let message):
            VStack(spacing: 16) {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load \(rec.name)", message: message)
                Button("Try Again") {
                    Task { await store.loadPreview(rec.url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle(rec.name)
        case .loading, .none:
            ProgressView("Loading \(rec.name)…")
                .navigationTitle(rec.name)
        }
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String? = nil
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/apps.json", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    if UIPasteboard.general.hasStrings {
                        Button {
                            if let s = UIPasteboard.general.string { text = s }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    }
                } header: {
                    Text("Source URL")
                } footer: {
                    Text("Paste a source URL, or a sidestore:// or altstore:// link. It's checked before it's saved.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                let suggestions = Recommendations.all.filter { !store.contains($0.url) }
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { rec in RecommendedRow(rec: rec) }
                    } header: {
                        Text("Recommended")
                    }
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func add() {
        guard !working, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        Task {
            do {
                let source = try await store.add(text)
                Haptics.success()
                toast.show("Added \(source.name)")
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

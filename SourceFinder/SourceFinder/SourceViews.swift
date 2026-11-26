import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: SourceStore
    @State private var showingAdd = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sourceURLs, id: \.self) { url in
                    SourceRow(url: url, state: store.states[url])
                }
                .onDelete { idx in idx.map { store.sourceURLs[$0] }.forEach(store.remove) }
                .onMove(perform: store.move)
            }
            .refreshable { await store.refreshAll() }
            .navigationTitle("My Sources")
            .navigationDestination(for: AltSource.self) { SourceDetailView(source: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { Task { await store.refreshAll() } } label: { Label("Refresh all", systemImage: "arrow.clockwise") }
                        Button(role: .destructive) { confirmReset = true } label: { Label("Reset to defaults", systemImage: "arrow.counterclockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { AddSourceSheet() }
            .confirmationDialog("Replace your list with the default sources?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { Task { await store.resetToDefaults() } }
            }
        }
    }
}

private struct SourceRow: View {
    let url: String
    let state: SourceStore.LoadState?

    var body: some View {
        switch state {
        case .loaded(let source):
            NavigationLink(value: source) {
                HStack(spacing: 12) {
                    IconView(url: source.iconURL ?? source.apps.first?.iconURL, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(.headline).lineLimit(1)
                        Text("\(source.apps.count) app\(source.apps.count == 1 ? "" : "s") · \(url)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                Label(url, systemImage: "exclamationmark.triangle").font(.subheadline).lineLimit(1)
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        case .loading, .none:
            HStack {
                ProgressView()
                Text(url).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SourceDetailView: View {
    @EnvironmentObject private var store: SourceStore
    let source: AltSource
    @Environment(\.openURL) private var openURL
    @State private var failedTarget: String?
    @State private var query = ""
    @State private var copied = false

    private var apps: [AltApp] {
        let q = query.lowercased()
        return q.isEmpty ? source.apps : source.apps.filter { $0.searchKey.contains(q) }
    }

    var body: some View {
        List {
            Section {
                if let subtitle = source.subtitle { Text(subtitle).font(.callout) }
                Text(source.url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if !store.contains(source.url) {
                    Button { store.add(loaded: source) } label: {
                        Label("Save to My Sources", systemImage: "tray.and.arrow.down")
                    }
                }
                ForEach(DeepLink.Store.allCases) { target in
                    Button {
                        guard let link = DeepLink.addSource(source.url, in: target) else { return }
                        openURL(link) { ok in if !ok { failedTarget = target.title } }
                    } label: {
                        Label("Add to \(target.title)", systemImage: "plus.circle")
                    }
                }
                Button {
                    UIPasteboard.general.string = source.url
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy source URL", systemImage: "doc.on.doc")
                }
                if let site = source.website {
                    Button { openURL(site) } label: { Label("Website", systemImage: "safari") }
                }
            }
            Section("\(source.apps.count) apps") {
                ForEach(apps) { app in
                    NavigationLink { AppDetailView(app: app) } label: { AppRow(app: app, showSource: false) }
                }
            }
        }
        .searchable(text: $query, prompt: "Search this source")
        .navigationTitle(source.name)
        .modifier(LinkOpener(failedTarget: $failedTarget))
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject private var store: SourceStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/apps.json", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Paste from clipboard") {
                        if let s = UIPasteboard.general.string { text = s }
                    }
                } footer: {
                    Text("Source URLs and sidestore:// or altstore:// source links both work. The source is checked before it's saved.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Add") {
                            working = true
                            error = nil
                            Task {
                                do { try await store.add(text); dismiss() }
                                catch { self.error = error.localizedDescription }
                                working = false
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var discovery: Discovery
    @State private var query = "altstore source"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Search GitHub for sources", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { discovery.search(query) }
                        if discovery.isSearching {
                            Button("Stop") { discovery.cancel() }
                        } else {
                            Button("Search") { discovery.search(query) }
                                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Discovery.presets, id: \.self) { p in
                                Button(p) { query = p; discovery.search(p) }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                            }
                        }
                    }
                } footer: {
                    Text("Searches public GitHub repositories and checks each one for a working AltStore/SideStore source file. Anyone can publish a source, so only install apps from sources you trust.")
                }

                if let status = discovery.status {
                    Section {
                        HStack {
                            if discovery.isSearching { ProgressView() }
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if !discovery.results.isEmpty {
                    Section("Found sources") {
                        ForEach(discovery.results) { found in
                            NavigationLink(value: found.source) {
                                HStack(spacing: 12) {
                                    IconView(url: found.source.iconURL ?? found.source.apps.first?.iconURL, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(found.source.name).font(.headline).lineLimit(1)
                                        Text("\(found.source.apps.count) apps · \(found.repo)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if store.contains(found.source.url) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Button { store.add(loaded: found.source) } label: {
                                            Image(systemName: "plus.circle.fill").font(.title2)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                        if discovery.canLoadMore && !discovery.isSearching {
                            Button("Search more repositories") { discovery.loadMore() }
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationDestination(for: AltSource.self) { SourceDetailView(source: $0) }
        }
    }
}

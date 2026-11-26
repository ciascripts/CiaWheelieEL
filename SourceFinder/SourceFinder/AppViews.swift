import SwiftUI

struct AppSearchView: View {
    @EnvironmentObject private var store: SourceStore
    @State private var query = ""
    @State private var sourceFilter: String? = nil

    private var results: [AltApp] {
        var apps = store.allApps
        if let sourceFilter { apps = apps.filter { $0.sourceURL == sourceFilter } }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        if !terms.isEmpty {
            apps = apps.filter { app in terms.allSatisfy { app.searchKey.contains($0) } }
            // Names that start with the query first.
            let q = query.lowercased()
            apps.sort { a, b in
                let aw = a.name.lowercased().hasPrefix(q), bw = b.name.lowercased().hasPrefix(q)
                if aw != bw { return aw }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        } else {
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return apps
    }

    var body: some View {
        NavigationStack {
            let list = results
            List {
                if store.isRefreshing && store.allApps.isEmpty {
                    HStack { ProgressView(); Text("Loading sources…").foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(list) { app in
                        NavigationLink(value: app) { AppRow(app: app) }
                    }
                } header: {
                    if !store.allApps.isEmpty {
                        Text("\(list.count) apps from \(sourceFilter == nil ? store.loadedSources.count : 1) source\(sourceFilter == nil && store.loadedSources.count != 1 ? "s" : "")")
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if !store.allApps.isEmpty && list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No apps match \"\(query)\"").foregroundStyle(.secondary)
                        Text("Try the Discover tab to find more sources.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search apps, developers, bundle IDs")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await store.refreshAll() }
            .navigationTitle("Apps")
            .navigationDestination(for: AltApp.self) { AppDetailView(app: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Source", selection: $sourceFilter) {
                            Text("All sources").tag(String?.none)
                            ForEach(store.loadedSources) { s in
                                Text(s.name).tag(String?.some(s.url))
                            }
                        }
                    } label: {
                        Image(systemName: sourceFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }
}

struct AppRow: View {
    let app: AltApp
    var showSource = true

    var body: some View {
        HStack(spacing: 12) {
            IconView(url: app.iconURL, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline).lineLimit(1)
                Text([app.developerName, app.latest.map { "v\($0.version)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if showSource {
                    Text(app.sourceName).font(.caption).foregroundStyle(.tint).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct AppDetailView: View {
    let app: AltApp
    @Environment(\.openURL) private var openURL
    @State private var failedTarget: String?
    @State private var copied = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    IconView(url: app.iconURL, size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold())
                        Text(app.developerName).foregroundStyle(.secondary)
                        if let subtitle = app.subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 4)
            }

            if let latest = app.latest, let ipa = latest.downloadURL {
                Section("Install v\(latest.version)") {
                    ForEach(DeepLink.Store.allCases) { target in
                        Button {
                            open(DeepLink.install(ipa, in: target), name: target.title)
                        } label: {
                            Label("Install with \(target.title)", systemImage: "arrow.down.app")
                        }
                    }
                    Button { openURL(ipa) } label: { Label("Download IPA", systemImage: "safari") }
                    Button {
                        UIPasteboard.general.string = ipa.absoluteString
                        copied = true
                    } label: {
                        Label(copied ? "Copied!" : "Copy IPA link", systemImage: "doc.on.doc")
                    }
                }
            } else {
                Section { Text("This source lists no download link for this app.").foregroundStyle(.secondary) }
            }

            Section("Source") {
                LabeledContent("Name", value: app.sourceName)
                ForEach(DeepLink.Store.allCases) { target in
                    Button {
                        open(DeepLink.addSource(app.sourceURL, in: target), name: target.title)
                    } label: {
                        Label("Add source to \(target.title)", systemImage: "plus.circle")
                    }
                }
            }

            if !app.screenshotURLs.isEmpty {
                Section("Screenshots") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(app.screenshotURLs, id: \.self) { url in
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFit() }
                                    else { Color.secondary.opacity(0.15).frame(width: 140) }
                                }
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if let desc = app.description {
                Section("About") { Text(desc).font(.callout) }
            }

            Section("Info") {
                LabeledContent("Bundle ID", value: app.bundleIdentifier)
                if let cat = app.category { LabeledContent("Category", value: cat.capitalized) }
                if let size = formatBytes(app.latest?.size) { LabeledContent("Size", value: size) }
                if let min = app.latest?.minOSVersion { LabeledContent("Requires iOS", value: min + "+") }
            }

            if app.versions.count > 0 {
                Section("Versions (\(app.versions.count))") {
                    ForEach(app.versions.prefix(25)) { v in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(v.version).font(.headline)
                                Spacer()
                                if let date = v.date { Text(date.prefix(10)).font(.caption).foregroundStyle(.secondary) }
                            }
                            if let notes = v.notes { Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                            if let ipa = v.downloadURL, v != app.latest {
                                Button("Install this version with SideStore") {
                                    open(DeepLink.install(ipa, in: .sidestore), name: "SideStore")
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(LinkOpener(failedTarget: $failedTarget))
    }

    private func open(_ url: URL?, name: String) {
        guard let url else { return }
        openURL(url) { accepted in if !accepted { failedTarget = name } }
    }
}

import SwiftUI

struct DiscoverView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case recommended = "Recommended"
        case github = "Search GitHub"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var discovery: Discovery
    @EnvironmentObject private var router: Router
    @State private var mode: Mode = .recommended
    @State private var query = "altstore source"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if mode == .recommended {
                    recommendedContent
                } else {
                    githubContent
                }
            }
            .navigationTitle("Discover")
            .appDestinations()
            .onReceive(router.$pendingGitHubQuery) { pending in
                guard let pending else { return }
                mode = .github
                query = pending
                discovery.search(pending)
                router.pendingGitHubQuery = nil
            }
            .onChange(of: discovery.sort) { _ in
                if !discovery.results.isEmpty || discovery.isSearching {
                    discovery.search(query)
                }
            }
        }
    }

    // MARK: Recommended

    @ViewBuilder private var recommendedContent: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Recommendations.featured) { rec in
                        NavigationLink(value: rec) { SourceCard(rec: rec) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Featured")
        }

        ForEach(RecommendedSource.Category.allCases) { category in
            let items = Recommendations.all.filter { $0.category == category }
            if !items.isEmpty {
                Section {
                    ForEach(items) { rec in
                        NavigationLink(value: rec) { RecommendedRow(rec: rec) }
                    }
                } header: {
                    Text(category.title)
                } footer: {
                    if let note = category.footnote {
                        Text(note)
                    }
                }
            }
        }
    }

    // MARK: GitHub

    @ViewBuilder private var githubContent: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search GitHub for sources", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { discovery.search(query) }
                if discovery.isSearching {
                    Button("Stop") { discovery.cancel() }
                        .buttonStyle(.borderless)
                } else {
                    Button("Search") { discovery.search(query) }
                        .buttonStyle(.borderless)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Picker("Sort Results By", selection: $discovery.sort) {
                ForEach(Discovery.Sort.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Discovery.presets, id: \.self) { preset in
                        Chip(title: preset, isSelected: query == preset) {
                            query = preset
                            discovery.search(preset)
                        }
                    }
                }
            }
        } footer: {
            Text("Searches public GitHub repositories and checks each one for a working source file. Anyone can publish a source, so only install apps from sources you trust.")
        }

        if let status = discovery.status {
            Section {
                HStack(spacing: 10) {
                    if discovery.isSearching { ProgressView() }
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }

        if !discovery.results.isEmpty {
            Section {
                ForEach(discovery.results) { found in
                    NavigationLink(value: found.source) { FoundSourceRow(found: found) }
                }
                if discovery.canLoadMore && !discovery.isSearching {
                    Button("Search More Repositories") { discovery.loadMore() }
                }
            } header: {
                Text("Found on GitHub")
            }
        }
    }
}

private struct FoundSourceRow: View {
    let found: Discovery.Found
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter

    var body: some View {
        HStack(spacing: 12) {
            IconView(url: found.source.displayIconURL, size: 44, tint: HexColor.color(found.source.displayTintHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(found.source.name).font(.headline).lineLimit(1)
                Text("\(found.source.apps.count) apps · \(found.repo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let stars = found.stars {
                    Label("\(stars)", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if store.contains(found.source.url) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Added")
            } else {
                Button {
                    store.add(loaded: found.source)
                    Haptics.success()
                    toast.show("Added \(found.source.name)")
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(found.source.name)")
            }
        }
    }
}

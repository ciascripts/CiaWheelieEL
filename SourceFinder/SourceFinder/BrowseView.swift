import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var recents: RecentSearches

    @State private var query = ""
    @State private var sort: SearchSort = .relevance
    @State private var category: String? = nil
    @State private var sourceFilter: String? = nil
    @State private var results = SearchResults.empty
    @State private var isWorking = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasFilters: Bool { category != nil || sourceFilter != nil }
    private var isSearching: Bool { !trimmedQuery.isEmpty || hasFilters }

    private var searchKey: SearchKey {
        SearchKey(
            query: SearchQuery(text: trimmedQuery, category: category, sourceURL: sourceFilter, sort: sort),
            version: store.dataVersion
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    SearchResultsList(
                        query: trimmedQuery,
                        results: results,
                        isWorking: isWorking,
                        category: $category,
                        sourceFilter: $sourceFilter
                    )
                } else {
                    BrowseHome()
                }
            }
            .navigationTitle("Browse")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Apps, developers, sources")
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(recents.items, id: \.self) { term in
                        Label(term, systemImage: "clock.arrow.circlepath").searchCompletion(term)
                    }
                }
            }
            .onSubmit(of: .search) { recents.add(trimmedQuery) }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { filterMenu }
            }
            .task(id: searchKey) { await runSearch() }
            .appDestinations()
        }
    }

    private func runSearch() async {
        let key = searchKey
        guard isSearching else {
            results = .empty
            isWorking = false
            return
        }
        // Wait for a pause in typing.
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else { return }
        isWorking = true
        let found = await SearchEngine.run(key.query, apps: store.allApps, recommendedApps: store.recommendedApps)
        guard !Task.isCancelled else { return }
        results = found
        isWorking = false
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(SearchSort.allCases) { s in
                    Label(s.title, systemImage: s.systemImage).tag(s)
                }
            }
            Menu {
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(String?.none)
                    ForEach(store.categories) { c in
                        Text("\(CategoryInfo.title(c.id)) (\(c.count))").tag(String?.some(c.id))
                    }
                }
            } label: {
                Label("Category", systemImage: "square.grid.2x2")
            }
            Menu {
                Picker("Source", selection: $sourceFilter) {
                    Text("All Sources").tag(String?.none)
                    ForEach(store.loadedSources) { s in
                        Text(s.name).tag(String?.some(s.url))
                    }
                }
            } label: {
                Label("Source", systemImage: "tray.full")
            }
            if hasFilters {
                Button(role: .destructive) {
                    category = nil
                    sourceFilter = nil
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
    }
}

struct SearchKey: Equatable {
    let query: SearchQuery
    let version: Int
}

// MARK: - Results

struct SearchResultsList: View {
    let query: String
    let results: SearchResults
    let isWorking: Bool
    @Binding var category: String?
    @Binding var sourceFilter: String?

    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var recents: RecentSearches

    var body: some View {
        let words = TextNormalizer.words(query)
        let mySources = matchingMySources(words)
        let recSources = matchingRecommended(words)
        let nothingFound = results.hits.isEmpty && results.recommendedHits.isEmpty
            && mySources.isEmpty && recSources.isEmpty
        List {
            if category != nil || sourceFilter != nil {
                Section { filterChips }
            }

            if !mySources.isEmpty || !recSources.isEmpty {
                Section {
                    ForEach(mySources) { s in
                        NavigationLink(value: s) {
                            SourceListRow(name: s.name, detail: "\(s.apps.count) apps · In your sources",
                                          iconURL: s.displayIconURL, tintHex: s.displayTintHex)
                        }
                    }
                    ForEach(recSources) { rec in
                        NavigationLink(value: rec) { RecommendedRow(rec: rec) }
                    }
                } header: {
                    Text("Sources")
                }
            }

            if !results.hits.isEmpty {
                Section {
                    ForEach(results.hits) { hit in
                        NavigationLink(value: hit.app) {
                            AppRow(app: hit.app, highlight: words, alsoIn: hit.alsoIn)
                        }
                        .simultaneousGesture(TapGesture().onEnded { recents.add(query) })
                    }
                } header: {
                    Text("\(results.hits.count) App\(results.hits.count == 1 ? "" : "s")")
                }
            }

            if !results.recommendedHits.isEmpty {
                Section {
                    ForEach(results.recommendedHits) { hit in
                        NavigationLink(value: hit.app) {
                            AppRow(app: hit.app, highlight: words, alsoIn: hit.alsoIn)
                        }
                        .simultaneousGesture(TapGesture().onEnded { recents.add(query) })
                    }
                } header: {
                    Text("In Recommended Sources")
                } footer: {
                    Text("These sources aren't in your list yet. Open an app to install it or save its source.")
                }
            }

            if nothingFound {
                Section { emptyState }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .overlay(alignment: .top) {
            if isWorking && !nothingFound {
                ProgressView().padding(.top, 6)
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let c = category {
                    Chip(title: CategoryInfo.title(c), systemImage: "xmark", isSelected: true) { category = nil }
                }
                if let s = sourceFilter {
                    Chip(title: store.loadedSource(s)?.name ?? "Source", systemImage: "xmark", isSelected: true) {
                        sourceFilter = nil
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if isWorking || (store.isLoadingPreviews && !query.isEmpty) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 14) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: query.isEmpty ? "No apps here" : "No results for “\(query)”",
                    message: query.isEmpty
                        ? "Try another category or source."
                        : "Check the spelling, or search GitHub for a source that has it."
                )
                if !query.isEmpty {
                    Button {
                        router.pendingGitHubQuery = "\(query) altstore"
                        router.tab = .discover
                    } label: {
                        Label("Search GitHub for Sources", systemImage: "globe")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
    }

    private func matchingMySources(_ words: [String]) -> [AltSource] {
        guard !words.isEmpty else { return [] }
        let matches = store.loadedSources.filter { s in
            let hay = TextNormalizer.fold(s.name + " " + (s.subtitle ?? ""))
            return words.allSatisfy { hay.contains($0) }
        }
        return Array(matches.prefix(3))
    }

    private func matchingRecommended(_ words: [String]) -> [RecommendedSource] {
        guard !words.isEmpty else { return [] }
        let matches = Recommendations.all.filter { rec in
            !store.contains(rec.url) && words.allSatisfy { rec.searchText.contains($0) }
        }
        return Array(matches.prefix(3))
    }
}

// MARK: - Home

struct BrowseHome: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.sourceURLs.isEmpty {
                    noSources
                } else if store.allApps.isEmpty && store.isRefreshing {
                    loadingCard
                }
                featured
                recentlyUpdated
                categoriesGrid
                if !store.groups.isEmpty { browseAll }
            }
            .padding(.vertical, 12)
        }
        .refreshable { await store.refreshAll() }
    }

    private var noSources: some View {
        VStack(spacing: 14) {
            EmptyStateView(systemImage: "tray", title: "No sources yet",
                           message: "Add a recommended source below, or find more on the Discover tab.")
            Button("Open Discover") { router.tab = .discover }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading sources… \(store.loadedCount) of \(store.sourceURLs.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var featured: some View {
        let items = Recommendations.featured.filter { !store.contains($0.url) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recommended Sources", subtitle: "Hand-picked sources you haven't added yet") {
                    Button("See All") { router.tab = .discover }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { rec in
                            NavigationLink(value: rec) { SourceCard(rec: rec) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder private var recentlyUpdated: some View {
        let apps = Array(store.recentGroups.prefix(6))
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Recently Updated") {
                    NavigationLink("See All", value: AppListRoute.recent)
                }
                VStack(spacing: 0) {
                    ForEach(apps) { hit in
                        NavigationLink(value: hit.app) {
                            AppRow(app: hit.app, alsoIn: hit.alsoIn, showDate: true)
                                .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        if hit.id != apps.last?.id {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var categoriesGrid: some View {
        if !store.categories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Categories")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(store.categories) { c in
                        NavigationLink(value: AppListRoute.category(c.id)) {
                            CategoryTile(id: c.id, count: c.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var browseAll: some View {
        NavigationLink(value: AppListRoute.all) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse All Apps").font(.headline)
                    Text("\(store.groups.count) apps from \(store.loadedSources.count) sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - App lists

enum AppListRoute: Hashable {
    case all
    case recent
    case category(String)
}

struct AppListView: View {
    let route: AppListRoute
    @EnvironmentObject private var store: SourceStore
    @State private var sort: SearchSort
    @State private var filter = ""

    init(route: AppListRoute) {
        self.route = route
        _sort = State(initialValue: route == .recent ? .recent : .name)
    }

    private var title: String {
        switch route {
        case .all: return "All Apps"
        case .recent: return "Recently Updated"
        case .category(let id): return CategoryInfo.title(id)
        }
    }

    private var items: [SearchHit] {
        var list = store.groups
        if case .category(let id) = route {
            list = list.filter { $0.app.search.category == id }
        }
        let words = TextNormalizer.words(filter)
        if !words.isEmpty {
            list = list.filter { hit in
                words.allSatisfy { w in hit.app.search.name.contains(w) || hit.app.search.developer.contains(w) }
            }
        }
        if sort == .recent {
            list.sort { ($0.app.latestDate ?? .distantPast) > ($1.app.latestDate ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        let list = items
        let words = TextNormalizer.words(filter)
        List(list) { hit in
            NavigationLink(value: hit.app) {
                AppRow(app: hit.app, highlight: words, alsoIn: hit.alsoIn, showDate: sort == .recent)
            }
        }
        .listStyle(.plain)
        .overlay {
            if list.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack.3d.up.slash",
                    title: "No apps",
                    message: filter.isEmpty ? "Add sources to see apps here." : "Nothing matches “\(filter)”."
                )
            }
        }
        .searchable(text: $filter, prompt: "Filter")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Label("Name", systemImage: "textformat").tag(SearchSort.name)
                        Label("Recently Updated", systemImage: "clock").tag(SearchSort.recent)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort")
            }
        }
    }
}

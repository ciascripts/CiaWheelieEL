import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @EnvironmentObject private var recents: RecentSearches
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.preferredStoreKey) private var preferred: DeepLink.Store = .sidestore
    @State private var clearedCopies = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Install With", selection: $preferred) {
                        ForEach(DeepLink.Store.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                } header: {
                    Text("Installing")
                } footer: {
                    Text("GET and Install buttons open this app. The other one is still in each app's ⋯ menu.")
                }

                Section {
                    Button("Clear Recent Searches") { recents.clear() }
                        .disabled(recents.items.isEmpty)
                } header: {
                    Text("Search")
                }

                Section {
                    Button(clearedCopies ? "Saved Copies Cleared" : "Clear Saved Source Copies") {
                        SourceCache.clear()
                        clearedCopies = true
                    }
                    .disabled(clearedCopies)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Source Finder keeps a copy of each source so it opens instantly and works offline.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Sources", value: "\(store.sourceURLs.count)")
                    LabeledContent("Apps", value: "\(store.groups.count)")
                    Link(destination: URL(string: "https://sidestore.io")!) {
                        Label("SideStore Website", systemImage: "safari")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI
import UIKit

struct AppDetailView: View {
    let app: AltApp
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.preferredStoreKey) private var preferred: DeepLink.Store = .sidestore
    @State private var notesExpanded = false
    @State private var aboutExpanded = false
    @State private var showAllVersions = false

    private var tint: Color { HexColor.color(app.tintHex) ?? .accentColor }

    /// The app's own color, unless it's too pale for white text.
    private var buttonTint: Color {
        guard let hex = app.tintHex, HexColor.color(hex) != nil, !HexColor.isLight(hex) else { return .accentColor }
        return tint
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                statsStrip
                if let latest = app.latest, let notes = latest.notes, !notes.isEmpty {
                    whatsNew(latest, notes: notes)
                }
                if !app.screenshotURLs.isEmpty { screenshots }
                if let text = app.description, !text.isEmpty { about(text) }
                alternates
                sourceCard
                if app.versions.count > 1 { versionHistory }
                infoSection
            }
            .padding(.vertical, 16)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            IconView(url: app.iconURL, size: 112, tint: tint)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                if app.isBeta { BetaBadge() }
                Text(app.developerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let subtitle = app.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    installButton
                    moreMenu
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var installButton: some View {
        if let ipa = app.downloadURL {
            Button {
                Installer.install(ipa, with: preferred, openURL: openURL, toast: toast)
            } label: {
                Text("Install")
                    .font(.headline)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(buttonTint)
            .accessibilityLabel("Install with \(preferred.title)")
        } else {
            Text("No download link")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var moreMenu: some View {
        Menu {
            if let ipa = app.downloadURL {
                ForEach(DeepLink.Store.allCases.filter { $0 != preferred }) { other in
                    Button {
                        Installer.install(ipa, with: other, openURL: openURL, toast: toast)
                    } label: {
                        Label("Install with \(other.title)", systemImage: "arrow.down.app")
                    }
                }
                Button {
                    openURL(ipa)
                } label: {
                    Label("Download IPA", systemImage: "arrow.down.circle")
                }
                Button {
                    UIPasteboard.general.string = ipa.absoluteString
                    toast.show("IPA link copied", systemImage: "doc.on.doc.fill")
                } label: {
                    Label("Copy IPA Link", systemImage: "doc.on.doc")
                }
                ShareLink(item: ipa) {
                    Label("Share IPA Link", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                UIPasteboard.general.string = app.bundleIdentifier
                toast.show("Bundle ID copied", systemImage: "doc.on.doc.fill")
            } label: {
                Label("Copy Bundle ID", systemImage: "number")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: Stats

    private var stats: [(title: String, value: String)] {
        var out: [(title: String, value: String)] = []
        if let v = app.latest?.version { out.append((title: "VERSION", value: String(v.prefix(14)))) }
        if let size = formatBytes(app.latest?.size) { out.append((title: "SIZE", value: size)) }
        if let d = app.latestDate { out.append((title: "UPDATED", value: d.formatted(.relative(presentation: .named)))) }
        if let min = app.latest?.minOSVersion { out.append((title: "REQUIRES", value: "iOS \(min)+")) }
        if let c = app.category { out.append((title: "CATEGORY", value: CategoryInfo.title(TextNormalizer.fold(c)))) }
        out.append((title: "SOURCE", value: app.sourceName))
        return out
    }

    private var statsStrip: some View {
        let items = stats
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    if index > 0 {
                        Divider().frame(height: 34)
                    }
                    VStack(spacing: 4) {
                        Text(items[index].title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(items[index].value)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(minWidth: 84)
                    .padding(.horizontal, 10)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Sections

    private func whatsNew(_ latest: AltVersion, notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("What's New").font(.title3.weight(.bold))
                Spacer()
                if let d = latest.parsedDate {
                    Text(d.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Version \(latest.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.callout)
                .lineLimit(notesExpanded ? nil : 4)
            if notes.count > 180 {
                Button(notesExpanded ? "Show Less" : "Show More") {
                    withAnimation(.easeInOut) { notesExpanded.toggle() }
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal)
    }

    private var screenshots: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.screenshotURLs, id: \.self) { url in
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                screenshotPlaceholder(failed: phase.error != nil)
                            }
                        }
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func screenshotPlaceholder(failed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .frame(width: 185)
            .overlay {
                if failed {
                    Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
    }

    private func about(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About").font(.title3.weight(.bold))
            Text(text)
                .font(.callout)
                .lineLimit(aboutExpanded ? nil : 5)
            if text.count > 240 {
                Button(aboutExpanded ? "Show Less" : "Show More") {
                    withAnimation(.easeInOut) { aboutExpanded.toggle() }
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var alternates: some View {
        let others = store.alternates(for: app)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Also Available From").font(.title3.weight(.bold))
                VStack(spacing: 0) {
                    ForEach(others) { other in
                        NavigationLink(value: other) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(other.sourceName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(store.contains(other.sourceURL) ? "In your sources" : "Recommended source")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let v = other.latest?.version {
                                    Text("v" + String(v.prefix(12)))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if other.id != others.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal)
        }
    }

    private var sourceCard: some View {
        let saved = store.contains(app.sourceURL)
        let source = store.loadedSource(app.sourceURL)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Source").font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconView(url: source?.displayIconURL, size: 44, tint: HexColor.color(source?.displayTintHex))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.sourceName).font(.headline).lineLimit(1)
                        Text(saved ? "In your sources" : "Not in your sources yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let source {
                        NavigationLink(value: source) {
                            Text("View").font(.subheadline.weight(.semibold))
                        }
                    }
                }
                HStack(spacing: 10) {
                    if !saved, let source {
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
                        Installer.addSource(app.sourceURL, to: preferred, openURL: openURL, toast: toast)
                    } label: {
                        Label("Add to \(preferred.title)", systemImage: "plus.app").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
    }

    private var versionHistory: some View {
        let shown = showAllVersions ? app.versions : Array(app.versions.prefix(3))
        let toggleTitle = showAllVersions ? "Show Less" : "See All (\(app.versions.count))"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Version History").font(.title3.weight(.bold))
                Spacer()
                if app.versions.count > 3 {
                    Button(toggleTitle) {
                        withAnimation(.easeInOut) { showAllVersions.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            VStack(spacing: 0) {
                ForEach(shown) { v in
                    VersionRow(version: v, isLatest: v == app.latest) { ipa in
                        Installer.install(ipa, with: preferred, openURL: openURL, toast: toast)
                    }
                    if v.id != shown.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Information").font(.title3.weight(.bold))
            VStack(spacing: 0) {
                infoRow("Developer", app.developerName)
                Divider()
                infoRow("Bundle ID", app.bundleIdentifier)
                if let size = formatBytes(app.latest?.size) {
                    Divider()
                    infoRow("Size", size)
                }
                if let c = app.category {
                    Divider()
                    infoRow("Category", CategoryInfo.title(TextNormalizer.fold(c)))
                }
                if let min = app.latest?.minOSVersion {
                    Divider()
                    infoRow("Compatibility", "iOS \(min) or later")
                }
                Divider()
                infoRow("Source", app.sourceName)
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }
}

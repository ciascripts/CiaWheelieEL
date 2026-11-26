import SwiftUI
import UIKit

// MARK: - Colors

enum HexColor {
    static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s.prefix(6), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    static func color(_ hex: String?) -> Color? {
        guard let c = rgb(hex) else { return nil }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// True for pale colors, where white text would be hard to read.
    static func isLight(_ hex: String?) -> Bool {
        guard let c = rgb(hex) else { return false }
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.7
    }
}

enum CategoryInfo {
    static func title(_ id: String) -> String {
        switch id {
        case "photo-video": return "Photo & Video"
        case "developer": return "Developer Tools"
        default: return id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "games": return "gamecontroller.fill"
        case "entertainment": return "tv.fill"
        case "utilities": return "wrench.and.screwdriver.fill"
        case "developer": return "hammer.fill"
        case "photo-video": return "camera.fill"
        case "social": return "bubble.left.and.bubble.right.fill"
        case "lifestyle": return "heart.fill"
        case "music": return "music.note"
        default: return "square.grid.2x2.fill"
        }
    }

    static func color(_ id: String) -> Color {
        switch id {
        case "games": return .purple
        case "entertainment": return .pink
        case "utilities": return .blue
        case "developer": return .gray
        case "photo-video": return .orange
        case "social": return .green
        case "lifestyle": return .red
        case "music": return .indigo
        default: return .teal
        }
    }
}

func formatBytes(_ n: Int?) -> String? {
    guard let n, n > 0 else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

enum Haptics {
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// The first place any search word appears, tinted.
func highlightedText(_ text: String, words: [String]) -> Text {
    var best: Range<String.Index>?
    for w in words where !w.isEmpty {
        guard let r = text.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
        if let current = best, current.lowerBound <= r.lowerBound { continue }
        best = r
    }
    guard let r = best else { return Text(text) }
    return Text(text[..<r.lowerBound])
        + Text(text[r]).foregroundColor(.accentColor)
        + Text(text[r.upperBound...])
}

// MARK: - Icons and rows

struct IconView: View {
    let url: URL?
    var size: CGFloat = 56
    var tint: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        let color = tint ?? Color.accentColor
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    color.opacity(0.16)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: size * 0.36))
                        .foregroundStyle(color.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}

/// App Store style "GET" button that opens the preferred installer.
struct GetButton: View {
    let app: AltApp
    @AppStorage(Prefs.preferredStoreKey) private var preferred: DeepLink.Store = .sidestore
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var toast: ToastCenter

    var body: some View {
        if let ipa = app.downloadURL {
            Button {
                Installer.install(ipa, with: preferred, openURL: openURL, toast: toast)
            } label: {
                Text("GET")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Install \(app.name) with \(preferred.title)")
        }
    }
}

struct AppRow: View {
    let app: AltApp
    var highlight: [String] = []
    var alsoIn: Int = 0
    var showSource = true
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            IconView(url: app.iconURL, size: 56, tint: HexColor.color(app.tintHex))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    highlightedText(app.name, words: highlight)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if app.isBeta { BetaBadge() }
                }
                Text(app.subtitle ?? app.developerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            GetButton(app: app)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var metaLine: String {
        var parts: [String] = []
        if showDate, let d = app.latestDate { parts.append(d.formatted(.relative(presentation: .named))) }
        if let v = app.latest?.version { parts.append("v" + String(v.prefix(14))) }
        if let size = formatBytes(app.latest?.size) { parts.append(size) }
        if showSource { parts.append(app.sourceName) }
        if alsoIn > 0 { parts.append("+\(alsoIn) source\(alsoIn == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

struct SourceListRow: View {
    let name: String
    let detail: String
    let iconURL: URL?
    let tintHex: String?

    var body: some View {
        HStack(spacing: 12) {
            IconView(url: iconURL, size: 44, tint: HexColor.color(tintHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A recommended source as a row with an add button.
struct RecommendedRow: View {
    let rec: RecommendedSource
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @State private var adding = false

    var body: some View {
        let preview = store.loadedSource(rec.url)
        HStack(spacing: 12) {
            IconView(url: preview?.displayIconURL, size: 46, tint: HexColor.color(preview?.displayTintHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.name).font(.headline).lineLimit(1)
                Text(rec.blurb).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let preview {
                    Text("\(preview.apps.count) app\(preview.apps.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            if store.contains(rec.url) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Added")
            } else if adding {
                ProgressView()
            } else {
                Button {
                    adding = true
                    Task {
                        let ok = await store.addRecommended(rec)
                        adding = false
                        if ok {
                            Haptics.success()
                            toast.show("Added \(rec.name)")
                        } else {
                            toast.show("Couldn't load \(rec.name)", systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(rec.name)")
            }
        }
        .padding(.vertical, 4)
        .task { await store.loadPreview(rec.url) }
    }
}

/// A recommended source as a card for horizontal carousels.
struct SourceCard: View {
    let rec: RecommendedSource
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var toast: ToastCenter
    @State private var adding = false

    var body: some View {
        let preview = store.loadedSource(rec.url)
        let tint = HexColor.color(preview?.displayTintHex) ?? Color.accentColor
        let added = store.contains(rec.url)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconView(url: preview?.displayIconURL, size: 46, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.name).font(.headline).lineLimit(1)
                    Text(preview.map { "\($0.apps.count) app\($0.apps.count == 1 ? "" : "s")" } ?? rec.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(rec.blurb)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Button {
                adding = true
                Task {
                    let ok = await store.addRecommended(rec)
                    adding = false
                    if ok {
                        Haptics.success()
                        toast.show("Added \(rec.name)")
                    } else {
                        toast.show("Couldn't load \(rec.name)", systemImage: "exclamationmark.triangle.fill")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if adding { ProgressView().controlSize(.small) }
                    Label(added ? "Added" : "Add Source", systemImage: added ? "checkmark" : "plus")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(added || adding)
        }
        .padding(14)
        .frame(width: 260)
        .background(
            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
        .task { await store.loadPreview(rec.url) }
    }
}

struct CategoryTile: View {
    let id: String
    let count: Int

    var body: some View {
        let color = CategoryInfo.color(id)
        HStack(spacing: 10) {
            Image(systemName: CategoryInfo.symbol(id))
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(CategoryInfo.title(id)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(count) app\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VersionRow: View {
    let version: AltVersion
    let isLatest: Bool
    let install: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(version.version).font(.subheadline.weight(.semibold)).lineLimit(1)
                if isLatest {
                    Text("LATEST")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Spacer()
                if let d = version.parsedDate {
                    Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notes = version.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack {
                if let size = formatBytes(version.size) {
                    Text(size).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let ipa = version.downloadURL, !isLatest {
                    Button("Install") { install(ipa) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Small pieces

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.orange)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Beta")
    }
}

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

// MARK: - Toasts

@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let systemImage: String
    }

    @Published private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            current = Toast(message: message, systemImage: systemImage)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.current = nil }
        }
    }
}

struct ToastOverlay: View {
    @EnvironmentObject private var toast: ToastCenter

    var body: some View {
        VStack {
            if let t = toast.current {
                Label(t.message, systemImage: t.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(t.id)
            }
            Spacer()
        }
        .padding(.top, 6)
        .allowsHitTesting(false)
    }
}

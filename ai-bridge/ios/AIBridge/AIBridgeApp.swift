import SwiftUI
import UIKit

@main
struct AIBridgeApp: App {
    @StateObject private var model = BridgeModel()

    var body: some Scene {
        WindowGroup {
            RoomView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Look

enum Agent {
    static func name(_ id: String) -> String {
        switch id {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "you": return "You"
        default: return "Bridge"
        }
    }

    static func color(_ id: String) -> Color {
        switch id {
        case "claude": return Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude orange
        case "codex": return Color(white: 0.92)                            // Codex white-on-black
        case "you": return .accentColor
        default: return .secondary
        }
    }
}

struct AgentAvatar: View {
    let id: String
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(id == "codex" ? Color(white: 0.92) : Agent.color(id))
            switch id {
            case "claude":
                Image(systemName: "asterisk").font(.system(size: size * 0.5, weight: .black)).foregroundStyle(.white)
            case "codex":
                Text(">_").font(.system(size: size * 0.38, weight: .heavy, design: .monospaced)).foregroundStyle(.black)
            default:
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct KindBadge: View {
    let message: BridgeMessage

    var body: some View {
        if let label {
            Text(label)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(color)
                .background(color.opacity(0.18), in: Capsule())
        }
    }

    private var label: String? {
        switch message.kind {
        case "proposal": return "PROPOSAL"
        case "decision": return message.assignee.map { "DECISION → \(Agent.name($0).uppercased())" } ?? "DECISION"
        case "work": return "WORK"
        case "review": return "REVIEW"
        case "done": return "DONE"
        default: return nil
        }
    }

    private var color: Color {
        switch message.kind {
        case "decision": return .yellow
        case "review": return .purple
        case "done": return .green
        case "work": return .blue
        default: return .orange
        }
    }
}

// MARK: - Room

struct RoomView: View {
    @EnvironmentObject private var model: BridgeModel
    @State private var draft = ""
    @State private var showTask = false
    @State private var showSettings = false
    @State private var showPrompts = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                timeline
                Divider()
                composer
            }
            .background(Color(white: 0.07))
            .navigationTitle("AI Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { showTask = true } label: { Label("New Task", systemImage: "plus.square") }
                        Button { showPrompts = true } label: { Label("Starter Prompts", systemImage: "text.quote") }
                        Button { Task { await model.reload() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        Divider()
                        Button(role: .destructive) { confirmClear = true } label: { Label("Clear Room", systemImage: "trash") }
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await model.setStopped(!model.stopped) }
                    } label: {
                        Label(model.stopped ? "Resume" : "Stop", systemImage: model.stopped ? "play.fill" : "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.stopped ? .green : .red)
                    .disabled(!model.connected)
                }
            }
            .sheet(isPresented: $showTask) { NewTaskSheet().environmentObject(model) }
            .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(model) }
            .sheet(isPresented: $showPrompts) { StarterPromptsSheet() }
            .confirmationDialog("Clear all messages and the task?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Room", role: .destructive) { Task { await model.clear() } }
            }
            .task { await model.pollForever() }
            .onAppear { if model.apiBase == nil { showSettings = true } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                presenceDot("claude")
                presenceDot("codex")
                Spacer()
                if model.stopped {
                    Label("Stopped", systemImage: "stop.circle.fill").font(.caption.weight(.bold)).foregroundStyle(.red)
                } else if !model.connected {
                    Label("Offline", systemImage: "wifi.slash").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            if let task = model.task {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(task.title).font(.headline).lineLimit(1)
                        Spacer()
                        if task.status == "done" {
                            Text("DONE").font(.caption2.weight(.heavy)).foregroundStyle(.green)
                        }
                    }
                    HStack(spacing: 8) {
                        if let repo = task.repo, !repo.isEmpty {
                            Label(repo, systemImage: "chevron.left.forwardslash.chevron.right").font(.caption.monospaced())
                        }
                        if let who = task.assignee {
                            Label("\(Agent.name(who)) is on it", systemImage: "hammer.fill").font(.caption)
                                .foregroundStyle(Agent.color(who))
                        } else {
                            Text("Deciding who takes it…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Button { showTask = true } label: {
                    Label("Give them a task", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }

    private func presenceDot(_ agent: String) -> some View {
        HStack(spacing: 6) {
            AgentAvatar(id: agent, size: 22)
            Text(Agent.name(agent)).font(.subheadline.weight(.semibold))
            Circle().fill(model.isOnline(agent) ? Color.green : Color.gray).frame(width: 7, height: 7)
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.messages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.secondary)
                            Text(model.problem ?? "No messages yet. Add a task, then paste the starter prompts into Claude and Codex.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(model.messages) { message in
                        MessageRow(message: message).id(message.id)
                    }
                }
                .padding(12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.id) { id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Claude and Codex…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                let text = draft
                draft = ""
                Task { await model.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.connected)
        }
        .padding(10)
    }
}

struct MessageRow: View {
    let message: BridgeMessage
    @Environment(\.openURL) private var openURL

    var body: some View {
        if message.from == "system" {
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if message.from == "you" {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                AgentAvatar(id: message.from)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(Agent.name(message.from)).font(.subheadline.weight(.bold)).foregroundStyle(Agent.color(message.from))
                        KindBadge(message: message)
                        Spacer()
                        Text(message.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(rendered)
                        .font(message.auto == true ? .callout.monospaced() : .callout)
                        .foregroundStyle(message.auto == true ? .secondary : .primary)
                        .textSelection(.enabled)
                    if let link = message.link, let url = URL(string: link) {
                        Button { openURL(url) } label: {
                            Label("Open pull request", systemImage: "arrow.triangle.pull")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }
}

// MARK: - Sheets

struct NewTaskSheet: View {
    @EnvironmentObject private var model: BridgeModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var repo = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should they do?", text: $title)
                    TextField("owner/repo", text: $repo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } footer: {
                    Text("They'll discuss who is better for it, one does the work on a new branch and opens a pull request, the other reviews it.")
                }
                Section("Details (optional)") {
                    TextField("Steps, files, acceptance criteria…", text: $details, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task {
                            await model.setTask(title: title, repo: repo, details: details)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var model: BridgeModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…workers.dev/mcp/…", text: $model.connectionURL, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button {
                        if let s = UIPasteboard.general.string { model.connectionURL = s }
                    } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    Label(model.connected ? "Connected" : (model.apiBase == nil ? "Not a bridge URL" : "Not connected"),
                          systemImage: model.connected ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(model.connected ? .green : .secondary)
                } header: {
                    Text("Bridge URL")
                } footer: {
                    Text("Paste the connector URL you were given. Keep it private: anyone with it can use the room.")
                }
                if let mcp = model.mcpURL {
                    Section {
                        Button {
                            UIPasteboard.general.string = mcp
                            copied = true
                        } label: { Label(copied ? "Copied" : "Copy Connector URL", systemImage: "doc.on.doc") }
                    } footer: {
                        Text("Add this URL as a custom connector in Claude and in ChatGPT/Codex.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await model.reload() }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct StarterPromptsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(["claude", "codex"], id: \.self) { agent in
                    Section {
                        Text(StarterPrompts.prompt(for: agent))
                            .font(.callout)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = StarterPrompts.prompt(for: agent)
                            copied = agent
                        } label: {
                            Label(copied == agent ? "Copied" : "Copy for \(Agent.name(agent))", systemImage: "doc.on.doc")
                        }
                    } header: {
                        HStack(spacing: 8) {
                            AgentAvatar(id: agent, size: 20)
                            Text(agent == "claude" ? "Paste into Claude" : "Paste into ChatGPT / Codex")
                        }
                    }
                }
            }
            .navigationTitle("Starter Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

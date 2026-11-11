import SwiftUI
import ConsoleCore

/// S-007: the Copilot screen. Chat talks to JARVIS's existing CopilotKit
/// runtime on loopback (AG-UI runs on its /api/copilotkit agent route); the
/// console runs no runtime of its own and never starts JARVIS. Runtime
/// status keeps the M2 live view.
struct CopilotPanelView: View {
    @State private var tab = "Chat"
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Chat").tag("Chat")
                Text("Runtime status").tag("Status")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(10)
            Divider()
            if tab == "Chat" { CopilotChatView() } else { JarvisLiveView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Copilot")
    }
}

/// App-level chat run store (lifted from a CopilotChatView-owned model
/// per the dashboard spec, Panel 2): the dashboard's voice presence orb
/// reads the same run state the chat screen drives. Injected in the
/// environment at the app root; chat behavior is unchanged.
@MainActor @Observable
final class ChatRunStore {
    var connection: CopilotHealth.Result?
    var acc = CopilotRunAccumulator()
    var input = ""
    var checking = false
    let threadId = UUID().uuidString
    var port: Int { JarvisEndpoint.fromDefaults().runtimePort }

    func connect() async {
        checking = true
        connection = await CopilotHealth.check()
        checking = false
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !acc.isRunning else { return }
        input = ""
        acc.appendUser(CopilotMessage(id: UUID().uuidString, role: .user, content: text))
        acc.fold(.runStarted(threadId: threadId))
        do {
            for try await ev in CopilotClient.run(threadId: threadId, messages: acc.messages, credential: CopilotClient.currentCredential()) {
                acc.fold(ev)
            }
            acc.streamEnded()
        } catch CopilotClient.Failure.missingCredential {
            connection = .offline("A console session token is required before a run can leave this app.")
            acc.fold(.runError("missing credential"))
        } catch {
            // A transport failure means JARVIS is unreachable: show the offline card.
            connection = .offline(error.localizedDescription)
            acc.fold(.runError(error.localizedDescription))
        }
    }
}

struct CopilotChatView: View {
    @Environment(ChatRunStore.self) private var model
    var body: some View {
        Group {
            switch model.connection {
            case .none:
                ProgressView("Checking JARVIS runtime on 127.0.0.1:\(String(model.port))…")
            case .offline(let why):
                VStack(spacing: 16) {
                    ContentUnavailableView("Copilot offline", systemImage: "bolt.horizontal.circle",
                        description: Text("JARVIS runtime at 127.0.0.1:\(String(model.port)) is not answering (\(why)). The rest of the console still works. This panel never starts JARVIS."))
                    Button("Retry") { Task { await model.connect() } }.disabled(model.checking)
                }.padding()
            case .online:
                chat
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if model.connection == nil { await model.connect() } }
    }

    private var chat: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            Text("Copilot · JARVIS runtime 127.0.0.1:\(String(model.port)) · local models first · actions that send, spend, or delete are held by the JEV approval gate")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.acc.messages.isEmpty {
                            Text("Ask about the mesh: status, modules, what is live. Answers come from JARVIS's runtime, not from this app.")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(model.acc.messages) { m in bubble(m).id(m.id) }
                        if model.acc.isRunning {
                            Label("JARVIS is working…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.acc.toolActivity.isEmpty {
                            Text("Tools used in JARVIS: " + model.acc.toolActivity.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = model.acc.error {
                            Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.acc.messages.map(\.content).joined()) { _, _ in
                    if let last = model.acc.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Message JARVIS…", text: $model.input, axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { Task { await model.send() } }
                Button("Send") { Task { await model.send() } }
                    .disabled(model.acc.isRunning || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
    }

    private func bubble(_ m: CopilotMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 60) }
            Text(m.content.isEmpty ? "…" : m.content)
                .textSelection(.enabled)
                .padding(10)
                .background(m.role == .user ? Color.m3taGold.opacity(0.20) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
            if m.role != .user { Spacer(minLength: 60) }
        }
    }
}

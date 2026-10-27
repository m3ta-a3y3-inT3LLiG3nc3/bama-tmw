import SwiftUI
import ConsoleCore

@MainActor @Observable
final class BotStore {
    var map: BotMap?
    var error: String?
    var sourcePath = "bundled copy"
    init() { refresh() }
    /// Live file (Settings › bot map path) wins; falls back to the bundled copy.
    func refresh() {
        let p = UserDefaults.standard.string(forKey: "botMapPath") ?? ""
        do {
            if !p.isEmpty { map = try BotMapLoader.load(from: URL(fileURLWithPath: (p as NSString).expandingTildeInPath)); sourcePath = p }
            else { map = try BotMapLoader.loadBundled(); sourcePath = "bundled copy" }
            error = nil
        } catch {
            self.error = "Live bot map unreadable (\(error.localizedDescription)); showing bundled copy."
            map = try? BotMapLoader.loadBundled(); sourcePath = "bundled copy"
        }
    }
}

struct BrainBadge: View {
    let wired: Bool?
    var body: some View {
        let (t, i, c): (String, String, Color) = switch wired {
        case .some(true): ("Brain", "brain.fill", .green)
        case .some(false): ("No brain", "brain", .secondary)
        case .none: ("Brain unknown", "questionmark.circle", .orange)
        }
        Label(t, systemImage: i).font(.caption).foregroundStyle(c)
            .accessibilityLabel(wired == true ? "Wired to the brain" : wired == false ? "Not wired to the brain" : "Brain wiring unknown")
    }
}

struct BotsView: View {
    @Environment(BotStore.self) var bots
    @State private var query = ""
    @State private var filter: BotFilter = .all
    var body: some View {
        if let m = bots.map {
            let list = m.filtered(query: query, filter: filter)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Picker("Filter", selection: $filter) { ForEach(BotFilter.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)
                    Spacer()
                    Text("\(list.count) of \(m.bots.count) · \(bots.sourcePath)").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal).padding(.vertical, 8)
                if let e = bots.error { Text(e).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if list.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(list) { b in BotRow(b: b) }.listStyle(.inset)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search bots, Orbit, Grok Bot, flags")
        } else {
            ContentUnavailableView("No bot map", systemImage: "person.3", description: Text(bots.error ?? "Bot map missing."))
        }
    }
}

struct BotRow: View {
    let b: BotMap.Bot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(b.openbot.name).font(.headline)
                Text(b.role).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                BrainBadge(wired: b.brainWired)
                Text("\(b.openbot.provider ?? "?")/\(b.openbot.model ?? "?")").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Label(b.orbit.isEmpty ? "No Orbit record" : b.orbit.map { "\($0.name) (\($0.status ?? "?"))" }.joined(separator: " · "), systemImage: "circle.hexagongrid")
                    .foregroundStyle(b.orbit.isEmpty ? Color.orange : Color.primary)
                Label(b.grokbot?.name ?? "No Grok Bot agent", systemImage: "sparkle")
                    .foregroundStyle(b.grokbot == nil ? Color.orange : Color.primary)
            }.font(.caption).lineLimit(1)
            if !b.flags.isEmpty {
                HStack { ForEach(b.flags, id: \.self) { f in FlagChip(text: f) } }
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}

struct FlagChip: View {
    let text: String
    var body: some View {
        let bad = text.hasPrefix("conflict") || text == "duplicate-name"
        Text(text).font(.caption2.monospaced()).padding(.horizontal, 6).padding(.vertical, 1)
            .background((bad ? Color.red : Color.secondary).opacity(0.15), in: .capsule)
            .foregroundStyle(bad ? Color.red : Color.secondary)
    }
}

struct BrainView: View {
    @State private var status: BrainClient.StatusOutcome?
    @State private var outcome: BrainClient.Outcome?
    @State private var q = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch status {
            case .none: ProgressView("Checking brain on 127.0.0.1:9783…")
            case .offline(let why):
                ContentUnavailableView {
                    Label("Brain offline", systemImage: "brain")
                } description: {
                    Text("rea-mcp at 127.0.0.1:9783 is not answering (\(why)). This screen never starts JARVIS.")
                } actions: { Button("Retry") { Task { await check() } } }
            case .online(let m):
                HStack(spacing: 8) {
                    ForEach(m.keys.sorted(), id: \.self) { k in
                        VStack(alignment: .leading) { Text(k.capitalized).font(.caption.bold()); Text(m[k] ?? "unknown").font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    }
                }
                HStack {
                    TextField("Search the brain (read-only)", text: $q).textFieldStyle(.roundedBorder).onSubmit { Task { await run() } }
                    Button("Search") { Task { await run() } }.disabled(q.isEmpty || busy).keyboardShortcut(.return)
                }
                if busy { ProgressView("Searching…") }
                switch outcome {
                case .none: Text("Read-only search over the MetaOS vault via JARVIS's rea_brains_search. Nothing is written.").font(.caption).foregroundStyle(.secondary)
                case .offline(let why): Text("Search failed: \(why)").foregroundStyle(.orange)
                case .results(let st, let hits):
                    Text("Status: \(st) · \(hits.count) results").font(.caption).foregroundStyle(st == "ok" ? Color.secondary : Color.orange)
                    if hits.isEmpty { ContentUnavailableView("No results", systemImage: "doc.text.magnifyingglass", description: Text(st)) }
                    else { List(hits) { h in VStack(alignment: .leading) { Text(h.path).font(.callout.monospaced()); Text(h.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3) } } }
                }
            }
            Spacer(minLength: 0)
        }.padding().task { await check() }
    }
    func check() async { status = nil; status = await BrainClient.status() }
    func run() async { busy = true; outcome = await BrainClient.search(q); busy = false }
}

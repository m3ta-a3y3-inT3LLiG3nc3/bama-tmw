import SwiftUI
import ConsoleCore

/// M2: live JARVIS health/status (read-only GETs on loopback). Never starts, stops or restarts JARVIS.
struct JarvisLiveView: View {
    @AppStorage("jarvisRuntimePort") private var runtimePort = 9782
    @AppStorage("jarvisReaPort") private var reaPort = 9783
    @AppStorage("jarvisRefreshSeconds") private var refreshSeconds = 10
    @State private var status: JarvisStatus?
    @State private var checking = false
    var endpoint: JarvisEndpoint {
        JarvisEndpoint(runtimePort: JarvisEndpoint.validPort(runtimePort) ? runtimePort : 9782,
                       reaPort: JarvisEndpoint.validPort(reaPort) ? reaPort : 9783)
    }
    var body: some View {
        Group {
            if let s = status, s.fullyOffline {
                VStack(spacing: 16) {
                    ContentUnavailableView("JARVIS offline", systemImage: "bolt.horizontal.circle",
                        description: Text("Nothing answered on 127.0.0.1:\(String(endpoint.runtimePort)) or :\(String(endpoint.reaPort)).\n\(reason(s.runtime))\nThe rest of the console still works. This panel never starts JARVIS."))
                    Button("Retry") { Task { await refresh() } }.disabled(checking)
                    Text("Last checked \(s.checkedAt.formatted(date: .omitted, time: .standard)) · auto-retry every \(refreshSeconds)s").font(.caption).foregroundStyle(.secondary)
                }.padding()
            } else if let s = status {
                live(s)
            } else {
                ProgressView("Checking JARVIS on 127.0.0.1…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("JARVIS live")
        .onReceive(NotificationCenter.default.publisher(for: .consoleRefresh)) { _ in Task { await refresh() } }
        .task(id: "\(runtimePort)-\(reaPort)-\(refreshSeconds)") {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(max(5, refreshSeconds)))
            }
        }
    }
    func reason<T>(_ p: Probe<T>) -> String { if case .offline(let w) = p { w } else { "" } }

    @ViewBuilder func live(_ s: JarvisStatus) -> some View {
        Form {
            Section("agent-runtime · 127.0.0.1:\(String(endpoint.runtimePort))/health") {
                switch s.runtime {
                case .ok(let h):
                    row("Status", h.ok ? "Healthy" : "Unhealthy", h.ok)
                    row("MCP link to rea-mcp", h.mcp == true ? "Up" : "Down", h.mcp == true)
                    row("Copilot runtime", h.copilotRuntime ?? "unknown", h.copilotRuntime == "available")
                    LabeledContent("Copilot mount", value: h.copilot ?? "unknown")
                case .offline(let w): row("Status", "Offline (\(w))", false)
                }
            }
            Section("rea-mcp · 127.0.0.1:\(String(endpoint.reaPort))/health") {
                switch s.rea {
                case .ok(let h):
                    row("Status", h.ok ? "Healthy" : "Unhealthy", h.ok)
                    LabeledContent("Skills", value: h.skills.map(String.init) ?? "unknown")
                    LabeledContent("Extensions", value: h.extensions.map(String.init) ?? "unknown")
                    LabeledContent("Pending approvals", value: h.pending.map(String.init) ?? "unknown")
                case .offline(let w): row("Status", "Offline (\(w))", false)
                }
            }
            Section("Models · /api/models") {
                switch s.models {
                case .ok(let m):
                    LabeledContent("Default", value: "\(m.default.model) (\(m.default.paid ? "paid" : "local"))")
                    LabeledContent("Fallback", value: m.fallback ?? "unknown")
                    LabeledContent("Paid models on", value: String(m.paidEnabledCount))
                    LabeledContent("JEV daily cap", value: "$\(Int(m.jev?.daily_usd_cap ?? 0))")
                case .offline(let w): row("Models", "Unavailable (\(w))", false)
                }
            }
            Section("REA skills · /api/rea/skills") {
                switch s.skills {
                case .ok(let k):
                    LabeledContent("Tools exposed", value: String(k.tools.count))
                    Text(k.tools.prefix(12).map(\.name).joined(separator: ", ") + (k.tools.count > 12 ? " …" : "")).font(.caption).foregroundStyle(.secondary)
                case .offline(let w): row("Skills", "Unavailable (\(w))", false)
                }
            }
            Section {
                HStack {
                    Text("Checked \(s.checkedAt.formatted(date: .omitted, time: .standard)) · auto-refresh every \(refreshSeconds)s · read-only").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh now") { Task { await refresh() } }.disabled(checking)
                }
            }
        }.formStyle(.grouped)
    }
    func row(_ k: String, _ v: String, _ good: Bool) -> some View {
        LabeledContent(k) { Label(v, systemImage: good ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(good ? .green : .red) }
    }
    func refresh() async { checking = true; status = await JarvisClient.status(endpoint); checking = false }
}

import SwiftUI
import ConsoleCore

// Lookout v1 (spec §4 Phase 1 / D15): EXACTLY three panels —
// (1) today's calendar strip, (2) week goals, (3) canonical docs row.
// Everything read-only, everything from real files (or, in demo mode,
// synthetic fixtures with live sources hard-off).

struct LookoutView: View {
    @Environment(FieldBookStore.self) var fb
    var onOpenRecord: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if fb.demo { demoBanner }
                if let refusal = fb.demoRefusal {
                    Label(refusal, systemImage: "hand.raised.fill").foregroundStyle(.red).font(.headline)
                } else {
                    indexStatusBar
                    calendarPanel
                    goalsPanel
                    canonicalPanel
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.tmwBg)
        .navigationTitle("Lookout")
    }

    private var demoBanner: some View {
        Text("DEMO MODE — synthetic data only. All live sources are off.")
            .font(.headline).padding(10).frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.25), in: .rect(cornerRadius: 8))
            .accessibilityLabel("Demo mode banner")
    }

    private var indexStatusBar: some View {
        HStack(spacing: 12) {
            if fb.isIndexing { ProgressView().controlSize(.small) }
            if let log = fb.snapshot?.passLog {
                Text("Vault index: \(log.recordsIndexed) records · \(log.skippedDataless) evicted skipped · \(log.needsAttentionCount) need attention")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Vault index: building…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let r = fb.lastReconciliation {
                Text(r.isClean ? "Reconciliation: clean" : "Reconciliation: \(r.changedOnDisk.count) changed, \(r.missingFromIndex.count) new, \(r.missingOnDisk.count) missing")
                    .font(.caption).foregroundStyle(r.isClean ? .green : .orange)
            }
            Button("Rebuild index") { fb.refresh() }
            Button("Reconcile") { fb.reconcile() }
        }
    }

    // Panel 1 of 3: today's calendar strip (allowlisted EventKit calendars).
    private var calendarPanel: some View {
        panel("Today — Calendar", icon: "calendar") {
            switch fb.calendar.state {
            case .loading: Text("Loading calendar…").foregroundStyle(.secondary)
            case .accessDenied: Text("Calendar access not granted. The Lookout reads only allowlisted calendars; grant access in System Settings to enable this panel.").foregroundStyle(.orange)
            case .noAllowlistedCalendar: Text("No allowlisted calendar found. Default posture is business-only (allowlist: \(fb.config.calendarAllowlist.isEmpty ? fb.config.businessCalendarHint : fb.config.calendarAllowlist.joined(separator: ", "))); personal calendars are never shown unless allowlisted.").foregroundStyle(.orange)
            case .synthetic, .ready:
                if fb.calendar.events.isEmpty {
                    Text("No events today on the allowlisted calendars.").foregroundStyle(.secondary)
                } else {
                    ForEach(fb.calendar.events) { e in
                        HStack {
                            Text(e.isAllDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospaced()).frame(width: 70, alignment: .leading)
                            Text(e.title)
                            Spacer()
                            Text(e.calendarTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // Panel 2 of 3: week goals from planning/week.md (§1.3c).
    private var goalsPanel: some View {
        panel("Week Goals — planning/week.md", icon: "checklist") {
            switch fb.goals {
            case .fileMissing, .sectionMissing:
                Text(fb.goals.displayText).foregroundStyle(.orange).font(.callout.weight(.medium))
            case .parsed(let items):
                if items.isEmpty { Text("Goals section found in `week.md` — no checkboxes in it.").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    HStack {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Text(item.text).strikethrough(item.done)
                    }.padding(.leading, CGFloat(item.depth) * 18)
                }
                Button("Open week.md") { onOpenRecord(fb.config.planningWeekRelativePath) }.font(.caption)
            }
        }
    }

    // Panel 3 of 3: canonical docs row (§1.3d). Private never renders here.
    private var canonicalPanel: some View {
        panel("Canonical Documents", icon: "pin") {
            let docs = fb.snapshot?.canonicalDocs ?? []
            if docs.isEmpty {
                Text("No canonical documents in the scoped vault yet.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(docs) { doc in
                            Button { onOpenRecord(doc.relativePath) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: "doc.text").foregroundStyle(Color.m3taGold)
                                    Text(doc.title).font(.callout.weight(.medium)).lineLimit(2)
                                    Text(doc.relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(10).frame(width: 200, alignment: .leading)
                                .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(Color.m3taGold)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Vault folder browser + record reader (preview only)

struct VaultBrowserView: View {
    @Environment(FieldBookStore.self) var fb

    var body: some View {
        @Bindable var fb = fb
        NavigationSplitView {
            List(selection: $fb.selectedRelativePath) {
                if let snap = fb.snapshot {
                    let attention = snap.needsAttention
                    if !attention.isEmpty {
                        Section("Needs attention (\(attention.count))") {
                            ForEach(attention) { rec in
                                Label(rec.relativePath, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange).tag(rec.relativePath)
                            }
                        }
                    }
                    Section("Records (\(snap.records.count))") {
                        ForEach(snap.records) { rec in
                            HStack {
                                Text(rec.title).lineLimit(1)
                                Spacer()
                                Text(rec.classification.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }.tag(rec.relativePath)
                        }
                    }
                    if snap.passLog.skippedDataless > 0 {
                        Section("Index pass") {
                            Text("\(snap.passLog.skippedDataless) evicted (dataless) files skipped — never opened, never downloaded.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Index building…").foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 340)
        } detail: {
            if let rel = fb.selectedRelativePath, let text = fb.readRecord(relativePath: rel) {
                RecordPreviewView(relativePath: rel, text: text,
                                  record: fb.snapshot?.records.first { $0.relativePath == rel })
            } else {
                ContentUnavailableView("No record selected", systemImage: "doc.text",
                                       description: Text("Pick a record from the vault browser. The reader is preview-only in Phase 1."))
            }
        }
        .background(Color.tmwBg)
    }
}

// Editor in pure preview (Phase 1): render only — no outline, backlinks,
// or recents (those are Phase 2+).
struct RecordPreviewView: View {
    let relativePath: String
    let text: String
    let record: VaultRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(record?.title ?? relativePath).font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(relativePath).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let r = record {
                        Text("· \(r.classification.rawValue)").font(.caption).foregroundStyle(.secondary)
                        if let t = r.typeRaw { Text("· \(t)").font(.caption).foregroundStyle(.secondary) }
                        if r.isNewerSchema { Text("· newer schema (read-only)").font(.caption).foregroundStyle(.orange) }
                    }
                }
                if let issues = record?.issues, !issues.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(issues, id: \.self) { Text("⚠︎ \($0)").font(.caption).foregroundStyle(.orange) }
                    }
                }
                Divider()
                MarkdownPreview(markdown: FrontmatterParser.parse(text).body)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }
}

/// Minimal markdown preview renderer: headings, checkbox lines, fenced
/// code, and paragraphs with inline markdown where AttributedString can
/// parse it. Render only; nothing here writes.
struct MarkdownPreview: View {
    let markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading(let level):
                    Text(block.text).font(level <= 1 ? .title3.weight(.bold) : .headline).padding(.top, 4)
                case .code:
                    Text(block.text).font(.caption.monospaced()).padding(8)
                        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 6))
                case .checkbox(let done):
                    HStack {
                        Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? .green : .secondary)
                        Text(block.text)
                    }
                case .paragraph:
                    Text((try? AttributedString(markdown: block.text)) ?? AttributedString(block.text))
                }
            }
        }
    }

    private enum Kind { case heading(Int), code, checkbox(Bool), paragraph }
    private struct Block { var kind: Kind; var text: String }
    private var blocks: [Block] {
        var out: [Block] = []
        var inFence = false
        var code: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inFence { out.append(Block(kind: .code, text: code.joined(separator: "\n"))); code = [] }
                inFence.toggle(); continue
            }
            if inFence { code.append(line); continue }
            if t.isEmpty { continue }
            if let item = WeekGoalsParser.checkboxItemPublic(line) {
                out.append(Block(kind: .checkbox(item.done), text: item.text)); continue
            }
            if let level = WeekGoalsParser.headingLevelPublic(t) {
                out.append(Block(kind: .heading(level), text: WeekGoalsParser.headingTextPublic(t))); continue
            }
            out.append(Block(kind: .paragraph, text: t))
        }
        if !code.isEmpty { out.append(Block(kind: .code, text: code.joined(separator: "\n"))) }
        return out
    }
}

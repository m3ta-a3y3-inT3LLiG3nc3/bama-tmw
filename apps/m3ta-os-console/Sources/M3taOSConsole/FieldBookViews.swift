import SwiftUI
import AppKit
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
            case .accessDenied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar access not granted. The Lookout reads only allowlisted calendars.").foregroundStyle(.orange)
                    HStack(spacing: 10) {
                        Button("Request calendar access") { fb.requestCalendarAccess() }
                        Button("Open Calendar privacy settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
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
                    let recents = fb.appState.recents.compactMap { rel in snap.records.first { $0.relativePath == rel } }
                    if !recents.isEmpty {
                        Section("Recents") {
                            ForEach(recents) { rec in
                                Label(rec.title, systemImage: "clock.arrow.circlepath").tag(rec.relativePath)
                            }
                        }
                    }
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
            if let rel = fb.selectedRelativePath, fb.editor.relativePath == rel {
                RecordEditorView(relativePath: rel)
            } else if let rel = fb.selectedRelativePath, let text = fb.readRecord(relativePath: rel) {
                RecordPreviewView(relativePath: rel, text: text,
                                  record: fb.snapshot?.records.first { $0.relativePath == rel })
            } else {
                ContentUnavailableView("No record selected", systemImage: "doc.text",
                                       description: Text("Pick a record from the vault browser, or double-click a board card to edit it."))
            }
        }
        .background(Color.tmwBg)
    }
}

// Preview (Phase 1) — now carries the Edit entry point into the Phase 2
// editor. Newer-schema records stay read-only (§2.2): no Edit button.
struct RecordPreviewView: View {
    @Environment(FieldBookStore.self) var fb
    let relativePath: String
    let text: String
    let record: VaultRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(record?.title ?? relativePath).font(.title2.weight(.semibold))
                    Spacer()
                    if record?.isNewerSchema != true {
                        Button("Edit") { fb.openEditor(relativePath: relativePath) }
                            .accessibilityLabel("Edit \(relativePath)")
                    }
                }
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

// MARK: - Phase 2 editor

/// Standard NSTextView backing for the body editor. A plain editable
/// NSTextView is the dictation-friendly surface on macOS: system dictation,
/// text replacement, and spell services all work with no custom input
/// handling anywhere in this view.
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    var jumpToLine: Int?
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        tv.string = text
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text && !context.coordinator.isEditing { tv.string = text }
        if let line = jumpToLine, line != context.coordinator.lastJump {
            context.coordinator.lastJump = line
            let lines = tv.string.components(separatedBy: "\n")
            let charIndex = lines.prefix(line).reduce(0) { $0 + $1.count + 1 }
            if charIndex <= tv.string.count {
                tv.scrollRangeToVisible(NSRange(location: charIndex, length: 0))
                tv.setSelectedRange(NSRange(location: charIndex, length: 0))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        weak var textView: NSTextView?
        var isEditing = false
        var lastJump: Int?
        init(_ parent: BodyTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = tv.string
            parent.onEdit()
            isEditing = false
        }
    }
}

struct RecordEditorView: View {
    @Environment(FieldBookStore.self) var fb
    let relativePath: String
    @State private var jumpToLine: Int?

    private var record: VaultRecord? { fb.snapshot?.records.first { $0.relativePath == relativePath } }
    private var readOnly: Bool { record?.isNewerSchema == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let copy = fb.editor.conflictCopyPath {
                conflictBanner(copy)
            }
            if let msg = fb.editor.message {
                Text(msg).font(.caption).foregroundStyle(.orange)
            }
            if readOnly {
                Text("Newer schema (m3ta: 2+) — read-only everywhere (§2.2).")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if !fb.editor.focusMode {
                metadataPanel
            }
            HStack(alignment: .top, spacing: 12) {
                if !fb.editor.focusMode {
                    outlinePanel.frame(width: 200)
                }
                editorColumn
                if fb.editor.splitView {
                    previewColumn
                }
                if !fb.editor.focusMode {
                    backlinksPanel.frame(width: 190)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.tmwBg)
        // Escape exits ONE level: focus -> normal, split -> single,
        // editor -> browser (§3.1 checklist). Handled by an AppKit key
        // monitor, NOT SwiftUI onKeyPress: the body NSTextView is first
        // responder while editing and consumes Escape itself, so the
        // SwiftUI handler never fired (verified live 2026-11-09).
        .background {
            EscapeCatcher {
                if fb.editor.focusMode { fb.editor.focusMode = false }
                else if fb.editor.splitView { fb.editor.splitView = false }
                else { fb.closeEditor() }
            }
        }
        .onDisappear { fb.editorHeartbeat() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record?.title ?? relativePath).font(.title3.weight(.semibold))
                Text(relativePath).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if fb.editor.dirty {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Unsaved changes").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Toggle("Focus", isOn: Binding(get: { fb.editor.focusMode }, set: { fb.editor.focusMode = $0 }))
                .toggleStyle(.button)
            Toggle("Split", isOn: Binding(get: { fb.editor.splitView }, set: { fb.editor.splitView = $0 }))
                .toggleStyle(.button)
            Button("Save") { fb.saveEditor() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!fb.editor.dirty || readOnly)
            Button("Close") { fb.closeEditor() }
        }
    }

    private func conflictBanner(_ copyPath: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Conflict — save refused, nothing overwritten", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(.orange)
            Text("The file changed on disk after you opened it. Your buffer is intact, and a conflict copy was written to \((copyPath as NSString).lastPathComponent) (listed under Needs attention).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reload file & reapply my edits") { fb.editorReloadAndReapply() }
                Button("Discard my edits & reload") { fb.openEditor(relativePath: relativePath) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    private func fieldBinding(_ key: String) -> Binding<String> {
        Binding(get: { fb.editor.fields[key] ?? "" },
                set: { fb.editor.fields[key] = $0; fb.editorBecameDirty() })
    }

    private var metadataPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Metadata — §2.2 schema").font(.caption.weight(.semibold)).foregroundStyle(Color.m3taGold)
            HStack(spacing: 14) {
                pickerField("type", options: [""] + VaultRecord.typeEnum.sorted())
                pickerField("status", options: statusOptions)
                pickerField("tier", options: ["", "idea", "shelf", "bench"])
                pickerField("classification", options: ["", "public", "internal", "private"])
            }
            HStack(spacing: 14) {
                textField("brand")
                textField("channel")
                textField("owner")
                textField("due (yyyy-MM-dd)")
                textField("snooze_until")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 8))
    }

    private var statusOptions: [String] {
        let type = fb.editor.fields["type"] ?? ""
        var options = [""]
        if let allowed = VaultRecord.statusEnum(for: type) { options += allowed.sorted() }
        let current = fb.editor.fields["status"] ?? ""
        if !current.isEmpty && !options.contains(current) { options.append(current) }
        return options
    }

    private func pickerField(_ key: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Picker(key, selection: fieldBinding(key)) {
                ForEach(options, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
            }
            .labelsHidden().frame(width: 150)
            .disabled(readOnly)
        }
    }

    private func textField(_ label: String) -> some View {
        let key = label.components(separatedBy: " ").first ?? label
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, text: fieldBinding(key))
                .textFieldStyle(.roundedBorder).frame(width: 130)
                .disabled(readOnly)
        }
    }

    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Outline").font(.caption.weight(.semibold)).foregroundStyle(Color.m3taGold)
            let outline = EditorSupport.outline(body: fb.editor.body)
            if outline.isEmpty { Text("No headings.").font(.caption).foregroundStyle(.secondary) }
            ForEach(outline) { item in
                HStack(spacing: 4) {
                    Button {
                        if fb.editor.foldedHeadings.contains(item.lineIndex) { fb.editor.foldedHeadings.remove(item.lineIndex) }
                        else { fb.editor.foldedHeadings.insert(item.lineIndex) }
                    } label: {
                        Image(systemName: fb.editor.foldedHeadings.contains(item.lineIndex) ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                    }.buttonStyle(.plain)
                    Button(item.text) { jumpToLine = item.lineIndex }
                        .buttonStyle(.plain).font(.caption).lineLimit(1)
                }
                .padding(.leading, CGFloat(item.level - 1) * 10)
            }
            Spacer()
        }
    }

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body").font(.caption.weight(.semibold)).foregroundStyle(Color.m3taGold)
            BodyTextView(text: Binding(get: { fb.editor.body },
                                       set: { fb.editor.body = $0; fb.editorBecameDirty() }),
                         jumpToLine: jumpToLine,
                         onEdit: { fb.editorBecameDirty() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(readOnly)
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview (folded sections hidden)").font(.caption.weight(.semibold)).foregroundStyle(Color.m3taGold)
            ScrollView {
                MarkdownPreview(markdown: foldedBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.02), in: .rect(cornerRadius: 6))
        }
    }

    /// Fold semantics: a folded heading hides its section — every line
    /// until the next heading of equal-or-higher level — in the preview.
    private var foldedBody: String {
        let lines = fb.editor.body.components(separatedBy: "\n")
        var out: [String] = []
        var hidingLevel: Int?
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            let level = WeekGoalsParser.headingLevelPublic(t)
            if let level, let hiding = hidingLevel, level <= hiding { hidingLevel = nil }
            if let level, fb.editor.foldedHeadings.contains(i) {
                out.append(line + " …")
                hidingLevel = level
                continue
            }
            if hidingLevel == nil { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backlinks").font(.caption.weight(.semibold)).foregroundStyle(Color.m3taGold)
            if let rec = record {
                let links = fb.backlinks(for: rec)
                if links.isEmpty { Text("No records link here.").font(.caption).foregroundStyle(.secondary) }
                ForEach(links) { link in
                    Button(link.title) { fb.openEditor(relativePath: link.relativePath) }
                        .buttonStyle(.plain).font(.caption).lineLimit(2)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Phase 2 boards (§1.4)

struct BoardsView: View {
    @Environment(FieldBookStore.self) var fb
    var onOpenRecord: (String) -> Void
    @State private var boardType = "endeavor"
    @State private var brandFilter: String?
    @State private var channelFilter: String?

    private var board: BoardModel {
        BoardModel.build(records: fb.snapshot?.records ?? [], type: boardType,
                         todayString: fb.todayString, brand: brandFilter, channel: channelFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Board", selection: $boardType) {
                    Text("Endeavors").tag("endeavor")
                    Text("Content").tag("content")
                }.pickerStyle(.segmented).frame(width: 260)
                if boardType == "content" {
                    filterPicker("Brand", values: distinct(\.brandRaw), selection: $brandFilter)
                    filterPicker("Channel", values: distinct(\.channelRaw), selection: $channelFilter)
                }
                Spacer()
                Text("Drag a card to change status — one surgical line in the file. Double-click opens the editor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(board.columns, id: \.status) { column in
                        columnView(title: column.status, records: column.records, status: column.status)
                    }
                    columnView(title: "Unsorted", records: board.unsorted, status: nil)
                }
                .padding(.bottom, 8)
            }
            if !board.attention.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs attention — invalid status, never coerced").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    ForEach(board.attention) { rec in
                        Text("\(rec.relativePath) — status: \(rec.statusRaw ?? "?")")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            if !board.offBoard.isEmpty {
                Text("Off-board (terminal): \(board.offBoard.map(\.title).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.tmwBg)
        .navigationTitle("Boards")
    }

    private func distinct(_ keyPath: KeyPath<VaultRecord, String?>) -> [String] {
        Array(Set((fb.snapshot?.records ?? []).compactMap { $0[keyPath: keyPath] }.filter { !$0.isEmpty })).sorted()
    }

    private func filterPicker(_ label: String, values: [String], selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("All").tag(String?.none)
            ForEach(values, id: \.self) { Text($0).tag(String?.some($0)) }
        }.frame(width: 150)
    }

    private func columnView(title: String, records: [VaultRecord], status: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(records.count))").font(.callout.weight(.semibold)).foregroundStyle(Color.m3taGold)
            ForEach(records) { rec in card(rec) }
            Spacer()
        }
        .padding(10)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.03), in: .rect(cornerRadius: 10))
        .dropDestination(for: String.self) { items, _ in
            guard let status, let rel = items.first else { return false }
            fb.changeStatus(relativePath: rel, to: status)
            return true
        }
    }

    private func card(_ rec: VaultRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rec.title).font(.callout.weight(.medium)).lineLimit(2)
            HStack(spacing: 6) {
                if let tier = rec.tierRaw { Text(tier).font(.caption2).foregroundStyle(.secondary) }
                if let due = rec.dueRaw { Text("due \(due)").font(.caption2).foregroundStyle(.secondary) }
                if rec.classification == .private { Text("private").font(.caption2).foregroundStyle(.orange) }
                if rec.isNewerSchema { Text("newer schema").font(.caption2).foregroundStyle(.orange) }
            }
            Text(rec.relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))
        .draggable(rec.relativePath)
        // Double-click opens the editor (§1.4). Neither onTapGesture(count: 2)
        // nor a simultaneous TapGesture(count: 2) ever completed on this
        // card under real mouse input (verified live 2026-11-09 with three
        // independent input routes that all landed single clicks on other
        // controls: the ScrollView + dropDestination + draggable recognizer
        // stack swallows the second tap). The catcher below observes
        // clickCount == 2 through an AppKit local event monitor and never
        // consumes the event, so dragging is untouched.
        .overlay { DoubleClickCatcher { onOpenRecord(rec.relativePath) } }
        // Secondary path: the standard SwiftUI double-tap, kept alongside
        // the catcher — both call the same idempotent open.
        .onTapGesture(count: 2) { onOpenRecord(rec.relativePath) }
        .accessibilityLabel("Card \(rec.title)")
    }
}

// MARK: - Phase 2 ideas (capture / promote / snooze — the Heap is Phase 3a)

struct IdeasView: View {
    @Environment(FieldBookStore.self) var fb
    var onOpenRecord: (String) -> Void
    @State private var newTitle = ""

    private var ideas: [VaultRecord] {
        (fb.snapshot?.records ?? []).filter { $0.typeRaw == "idea" && !$0.isConflictCopy }
            .sorted { $0.effectiveUpdated > $1.effectiveUpdated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Capture an idea…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { capture() }
                Button("Capture") { capture() }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Capture writes a new record (type: idea, tier: idea, status: captured) into 00-Inbox. Snoozed ideas hide from boards and the Lookout through the end of the snooze date.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ideas) { rec in IdeaRow(rec: rec, onOpen: { onOpenRecord(rec.relativePath) }) }
                    if ideas.isEmpty { Text("No idea records in the scoped vault yet.").foregroundStyle(.secondary) }
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.tmwBg)
        .navigationTitle("Ideas")
    }

    private func capture() {
        if let rel = fb.captureIdea(title: newTitle) {
            newTitle = ""
            onOpenRecord(rel)
        }
    }
}

private struct IdeaRow: View {
    @Environment(FieldBookStore.self) var fb
    let rec: VaultRecord
    var onOpen: () -> Void
    @State private var snoozeDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private var snoozed: Bool { BoardModel.isSnoozed(rec, todayString: fb.todayString) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title).font(.callout.weight(.medium))
                Text("tier \(rec.tierRaw ?? "idea") · status \(rec.statusRaw ?? "—")\(snoozed ? " · snoozed until \(rec.snoozeUntilRaw ?? "")" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            DatePicker("", selection: $snoozeDate, displayedComponents: .date).labelsHidden()
            Button("Snooze") { fb.snooze(relativePath: rec.relativePath, until: VaultWriter.localDateString(snoozeDate)) }
            Button("Promote") { fb.promote(relativePath: rec.relativePath) }
                .disabled((rec.tierRaw ?? "idea") == "bench")
            Button("Open") { onOpen() }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}

/// Transparent overlay that reports double-clicks inside its bounds via an
/// NSEvent local monitor. hitTest returns nil so it never intercepts
/// anything; the monitor observes and returns every event unchanged.
struct DoubleClickCatcher: NSViewRepresentable {
    var onDoubleClick: () -> Void
    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) { view.onDoubleClick = onDoubleClick }

    final class CatcherView: NSView {
        var onDoubleClick: (() -> Void)?
        // nonisolated(unsafe): the token is only touched on the main thread
        // (view lifecycle + monitor delivery), but deinit must be able to
        // release it under Swift 6 concurrency checking.
        nonisolated(unsafe) private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            if ProcessInfo.processInfo.environment["FB_DEBUG_CLICKS"] == "1" {
                if let handle = FileHandle(forWritingAtPath: "/tmp/p2-clicks.log") {
                    handle.seekToEndOfFile(); handle.write(Data("installed\n".utf8)); try? handle.close()
                } else {
                    try? "installed\n".write(toFile: "/tmp/p2-clicks.log", atomically: false, encoding: .utf8)
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                if ProcessInfo.processInfo.environment["FB_DEBUG_CLICKS"] == "1" {
                    let raw = "mon: eventWindow=\(String(describing: event.window)) selfWindow=\(String(describing: self.window)) keyWindow=\(String(describing: NSApp.keyWindow)) mainWindow=\(String(describing: NSApp.mainWindow))\n"
                    if let handle = FileHandle(forWritingAtPath: "/tmp/p2-clicks.log") {
                        handle.seekToEndOfFile(); handle.write(Data(raw.utf8)); try? handle.close()
                    }
                }
                guard event.window === self.window else { return event }
                if ProcessInfo.processInfo.environment["FB_DEBUG_CLICKS"] == "1" {
                    let point = self.convert(event.locationInWindow, from: nil)
                    let line = "clickCount=\(event.clickCount) point=\(point) bounds=\(self.bounds) inside=\(self.bounds.contains(point))\n"
                    if let handle = FileHandle(forWritingAtPath: "/tmp/p2-clicks.log") {
                        handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
                    } else {
                        try? line.write(toFile: "/tmp/p2-clicks.log", atomically: false, encoding: .utf8)
                    }
                }
                guard event.clickCount == 2 else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    let action = self.onDoubleClick
                    DispatchQueue.main.async { action?() }
                }
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Escape-key catcher for the editor: a local key-down monitor that fires
/// on Escape (keyCode 53) in the editor's window and CONSUMES the event,
/// so the body text view's own Escape handling (completion) never races
/// the one-level exit ladder.
struct EscapeCatcher: NSViewRepresentable {
    var onEscape: () -> Void
    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) { view.onEscape = onEscape }

    final class CatcherView: NSView {
        var onEscape: (() -> Void)?
        nonisolated(unsafe) private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, event.keyCode == 53 else { return event }
                let action = self.onEscape
                DispatchQueue.main.async { action?() }
                return nil // consumed: exactly one ladder level per press
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

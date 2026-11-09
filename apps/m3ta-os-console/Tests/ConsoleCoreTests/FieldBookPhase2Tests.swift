import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#endif
@testable import ConsoleCore

// Field Book Phase 2 tests (spec §3.1 file-layer suite, §2.2, §4 Phase 2).
// The hostile fixture set is the point: comments, unknown keys, quoted
// strings, non-canonical formatting, duplicate keys, folded scalars,
// malformed YAML — the writer must preserve every byte it does not own.

private let hostileFixtures: [(name: String, content: String)] = [
    ("comments", """
    ---
    # a comment from another tool
    m3ta: 1
    type: endeavor
    x-custom-tool: keep me exactly
    status: active
    classification: internal
    # trailing comment
    ---
    # Heading
    Body text.
    """),
    ("quoted", """
    ---
    m3ta: 1
    type: endeavor
    title: "Quoted Title"
    status: "active"
    classification: 'internal'
    ---
    Body.
    """),
    ("noncanonical", """
    ---
    m3ta: 1
    type:   endeavor
    status:active
    classification: internal
    ---
    Body.
    """),
    ("duplicate", """
    ---
    m3ta: 1
    type: endeavor
    status: active
    status: planned
    classification: internal
    ---
    Body.
    """),
    ("folded", """
    ---
    m3ta: 1
    type: endeavor
    description: A long value
      folded across lines
      by another tool
    status: active
    classification: internal
    ---
    Body.
    """),
    ("canonical", """
    ---
    m3ta: 1
    id: abc123
    type: endeavor
    status: active
    tier: shelf
    classification: internal
    created: 2026-11-08
    updated: 2026-11-08
    ---
    # Title
    Body.
    """),
]

private let malformedFixture = """
---
m3ta: 1
type: endeavor
status: active
this block never closes
Body lines follow.
"""

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fb2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeFile(_ dir: URL, _ name: String, _ content: String) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func changedLineCount(_ a: String, _ b: String) -> Int {
    let x = a.components(separatedBy: "\n"), y = b.components(separatedBy: "\n")
    var n = abs(x.count - y.count)
    for i in 0..<min(x.count, y.count) where x[i] != y[i] { n += 1 }
    return n
}

@Suite struct SurgicalWriterTests {
    @Test func zeroByteDiffNoOpOnEveryHostileFixture() throws {
        let writer = VaultWriter()
        for fixture in hostileFixtures + [(name: "malformed", content: malformedFixture)] {
            let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = try writeFile(dir, "\(fixture.name).md", fixture.content)
            let before = try Data(contentsOf: url)
            let opened = try writer.open(url: url)
            let result = writer.save(opened: opened, edits: [], newBody: nil, synced: false)
            #expect(result == .noOp, "\(fixture.name): expected noOp, got \(result)")
            #expect(try Data(contentsOf: url) == before, "\(fixture.name): bytes changed on a no-op save")
        }
    }

    @Test func sameValueEditOnCanonicalFixtureIsAlsoNoOp() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "c.md", hostileFixtures.first { $0.name == "canonical" }!.content)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "active")], newBody: nil, synced: false)
        #expect(result == .noOp)
    }

    @Test func oneLineDiffStatusChangeOnEveryHostileFixture() throws {
        let writer = VaultWriter()
        for fixture in hostileFixtures {
            let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = try writeFile(dir, "\(fixture.name).md", fixture.content)
            let opened = try writer.open(url: url)
            let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "blocked")], newBody: nil, synced: false)
            #expect(result == .saved, "\(fixture.name): expected saved, got \(result)")
            let after = try String(contentsOf: url, encoding: .utf8)
            #expect(changedLineCount(fixture.content, after) == 1, "\(fixture.name): diff was not exactly one line")
            #expect(after.contains("status: blocked") || after.contains("status:blocked") == false)
            let parse = FrontmatterParser.parse(after)
            #expect(parse.string("status") == "blocked", "\(fixture.name): status did not land")
        }
        // Duplicate-key fixture: first status line replaced, second survives.
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "dup.md", hostileFixtures.first { $0.name == "duplicate" }!.content)
        let opened = try writer.open(url: url)
        _ = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "review")], newBody: nil, synced: false)
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("status: planned"), "duplicate: the second status line must survive untouched")
        #expect(after.components(separatedBy: "status:").count - 1 == 2)
    }

    @Test func malformedFixtureRefusesFrontmatterEditButKeepsBytes() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "m.md", malformedFixture)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "blocked")], newBody: nil, synced: false)
        guard case .refused = result else { Issue.record("malformed: expected refusal, got \(result)"); return }
        #expect(try String(contentsOf: url, encoding: .utf8) == malformedFixture)
    }

    @Test func hostileBytesSurviveAStatusEdit() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let comments = hostileFixtures.first { $0.name == "comments" }!.content
        let url = try writeFile(dir, "c.md", comments)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        _ = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "done")], newBody: nil, synced: false)
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("# a comment from another tool"))
        #expect(after.contains("x-custom-tool: keep me exactly"))
        #expect(after.contains("# trailing comment"))
        let folded = hostileFixtures.first { $0.name == "folded" }!.content
        let url2 = try writeFile(dir, "f.md", folded)
        let opened2 = try writer.open(url: url2)
        _ = writer.save(opened: opened2, edits: [KeyEdit(key: "status", value: "done")], newBody: nil, synced: false)
        let after2 = try String(contentsOf: url2, encoding: .utf8)
        #expect(after2.contains("  folded across lines"))
        #expect(after2.contains("  by another tool"))
    }

    @Test func insertMissingKeyAddsOneLineBeforeClosingFence() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let content = hostileFixtures.first { $0.name == "canonical" }!.content
        let url = try writeFile(dir, "c.md", content)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        let result = writer.save(opened: opened, edits: [VaultWriter.snoozeEdit(until: "2026-11-20")], newBody: nil, synced: false)
        #expect(result == .saved)
        let after = try String(contentsOf: url, encoding: .utf8)
        // Exactly one inserted line; removing it reproduces the original.
        var afterLines = after.components(separatedBy: "\n")
        #expect(afterLines.count == content.components(separatedBy: "\n").count + 1)
        if let idx = afterLines.firstIndex(of: "snooze_until: 2026-11-20") {
            afterLines.remove(at: idx)
            #expect(afterLines.joined(separator: "\n") == content)
        } else { Issue.record("inserted snooze line missing") }
        #expect(after.contains("snooze_until: 2026-11-20\n---"))
        #expect(FrontmatterParser.parse(after).string("snooze_until") == "2026-11-20")
    }

    @Test func bodyOnlyEditLeavesFrontmatterBytesUntouchedAndViceVersa() throws {
        let content = hostileFixtures.first { $0.name == "comments" }!.content
        let writer = VaultWriter()
        // Body only.
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "b.md", content)
        let opened = try writer.open(url: url)
        let parsed = FrontmatterParser.parse(content)
        let result = writer.save(opened: opened, edits: [], newBody: parsed.body + "Appended line.\n", synced: false)
        #expect(result == .saved)
        let after = try String(contentsOf: url, encoding: .utf8)
        let fmPrefix = { (s: String) -> String in
            let lines = s.components(separatedBy: "\n")
            let range = VaultWriter.frontmatterRange(in: lines)!
            return lines[0...range.close].joined(separator: "\n")
        }
        #expect(fmPrefix(after) == fmPrefix(content))
        // Frontmatter only: body bytes identical.
        let dir2 = try tempDir(); defer { try? FileManager.default.removeItem(at: dir2) }
        let url2 = try writeFile(dir2, "b2.md", content)
        let opened2 = try writer.open(url: url2)
        _ = writer.save(opened: opened2, edits: [KeyEdit(key: "status", value: "review")], newBody: nil, synced: false)
        let after2 = try String(contentsOf: url2, encoding: .utf8)
        #expect(FrontmatterParser.parse(after2).body == parsed.body)
    }

    @Test func combinedFrontmatterAndBodySaveIsOneSave() throws {
        let content = hostileFixtures.first { $0.name == "canonical" }!.content
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "d13.md", content)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        let result = writer.save(opened: opened,
                                 edits: [KeyEdit(key: "status", value: "active"), KeyEdit(key: "tier", value: "bench")],
                                 newBody: "# Title\nEdited body in the same save (D13).\n", synced: false)
        #expect(result == .saved)
        let after = try String(contentsOf: url, encoding: .utf8)
        let parse = FrontmatterParser.parse(after)
        #expect(parse.string("tier") == "bench")
        #expect(parse.body.contains("Edited body in the same save (D13)."))
    }

    @Test func conflictRefusesAndConflictCopyHoldsTheRefusedBuffer() throws {
        let content = hostileFixtures.first { $0.name == "canonical" }!.content
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "conf.md", content)
        let fixedNow = Date(timeIntervalSince1970: 1_763_000_000)
        let writer = VaultWriter(now: { fixedNow })
        let opened = try writer.open(url: url)
        // External writer lands first.
        let external = content + "External line.\n"
        try external.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_763_500_000)], ofItemAtPath: url.path)
        let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "blocked")], newBody: nil, synced: false)
        guard case .conflict(let copyPath) = result else { Issue.record("expected conflict, got \(result)"); return }
        #expect(try String(contentsOf: url, encoding: .utf8) == external) // never overwritten
        let copy = try String(contentsOfFile: copyPath, encoding: .utf8)
        #expect(FrontmatterParser.parse(copy).string("status") == "blocked") // buffer survives
        #expect((copyPath as NSString).lastPathComponent.contains(".conflict-"))
        // And the index flags the copy as a conflict copy in Needs attention.
        let rec = VaultRecord.make(relativePath: (copyPath as NSString).lastPathComponent,
                                   parse: FrontmatterParser.parse(copy), mtime: Date(),
                                   contentHash: "x", sizeBytes: copy.count, links: [])
        #expect(rec.isConflictCopy)
        #expect(rec.needsAttention)
    }

    @Test func unknownSchemaMajorIsReadOnly() throws {
        let content = "---\nm3ta: 2\ntype: endeavor\nstatus: active\nclassification: internal\n---\nFuture.\n"
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "future.md", content)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        let result = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "blocked")], newBody: nil, synced: false)
        guard case .refused(let reason) = result else { Issue.record("expected refusal, got \(result)"); return }
        #expect(reason.contains("newer schema"))
        let bodyOnly = writer.save(opened: opened, edits: [], newBody: "Edited.\n", synced: false)
        guard case .refused = bodyOnly else { Issue.record("body save must also refuse on newer schema"); return }
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
    }

    @Test func validationRefusesInvalidChangedValues() throws {
        let content = hostileFixtures.first { $0.name == "canonical" }!.content
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = try writeFile(dir, "v.md", content)
        let writer = VaultWriter()
        let opened = try writer.open(url: url)
        guard case .refused = writer.save(opened: opened, edits: [KeyEdit(key: "status", value: "frobnicate")], newBody: nil, synced: false) else {
            Issue.record("invalid status must refuse"); return
        }
        guard case .refused = writer.save(opened: opened, edits: [VaultWriter.snoozeEdit(until: "next Tuesday")], newBody: nil, synced: false) else {
            Issue.record("invalid snooze date must refuse"); return
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
    }

    @Test func syncedPathDetection() {
        #expect(VaultWriter.looksSynced(URL(fileURLWithPath: "/Users/x/Library/Mobile Documents/iCloud~md~obsidian/Documents/vault/a.md")))
        #expect(!VaultWriter.looksSynced(URL(fileURLWithPath: "/tmp/fixture/a.md")))
    }
}

@Suite struct LeaseAndAppStateTests {
    @Test func leaseRegisterHeartbeatExpireRelease() {
        var state = AppState()
        let t0 = Date(timeIntervalSince1970: 1_763_000_000)
        state.registerLease(path: "a.md", recordID: "id1", now: t0)
        #expect(state.lease(for: "a.md", now: t0) != nil)
        state.heartbeatLease(path: "a.md", now: t0.addingTimeInterval(600))
        #expect(state.lease(for: "a.md", now: t0.addingTimeInterval(600 + 899)) != nil)
        #expect(state.lease(for: "a.md", now: t0.addingTimeInterval(600 + 901)) == nil) // 15-min expiry
        #expect(state.activeLeases(now: t0.addingTimeInterval(2000)).isEmpty)           // pruned
        state.registerLease(path: "b.md", recordID: nil, now: t0)
        state.releaseLease(path: "b.md")
        #expect(state.lease(for: "b.md", now: t0) == nil)
    }

    @Test func recentsAndSaveLogPersist() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = AppStateStore(directory: dir)
        var state = store.load()
        #expect(state.recents.isEmpty)
        state.touchRecent("one.md"); state.touchRecent("two.md"); state.touchRecent("one.md")
        #expect(state.recents == ["one.md", "two.md"])
        state.appendSaveLog(path: "one.md", at: Date(timeIntervalSince1970: 1_763_000_000), summary: "status: active -> blocked")
        try store.save(state)
        let reloaded = store.load()
        #expect(reloaded == state)
        #expect(reloaded.saveLog.first?.summary.contains("active -> blocked") == true)
        #expect(SaveLogEntry.coverageLabel == "Console saves only")
    }
}

@Suite struct BoardAndTierTests {
    private func record(_ path: String, _ fm: String) -> VaultRecord {
        VaultRecord.make(relativePath: path, parse: FrontmatterParser.parse(fm),
                         mtime: Date(timeIntervalSince1970: 1_700_000_000), contentHash: "x", sizeBytes: 10, links: [])
    }

    @Test func promotionEditsFollowTheTierLadder() {
        #expect(VaultWriter.promotionEdits(tierRaw: "idea", typeRaw: "endeavor") == [KeyEdit(key: "tier", value: "shelf")])
        #expect(VaultWriter.promotionEdits(tierRaw: nil, typeRaw: "endeavor") == [KeyEdit(key: "tier", value: "shelf")])
        let toBench = VaultWriter.promotionEdits(tierRaw: "shelf", typeRaw: "idea")
        #expect(toBench == [KeyEdit(key: "tier", value: "bench"), KeyEdit(key: "status", value: "promoted")])
        #expect(VaultWriter.promotionEdits(tierRaw: "bench", typeRaw: "idea").isEmpty)
    }

    @Test func promoteAndSnoozeApplyAsLineEdits() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let content = "---\nm3ta: 1\ntype: idea\nstatus: triaged\ntier: shelf\nclassification: internal\n---\nIdea body.\n"
        let url = try writeFile(dir, "idea.md", content)
        let writer = VaultWriter()
        var opened = try writer.open(url: url)
        let edits = VaultWriter.promotionEdits(tierRaw: "shelf", typeRaw: "idea")
        #expect(writer.save(opened: opened, edits: edits, newBody: nil, synced: false) == .saved)
        var after = try String(contentsOf: url, encoding: .utf8)
        #expect(changedLineCount(content, after) == 2) // tier + status lines, nothing else
        #expect(FrontmatterParser.parse(after).string("status") == "promoted")
        opened = try writer.open(url: url)
        #expect(writer.save(opened: opened, edits: [VaultWriter.snoozeEdit(until: "2026-12-01")], newBody: nil, synced: false) == .saved)
        after = try String(contentsOf: url, encoding: .utf8)
        #expect(FrontmatterParser.parse(after).string("snooze_until") == "2026-12-01")
    }

    @Test func boardColumnsUnsortedAttentionAndSnooze() {
        let recs = [
            record("a.md", "---\ntype: endeavor\nstatus: active\nclassification: internal\n---\n"),
            record("b.md", "---\ntype: endeavor\nclassification: internal\n---\n"),                       // missing status -> Unsorted
            record("c.md", "---\ntype: endeavor\nstatus: frobnicate\nclassification: internal\n---\n"),   // invalid -> attention
            record("d.md", "---\ntype: endeavor\nstatus: dropped\nclassification: internal\n---\n"),      // off-board terminal
            record("e.md", "---\ntype: endeavor\nstatus: active\nsnooze_until: 2026-11-20\nclassification: internal\n---\n"),
            record("f.conflict-20261109-100000.md", "---\ntype: endeavor\nstatus: active\nclassification: internal\n---\n"),
        ]
        let board = BoardModel.build(records: recs, type: "endeavor", todayString: "2026-11-09")
        #expect(board.columns.first { $0.status == "active" }?.records.map(\.relativePath) == ["a.md"])
        #expect(board.unsorted.map(\.relativePath) == ["b.md"])
        #expect(board.attention.map(\.relativePath) == ["c.md"])
        #expect(board.offBoard.map(\.relativePath) == ["d.md"])
        // Snooze hides through the END of the snooze date, then releases.
        let later = BoardModel.build(records: recs, type: "endeavor", todayString: "2026-11-21")
        #expect(later.columns.first { $0.status == "active" }?.records.map(\.relativePath) == ["a.md", "e.md"])
        // On the snooze date itself the record is still hidden.
        let sameDay = BoardModel.build(records: recs, type: "endeavor", todayString: "2026-11-20")
        #expect(sameDay.columns.first { $0.status == "active" }?.records.map(\.relativePath) == ["a.md"])
    }

    @Test func boardNeverCrashesAndNothingVanishesOnMalformedSuite() throws {
        // Index a vault holding every §2.2 tolerance class and lay boards over it.
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for sub in ["00-Inbox", "Meetings"] { try FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true) }
        _ = try writeFile(dir, "Meetings/unclosed.md", malformedFixture)
        _ = try writeFile(dir, "Meetings/plain.md", "# No frontmatter at all\n")
        _ = try writeFile(dir, "Meetings/future.md", "---\nm3ta: 2\ntype: endeavor\nstatus: active\n---\n")
        _ = try writeFile(dir, "Meetings/dupe.md", hostileFixtures.first { $0.name == "duplicate" }!.content)
        _ = try writeFile(dir, "00-Inbox/idea.md", "---\nm3ta: 1\ntype: idea\nstatus: captured\ntier: idea\nclassification: internal\n---\n")
        let cfg = FieldBookConfig(vaultRootPath: dir.path)
        let snap = VaultIndexer(config: cfg).scan()
        #expect(snap.records.count == 5) // every file visible somewhere
        let board = BoardModel.build(records: snap.records, type: "endeavor", todayString: "2026-11-09")
        let accounted = board.columns.flatMap(\.records).count + board.unsorted.count + board.attention.count + board.offBoard.count
        #expect(accounted == 2) // future + dupe endeavors render; the unclosed file's frontmatter
                                 // never parsed, so it is a note-class record — visible in the
                                 // census + Needs attention, never silently on a board
        #expect(board.columns.flatMap(\.records).contains { $0.relativePath == "Meetings/dupe.md" })
        let unclosed = snap.records.first { $0.relativePath == "Meetings/unclosed.md" }
        #expect(unclosed?.needsAttention == true)
    }

    @Test func contentBoardBrandChannelFilters() {
        let recs = [
            record("x.md", "---\ntype: content\nstatus: drafting\nbrand: edge\nchannel: youtube\nclassification: internal\n---\n"),
            record("y.md", "---\ntype: content\nstatus: drafting\nbrand: edge\nchannel: tiktok\nclassification: internal\n---\n"),
        ]
        let filtered = BoardModel.build(records: recs, type: "content", todayString: "2026-11-09", brand: "edge", channel: "youtube")
        #expect(filtered.columns.first { $0.status == "drafting" }?.records.map(\.relativePath) == ["x.md"])
    }
}

@Suite struct CaptureTests {
    @Test func slugAndCaptureContent() throws {
        #expect(VaultWriter.slug("My Big Idea!") == "my-big-idea")
        #expect(VaultWriter.slug("  --Weird__Title--  ") == "weird-title")
        #expect(VaultWriter.slug("!!!") == "idea")
        let content = VaultWriter.captureContent(title: "My Big Idea!", id: "testid123", dateString: "2026-11-09")
        let parse = FrontmatterParser.parse(content)
        #expect(parse.string("type") == "idea")
        #expect(parse.string("tier") == "idea")
        #expect(parse.string("status") == "captured")
        #expect(parse.string("classification") == "internal")
        #expect(parse.fields["m3ta"]?.intValue == 1)
        #expect(parse.string("id") == "testid123")
        let rec = VaultRecord.make(relativePath: "00-Inbox/my-big-idea.md", parse: parse,
                                   mtime: Date(), contentHash: "x", sizeBytes: content.count, links: [])
        #expect(!rec.needsAttention)
        // createFile writes it exactly once; a second create refuses.
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("00-Inbox/my-big-idea.md")
        let writer = VaultWriter()
        #expect(writer.createFile(url: url, content: content, synced: false) == .saved)
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
        guard case .refused = writer.createFile(url: url, content: content, synced: false) else {
            Issue.record("second create must refuse"); return
        }
    }
}

@Suite struct EditorSupportTests {
    @Test func outlineSkipsFencedCode() {
        let body = "# Top\n\n```\n# not a heading\n```\n\n## Goals\ntext\n### Deep\n"
        let outline = EditorSupport.outline(body: body)
        #expect(outline.map(\.text) == ["Top", "Goals", "Deep"])
        #expect(outline.map(\.level) == [1, 2, 3])
    }

    @Test func backlinksMatchTitleAndStem() {
        let target = VaultRecord.make(relativePath: "Meetings/target.md",
                                      parse: FrontmatterParser.parse("---\ntitle: Target Doc\nclassification: internal\n---\n"),
                                      mtime: Date(), contentHash: "x", sizeBytes: 1, links: [])
        let linker = VaultRecord.make(relativePath: "a.md",
                                      parse: FrontmatterParser.parse("---\ntitle: A\nclassification: internal\n---\n"),
                                      mtime: Date(), contentHash: "x", sizeBytes: 1, links: ["Target Doc"])
        let stemLinker = VaultRecord.make(relativePath: "b.md",
                                          parse: FrontmatterParser.parse("---\ntitle: B\nclassification: internal\n---\n"),
                                          mtime: Date(), contentHash: "x", sizeBytes: 1, links: ["target"])
        let links = EditorSupport.backlinks(to: target, in: [target, linker, stemLinker])
        #expect(links.map(\.relativePath) == ["a.md", "b.md"])
    }
}

@Suite struct IndexerTimeoutTests {
    @Test func blockingFileTimesOutAndPassCompletes() throws {
        #if canImport(Darwin)
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Meetings"), withIntermediateDirectories: true)
        _ = try writeFile(dir, "Meetings/good.md", "---\nm3ta: 1\ntitle: Good\nclassification: internal\n---\nFine.\n")
        let fifo = dir.appendingPathComponent("Meetings/blocker.md")
        #expect(mkfifo(fifo.path, 0o644) == 0)
        let cfg = FieldBookConfig(vaultRootPath: dir.path, scopedSubtrees: ["Meetings"])
        let start = Date()
        let snap = VaultIndexer(config: cfg).scan()
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 30) // the pass completed despite the blocking open
        let blocker = snap.records.first { $0.relativePath == "Meetings/blocker.md" }
        #expect(blocker != nil) // never dropped
        #expect(blocker?.needsAttention == true)
        #expect(blocker?.issues.contains { $0.contains("timed out") } == true)
        #expect(snap.records.contains { $0.relativePath == "Meetings/good.md" })
        #endif
    }
}

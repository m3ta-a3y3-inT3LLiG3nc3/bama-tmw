import Testing
import Foundation
@testable import ConsoleCore

// Field Book Phase 1 tests (spec v2 §4 Phase 1 acceptance, §2.2, §1.3c, D16).

private func makeFixtureVault() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fieldbook-fixture-\(UUID().uuidString)")
    for sub in ["00-Inbox", "10-Projects!", "Meetings", "Global-Wiki", "knowledge", "MLXModels", "planning"] {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    func write(_ rel: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(rel), atomically: true, encoding: .utf8)
    }
    try write("canon.md", "---\nm3ta: 1\ntitle: Canon Doc\ntype: canonical\nclassification: internal\ncanonical: true\nupdated: 2026-11-08\n---\n# Canon Doc\nBody.\n")
    try write("secret.md", "---\ntitle: Unclassified Secret\ncanonical: true\n---\n# Secret\nNo classification = private.\n")
    try write("bad.md", "---\ntitle: Bad One\ntitle: Duplicate\nstatus: frobnicate\nclassification: sideways\n---\nBody\n")
    try write("10-Projects!/proj.md", "---\nm3ta: 1\ntitle: Project A\ntype: endeavor\nstatus: active\nclassification: public\n---\n# Project A\nLinks [[Canon Doc]] and [[Other|alias]].\n")
    try write("MLXModels/excluded.md", "---\ntitle: Excluded\nclassification: public\ncanonical: true\n---\nShould never be indexed.\n")
    try write("planning/week.md", "# Week\n\n## Goals\n- [ ] Ship Phase 1\n- [x] Approve ballot\n  - [ ] Nested goal\n\n```\n- [ ] Code block checkbox, ignore me\n```\n\n## Later\n- [ ] Not a goal\n")
    return dir
}

@Suite struct FieldBookIndexTests {
    @Test func scopedIndexExcludesUnscopedTrees() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let cfg = FieldBookConfig(vaultRootPath: vault.path)
        let snap = VaultIndexer(config: cfg).scan()
        #expect(!snap.records.contains { $0.relativePath.contains("MLXModels") })
        #expect(snap.records.contains { $0.relativePath == "canon.md" })
        #expect(snap.records.contains { $0.relativePath == "10-Projects!/proj.md" })
    }

    @Test func unclassifiedFileNeverAppearsOnLookout() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let snap = VaultIndexer(config: FieldBookConfig(vaultRootPath: vault.path)).scan()
        let secret = snap.records.first { $0.relativePath == "secret.md" }
        #expect(secret?.classification == .private)          // fail-closed
        #expect(secret?.canonical == false)                   // canonical stripped for private
        #expect(!snap.canonicalDocs.contains { $0.relativePath == "secret.md" })
        #expect(!snap.lookoutVisible.contains { $0.relativePath == "secret.md" })
        #expect(snap.canonicalDocs.contains { $0.relativePath == "canon.md" })
    }

    @Test func malformedRecordIsVisibleAsFailed() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let snap = VaultIndexer(config: FieldBookConfig(vaultRootPath: vault.path)).scan()
        let bad = snap.records.first { $0.relativePath == "bad.md" }
        #expect(bad != nil)                                   // never dropped
        #expect(bad?.needsAttention == true)
        #expect(bad?.issues.contains { $0.contains("duplicate key") } == true)
        #expect(bad?.classification == .private)              // invalid value -> private
    }

    @Test func datalessFilesAreSkippedAndReported() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let cfg = FieldBookConfig(vaultRootPath: vault.path)
        let indexer = VaultIndexer(config: cfg, datalessDetector: { $0.lastPathComponent == "secret.md" })
        let snap = indexer.scan()
        #expect(snap.passLog.skippedDataless == 1)
        #expect(!snap.records.contains { $0.relativePath == "secret.md" })
    }

    @Test func deleteIndexRebuildYieldsIdenticalRenderedOutput() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let cfg = FieldBookConfig(vaultRootPath: vault.path)
        let store = VaultIndexStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fb-index-\(UUID().uuidString)"))
        let indexer = VaultIndexer(config: cfg)
        let goals = WeekGoalsParser.load(from: cfg.planningWeekURL)
        let first = indexer.scan()
        try store.save(first)
        let renderedFirst = first.renderedVaultContent(goals: goals)
        try store.delete()
        #expect(try store.load() == nil)
        let second = indexer.scan()
        #expect(second.renderedVaultContent(goals: goals) == renderedFirst)
    }

    @Test func reconciliationReportsChanges() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let cfg = FieldBookConfig(vaultRootPath: vault.path)
        let indexer = VaultIndexer(config: cfg)
        let stored = indexer.scan()
        try "changed".write(to: vault.appendingPathComponent("canon.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: New\n---\n".write(to: vault.appendingPathComponent("Meetings/new.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: vault.appendingPathComponent("bad.md"))
        let report = VaultIndexer.reconcile(stored: stored, fresh: indexer.scan())
        #expect(report.changedOnDisk.contains("canon.md"))
        #expect(report.missingFromIndex.contains("Meetings/new.md"))
        #expect(report.missingOnDisk.contains("bad.md"))
        #expect(!report.isClean)
    }
}

@Suite struct WeekGoalsParserTests {
    @Test func parsesGoalsSectionPerRule() {
        let text = "# Week\n\n## Goals\n- [ ] A\n- [x] B\n  - [ ] nested\n\n```\n- [ ] ignored\n```\n\n## Next\n- [ ] not a goal\n"
        let outcome = WeekGoalsParser.parse(text: text)
        #expect(outcome.items.map(\.text) == ["A", "B", "nested"])
        #expect(outcome.items.map(\.done) == [false, true, false])
        #expect(outcome.items.last?.depth == 1)
    }
    @Test func missingSectionIsExplicitNotFound() {
        let outcome = WeekGoalsParser.parse(text: "# Week\n\n## Plans\n- [ ] A\n")
        #expect(outcome == .sectionMissing)
        #expect(outcome.displayText == "Goals section not found in `week.md`")
    }
    @Test func missingFileIsFileMissing() {
        let outcome = WeekGoalsParser.load(from: URL(fileURLWithPath: "/nonexistent/week.md"))
        #expect(outcome == .fileMissing)
    }
    @Test func deeperHeadingDoesNotEndSection() {
        let text = "## Goals\n- [ ] A\n### Detail\n- [ ] B\n## Other\n- [ ] C\n"
        #expect(WeekGoalsParser.parse(text: text).items.map(\.text) == ["A", "B"])
    }
    @Test func fixtureVaultWeekParses() throws {
        let vault = try makeFixtureVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let outcome = WeekGoalsParser.load(from: vault.appendingPathComponent("planning/week.md"))
        #expect(outcome.items.map(\.text) == ["Ship Phase 1", "Approve ballot", "Nested goal"])
    }
}

@Suite struct FrontmatterToleranceTests {
    @Test func unclosedFrontmatterDegradesVisibly() {
        let p = FrontmatterParser.parse("---\ntitle: X\nno closing fence\n")
        #expect(p.error != nil)
        #expect(p.body.contains("no closing fence"))
    }
    @Test func noFrontmatterIsNotePrivate() {
        let rec = VaultRecord.make(relativePath: "plain.md", parse: FrontmatterParser.parse("# Plain\n"),
                                   mtime: Date(timeIntervalSince1970: 0), contentHash: "x", sizeBytes: 7, links: [])
        #expect(rec.classification == .private)
        #expect(!rec.isLookoutVisible)
    }
    @Test func newerSchemaIsReadOnlyFlaggedNotDropped() {
        let rec = VaultRecord.make(relativePath: "future.md", parse: FrontmatterParser.parse("---\nm3ta: 2\ntitle: Future\nclassification: public\n---\n"),
                                   mtime: Date(timeIntervalSince1970: 0), contentHash: "x", sizeBytes: 10, links: [])
        #expect(rec.isNewerSchema)
        #expect(rec.issues.contains { $0.contains("newer schema") })
    }
    @Test func wrongTypeDateIsNeedsAttention() {
        let rec = VaultRecord.make(relativePath: "d.md", parse: FrontmatterParser.parse("---\ntitle: D\ndue: next Tuesday\n---\n"),
                                   mtime: Date(timeIntervalSince1970: 0), contentHash: "x", sizeBytes: 10, links: [])
        #expect(rec.needsAttention)
        #expect(rec.issues.contains { $0.contains("invalid due value") })
    }
    @Test func effectiveUpdatedUsesMaxOfFieldAndMtime() {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let rec = VaultRecord.make(relativePath: "e.md", parse: FrontmatterParser.parse("---\ntitle: E\nupdated: 2026-11-08\n---\n"),
                                   mtime: mtime, contentHash: "x", sizeBytes: 10, links: [])
        #expect(rec.effectiveUpdated > mtime)
    }
}

@Suite struct DemoGuardTests {
    @Test func demoInsideRealTreeHardRefuses() {
        #expect(throws: DemoGuardError.self) {
            try DemoGuard.verify(demoVaultPath: "/vault/real/demo-data", realVaultPath: "/vault/real")
        }
        #expect(throws: DemoGuardError.self) {
            try DemoGuard.verify(demoVaultPath: "/vault/real", realVaultPath: "/vault/real")
        }
    }
    @Test func demoSiblingTreePasses() throws {
        try DemoGuard.verify(demoVaultPath: "/vault/demo-fixtures", realVaultPath: "/vault/real")
    }
    @Test func demoSourcesAreAllOff() {
        #expect(!SourceAccess.demo.anyLiveSourceOn)
        #expect(SourceAccess.live.anyLiveSourceOn)
        let liveDir = FieldBookConfig.appDataDirectory(demo: false, base: URL(fileURLWithPath: "/tmp/fb-base"))
        let demoDir = FieldBookConfig.appDataDirectory(demo: true, base: URL(fileURLWithPath: "/tmp/fb-base"))
        #expect(liveDir != demoDir)
        #expect(FieldBookConfig.indexDirectory(demo: true, base: URL(fileURLWithPath: "/tmp/fb-base")).path.contains("demo"))
    }
}

@Suite struct FieldBookConfigTests {
    @Test func calendarAllowlistDefaultsToBusinessOnly() {
        // Default = the business calendar as titled on the Mac (2026-11-09
        // Calendar.app recon: "Th3 M3ta Way"; no calendar carries the
        // business domain in its title).
        let cfg = FieldBookConfig()
        #expect(cfg.calendarAllowed(title: "Th3 M3ta Way", sourceTitle: "Google"))
        #expect(!cfg.calendarAllowed(title: "Family", sourceTitle: "iCloud"))
        #expect(!cfg.calendarAllowed(title: "Personal", sourceTitle: "Google"))
        #expect(!cfg.calendarAllowed(title: "Builder Brokerz", sourceTitle: "Google"))
        // Empty allowlist falls back to the business-domain hint.
        let hinted = FieldBookConfig(calendarAllowlist: [])
        #expect(hinted.calendarAllowed(title: "info@th3m3taway.com", sourceTitle: "iCloud"))
        #expect(!hinted.calendarAllowed(title: "Family", sourceTitle: "iCloud"))
        let explicit = FieldBookConfig(calendarAllowlist: ["Ops"])
        #expect(explicit.calendarAllowed(title: "Ops", sourceTitle: ""))
        #expect(!explicit.calendarAllowed(title: "info@th3m3taway.com", sourceTitle: ""))
    }
    @Test func fullScreenIsDefaultPosture() {
        #expect(LaunchPosture.shouldLaunchFullScreen(environment: [:]))
        #expect(!LaunchPosture.shouldLaunchFullScreen(environment: ["CONSOLE_NO_FULLSCREEN": "1"]))
    }
}

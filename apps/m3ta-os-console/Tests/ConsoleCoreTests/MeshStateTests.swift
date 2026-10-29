import Testing
import Foundation
@testable import ConsoleCore

@Suite struct MeshStateTests {
    let s = try! MeshStateLoader.loadBundled()

    @Test func decodesStatus() {
        #expect(s.schema == 1)
        #expect(s.pluto.instanceId == "th3-m3ta-way-62da")
        #expect(s.pluto.plan == "FREE")
        #expect(s.pluto.imessage?.state == "Paired")
        #expect(s.pluto.apps.count == 6)
        #expect(s.pluto.notionHeld == true)
        #expect(s.pluto.creditsRemainingUSD == 2.22)
    }
    @Test func meshCounts() {
        #expect(s.mesh.layers.count == 5)
        #expect(s.mesh.modules.count == 11)
        #expect(s.mesh.flagships.count == 5)
        #expect(s.mesh.flagships.first { $0.name.hasPrefix("A.D.A.M") }?.status == "NOT BUILT")
        let bez = s.mesh.layers.flatMap(\.components).first { $0.name.hasPrefix("Bezalel") }
        #expect(bez?.status == "LIVE")
    }
    @Test func snapshotDateParses() {
        #expect(SnapshotAge.date(s.capturedAt) != nil)
        #expect(SnapshotAge.describe("garbage").contains("unknown"))
    }
    @Test func pairingNextActionIsDriveInstaller() {
        let st = s.pluto.pairing!.states()
        #expect(st.first { $0.1 == .next }?.0 == .installed)
        #expect(PairingStep.installed.rawValue == "Open the Drive installer")
        #expect(st.filter { $0.1 == .next }.count == 1)
    }
    @Test func unknownPairingNeverGuessed() throws {
        let json = #"{"schema":1,"capturedAt":"x","source":"t","pluto":{"instanceId":"i","apps":[],"pairing":{}},"mesh":{"layers":[],"modules":[],"flagships":[]}}"#
        let m = try MeshStateLoader.decode(Data(json.utf8))
        #expect(m.pluto.pairing!.states().allSatisfy { $0.1 == .unknown })
        #expect(m.pluto.notionHeld.tri == .unknown)
    }
    @Test func pairedWithoutVaultTestStaysUntested() {
        var p = s.pluto.pairing!; p.paired = true; p.vaultReach = nil
        #expect(p.vaultReachDisplay == "Untested")
    }
    @Test func unknownStatusRendersRaw() {
        #expect(StatusStyle("WOBBLY") == .raw)
        #expect(StatusStyle("NOT BUILT") == .notBuilt)
    }
}

import Foundation

// D16 demo-mode isolation as mechanism, not policy (§1.11):
// - demo runs against a separate container with its own index/App State
//   (see FieldBookConfig.appDataDirectory(demo:))
// - every live source is hard-off in demo (EventKit, Plaid/Stripe, CRM,
//   Orbit, QB) — synthetic equivalents only
// - a launch-time self-check HARD-REFUSES if the demo vault path resolves
//   inside the real tree

public enum DemoGuardError: Error, Equatable, Sendable {
    case demoPathInsideRealTree(demo: String, real: String)
    case demoPathEqualsRealTree(String)
}

public enum DemoGuard {
    /// Resolved (symlink-free, standardized) containment check.
    public static func verify(demoVaultPath: String, realVaultPath: String) throws {
        let demo = URL(fileURLWithPath: (demoVaultPath as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardizedFileURL.path
        let real = URL(fileURLWithPath: (realVaultPath as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardizedFileURL.path
        if demo == real { throw DemoGuardError.demoPathEqualsRealTree(demo) }
        if demo.hasPrefix(real + "/") { throw DemoGuardError.demoPathInsideRealTree(demo: demo, real: real) }
    }
}

/// Which sources a launch configuration may touch. In demo mode every
/// live source is false — the views render synthetic fixtures instead.
public struct SourceAccess: Equatable, Sendable {
    public var eventKit: Bool
    public var crm: Bool
    public var orbit: Bool
    public var qb: Bool
    public var plaidStripe: Bool

    public static let live = SourceAccess(eventKit: true, crm: true, orbit: true, qb: true, plaidStripe: true)
    public static let demo = SourceAccess(eventKit: false, crm: false, orbit: false, qb: false, plaidStripe: false)
    public var anyLiveSourceOn: Bool { eventKit || crm || orbit || qb || plaidStripe }
}

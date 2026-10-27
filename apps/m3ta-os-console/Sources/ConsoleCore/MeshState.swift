import Foundation

/// Codable snapshot of the M3ta-OS mesh and the Pluto instance.
/// Every field that might be missing is optional so a missing value renders as "unknown".
public struct MeshState: Codable, Sendable {
    public var schema: Int
    public var capturedAt: String
    public var source: String
    public var pluto: Pluto
    public var mesh: Mesh

    public struct Pluto: Codable, Sendable {
        public var instanceId: String
        public var instanceName: String?
        public var plan: String?
        public var deployment: String?
        public var model: String?
        public var inbox: String?
        public var creditsRemainingUSD: Double?
        public var creditsRefillDate: String?
        public var notionHeld: Bool?
        public var notionNote: String?
        public var testTextWart: String?
        public var apps: [App]
        public var imessage: IMessage?
        public var pairing: Pairing?
    }
    public struct App: Codable, Sendable, Identifiable {
        public var name: String
        public var account: String?
        public var state: String?
        public var id: String { name }
    }
    public struct IMessage: Codable, Sendable {
        public var state: String?
        public var featuresOn: String?
        public var servicesReady: String?
        public var loopVerified: String?
    }
    public struct Pairing: Codable, Sendable {
        public var app: String?
        public var installerStaged: Bool?
        public var installed: Bool?
        public var launched: Bool?
        public var connectWindowOpen: Bool?
        public var paired: Bool?
        public var permissions: [String: String]?
        public var vaultReach: String?
        public var installerLocation: String?
    }
    public struct Mesh: Codable, Sendable {
        public var layers: [Layer]
        public var modules: [Item]
        public var flagships: [Item]
        public var mvpDeclared: String?
        public var relay: Relay?
    }
    public struct Layer: Codable, Sendable, Identifiable {
        public var name: String
        public var components: [Item]
        public var id: String { name }
    }
    public struct Item: Codable, Sendable, Identifiable {
        public var name: String
        public var status: String
        public var note: String?
        public var id: String { name }
        public init(name: String, status: String, note: String? = nil) { self.name = name; self.status = status; self.note = note }
    }
    public struct Relay: Codable, Sendable {
        public var name: String
        public var status: String
        public var evidence: String?
    }
}

public enum MeshStateLoader {
    public static var bundledFixtureURL: URL? {
        Bundle.module.url(forResource: "mesh-state-2026-10-26", withExtension: "json")
    }
    public static func decode(_ data: Data) throws -> MeshState {
        try JSONDecoder().decode(MeshState.self, from: data)
    }
    public static func load(from url: URL) throws -> MeshState {
        try decode(Data(contentsOf: url))
    }
    public static func loadBundled() throws -> MeshState {
        guard let url = bundledFixtureURL else { throw CocoaError(.fileNoSuchFile) }
        return try load(from: url)
    }
}

/// Tri-state: never guess. nil means unknown.
public enum Tri: String, Sendable { case yes = "Yes", no = "No", unknown = "Unknown" }
public extension Optional where Wrapped == Bool {
    var tri: Tri { switch self { case .some(true): .yes; case .some(false): .no; case .none: .unknown } }
}

public enum PairingStep: String, CaseIterable, Sendable {
    case installerStaged = "Installer staged in Drive"
    case installed = "Open the Drive installer"
    case launched = "Launch Ruth Local"
    case connectWindowOpen = "Connect (10-minute window)"
    case paired = "Paired"
    case permissionsGranted = "Grant Accessibility + Screen Recording"

    public enum State: Sendable, Equatable { case done, next, pending, unknown }
}

public extension MeshState.Pairing {
    /// Raw known value per step; nil = unknown (never guessed).
    func value(for step: PairingStep) -> Bool? {
        switch step {
        case .installerStaged: return installerStaged
        case .installed: return installed
        case .launched: return launched
        case .connectWindowOpen: return paired // the Connect step is done only when pairing is recorded
        case .paired: return paired
        case .permissionsGranted:
            guard let p = permissions, !p.isEmpty else { return nil }
            return p.values.allSatisfy { $0.lowercased() == "granted" }
        }
    }
    /// The first incomplete step is the next action; earlier unknowns stay unknown.
    func states() -> [(PairingStep, PairingStep.State)] {
        var foundNext = false
        return PairingStep.allCases.map { step in
            let v = value(for: step)
            if foundNext { return (step, .pending) }
            switch v {
            case .some(true): return (step, .done)
            case .some(false): foundNext = true; return (step, .next)
            case .none: return (step, .unknown)
            }
        }
    }
    /// Vault reach stays "Untested" unless a test result string says otherwise.
    var vaultReachDisplay: String { vaultReach ?? "Untested" }
}

public enum SnapshotAge {
    public static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    public static func describe(_ s: String, now: Date = Date()) -> String {
        guard let d = date(s) else { return "Snapshot age unknown (capturedAt \(s))" }
        let r = RelativeDateTimeFormatter(); r.unitsStyle = .full
        return "Snapshot \(r.localizedString(for: d, relativeTo: now)) (captured \(s))"
    }
}

/// Known statuses map to a style key; anything else renders raw with neutral style.
public enum StatusStyle: String, Sendable {
    case live, built, partial, notBuilt, retired, raw
    public init(_ s: String) {
        switch s.uppercased() {
        case "LIVE": self = .live
        case "BUILT": self = .built
        case "PARTIAL": self = .partial
        case "NOT BUILT": self = .notBuilt
        case "RETIRED": self = .retired
        default: self = .raw
        }
    }
}

import Foundation
import Darwin
import Security
import CryptoKit
import ConsoleCore

// ConsoleCoreService — §4.4 boundary service (Shape A1).
// Transport: HTTP/1.1 semantics over a Unix domain socket (POSIX sockets,
// Foundation only — no third-party code, no new TCP port).
//   ~/Library/Application Support/M3taOS/ConsoleCore/boundary.sock
//   directory 0700, socket 0600, peer-UID verified on every connection.
// Auth: per-install 256-bit boundary secret, macOS Keychain, bearer on
// every request. CRM_API_TOKEN exists only in this process's environment
// (CRMConfig.current) — it never crosses the boundary in either direction.

let serviceName = "com.m3ta.consolecore-service"
let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/M3taOS/ConsoleCore")
let socketPath = supportDir.appendingPathComponent("boundary.sock").path
let configURL = supportDir.appendingPathComponent("service-config.json")
let auditURL = supportDir.appendingPathComponent("audit.log")
let snapshotsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/M3taOS/snapshots")
let startedAt = Date()

// MARK: - Keychain boundary secret

enum BoundarySecret {
    static let service = "com.m3ta.consolecore.boundary"
    static let account = "boundary-secret"

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /// Store the secret in the login Keychain. ACL posture: the item is
    /// created WITHOUT a custom SecAccess, so the platform-default ACL
    /// applies — the creating identity (this service binary's signature)
    /// is trusted silently; any other identity (the shell) gets the
    /// standard Keychain confirmation, and §4.4's re-issue recovery
    /// (re-review N5) covers signing-identity changes. NOTE (step-2
    /// finding): a custom SecAccess built from SecTrustedApplication
    /// path refs silently poisoned read-back on this OS (macOS 27) —
    /// SecItemAdd succeeded but every later SecItemCopyMatching failed,
    /// so each process generated a different secret. Default ACL verified
    /// working; custom-ACL is a documented deviation with reason.
    static func store(_ secret: String) {
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: Data(secret.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
            status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: Data(secret.utf8)] as CFDictionary)
        }
        if status != errSecSuccess {
            FileHandle.standardError.write(Data("ConsoleCoreService: keychain store failed, OSStatus \(status)\n".utf8))
        } else if load() != secret {
            FileHandle.standardError.write(Data("ConsoleCoreService: keychain verify-after-store failed\n".utf8))
        }
    }

    static func loadOrGenerate() -> String {
        if let s = load(), !s.isEmpty { return s }
        var bytes = [UInt8](repeating: 0, count: 32)  // 256-bit
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        store(secret)
        return secret
    }
}

let operatorFlags = ["--print-boundary-secret", "--healthcheck", "--writegate-phase1", "--writegate-phase2", "--snapshotcheck"]
let isOperatorMode = CommandLine.arguments.contains(where: { operatorFlags.contains($0) })

let boundarySecret: String = {
    if isOperatorMode {
        // Operator modes NEVER generate: a failed Keychain load (wrong
        // session context) must fail closed, not mint a divergent secret.
        guard let s = BoundarySecret.load(), !s.isEmpty else {
            FileHandle.standardError.write(Data("ConsoleCoreService: boundary secret not readable from Keychain in this session context (run inside the GUI session, e.g. via the one-shot LaunchAgent or a local Terminal)\n".utf8))
            exit(3)
        }
        return s
    }
    return BoundarySecret.loadOrGenerate()
}()

// MARK: - Operator client modes (native socket client; secret never printed)

func apicall(method: String, path: String, body: Data? = nil, headers: [String: String] = [:], withAuth: Bool = true) -> (Int, String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return (-1, "socket() failed") }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pb = Array(socketPath.utf8)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pb.count + 1) { dst in
            for (i, b) in pb.enumerated() { dst[i] = CChar(bitPattern: b) }
            dst[pb.count] = 0
        }
    }
    let rc = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard rc == 0 else { close(fd); return (-1, "connect() failed errno=\(errno)") }
    var head = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
    if withAuth { head += "Authorization: Bearer \(boundarySecret)\r\n" }
    for (k, v) in headers { head += "\(k): \(v)\r\n" }
    if let body { head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n" }
    head += "\r\n"
    var req = Data(head.utf8)
    if let body { req.append(body) }
    req.withUnsafeBytes { _ = send(fd, $0.baseAddress, req.count, 0) }
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = recv(fd, &buf, buf.count, 0)
        if n <= 0 { break }
        out.append(contentsOf: buf[0..<n])
    }
    close(fd)
    let text = String(decoding: out, as: UTF8.self)
    let status = Int(text.split(separator: " ").dropFirst().first.map(String.init) ?? "") ?? -1
    let parts = text.components(separatedBy: "\r\n\r\n")
    return (status, parts.dropFirst().joined(separator: "\r\n\r\n"))
}

func opPrint(_ label: String, _ r: (Int, String), limit: Int = 700) {
    // Unbuffered write: print() buffers when stdout is a file and a
    // launchd SIGTERM would discard the proof output.
    FileHandle.standardOutput.write(Data("\(label) -> HTTP \(r.0): \(String(r.1.prefix(limit)))\n".utf8))
}

if CommandLine.arguments.contains("--print-boundary-secret") {
    FileHandle.standardOutput.write(Data(boundarySecret.utf8))
    exit(0)
}

if CommandLine.arguments.contains("--healthcheck") {
    opPrint("GET /health (no auth, expect 401)", apicall(method: "GET", path: "/health", withAuth: false))
    opPrint("GET /health", apicall(method: "GET", path: "/health"))
    for surface in BoundaryProviders.surfaces {
        opPrint("GET /v1/state/\(surface)", apicall(method: "GET", path: "/v1/state/\(surface)"), limit: 450)
    }
    opPrint("GET /v1/state/nope (expect 404)", apicall(method: "GET", path: "/v1/state/nope"))
    opPrint("POST /v1/nonces (expect 404, no mint path)", apicall(method: "POST", path: "/v1/nonces", body: Data("{}".utf8)))
    exit(0)
}

if CommandLine.arguments.contains("--snapshotcheck") {
    for surface in ["command", "agents"] {
        let r = apicall(method: "GET", path: "/v1/state/\(surface)")
        var summary: [String: Any] = ["http": r.0]
        if let obj = try? JSONSerialization.jsonObject(with: Data(r.1.utf8)) as? [String: Any] {
            summary["face"] = obj["face"] ?? ""
            if let src = obj["source"] as? [String: Any] { summary["capturedAt"] = src["capturedAt"] ?? "" }
            if let err = obj["error"] as? [String: Any] { summary["errorCode"] = err["code"] ?? "" }
        }
        FileHandle.standardOutput.write(Data("\(surface): \(CanonicalJSON.string(summary))\n".utf8))
    }
    exit(0)
}

if CommandLine.arguments.contains("--writegate-phase1") {
    // Writes still disabled by operator config: even a valid nonce must fail.
    let payload: [String: Any] = ["message": "phase1"]
    let nonce = BoundaryNonce.mint(secret: boundarySecret, action: "ping-write", payloadHash: BoundaryNonce.payloadHash(payload))
    let r = apicall(method: "POST", path: "/v1/actions/ping-write", body: CanonicalJSON.data(payload),
                    headers: ["x-agent-id": "step2-selftest", "x-boundary-nonce": nonce])
    opPrint("phase1 ping-write with valid nonce, writes disabled (expect 403 writes_disabled)", r)
    exit(0)
}

if CommandLine.arguments.contains("--writegate-phase2") {
    // Operator has set writesEnabled=true between phases.
    let payload: [String: Any] = ["message": "phase2"]
    let hash = BoundaryNonce.payloadHash(payload)
    let nonce = BoundaryNonce.mint(secret: boundarySecret, action: "ping-write", payloadHash: hash)
    let hdrs = ["x-agent-id": "step2-selftest", "x-boundary-nonce": nonce]
    opPrint("phase2 ping-write (expect 200 pong)", apicall(method: "POST", path: "/v1/actions/ping-write", body: CanonicalJSON.data(payload), headers: hdrs))
    opPrint("phase2 ping-write nonce REUSE (expect 400 nonce_reused)", apicall(method: "POST", path: "/v1/actions/ping-write", body: CanonicalJSON.data(payload), headers: hdrs))
    let payloadB: [String: Any] = ["message": "tampered"]
    opPrint("phase2 ping-write HASH MISMATCH (expect 400 nonce_hashMismatch)", apicall(method: "POST", path: "/v1/actions/ping-write", body: CanonicalJSON.data(payloadB), headers: hdrs.merging(["x-boundary-nonce": BoundaryNonce.mint(secret: boundarySecret, action: "ping-write", payloadHash: hash)]) { $1 }))
    let vpayload: [String: Any] = ["text": "Boundary voice test."]
    let vnonce = BoundaryNonce.mint(secret: boundarySecret, action: "voice-test", payloadHash: BoundaryNonce.payloadHash(vpayload))
    opPrint("phase2 voice-test brokered (expect 200 or shaped broker error)", apicall(method: "POST", path: "/v1/actions/voice-test", body: CanonicalJSON.data(vpayload), headers: ["x-agent-id": "step2-selftest", "x-boundary-nonce": vnonce]), limit: 600)
    exit(0)
}

// MARK: - Shared state

let store = SnapshotStore()
let folderLock = NSLock()
nonisolated(unsafe) var folder = AGUIFolder()
let nonceLock = NSLock()
nonisolated(unsafe) var usedNonces: Set<String> = []
let sseLock = NSLock()
nonisolated(unsafe) var sseClients: Set<Int32> = []

func consumeNonce(_ n: String) -> Bool {
    nonceLock.lock(); defer { nonceLock.unlock() }
    if usedNonces.contains(n) { return false }
    usedNonces.insert(n); return true
}

func audit(action: String, agentId: String, result: String, code: String, payloadHash: String?) {
    var line: [String: Any] = ["ts": BoundaryEnvelope.iso(Date()), "action": action,
                               "agentId": agentId, "result": result, "code": code]
    if let h = payloadHash { line["payloadHash"] = h }
    let data = CanonicalJSON.data(line) + Data("\n".utf8)
    if let fh = try? FileHandle(forWritingTo: auditURL) {
        fh.seekToEndOfFile(); fh.write(data); try? fh.close()
    } else {
        try? data.write(to: auditURL)
    }
}

func buildHash() -> String {
    guard let exe = Bundle.main.executablePath, let d = try? Data(contentsOf: URL(fileURLWithPath: exe)) else { return "unknown" }
    return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(12).uppercased()
}

// MARK: - Snapshot seed + watcher

func seedBundled() {
    // ConsoleCore's bundled resources, addressed through its own loaders.
    if let u = DashboardStateLoader.bundledFixtureURL, let d = try? Data(contentsOf: u),
       let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        let env: [String: Any] = ["schemaName": "dashboard-state", "schemaVersion": "1.0",
                                  "capturedAt": (p["capturedAt"] as? String) ?? "",
                                  "producerVersion": "bundled-seed", "payload": p]
        store.ingest(CanonicalJSON.data(env))
    }
    if let u = MeshStateLoader.bundledFixtureURL, let d = try? Data(contentsOf: u),
       let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        let env: [String: Any] = ["schemaName": "mesh-state", "schemaVersion": "1.0",
                                  "capturedAt": (p["capturedAt"] as? String) ?? "",
                                  "producerVersion": "bundled-seed", "payload": p]
        store.ingest(CanonicalJSON.data(env))
    }
    if let u = BotMapLoader.bundledFixtureURL, let d = try? Data(contentsOf: u),
       let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        // Bot-map's bundled file carries `generated: "2026-10-27"` (date only).
        let gen = (p["generated"] as? String) ?? ""
        let cap = gen.count == 10 ? gen + "T00:00:00Z" : gen
        let env: [String: Any] = ["schemaName": "bot-map", "schemaVersion": "1.0",
                                  "capturedAt": cap, "producerVersion": "bundled-seed", "payload": p]
        store.ingest(CanonicalJSON.data(env))
    }
}

nonisolated(unsafe) var seenFiles: [String: String] = [:]
func pollSnapshots() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    for f in files where f.pathExtension == "json" {
        let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { "\($0.timeIntervalSince1970)" } ?? ""
        if seenFiles[f.path] == mod { continue }
        seenFiles[f.path] = mod
        if let d = try? Data(contentsOf: f) { store.ingest(d) }
    }
}

// MARK: - HTTP plumbing (POSIX)

struct HTTPRequest {
    var method: String; var path: String; var headers: [String: String]; var body: Data
}

func readRequest(_ fd: Int32) -> HTTPRequest? {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 8192)
    // Read until header terminator.
    while data.count < 65536 {
        let n = recv(fd, &buf, buf.count, 0)
        if n <= 0 { return nil }
        data.append(contentsOf: buf[0..<n])
        if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
    }
    guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: data[data.startIndex..<sep.lowerBound], as: UTF8.self)
    var body = Data(data[sep.upperBound...])
    let lines = head.components(separatedBy: "\r\n")
    guard let first = lines.first else { return nil }
    let parts = first.split(separator: " ").map(String.init)
    guard parts.count >= 2 else { return nil }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        if let c = line.firstIndex(of: ":") {
            headers[line[line.startIndex..<c].lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
    }
    let contentLength = Int(headers["content-length"] ?? "0") ?? 0
    while body.count < contentLength && body.count < 1_048_576 {
        let n = recv(fd, &buf, buf.count, 0)
        if n <= 0 { break }
        body.append(contentsOf: buf[0..<n])
    }
    return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
}

func sendJSON(_ fd: Int32, status: Int, object: Any) {
    let body = CanonicalJSON.data(object)
    let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 502: "Bad Gateway", 503: "Service Unavailable"][status] ?? "OK"
    let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    var out = Data(head.utf8); out.append(body)
    out.withUnsafeBytes { _ = send(fd, $0.baseAddress, out.count, 0) }
}

func errorObject(_ e: BoundaryError) -> [String: Any] { ["error": e.jsonObject] }

final class EnvelopeBox: @unchecked Sendable { var value: [String: Any]? }
final class StringBox: @unchecked Sendable { var value: String? }
final class VoiceSpeakBox: @unchecked Sendable { var status: Int?; var respBody: [String: Any]?; var transport: String? }
nonisolated func fetchState(surface: String, store: SnapshotStore) -> [String: Any]? {
    let sem = DispatchSemaphore(value: 0)
    let box = EnvelopeBox()
    Task.detached { box.value = await BoundaryProviders.state(surface: surface, store: store); sem.signal() }
    sem.wait()
    return box.value
}

// MARK: - Voice broker (§5.5, boundary-routed per ballot-time N4 reversal)

/// Resolve the VoiceBox profile for this client from the MCP bindings
/// table (GET /mcp/bindings): the binding is how Hermes resolves its
/// voice, and the boundary brokers the same way. REST /speak does not
/// resolve bindings from a header (verified live 2026-11-06: header-only
/// calls answer 400 "No voice profile resolved").
func voiceboxBoundProfile() -> String? {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:17493/mcp/bindings")!, timeoutInterval: 3)
    req.httpMethod = "GET"
    let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForRequest = 3; cfg.connectionProxyDictionary = [:]
    let found = StringBox()
    let sem = DispatchSemaphore(value: 0)
    URLSession(configuration: cfg).dataTask(with: req) { data, _, _ in
        if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = j["items"] as? [[String: Any]] {
            found.value = items.first(where: { ($0["client_id"] as? String) == "m3ta-os-console" })?["profile_id"] as? String
        }
        sem.signal()
    }.resume()
    sem.wait()
    return found.value
}

func voiceSpeak(payload: [String: Any]) -> (Int, [String: Any]) {
    let text = payload["text"] as? String ?? ""
    var body: [String: Any] = ["text": text]
    if let p = payload["profile"] as? String { body["profile"] = p }
    else if let bound = voiceboxBoundProfile() { body["profile"] = bound }
    var req = URLRequest(url: URL(string: "http://127.0.0.1:17493/speak")!, timeoutInterval: 60)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue("m3ta-os-console", forHTTPHeaderField: "x-client-id")
    req.httpBody = CanonicalJSON.data(body)
    let cfg = URLSessionConfiguration.ephemeral; cfg.timeoutIntervalForRequest = 60; cfg.connectionProxyDictionary = [:]
    let box = VoiceSpeakBox()
    let sem = DispatchSemaphore(value: 0)
    URLSession(configuration: cfg).dataTask(with: req) { data, resp, err in
        box.status = (resp as? HTTPURLResponse)?.statusCode
        if let data { box.respBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
        if let err { box.transport = err.localizedDescription }
        sem.signal()
    }.resume()
    sem.wait()
    let status = box.status; let respBody = box.respBody; let transport = box.transport
    if let status, status == 200 {
        return (200, ["schemaVersion": "v1", "action": "voice-speak", "ok": true,
                      "result": ["broker": "voicebox", "route": "POST 127.0.0.1:17493/speak", "response": respBody ?? [String: Any]()]])
    }
    if let status {
        return (502, ["schemaVersion": "v1", "action": "voice-speak", "ok": false,
                      "error": BoundaryError(code: "voicebox_http_\(status)", message: "VoiceBox /speak answered HTTP \(status)", retryable: status >= 500, sourceStatus: status).jsonObject])
    }
    return (503, ["schemaVersion": "v1", "action": "voice-speak", "ok": false,
                  "error": BoundaryError(code: "voicebox_offline", message: "VoiceBox broker call failed: \(transport ?? "unknown")", retryable: true).jsonObject])
}

// MARK: - Routing

func broadcastFold() {
    folderLock.lock(); let obj = folder.canonicalObject; folderLock.unlock()
    let env = BoundaryEnvelope.make(surface: "events", face: .live, data: obj, sourceKind: "ag-ui-fold", checkedAt: Date())
    let line = "data: \(CanonicalJSON.string(env))\n\n"
    sseLock.lock(); let clients = sseClients; sseLock.unlock()
    for fd in clients { _ = line.withCString { send(fd, $0, strlen($0), 0) } }
}

func handle(_ fd: Int32, _ req: HTTPRequest) {
    // Peer-UID verification.
    var uid = uid_t(0); var gid = gid_t(0)
    guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
        sendJSON(fd, status: 403, object: errorObject(BoundaryError(code: "peer_uid_mismatch", message: "Peer UID is not the service user", retryable: false)))
        return
    }
    // Boundary auth on EVERY request.
    guard req.headers["authorization"] == "Bearer \(boundarySecret)" else {
        sendJSON(fd, status: 401, object: errorObject(BoundaryError(code: "unauthorized", message: "Missing or invalid boundary bearer secret", retryable: false)))
        return
    }
    let path = req.path.split(separator: "?").first.map(String.init) ?? req.path

    if req.method == "GET" && path == "/health" {
        let cfg = ServiceConfig.load(from: configURL)
        sendJSON(fd, status: 200, object: ["serviceVersion": BoundarySchema.serviceVersion,
                                           "schemaVersions": BoundarySchema.supported,
                                           "buildHash": buildHash(),
                                           "uptimeSeconds": Int(Date().timeIntervalSince(startedAt)),
                                           "writesEnabled": cfg.writesEnabled,
                                           "schemaVersion": "v1"])
        return
    }
    if req.method == "GET" && path.hasPrefix("/v1/state/") {
        let surface = String(path.dropFirst("/v1/state/".count))
        if let env = fetchState(surface: surface, store: store) {
            sendJSON(fd, status: 200, object: env)
        } else {
            sendJSON(fd, status: 404, object: errorObject(BoundaryError(code: "unknown_surface", message: "Unknown surface: \(surface)", retryable: false)))
        }
        return
    }
    if req.method == "GET" && path == "/v1/events" {
        // SSE: folded AG-UI state. Stays open; handled by caller (no close).
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        _ = head.withCString { send(fd, $0, strlen($0), 0) }
        sseLock.lock(); sseClients.insert(fd); sseLock.unlock()
        broadcastFold()
        // Keep the connection parked; heartbeats come from the timer in main.
        while true {
            var b: UInt8 = 0
            let n = recv(fd, &b, 1, 0)
            if n <= 0 { break }
        }
        sseLock.lock(); sseClients.remove(fd); sseLock.unlock()
        return
    }
    if req.method == "POST" && path == "/v1/events" {
        // Fold ingest seam: the boundary owns the canonical fold (§4.4);
        // AG-UI events arrive here and fold service-side. Bearer-auth only —
        // this writes in-memory fold state, never a system of record.
        guard let events = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any])?["events"] as? [[String: Any]] else {
            sendJSON(fd, status: 400, object: errorObject(BoundaryError(code: "schema_invalid", message: "Body must be { events: [AG-UI event objects] }", retryable: false)))
            return
        }
        folderLock.lock()
        for raw in events { if let e = AGUIEvent.parse(json: raw) { folder.fold(e) } }
        let obj = folder.canonicalObject
        folderLock.unlock()
        broadcastFold()
        sendJSON(fd, status: 200, object: ["schemaVersion": "v1", "folded": obj])
        return
    }
    if req.method == "POST" && path.hasPrefix("/v1/actions/") {
        let action = String(path.dropFirst("/v1/actions/".count))
        let agentId = req.headers["x-agent-id"] ?? ""
        let payload = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [String: Any]()
        let hash = BoundaryNonce.payloadHash(payload)
        let cfg = ServiceConfig.load(from: configURL)
        // Gate order: writesEnabled -> nonce -> schema.
        var nonceResult: BoundaryNonce.VerifyResult? = nil
        if cfg.writesEnabled {
            if let nonce = req.headers["x-boundary-nonce"] {
                nonceResult = BoundaryNonce.verify(secret: boundarySecret, nonce: nonce, action: action, payloadHash: hash, consume: consumeNonce)
            } else { nonceResult = .malformed }
        }
        let schemaError = ActionSchema.validate(action: action, payload: payload)
        let decision = WriteGate.decide(config: cfg, nonceResult: nonceResult, schemaError: schemaError)
        guard decision == .allowed else {
            let e = WriteGate.error(for: decision)
            audit(action: action, agentId: agentId, result: "denied", code: e.code, payloadHash: hash)
            sendJSON(fd, status: decision == .writesDisabled ? 403 : 400, object: ["schemaVersion": "v1", "action": action, "ok": false, "error": e.jsonObject])
            return
        }
        guard !agentId.isEmpty else {
            sendJSON(fd, status: 400, object: errorObject(BoundaryError(code: "missing_agent_id", message: "x-agent-id header is required for writes", retryable: false)))
            return
        }
        switch action {
        case "ping-write":
            audit(action: action, agentId: agentId, result: "ok", code: "ok", payloadHash: hash)
            sendJSON(fd, status: 200, object: ["schemaVersion": "v1", "action": action, "ok": true, "result": ["pong": true]])
        case "voice-speak", "voice-test":
            let (status, obj) = voiceSpeak(payload: payload)
            audit(action: action, agentId: agentId, result: status == 200 ? "ok" : "broker_error", code: status == 200 ? "ok" : "voicebox", payloadHash: hash)
            sendJSON(fd, status: status, object: obj)
        default:
            sendJSON(fd, status: 404, object: errorObject(BoundaryError(code: "unknown_action", message: "Unknown action: \(action)", retryable: false)))
        }
        return
    }
    // No nonce-mint route exists — by design (see BoundaryGate).
    sendJSON(fd, status: 404, object: errorObject(BoundaryError(code: "not_found", message: "No such route: \(req.method) \(path)", retryable: false)))
}

// MARK: - Boot

signal(SIGPIPE, SIG_IGN)
try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
chmod(supportDir.path, 0o700)
seedBundled()
pollSnapshots()
DispatchQueue.global().async {
    while true { Thread.sleep(forTimeInterval: 2); pollSnapshots() }
}
DispatchQueue.global().async {
    while true {
        Thread.sleep(forTimeInterval: 15)
        sseLock.lock(); let clients = sseClients; sseLock.unlock()
        for fd in clients { _ = ": hb\n\n".withCString { send(fd, $0, strlen($0), 0) } }
    }
}

unlink(socketPath)
let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
precondition(serverFD >= 0, "socket() failed")
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
precondition(pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path), "socket path too long")
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
        for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
        dst[pathBytes.count] = 0
    }
}
let bindResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
precondition(bindResult == 0, "bind() failed errno=\(errno)")
chmod(socketPath, 0o600)
precondition(listen(serverFD, 64) == 0, "listen() failed")
FileHandle.standardError.write(Data("ConsoleCoreService listening on \(socketPath)\n".utf8))

while true {
    let client = accept(serverFD, nil, nil)
    if client < 0 { continue }
    DispatchQueue.global().async {
        if let req = readRequest(client) { handle(client, req) }
        close(client)
    }
}

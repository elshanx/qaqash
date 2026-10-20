import CryptoKit
import Foundation
import Network
import Security

struct PhoneKeys {
    var token: String
    var certificate: String
    var privateKey: String
    var pin: String
}

final class Phone {
    static let port: UInt16 = 47832
    private static let keptEvents = 200
    private let condition = NSCondition()
    private var seq = 0
    private var events: [JSON] = []
    private var asks: [Int: JSON] = [:]
    private var sessions: [String: JSON] = [:]
    private var pairing = false
    private var keys: PhoneKeys?
    private var server: HTTPServer?

    func start() {
        DispatchQueue.global().async { [self] in
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("dev.elshanx.qaqash")
            let file = folder.appendingPathComponent("phone.json")
            guard let keys = Self.load(file) ?? Self.create(file, folder: folder), let identity = Self.identity(keys), let secIdentity = sec_identity_create(identity) else { return }
            condition.withLock { self.keys = keys }
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            let name = localHostName()
            let service = NWListener.Service(name: name, type: "_qaqash._tcp", domain: "local", txtRecord: NWTXTRecord(["host": "\(name).local"]))
            server = try? HTTPServer(port: Self.port, parameters: NWParameters(tls: tls), service: service) { [self] in handle($0, token: keys.token) }
        }
    }

    private func publish(_ kind: String, _ data: Any) {
        seq += 1
        events.append(["seq": seq, "kind": kind, "data": data])
        if events.count > Self.keptEvents { events.removeFirst() }
        condition.broadcast()
    }

    func askOpened(_ ask: JSON) {
        guard let id = ask["id"] as? Int else { return }
        condition.withLock {
            asks[id] = ask
            publish("ask", ask)
        }
    }

    func askClosed(_ id: Int) {
        condition.withLock {
            if asks.removeValue(forKey: id) != nil { publish("resolved", ["id": id]) }
        }
    }

    func status(_ event: JSON) {
        condition.withLock {
            if let session = event["session_id"] as? String, event["transcript_path"] is String {
                sessions[session] = event["hook_event_name"] as? String == "SessionEnd" ? nil : event
            }
            publish("status", event)
        }
    }

    private func snapshot() -> JSON {
        condition.withLock {
            ["seq": seq, "asks": asks.sorted { $0.key < $1.key }.map(\.value), "sessions": sessions.sorted { $0.key < $1.key }.map(\.value)]
        }
    }

    private func events(after: Int) -> JSON {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(25)
        while seq <= after && condition.wait(until: deadline) {}
        let oldest = events.first?["seq"] as? Int ?? seq + 1
        if after + 1 < oldest && after < seq { return ["seq": seq, "reset": true, "events": []] }
        return ["seq": seq, "events": events.filter { $0["seq"] as? Int ?? 0 > after }]
    }

    private func handle(_ request: Request, token: String) -> Response {
        if request.method == "POST" && request.path == "/pair" { return pair(request) }
        let given = Array((request.headers["authorization"] ?? "").utf8)
        let expected = Array("Bearer \(token)".utf8)
        guard given.count == expected.count, zip(given, expected).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else {
            return Response(status: 401, body: jsonData(["error": "not paired"]))
        }
        switch (request.method, request.path) {
        case ("GET", "/state"):
            return Response(body: jsonData(snapshot()))
        case ("GET", "/events"):
            let after = request.query.hasPrefix("after=") ? Int(request.query.dropFirst(6)) ?? 0 : 0
            return Response(body: jsonData(events(after: after)))
        case ("POST", "/decide"):
            let decision = (try? JSONSerialization.jsonObject(with: request.body)) as? JSON ?? [:]
            guard let id = decision["id"] as? Int else { return Response(status: 400, body: jsonData(["error": "missing id"])) }
            pending.resolve(id, decision["answer"] ?? NSNull())
            return Response(body: jsonData(["ok": true]))
        default:
            return Response(status: 404, body: jsonData(["error": "not found"]))
        }
    }

    private func pair(_ request: Request) -> Response {
        let busy = condition.withLock {
            defer { pairing = true }
            return pairing
        }
        if busy { return Response(status: 429, body: jsonData(["error": "already pairing"])) }
        defer { condition.withLock { pairing = false } }
        guard let keys = condition.withLock({ keys }) else { return Response(status: 503, body: jsonData(["error": "not ready"])) }
        let asked = (try? JSONSerialization.jsonObject(with: request.body)) as? JSON ?? [:]
        let device = String((asked["device"] as? String ?? "iPhone").prefix(40))
        let answer = pending.wait(kind: "pair", event: ["device": device, "code": Self.pairCode(keys.pin)], timeout: 60)
        guard answer as? Bool == true else { return Response(status: 403, body: jsonData(["error": "declined"])) }
        let name = localHostName()
        return Response(body: jsonData(["token": keys.token, "name": name, "host": "\(name).local"]))
    }

    static func pairCode(_ pin: String) -> String {
        String(format: "%04d", (UInt32(pin.prefix(8), radix: 16) ?? 0) % 10_000)
    }

    func pairingText() -> String? {
        guard let keys = condition.withLock({ keys }) else { return nil }
        let name = localHostName()
        return json(["v": 1, "host": "\(name).local", "name": name, "ip": run("/usr/sbin/ipconfig", ["getifaddr", "en0"]) ?? "", "port": Int(Self.port), "token": keys.token, "pin": keys.pin])
    }

    private static func load(_ file: URL) -> PhoneKeys? {
        guard let data = try? Data(contentsOf: file), let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let token = saved["token"], let certificate = saved["certificate"], let privateKey = saved["private_key"], let pin = saved["pin"] else { return nil }
        return PhoneKeys(token: token, certificate: certificate, privateKey: privateKey, pin: pin)
    }

    private static func create(_ file: URL, folder: URL) -> PhoneKeys? {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let key = scratch.appendingPathComponent("key.pem")
        let cert = scratch.appendingPathComponent("cert.pem")
        let name = localHostName()
        let made = run("/usr/bin/openssl", ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-days", "3650", "-subj", "/CN=qaqash",
                                            "-addext", "subjectAltName=DNS:\(name).local,DNS:qaqash.local", "-keyout", key.path, "-out", cert.path])
        var token = [UInt8](repeating: 0, count: 32)
        guard made != nil, let certificate = try? String(contentsOf: cert, encoding: .utf8), let privateKey = try? String(contentsOf: key, encoding: .utf8),
              let der = der(certificate), SecRandomCopyBytes(kSecRandomDefault, token.count, &token) == errSecSuccess else { return nil }
        let keys = PhoneKeys(token: hex(token), certificate: certificate, privateKey: privateKey, pin: hex(Array(SHA256.hash(data: der))))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved = jsonData(["token": keys.token, "certificate": keys.certificate, "private_key": keys.privateKey, "pin": keys.pin])
        FileManager.default.createFile(atPath: file.path, contents: saved, attributes: [.posixPermissions: 0o600])
        return keys
    }

    private static func identity(_ keys: PhoneKeys) -> SecIdentity? {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let key = scratch.appendingPathComponent("key.pem")
        let cert = scratch.appendingPathComponent("cert.pem")
        let bundle = scratch.appendingPathComponent("id.p12")
        FileManager.default.createFile(atPath: key.path, contents: Data(keys.privateKey.utf8), attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: cert.path, contents: Data(keys.certificate.utf8))
        guard run("/usr/bin/openssl", ["pkcs12", "-export", "-inkey", key.path, "-in", cert.path, "-passout", "pass:qaqash", "-out", bundle.path]) != nil,
              let data = try? Data(contentsOf: bundle) else { return nil }
        var items: CFArray?
        let options = [kSecImportExportPassphrase: "qaqash", kSecImportToMemoryOnly: true] as CFDictionary
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first, let identity = first[kSecImportItemIdentity as String] else { return nil }
        return (identity as! SecIdentity)
    }

    private static func der(_ pem: String) -> Data? {
        Data(base64Encoded: pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined())
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

let phone = Phone()

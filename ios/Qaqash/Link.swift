import CryptoKit
import Foundation

struct Ask: Identifiable, Equatable {
    var id: Int
    var kind: String
    var event: [String: Any]

    static func == (left: Ask, right: Ask) -> Bool { left.id == right.id }

    init?(_ json: [String: Any]) {
        guard let id = json["id"] as? Int, let kind = json["kind"] as? String else { return nil }
        self.id = id
        self.kind = kind
        self.event = json["event"] as? [String: Any] ?? [:]
    }
}

final class PinnedTrust: NSObject, URLSessionDelegate {
    let pin: String

    init(pin: String) { self.pin = pin }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        if digest == pin {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

struct Link {
    let pairing: Pairing
    let session: URLSession

    init(_ pairing: Pairing) {
        self.pairing = pairing
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        session = URLSession(configuration: config, delegate: PinnedTrust(pin: pairing.pin), delegateQueue: nil)
    }

    private func request(_ path: String, host: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host):\(pairing.port)\(path)")!)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func json(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        var lastError: Error = URLError(.cannotConnectToHost)
        for host in [pairing.ip, pairing.host] where !host.isEmpty {
            do {
                let (bytes, response) = try await session.data(for: request(path, host: host, body: data))
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
                return try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func decide(_ id: Int, answer: Any) async throws {
        _ = try await json("/decide", body: ["id": id, "answer": answer])
    }
}

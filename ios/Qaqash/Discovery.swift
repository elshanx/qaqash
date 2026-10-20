import CryptoKit
import Foundation
import Network

struct FoundMac: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var host: String
}

func pairCode(_ pin: String) -> String {
    String(format: "%04d", (Int(pin.prefix(8), radix: 16) ?? 0) % 10_000)
}

@MainActor
final class Discovery: ObservableObject {
    @Published var macs: [FoundMac] = []
    private var browser: NWBrowser?

    func start() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_qaqash._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> FoundMac? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var host = "\(name).local"
                if case .bonjour(let record) = result.metadata, let advertised = record["host"] { host = advertised }
                return FoundMac(name: name, host: host)
            }
            Task { @MainActor in self?.macs = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

final class FirstTrust: NSObject, URLSessionDelegate {
    let seen: (String) -> Void
    var pin = ""

    init(seen: @escaping (String) -> Void) { self.seen = seen }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }
        pin = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        seen(pin)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum PairError: Error {
    case declined
}

func requestPairing(with mac: FoundMac, device: String, seen: @escaping (String) -> Void) async throws -> Pairing {
    let trust = FirstTrust(seen: seen)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 75
    let session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
    var request = URLRequest(url: URL(string: "https://\(mac.host):47832/pair")!)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: ["device": device])
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = reply["token"] as? String else { throw PairError.declined }
    return Pairing(
        host: reply["host"] as? String ?? mac.host,
        name: reply["name"] as? String ?? mac.name,
        ip: "",
        port: 47832,
        token: token,
        pin: trust.pin
    )
}

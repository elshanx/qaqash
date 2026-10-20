import Foundation
import Security

struct Pairing: Codable, Equatable {
    var host: String
    var name: String
    var ip: String
    var port: Int
    var token: String
    var pin: String

    static func parse(_ text: String) -> Pairing? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.elshanx.qaqash.pairing",
    ]

    static func load() -> Pairing? {
        var found: AnyObject?
        var lookup = query
        lookup[kSecReturnData as String] = true
        guard SecItemCopyMatching(lookup as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    func save() {
        Pairing.forget()
        var item = Pairing.query
        item[kSecValueData as String] = try? JSONEncoder().encode(self)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func forget() {
        SecItemDelete(query as CFDictionary)
    }
}

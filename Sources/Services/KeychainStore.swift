import Foundation
import Security

/// Credenziali OAuth 2.1 dell'API ufficiale InPost, salvate nel
/// Keychain del dispositivo (mai in chiaro su disco).
enum KeychainStore {
    private static let service = "com.spedizioni.inpost"
    private static let account = "oauth"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    struct Credentials {
        let clientID: String
        let clientSecret: String
    }

    /// Salva (o sostituisce) le credenziali.
    static func save(clientID: String, clientSecret: String) {
        delete()
        guard !clientID.isEmpty, !clientSecret.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data("\(clientID)|\(clientSecret)".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Legge le credenziali salvate, se presenti.
    static func credentials() -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Credentials(
            clientID: String(parts[0]),
            clientSecret: String(parts[1])
        )
    }

    /// Rimuove le credenziali.
    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var hasCredentials: Bool {
        credentials() != nil
    }
}

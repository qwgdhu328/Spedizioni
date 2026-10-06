import Foundation
import Security

/// Token di accesso a Vercel, salvato nel Keychain del dispositivo.
enum VercelKeychain {
    private static let service = "com.spedizioni.vercel"
    private static let account = "token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Salva (o sostituisce) il token.
    static func save(_ token: String) {
        delete()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Legge il token salvato, se presente.
    static func token() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Rimuove il token.
    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var hasToken: Bool { token() != nil }
}

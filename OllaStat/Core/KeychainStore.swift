import Foundation
import Security

/// Stores the ollama.com session cookie in the login keychain.
enum KeychainStore {
    private static let service = "com.diceone.ollastat"
    private static let account = "ollama-session"

    static func saveCookie(_ cookie: String) throws {
        var query = baseQuery
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = Data(cookie.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Keychain-Fehler (OSStatus \(status))"])
        }
    }

    static func loadCookie() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteCookie() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func hasCookie() -> Bool {
        loadCookie()?.isEmpty == false
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
import Foundation
import Security

/// Tüketici oturumunun refresh token'ı yalnızca Keychain'de tutulur (cihaza bağlı, kilit açıkken).
enum KeychainStore {
    private static let service = "com.masaport.app.customer-session"
    private static let refreshTokenAccount = "refresh-token"
    private static let installationIDAccount = "installation-id"

    static func saveRefreshToken(_ token: String) throws {
        try save(token, account: refreshTokenAccount)
    }

    static func refreshToken() throws -> String? {
        try value(for: refreshTokenAccount)
    }

    static func deleteRefreshToken() {
        delete(account: refreshTokenAccount)
    }

    static func installationID() -> String {
        if let existing = try? value(for: installationIDAccount) { return existing }
        let identifier = UUID().uuidString.lowercased()
        try? save(identifier, account: installationIDAccount)
        return identifier
    }

    private static func save(_ value: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery = query.merging([
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func value(for account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return token
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? { "Güvenli oturum saklanamadı." }
}

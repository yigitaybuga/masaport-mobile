import Foundation
import Security

enum KeychainStore {
    private static let service = "com.masaport.operation.session"
    private static let accessTokenAccount = "access-token"
    private static let refreshTokenAccount = "refresh-token"
    private static let installationIDAccount = "installation-id"

    static func saveAccessToken(_ token: String) throws {
        try save(token, account: accessTokenAccount)
    }

    static func saveRefreshToken(_ token: String) throws {
        try save(token, account: refreshTokenAccount)
    }

    static func accessToken() throws -> String? {
        try value(for: accessTokenAccount)
    }

    static func refreshToken() throws -> String? {
        try value(for: refreshTokenAccount)
    }

    static func installationID() throws -> String {
        if let existing = try value(for: installationIDAccount) { return existing }
        let identifier = UUID().uuidString
        try save(identifier, account: installationIDAccount)
        return identifier
    }

    static func deleteSession() {
        delete(account: accessTokenAccount)
        delete(account: refreshTokenAccount)
    }

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        let addQuery = query.merging([
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return token
    }

    static func deleteAccessToken() {
        delete(account: accessTokenAccount)
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? { "Güvenli oturum saklanamadı." }
}

import Foundation
import Security

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain storage"
        case .decodingFailed:
            return "Failed to decode data from Keychain"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .duplicateItem:
            return "Item already exists in Keychain"
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status: \(status)"
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        }
    }
}

/// Manages secure storage of authentication tokens in the system Keychain.
/// Tokens are stored as JSON-encoded data with the service identifier "ai.divehub.garth".
public final class KeychainManager: TokenStorage, Sendable {
    /// The service identifier used for Keychain items
    public let service: String

    /// Optional access group for sharing Keychain items across apps
    public let accessGroup: String?

    /// Shared instance with default configuration
    public static let shared = KeychainManager()

    /// Creates a new KeychainManager with the specified configuration.
    /// - Parameters:
    ///   - service: The service identifier for Keychain items. Defaults to "ai.divehub.garth".
    ///   - accessGroup: Optional access group for sharing across apps. Defaults to nil.
    public init(service: String = "ai.divehub.garth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - OAuth1 Token

    private static let oauth1TokenKey = "oauth1_token"

    /// Saves the OAuth1 token to the Keychain.
    /// - Parameter token: The OAuth1 token to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveOAuth1Token(_ token: OAuth1Token) throws {
        try save(token, forKey: Self.oauth1TokenKey)
    }

    /// Retrieves the OAuth1 token from the Keychain.
    /// - Returns: The stored OAuth1 token, or nil if not found.
    /// - Throws: `KeychainError` if the operation fails (except for item not found).
    public func getOAuth1Token() throws -> OAuth1Token? {
        try get(OAuth1Token.self, forKey: Self.oauth1TokenKey)
    }

    /// Deletes the OAuth1 token from the Keychain.
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteOAuth1Token() throws {
        try delete(forKey: Self.oauth1TokenKey)
    }

    // MARK: - OAuth2 Token

    private static let oauth2TokenKey = "oauth2_token"

    /// Saves the OAuth2 token to the Keychain.
    /// - Parameter token: The OAuth2 token to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveOAuth2Token(_ token: OAuth2Token) throws {
        try save(token, forKey: Self.oauth2TokenKey)
    }

    /// Retrieves the OAuth2 token from the Keychain.
    /// - Returns: The stored OAuth2 token, or nil if not found.
    /// - Throws: `KeychainError` if the operation fails (except for item not found).
    public func getOAuth2Token() throws -> OAuth2Token? {
        try get(OAuth2Token.self, forKey: Self.oauth2TokenKey)
    }

    /// Deletes the OAuth2 token from the Keychain.
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteOAuth2Token() throws {
        try delete(forKey: Self.oauth2TokenKey)
    }

    // MARK: - Both Tokens

    /// Saves both OAuth1 and OAuth2 tokens to the Keychain.
    /// - Parameters:
    ///   - oauth1Token: The OAuth1 token to save.
    ///   - oauth2Token: The OAuth2 token to save.
    /// - Throws: `KeychainError` if the operation fails.
    public func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) throws {
        try saveOAuth1Token(oauth1Token)
        try saveOAuth2Token(oauth2Token)
    }

    /// Retrieves both tokens from the Keychain.
    /// - Returns: A tuple of (OAuth1Token?, OAuth2Token?).
    /// - Throws: `KeychainError` if the operation fails.
    public func getTokens() throws -> (oauth1Token: OAuth1Token?, oauth2Token: OAuth2Token?) {
        let oauth1 = try getOAuth1Token()
        let oauth2 = try getOAuth2Token()
        return (oauth1, oauth2)
    }

    /// Deletes all tokens from the Keychain.
    /// - Throws: `KeychainError` if the operation fails.
    public func deleteAllTokens() throws {
        try? deleteOAuth1Token()
        try? deleteOAuth2Token()
    }

    // MARK: - Generic Keychain Operations

    private func save<T: Encodable>(_ item: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        guard let data = try? encoder.encode(item) else {
            throw KeychainError.encodingFailed
        }

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data

        // Try to add the item first
        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery = baseQuery(forKey: key)
            let updateAttributes: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        guard let item = try? decoder.decode(type, from: data) else {
            throw KeychainError.decodingFailed
        }

        return item
    }

    private func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        // Ignore "item not found" errors when deleting
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

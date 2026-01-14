import Foundation
import Garth
import Security

struct Credentials: Codable, Sendable {
    let email: String
    let password: String
}

protocol CredentialStore: Sendable {
    func saveCredentials(email: String, password: String) throws
    func getCredentials() throws -> Credentials?
    func deleteCredentials() throws
}

struct KeychainCredentialStore: CredentialStore {
    private let service = "ai.divehub.garth.credentials"
    private let account = "garmin_credentials"

    func saveCredentials(email: String, password: String) throws {
        let data = "\(email):\(password)".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GarthError.tokenExchangeFailed("Failed to save credentials: \(status)")
        }
    }

    func getCredentials() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
            let data = result as? Data,
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let parts = string.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        return Credentials(email: String(parts[0]), password: String(parts[1]))
    }

    func deleteCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

struct FileStoreLocation: Sendable {
    let baseDirectory: URL

    init(path: String? = nil) {
        if let path = path {
            baseDirectory = Self.resolveBaseDirectory(path)
        } else {
            baseDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".garmincli", isDirectory: true)
        }
    }

    var credentialsURL: URL {
        baseDirectory.appendingPathComponent("credentials.json", isDirectory: false)
    }

    var tokensURL: URL {
        baseDirectory.appendingPathComponent("tokens.json", isDirectory: false)
    }

    private static func resolveBaseDirectory(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let resolved: String
        if expanded.hasPrefix("/") {
            resolved = expanded
        } else {
            resolved = FileManager.default.currentDirectoryPath + "/" + expanded
        }
        return URL(fileURLWithPath: resolved, isDirectory: true)
    }
}

struct FileCredentialStore: CredentialStore, Sendable {
    let location: FileStoreLocation

    init(location: FileStoreLocation = FileStoreLocation()) {
        self.location = location
    }

    func saveCredentials(email: String, password: String) throws {
        let credentials = Credentials(email: email, password: password)
        try writeJSON(credentials, to: location.credentialsURL)
    }

    func getCredentials() throws -> Credentials? {
        try readJSON(Credentials.self, from: location.credentialsURL)
    }

    func deleteCredentials() throws {
        try removeFileIfExists(location.credentialsURL)
    }
}

struct FileTokenStorage: TokenStorage, Sendable {
    let location: FileStoreLocation

    init(location: FileStoreLocation = FileStoreLocation()) {
        self.location = location
    }

    func saveOAuth1Token(_ token: OAuth1Token) throws {
        var stored = try loadTokens()
        stored.oauth1Token = token
        try persistTokens(stored)
    }

    func getOAuth1Token() throws -> OAuth1Token? {
        try loadTokens().oauth1Token
    }

    func deleteOAuth1Token() throws {
        var stored = try loadTokens()
        stored.oauth1Token = nil
        try persistTokens(stored)
    }

    func saveOAuth2Token(_ token: OAuth2Token) throws {
        var stored = try loadTokens()
        stored.oauth2Token = token
        try persistTokens(stored)
    }

    func getOAuth2Token() throws -> OAuth2Token? {
        try loadTokens().oauth2Token
    }

    func deleteOAuth2Token() throws {
        var stored = try loadTokens()
        stored.oauth2Token = nil
        try persistTokens(stored)
    }

    func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) throws {
        let stored = StoredTokens(oauth1Token: oauth1Token, oauth2Token: oauth2Token)
        try writeJSON(stored, to: location.tokensURL)
    }

    func getTokens() throws -> (oauth1Token: OAuth1Token?, oauth2Token: OAuth2Token?) {
        let stored = try loadTokens()
        return (stored.oauth1Token, stored.oauth2Token)
    }

    func deleteAllTokens() throws {
        try removeFileIfExists(location.tokensURL)
    }

    private func loadTokens() throws -> StoredTokens {
        try readJSON(StoredTokens.self, from: location.tokensURL) ?? StoredTokens()
    }

    private func persistTokens(_ stored: StoredTokens) throws {
        if stored.oauth1Token == nil && stored.oauth2Token == nil {
            try removeFileIfExists(location.tokensURL)
        } else {
            try writeJSON(stored, to: location.tokensURL)
        }
    }
}

private struct StoredTokens: Codable {
    var oauth1Token: OAuth1Token?
    var oauth2Token: OAuth2Token?
}

private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
    let path = url.path
    guard FileManager.default.fileExists(atPath: path) else {
        return nil
    }
    let data = try Data(contentsOf: url)
    if data.isEmpty {
        return nil
    }
    return try JSONDecoder().decode(T.self, from: data)
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let data = try JSONEncoder().encode(value)
    let tempURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
    let created = FileManager.default.createFile(
        atPath: tempURL.path,
        contents: data,
        attributes: [.posixPermissions: 0o600]
    )
    guard created else {
        throw GarthError.tokenExchangeFailed("Failed to write file: \(url.path)")
    }

    do {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: tempURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    } catch {
        try? FileManager.default.removeItem(at: tempURL)
        throw error
    }
}

private func removeFileIfExists(_ url: URL) throws {
    let path = url.path
    guard FileManager.default.fileExists(atPath: path) else {
        return
    }
    try FileManager.default.removeItem(at: url)
}

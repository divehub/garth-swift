import Testing
@testable import Garth
import Foundation

// MARK: - Test Mocks

/// Mock token storage for testing without Keychain access
final class MockTokenStorage: TokenStorage, @unchecked Sendable {
    var oauth1Token: OAuth1Token?
    var oauth2Token: OAuth2Token?
    var saveOAuth1Called = false
    var saveOAuth2Called = false
    var deleteAllCalled = false

    func saveOAuth1Token(_ token: OAuth1Token) throws {
        oauth1Token = token
        saveOAuth1Called = true
    }

    func getOAuth1Token() throws -> OAuth1Token? {
        oauth1Token
    }

    func deleteOAuth1Token() throws {
        oauth1Token = nil
    }

    func saveOAuth2Token(_ token: OAuth2Token) throws {
        oauth2Token = token
        saveOAuth2Called = true
    }

    func getOAuth2Token() throws -> OAuth2Token? {
        oauth2Token
    }

    func deleteOAuth2Token() throws {
        oauth2Token = nil
    }

    func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) throws {
        try saveOAuth1Token(oauth1Token)
        try saveOAuth2Token(oauth2Token)
    }

    func getTokens() throws -> (oauth1Token: OAuth1Token?, oauth2Token: OAuth2Token?) {
        (oauth1Token, oauth2Token)
    }

    func deleteAllTokens() throws {
        oauth1Token = nil
        oauth2Token = nil
        deleteAllCalled = true
    }
}

/// Mock token exchanger for testing refresh logic
final class MockTokenExchanger: TokenExchanger, @unchecked Sendable {
    var exchangeCallCount = 0
    var lastOAuth1Token: OAuth1Token?
    var tokenToReturn: OAuth2Token?
    var errorToThrow: Error?
    var exchangeDelay: Duration?

    func exchange(oauth1Token: OAuth1Token) async throws -> OAuth2Token {
        exchangeCallCount += 1
        lastOAuth1Token = oauth1Token

        if let delay = exchangeDelay {
            try await Task.sleep(for: delay)
        }

        if let error = errorToThrow {
            throw error
        }

        guard let token = tokenToReturn else {
            throw GarthError.tokenExchangeFailed("No token configured")
        }

        return token
    }
}

// MARK: - Test Helpers

func makeValidOAuth1Token() -> OAuth1Token {
    OAuth1Token(
        oauthToken: "test_oauth_token",
        oauthTokenSecret: "test_oauth_secret",
        domain: "garmin.com"
    )
}

func makeValidOAuth2Token(expiresIn: TimeInterval = 3600, refreshExpiresIn: TimeInterval = 7200) -> OAuth2Token {
    let now = Date().timeIntervalSince1970
    return OAuth2Token(
        scope: "CONNECT_READ CONNECT_WRITE",
        jti: "test_jti_\(UUID().uuidString)",
        tokenType: "Bearer",
        accessToken: "test_access_token_\(UUID().uuidString)",
        refreshToken: "test_refresh_token",
        expiresIn: Int(expiresIn),
        expiresAt: now + expiresIn,
        refreshTokenExpiresIn: Int(refreshExpiresIn),
        refreshTokenExpiresAt: now + refreshExpiresIn
    )
}

func makeExpiredOAuth2Token(refreshExpired: Bool = false) -> OAuth2Token {
    let now = Date().timeIntervalSince1970
    return OAuth2Token(
        scope: "CONNECT_READ",
        jti: "expired_jti",
        tokenType: "Bearer",
        accessToken: "expired_access_token",
        refreshToken: "expired_refresh_token",
        expiresIn: 3600,
        expiresAt: now - 100, // Expired 100 seconds ago
        refreshTokenExpiresIn: 7200,
        refreshTokenExpiresAt: refreshExpired ? now - 50 : now + 3600
    )
}

// MARK: - OAuth Token Tests

@Suite("OAuth Token Tests")
struct OAuthTokenTests {
    @Test("OAuth1Token encodes and decodes correctly")
    func oauth1TokenCodable() throws {
        let token = OAuth1Token(
            oauthToken: "test_token",
            oauthTokenSecret: "test_secret",
            mfaToken: "mfa123",
            mfaExpirationTimestamp: Date(timeIntervalSince1970: 1700000000),
            domain: "garmin.com"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(token)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(OAuth1Token.self, from: data)

        #expect(decoded.oauthToken == token.oauthToken)
        #expect(decoded.oauthTokenSecret == token.oauthTokenSecret)
        #expect(decoded.mfaToken == token.mfaToken)
        #expect(decoded.domain == token.domain)
    }

    @Test("OAuth2Token expiration checks work correctly")
    func oauth2TokenExpiration() {
        let expiredToken = makeExpiredOAuth2Token(refreshExpired: false)
        #expect(expiredToken.isExpired == true)
        #expect(expiredToken.isRefreshExpired == false)

        let validToken = makeValidOAuth2Token()
        #expect(validToken.isExpired == false)
        #expect(validToken.isRefreshExpired == false)

        let fullyExpiredToken = makeExpiredOAuth2Token(refreshExpired: true)
        #expect(fullyExpiredToken.isExpired == true)
        #expect(fullyExpiredToken.isRefreshExpired == true)
    }

    @Test("OAuth2Token authorization header is formatted correctly")
    func oauth2TokenAuthHeader() {
        let token = OAuth2Token(
            scope: "CONNECT_READ",
            jti: "jti123",
            tokenType: "Bearer",
            accessToken: "myAccessToken",
            refreshToken: "myRefreshToken",
            expiresIn: 3600,
            expiresAt: Date().timeIntervalSince1970 + 3600,
            refreshTokenExpiresIn: 7200,
            refreshTokenExpiresAt: Date().timeIntervalSince1970 + 7200
        )

        #expect(token.authorizationHeader == "Bearer myAccessToken")
    }

    @Test("OAuth2Token encodes with snake_case keys")
    func oauth2TokenSnakeCaseEncoding() throws {
        let token = OAuth2Token(
            scope: "CONNECT_READ",
            jti: "jti123",
            tokenType: "Bearer",
            accessToken: "access123",
            refreshToken: "refresh123",
            expiresIn: 3600,
            expiresAt: 1700000000,
            refreshTokenExpiresIn: 7200,
            refreshTokenExpiresAt: 1700003600
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["access_token"] as? String == "access123")
        #expect(json?["token_type"] as? String == "Bearer")
        #expect(json?["refresh_token"] as? String == "refresh123")
        #expect(json?["expires_in"] as? Int == 3600)
        #expect(json?["expires_at"] as? Double == 1700000000)
    }
}

// MARK: - Token Manager Tests

@Suite("Token Manager Tests")
struct TokenManagerTests {
    @Test("TokenStatus correctly identifies authentication state")
    func tokenStatusAuthenticated() {
        let status = TokenManager.TokenStatus(
            hasOAuth1Token: true,
            hasOAuth2Token: true,
            oauth2Expired: false,
            oauth2ExpiresAt: Date().addingTimeInterval(3600),
            domain: "garmin.com"
        )

        #expect(status.isAuthenticated == true)
        #expect(status.needsRefresh == false)
        #expect(status.needsReauthentication == false)
    }

    @Test("TokenStatus identifies when refresh is needed")
    func tokenStatusNeedsRefresh() {
        let status = TokenManager.TokenStatus(
            hasOAuth1Token: true,
            hasOAuth2Token: true,
            oauth2Expired: true,
            oauth2ExpiresAt: Date().addingTimeInterval(-100),
            domain: "garmin.com"
        )

        #expect(status.isAuthenticated == false)
        #expect(status.needsRefresh == true)
        #expect(status.needsReauthentication == false)
    }

    @Test("TokenStatus identifies when reauthentication is needed (no OAuth1)")
    func tokenStatusNeedsReauth() {
        // Reauthentication is only needed when there's no OAuth1 token
        // OAuth2 refresh token expiration is irrelevant since OAuth1 can always generate new OAuth2
        let status = TokenManager.TokenStatus(
            hasOAuth1Token: false,
            hasOAuth2Token: true,
            oauth2Expired: true,
            oauth2ExpiresAt: Date().addingTimeInterval(-3600),
            domain: "garmin.com"
        )

        #expect(status.isAuthenticated == false)
        #expect(status.needsRefresh == false)
        #expect(status.needsReauthentication == true)
    }

    @Test("TokenManager saves and retrieves tokens")
    func saveAndRetrieveTokens() async throws {
        let storage = MockTokenStorage()
        let manager = TokenManager(storage: storage)

        let oauth1 = makeValidOAuth1Token()
        let oauth2 = makeValidOAuth2Token()

        try await manager.saveTokens(oauth1Token: oauth1, oauth2Token: oauth2)

        #expect(storage.saveOAuth1Called == true)
        #expect(storage.saveOAuth2Called == true)

        let retrievedOAuth1 = try await manager.getOAuth1Token()
        let retrievedOAuth2 = try await manager.getOAuth2Token()

        #expect(retrievedOAuth1?.oauthToken == oauth1.oauthToken)
        #expect(retrievedOAuth2?.accessToken == oauth2.accessToken)
    }

    @Test("TokenManager clears tokens correctly")
    func clearTokens() async throws {
        let storage = MockTokenStorage()
        storage.oauth1Token = makeValidOAuth1Token()
        storage.oauth2Token = makeValidOAuth2Token()

        let manager = TokenManager(storage: storage)
        try await manager.clearTokens()

        #expect(storage.deleteAllCalled == true)
        #expect(try await manager.hasTokens() == false)
    }

    @Test("getValidOAuth2Token returns valid token without refresh")
    func getValidTokenNoRefresh() async throws {
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        storage.oauth1Token = makeValidOAuth1Token()
        storage.oauth2Token = makeValidOAuth2Token()

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)
        let token = try await manager.getValidOAuth2Token()

        #expect(token.accessToken == storage.oauth2Token?.accessToken)
        #expect(exchanger.exchangeCallCount == 0) // No refresh needed
    }

    @Test("getValidOAuth2Token auto-refreshes expired token")
    func autoRefreshExpiredToken() async throws {
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        storage.oauth1Token = makeValidOAuth1Token()
        storage.oauth2Token = makeExpiredOAuth2Token()

        let newToken = makeValidOAuth2Token()
        exchanger.tokenToReturn = newToken

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)
        let token = try await manager.getValidOAuth2Token()

        #expect(exchanger.exchangeCallCount == 1)
        #expect(token.accessToken == newToken.accessToken)
        #expect(storage.oauth2Token?.accessToken == newToken.accessToken) // Saved to storage
    }

    @Test("getValidOAuth2Token auto-refreshes when OAuth2 is missing")
    func autoRefreshMissingOAuth2Token() async throws {
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        storage.oauth1Token = makeValidOAuth1Token()

        let newToken = makeValidOAuth2Token()
        exchanger.tokenToReturn = newToken

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)
        let token = try await manager.getValidOAuth2Token()

        #expect(exchanger.exchangeCallCount == 1)
        #expect(token.accessToken == newToken.accessToken)
        #expect(storage.oauth2Token?.accessToken == newToken.accessToken)
    }

    @Test("getValidOAuth2Token succeeds even when refresh token expired (uses OAuth1)")
    func succeedsWhenRefreshTokenExpired() async throws {
        // OAuth2 refresh token expiration is irrelevant - OAuth1 token is used to get new OAuth2
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        storage.oauth1Token = makeValidOAuth1Token()
        storage.oauth2Token = makeExpiredOAuth2Token(refreshExpired: true) // Both access and refresh expired

        let newToken = makeValidOAuth2Token()
        exchanger.tokenToReturn = newToken

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)
        let token = try await manager.getValidOAuth2Token()

        #expect(exchanger.exchangeCallCount == 1) // Should exchange using OAuth1
        #expect(token.accessToken == newToken.accessToken)
    }

    @Test("getValidOAuth2Token throws when no OAuth1 token")
    func throwsWhenNoOAuth1Token() async throws {
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        // Only OAuth2, no OAuth1
        storage.oauth2Token = makeExpiredOAuth2Token()

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)

        await #expect(throws: GarthError.self) {
            _ = try await manager.getValidOAuth2Token()
        }
    }

    @Test("Concurrent refresh requests are coalesced (thundering herd prevention)")
    func thunderingHerdPrevention() async throws {
        let storage = MockTokenStorage()
        let exchanger = MockTokenExchanger()

        storage.oauth1Token = makeValidOAuth1Token()
        storage.oauth2Token = makeExpiredOAuth2Token()

        let newToken = makeValidOAuth2Token()
        exchanger.tokenToReturn = newToken
        exchanger.exchangeDelay = .milliseconds(100) // Simulate network delay

        let manager = TokenManager(storage: storage, tokenExchanger: exchanger)

        // Launch multiple concurrent refresh requests
        async let token1 = manager.getValidOAuth2Token()
        async let token2 = manager.getValidOAuth2Token()
        async let token3 = manager.getValidOAuth2Token()

        let results = try await [token1, token2, token3]

        // All should get the same token
        #expect(results.allSatisfy { $0.accessToken == newToken.accessToken })

        // But exchange should only be called once
        #expect(exchanger.exchangeCallCount == 1)
    }
}

// MARK: - GarthError Tests

@Suite("GarthError Tests")
struct GarthErrorTests {
    @Test("GarthError descriptions are meaningful")
    func errorDescriptions() {
        #expect(GarthError.noOAuth1Token.errorDescription?.contains("OAuth1") == true)
        #expect(GarthError.noOAuth2Token.errorDescription?.contains("OAuth2") == true)
        #expect(GarthError.refreshTokenExpired.errorDescription?.contains("expired") == true)
        #expect(GarthError.httpError(statusCode: 401, message: "Unauthorized").errorDescription?.contains("401") == true)
    }
}

// MARK: - Token Storage Protocol Tests

@Suite("Token Storage Tests")
struct TokenStorageTests {
    @Test("MockTokenStorage correctly implements TokenStorage protocol")
    func mockStorageWorks() throws {
        let storage = MockTokenStorage()

        let oauth1 = makeValidOAuth1Token()
        let oauth2 = makeValidOAuth2Token()

        try storage.saveTokens(oauth1Token: oauth1, oauth2Token: oauth2)

        let (retrieved1, retrieved2) = try storage.getTokens()
        #expect(retrieved1?.oauthToken == oauth1.oauthToken)
        #expect(retrieved2?.accessToken == oauth2.accessToken)

        try storage.deleteAllTokens()
        let (deleted1, deleted2) = try storage.getTokens()
        #expect(deleted1 == nil)
        #expect(deleted2 == nil)
    }
}

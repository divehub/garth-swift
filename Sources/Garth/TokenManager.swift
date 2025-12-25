import Foundation

/// Protocol for token exchange operations (used for dependency injection/testing)
public protocol TokenExchanger: Sendable {
    /// Exchanges an OAuth1 token for a new OAuth2 token
    func exchange(oauth1Token: OAuth1Token) async throws -> OAuth2Token
}

/// Protocol for token storage operations (enables testability via dependency injection)
public protocol TokenStorage: Sendable {
    func saveOAuth1Token(_ token: OAuth1Token) throws
    func getOAuth1Token() throws -> OAuth1Token?
    func deleteOAuth1Token() throws

    func saveOAuth2Token(_ token: OAuth2Token) throws
    func getOAuth2Token() throws -> OAuth2Token?
    func deleteOAuth2Token() throws

    func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) throws
    func getTokens() throws -> (oauth1Token: OAuth1Token?, oauth2Token: OAuth2Token?)
    func deleteAllTokens() throws
}

/// Manages OAuth token lifecycle including storage, retrieval, and automatic refresh.
/// This class handles the complexity of maintaining valid tokens for API requests.
public actor TokenManager {
    /// The token storage for secure token persistence
    private let storage: TokenStorage

    /// The token exchanger for refreshing OAuth2 tokens
    private var tokenExchanger: TokenExchanger?

    /// Cached OAuth1 token (loaded from storage)
    private var cachedOAuth1Token: OAuth1Token?

    /// Cached OAuth2 token (loaded from storage)
    private var cachedOAuth2Token: OAuth2Token?

    /// Whether tokens have been loaded from storage
    private var tokensLoaded = false

    /// In-flight refresh task to prevent thundering herd
    private var refreshTask: Task<OAuth2Token, Error>?

    /// Buffer time (in seconds) before token expiration to trigger refresh
    /// Default is 60 seconds - refresh if token expires within 1 minute
    public var refreshBuffer: TimeInterval = 60

    /// Creates a new TokenManager with the specified configuration.
    /// - Parameters:
    ///   - storage: The token storage to use. Defaults to KeychainManager.shared.
    ///   - tokenExchanger: Optional token exchanger for OAuth2 refresh. Can be set later.
    public init(
        storage: TokenStorage = KeychainManager.shared,
        tokenExchanger: TokenExchanger? = nil
    ) {
        self.storage = storage
        self.tokenExchanger = tokenExchanger
    }

    /// Convenience initializer for backward compatibility with KeychainManager.
    public init(
        keychainManager: KeychainManager,
        tokenExchanger: TokenExchanger? = nil
    ) {
        self.storage = keychainManager
        self.tokenExchanger = tokenExchanger
    }

    /// Sets the token exchanger for OAuth2 refresh operations
    public func setTokenExchanger(_ exchanger: TokenExchanger) {
        self.tokenExchanger = exchanger
    }

    // MARK: - Token Access

    /// Returns the current OAuth1 token, loading from Keychain if needed.
    /// - Returns: The OAuth1 token, or nil if not available.
    public func getOAuth1Token() throws -> OAuth1Token? {
        try loadTokensIfNeeded()
        return cachedOAuth1Token
    }

    /// Returns a valid OAuth2 token, automatically refreshing if expired.
    /// - Parameter autoRefresh: Whether to automatically refresh an expired token. Defaults to true.
    /// - Returns: A valid OAuth2 token.
    /// - Throws: `GarthError` if no token is available or refresh fails.
    public func getValidOAuth2Token(autoRefresh: Bool = true) async throws -> OAuth2Token {
        try loadTokensIfNeeded()

        guard let oauth2Token = cachedOAuth2Token else {
            if autoRefresh {
                return try await refreshOAuth2Token()
            }
            throw GarthError.noOAuth2Token
        }

        // Check if token needs refresh (expired or expiring soon)
        let needsRefresh = Date().timeIntervalSince1970 >= (oauth2Token.expiresAt - refreshBuffer)

        if needsRefresh && autoRefresh {
            return try await refreshOAuth2Token()
        }

        if oauth2Token.isExpired && !autoRefresh {
            throw GarthError.noOAuth2Token
        }

        return oauth2Token
    }

    /// Returns the current OAuth2 token without refreshing.
    /// - Returns: The OAuth2 token, or nil if not available.
    public func getOAuth2Token() throws -> OAuth2Token? {
        try loadTokensIfNeeded()
        return cachedOAuth2Token
    }

    // MARK: - Token Refresh

    /// Refreshes the OAuth2 token by exchanging the long-lived OAuth1 token.
    /// Concurrent calls are coalesced to prevent thundering herd.
    ///
    /// Note: This always uses the OAuth1 token to get a fresh OAuth2 token.
    /// The OAuth2 refresh token expiration is irrelevant - the OAuth1 token (~1 year lifespan)
    /// can generate new OAuth2 tokens indefinitely until the OAuth1 token itself expires.
    ///
    /// - Returns: The new OAuth2 token.
    /// - Throws: `GarthError` if refresh fails (e.g., no OAuth1 token, network error, or OAuth1 expired on server).
    @discardableResult
    public func refreshOAuth2Token() async throws -> OAuth2Token {
        // If a refresh is already in progress, wait for it instead of starting another
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        try loadTokensIfNeeded()

        guard let oauth1Token = cachedOAuth1Token else {
            throw GarthError.noOAuth1Token
        }

        guard let exchanger = tokenExchanger else {
            throw GarthError.tokenExchangeFailed("No token exchanger configured")
        }

        // Create a new refresh task and store it
        let task = Task<OAuth2Token, Error> {
            try await exchanger.exchange(oauth1Token: oauth1Token)
        }
        refreshTask = task

        do {
            let newOAuth2Token = try await task.value
            // Save the new token
            try saveOAuth2Token(newOAuth2Token)
            // Clear the task now that we're done
            refreshTask = nil
            return newOAuth2Token
        } catch {
            // Clear the task on failure so next attempt can retry
            refreshTask = nil
            throw error
        }
    }

    // MARK: - Token Storage

    /// Saves both tokens to storage and updates the cache.
    /// - Parameters:
    ///   - oauth1Token: The OAuth1 token to save.
    ///   - oauth2Token: The OAuth2 token to save.
    public func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) throws {
        try storage.saveTokens(oauth1Token: oauth1Token, oauth2Token: oauth2Token)
        cachedOAuth1Token = oauth1Token
        cachedOAuth2Token = oauth2Token
        tokensLoaded = true
    }

    /// Saves only the OAuth1 token.
    public func saveOAuth1Token(_ token: OAuth1Token) throws {
        try storage.saveOAuth1Token(token)
        cachedOAuth1Token = token
    }

    /// Saves only the OAuth2 token.
    public func saveOAuth2Token(_ token: OAuth2Token) throws {
        try storage.saveOAuth2Token(token)
        cachedOAuth2Token = token
    }

    /// Clears all tokens from both cache and storage.
    public func clearTokens() throws {
        try storage.deleteAllTokens()
        cachedOAuth1Token = nil
        cachedOAuth2Token = nil
        tokensLoaded = false
    }

    /// Checks if tokens are available (either in cache or Keychain).
    public func hasTokens() throws -> Bool {
        try loadTokensIfNeeded()
        return cachedOAuth1Token != nil && cachedOAuth2Token != nil
    }

    /// Checks if the current OAuth2 token is valid (not expired).
    public func hasValidOAuth2Token() throws -> Bool {
        try loadTokensIfNeeded()
        guard let oauth2Token = cachedOAuth2Token else {
            return false
        }
        return !oauth2Token.isExpired
    }

    // MARK: - Private Helpers

    private func loadTokensIfNeeded() throws {
        guard !tokensLoaded else { return }

        let (oauth1, oauth2) = try storage.getTokens()
        cachedOAuth1Token = oauth1
        cachedOAuth2Token = oauth2
        tokensLoaded = true
    }

    /// Forces a reload of tokens from the Keychain.
    public func reloadTokens() throws {
        tokensLoaded = false
        try loadTokensIfNeeded()
    }
}

// MARK: - Token Status

extension TokenManager {
    /// Provides a summary of the current token status.
    public struct TokenStatus: Sendable {
        public let hasOAuth1Token: Bool
        public let hasOAuth2Token: Bool
        public let oauth2Expired: Bool
        public let oauth2ExpiresAt: Date?
        public let domain: String?

        /// Whether the client is ready to make API calls without refresh.
        public var isAuthenticated: Bool {
            hasOAuth1Token && hasOAuth2Token && !oauth2Expired
        }

        /// Whether the OAuth2 token needs refresh (but can be refreshed automatically).
        /// As long as OAuth1 token exists, refresh will succeed.
        public var needsRefresh: Bool {
            hasOAuth1Token && hasOAuth2Token && oauth2Expired
        }

        /// Whether the user must log in again.
        /// This only happens when there's no OAuth1 token (never logged in, or tokens cleared).
        /// Note: OAuth1 token server-side expiration (~1 year) is detected at refresh time via HTTP 401.
        public var needsReauthentication: Bool {
            !hasOAuth1Token
        }
    }

    /// Returns the current status of stored tokens.
    public func getTokenStatus() throws -> TokenStatus {
        try loadTokensIfNeeded()

        return TokenStatus(
            hasOAuth1Token: cachedOAuth1Token != nil,
            hasOAuth2Token: cachedOAuth2Token != nil,
            oauth2Expired: cachedOAuth2Token?.isExpired ?? true,
            oauth2ExpiresAt: cachedOAuth2Token?.expirationDate,
            domain: cachedOAuth1Token?.domain
        )
    }
}

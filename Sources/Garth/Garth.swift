import Foundation

/// Main client for interacting with Garmin Connect API.
/// Handles authentication, token management, and API requests with automatic token refresh.
public actor GarthClient {
    /// The Garmin domain (e.g., "garmin.com" or "garmin.cn")
    public let domain: String

    /// Token manager for handling OAuth token lifecycle
    public let tokenManager: TokenManager

    /// URLSession for network requests
    private let session: URLSession

    /// User-Agent header value (mimics official Garmin app)
    private let userAgent = "GCM-iOS-5.7.2.1"

    /// Request timeout in seconds
    public var timeout: TimeInterval = 10

    /// Creates a new GarthClient.
    /// - Parameters:
    ///   - domain: The Garmin domain to use. Defaults to "garmin.com".
    ///   - keychainManager: Keychain manager for token storage. Defaults to shared instance.
    ///   - session: URLSession for network requests. Defaults to shared session.
    ///   - consumerKey: OAuth consumer key for token exchange.
    ///   - consumerSecret: OAuth consumer secret for token exchange.
    public init(
        domain: String = "garmin.com",
        keychainManager: KeychainManager = .shared,
        session: URLSession = .shared,
        consumerKey: String,
        consumerSecret: String
    ) {
        self.domain = domain
        self.session = session

        let tokenExchanger = OAuthTokenExchanger(
            domain: domain,
            consumerKey: consumerKey,
            consumerSecret: consumerSecret,
            session: session
        )

        self.tokenManager = TokenManager(
            keychainManager: keychainManager,
            tokenExchanger: tokenExchanger
        )
    }

    /// Creates a GarthClient with an existing TokenManager.
    /// - Parameters:
    ///   - domain: The Garmin domain to use.
    ///   - tokenManager: Pre-configured token manager.
    ///   - session: URLSession for network requests.
    public init(
        domain: String = "garmin.com",
        tokenManager: TokenManager,
        session: URLSession = .shared
    ) {
        self.domain = domain
        self.tokenManager = tokenManager
        self.session = session
    }

    // MARK: - Authentication Status

    /// Checks if the client is authenticated (has valid tokens).
    public func isAuthenticated() async throws -> Bool {
        try await tokenManager.hasValidOAuth2Token()
    }

    /// Returns the current token status.
    public func getTokenStatus() async throws -> TokenManager.TokenStatus {
        try await tokenManager.getTokenStatus()
    }

    // MARK: - Token Management

    /// Saves tokens after successful login.
    /// Call this after completing the SSO login flow to persist tokens.
    public func saveTokens(oauth1Token: OAuth1Token, oauth2Token: OAuth2Token) async throws {
        try await tokenManager.saveTokens(oauth1Token: oauth1Token, oauth2Token: oauth2Token)
    }

    /// Clears all stored tokens (logout).
    public func logout() async throws {
        try await tokenManager.clearTokens()
    }

    /// Forces a refresh of the OAuth2 token.
    @discardableResult
    public func refreshToken() async throws -> OAuth2Token {
        try await tokenManager.refreshOAuth2Token()
    }

    // MARK: - API Requests

    /// Makes an authenticated request to the Garmin Connect API.
    /// Automatically refreshes the OAuth2 token if expired.
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, PUT, DELETE, etc.)
    ///   - subdomain: API subdomain (e.g., "connectapi", "connect")
    ///   - path: API path (e.g., "/userprofile-service/socialProfile")
    ///   - body: Optional request body data
    ///   - additionalHeaders: Optional additional headers
    /// - Returns: Tuple of (Data, HTTPURLResponse)
    public func request(
        method: String,
        subdomain: String,
        path: String,
        body: Data? = nil,
        additionalHeaders: [String: String]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        // Get a valid OAuth2 token (auto-refreshes if needed)
        let oauth2Token = try await tokenManager.getValidOAuth2Token()

        let urlString = "https://\(subdomain).\(domain)\(path)"
        guard let url = URL(string: urlString) else {
            throw GarthError.tokenExchangeFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(oauth2Token.authorizationHeader, forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        if let headers = additionalHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarthError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw GarthError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return (data, httpResponse)
    }

    /// Makes a GET request to the Connect API.
    public func connectAPI(_ path: String) async throws -> Data {
        let (data, _) = try await request(method: "GET", subdomain: "connectapi", path: path)
        return data
    }

    /// Makes a GET request and decodes the response as JSON.
    public func connectAPI<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T {
        let data = try await connectAPI(path)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// Makes a POST request to the Connect API.
    public func postConnectAPI(_ path: String, body: Data) async throws -> Data {
        let (data, _) = try await request(method: "POST", subdomain: "connectapi", path: path, body: body)
        return data
    }

    /// Makes a PUT request to the Connect API.
    public func putConnectAPI(_ path: String, body: Data) async throws -> Data {
        let (data, _) = try await request(method: "PUT", subdomain: "connectapi", path: path, body: body)
        return data
    }

    /// Makes a DELETE request to the Connect API.
    public func deleteConnectAPI(_ path: String) async throws -> Data {
        let (data, _) = try await request(method: "DELETE", subdomain: "connectapi", path: path)
        return data
    }
}

// MARK: - Convenience Extensions

extension GarthClient {
    /// Fetches the user's social profile.
    public func getUserProfile() async throws -> Data {
        try await connectAPI("/userprofile-service/socialProfile")
    }

    /// Fetches daily stress statistics for a date range.
    public func getStressStats(from startDate: String, to endDate: String) async throws -> Data {
        try await connectAPI("/usersummary-service/stats/stress/daily/\(startDate)/\(endDate)")
    }
}

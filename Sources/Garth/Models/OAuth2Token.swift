import Foundation

/// OAuth2 token used for API requests to Garmin Connect.
/// This token is short-lived (access token ~1 hour, refresh token ~2 hours)
/// and can be refreshed using the OAuth1 token.
public struct OAuth2Token: Codable, Equatable, Sendable {
    /// The scope of permissions (e.g., "CONNECT_READ CONNECT_WRITE")
    public let scope: String

    /// JWT ID - unique identifier for this token
    public let jti: String

    /// Token type (e.g., "Bearer")
    public let tokenType: String

    /// The access token for API requests
    public let accessToken: String

    /// Token used to refresh the access token
    public let refreshToken: String

    /// Seconds until access token expires (from when token was issued)
    public let expiresIn: Int

    /// Unix timestamp when access token expires
    public let expiresAt: TimeInterval

    /// Seconds until refresh token expires (from when token was issued)
    public let refreshTokenExpiresIn: Int

    /// Unix timestamp when refresh token expires
    public let refreshTokenExpiresAt: TimeInterval

    public init(
        scope: String,
        jti: String,
        tokenType: String,
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        expiresAt: TimeInterval,
        refreshTokenExpiresIn: Int,
        refreshTokenExpiresAt: TimeInterval
    ) {
        self.scope = scope
        self.jti = jti
        self.tokenType = tokenType
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.expiresAt = expiresAt
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    // MARK: - Computed Properties

    /// Whether the access token has expired
    public var isExpired: Bool {
        Date().timeIntervalSince1970 >= expiresAt
    }

    /// Whether the refresh token has expired
    public var isRefreshExpired: Bool {
        Date().timeIntervalSince1970 >= refreshTokenExpiresAt
    }

    /// The Authorization header value (e.g., "Bearer <token>")
    public var authorizationHeader: String {
        "\(tokenType.capitalized) \(accessToken)"
    }

    /// Date when the access token expires
    public var expirationDate: Date {
        Date(timeIntervalSince1970: expiresAt)
    }

    /// Date when the refresh token expires
    public var refreshExpirationDate: Date {
        Date(timeIntervalSince1970: refreshTokenExpiresAt)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case scope
        case jti
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case refreshTokenExpiresAt = "refresh_token_expires_at"
    }
}

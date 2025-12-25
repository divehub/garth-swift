import Foundation

/// OAuth1 token used for authenticating with Garmin Connect API.
/// This token is long-lived (~1 year) and used to obtain short-lived OAuth2 tokens.
public struct OAuth1Token: Codable, Equatable, Sendable {
    /// The OAuth1 access token
    public let oauthToken: String

    /// The OAuth1 token secret
    public let oauthTokenSecret: String

    /// Optional MFA token (present if MFA was used during authentication)
    public let mfaToken: String?

    /// Timestamp when the MFA token expires
    public let mfaExpirationTimestamp: Date?

    /// The Garmin domain (e.g., "garmin.com" or "garmin.cn")
    public let domain: String?

    public init(
        oauthToken: String,
        oauthTokenSecret: String,
        mfaToken: String? = nil,
        mfaExpirationTimestamp: Date? = nil,
        domain: String? = nil
    ) {
        self.oauthToken = oauthToken
        self.oauthTokenSecret = oauthTokenSecret
        self.mfaToken = mfaToken
        self.mfaExpirationTimestamp = mfaExpirationTimestamp
        self.domain = domain
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
        case oauthTokenSecret = "oauth_token_secret"
        case mfaToken = "mfa_token"
        case mfaExpirationTimestamp = "mfa_expiration_timestamp"
        case domain
    }
}

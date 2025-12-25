import Foundation
import CryptoKit

/// Handles OAuth token exchange operations with Garmin Connect API.
/// Exchanges OAuth1 tokens for OAuth2 tokens using the Garmin exchange endpoint.
/// All properties are immutable, making this type automatically Sendable.
public struct OAuthTokenExchanger: TokenExchanger, Sendable {
    /// The base domain for API requests (e.g., "garmin.com")
    public let domain: String

    /// URLSession for network requests
    private let session: URLSession

    /// Consumer key for OAuth1 signing
    private let consumerKey: String

    /// Consumer secret for OAuth1 signing
    private let consumerSecret: String

    /// User-Agent header value (mimics official Garmin app)
    private let userAgent = "com.garmin.android.apps.connectmobile"

    /// Creates a new OAuthTokenExchanger.
    /// - Parameters:
    ///   - domain: The Garmin domain to use. Defaults to "garmin.com".
    ///   - consumerKey: OAuth consumer key.
    ///   - consumerSecret: OAuth consumer secret.
    ///   - session: URLSession to use for requests. Defaults to shared session.
    public init(
        domain: String = "garmin.com",
        consumerKey: String,
        consumerSecret: String,
        session: URLSession = .shared
    ) {
        self.domain = domain
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.session = session
    }

    /// Exchanges an OAuth1 token for a new OAuth2 token.
    /// - Parameter oauth1Token: The OAuth1 token to exchange.
    /// - Returns: A new OAuth2 token.
    /// - Throws: `GarthError` if the exchange fails.
    public func exchange(oauth1Token: OAuth1Token) async throws -> OAuth2Token {
        let domain = oauth1Token.domain ?? self.domain
        let urlString = "https://connectapi.\(domain)/oauth-service/oauth/exchange/user/2.0"

        guard let url = URL(string: urlString) else {
            throw GarthError.tokenExchangeFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters: [String: String]
        if let mfaToken = oauth1Token.mfaToken {
            bodyParameters = ["mfa_token": mfaToken]
            let bodyString = bodyParameters
                .map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }
                .joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)
        } else {
            bodyParameters = [:]
        }

        // Build OAuth1 authorization header
        let authHeader = buildOAuth1AuthorizationHeader(
            method: "POST",
            url: url,
            oauthToken: oauth1Token.oauthToken,
            oauthTokenSecret: oauth1Token.oauthTokenSecret,
            bodyParameters: bodyParameters
        )
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarthError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw GarthError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try parseOAuth2Response(data)
    }

    // MARK: - OAuth1 Signature

    private func buildOAuth1AuthorizationHeader(
        method: String,
        url: URL,
        oauthToken: String,
        oauthTokenSecret: String,
        bodyParameters: [String: String] = [:]
    ) -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let oauthParams: [(String, String)] = [
            ("oauth_consumer_key", consumerKey),
            ("oauth_token", oauthToken),
            ("oauth_signature_method", "HMAC-SHA1"),
            ("oauth_timestamp", timestamp),
            ("oauth_nonce", nonce),
            ("oauth_version", "1.0")
        ]

        var signatureParams = oauthParams
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                signatureParams.append((item.name, item.value ?? ""))
            }
        }
        for (key, value) in bodyParameters {
            signatureParams.append((key, value))
        }

        // Create signature base string
        let sortedSignatureParams = signatureParams.sorted {
            if $0.0 == $1.0 { return $0.1 < $1.1 }
            return $0.0 < $1.0
        }
        let paramString = sortedSignatureParams
            .map { "\($0.0.urlEncoded)=\($0.1.urlEncoded)" }
            .joined(separator: "&")

        var baseURLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        baseURLComponents.query = nil
        let baseURLString = baseURLComponents.url!.absoluteString

        let baseString = [
            method.uppercased(),
            baseURLString.urlEncoded,
            paramString.urlEncoded
        ].joined(separator: "&")

        // Create signing key
        let signingKey = "\(consumerSecret.urlEncoded)&\(oauthTokenSecret.urlEncoded)"

        // Generate HMAC-SHA1 signature
        let signature = hmacSHA1(string: baseString, key: signingKey)
        var headerParams = oauthParams
        headerParams.append(("oauth_signature", signature))

        // Build Authorization header
        let sortedHeaderParams = headerParams.sorted {
            if $0.0 == $1.0 { return $0.1 < $1.1 }
            return $0.0 < $1.0
        }
        let headerString = sortedHeaderParams
            .map { "\($0.0)=\"\($0.1.urlEncoded)\"" }
            .joined(separator: ", ")

        return "OAuth \(headerString)"
    }

    private func hmacSHA1(string: String, key: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(string.utf8),
            using: keyData
        )
        return Data(signature).base64EncodedString()
    }

    // MARK: - Response Parsing

    private func parseOAuth2Response(_ data: Data) throws -> OAuth2Token {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            // First decode the raw response
            struct RawResponse: Decodable {
                let scope: String
                let jti: String
                let tokenType: String
                let accessToken: String
                let refreshToken: String
                let expiresIn: Int
                let refreshTokenExpiresIn: Int
            }

            let raw = try decoder.decode(RawResponse.self, from: data)
            let now = Date().timeIntervalSince1970

            return OAuth2Token(
                scope: raw.scope,
                jti: raw.jti,
                tokenType: raw.tokenType,
                accessToken: raw.accessToken,
                refreshToken: raw.refreshToken,
                expiresIn: raw.expiresIn,
                expiresAt: now + Double(raw.expiresIn),
                refreshTokenExpiresIn: raw.refreshTokenExpiresIn,
                refreshTokenExpiresAt: now + Double(raw.refreshTokenExpiresIn)
            )
        } catch {
            throw GarthError.parsingError(error)
        }
    }
}

// MARK: - String URL Encoding Extension

private extension String {
    var urlEncoded: String {
        // RFC 3986 unreserved characters
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

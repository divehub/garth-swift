import Foundation
import CryptoKit

/// Handles SSO (Single Sign-On) login flow with Garmin Connect.
/// This performs the web-based authentication to obtain OAuth1 and OAuth2 tokens.
public struct SSOClient: Sendable {
    /// The Garmin domain (e.g., "garmin.com" or "garmin.cn")
    public let domain: String

    /// URLSession for network requests
    private let session: URLSession

    /// User-Agent header value
    private let userAgent = "com.garmin.android.apps.connectmobile"

    /// OAuth consumer credentials URL
    private static let oauthConsumerURL = "https://thegarth.s3.amazonaws.com/oauth_consumer.json"

    /// Regex patterns
    private static let csrfPattern = try! NSRegularExpression(pattern: #"name="_csrf"\s+value="(.+?)""#)
    private static let titlePattern = try! NSRegularExpression(pattern: #"<title>(.+?)</title>"#)
    private static let ticketPattern = try! NSRegularExpression(pattern: #"embed\?ticket=([^"]+)""#)

    public init(domain: String = "garmin.com", session: URLSession = .shared) {
        self.domain = domain
        self.session = session
    }

    /// Performs full SSO login flow with username and password.
    /// - Parameters:
    ///   - email: Garmin account email
    ///   - password: Garmin account password
    ///   - mfaHandler: Optional handler for MFA code input. If nil and MFA is required, throws error.
    /// - Returns: Tuple of (OAuth1Token, OAuth2Token)
    public func login(
        email: String,
        password: String,
        mfaHandler: (() async throws -> String)? = nil
    ) async throws -> (OAuth1Token, OAuth2Token) {
        // Build URLs
        let ssoBase = "https://sso.\(domain)/sso"
        let ssoEmbed = "\(ssoBase)/embed"

        let embedParams: [String: String] = [
            "id": "gauth-widget",
            "embedWidget": "true",
            "gauthHost": ssoBase
        ]

        let signinParams: [String: String] = embedParams.merging([
            "gauthHost": ssoEmbed,
            "service": ssoEmbed,
            "source": ssoEmbed,
            "redirectAfterAccountLoginUrl": ssoEmbed,
            "redirectAfterAccountCreationUrl": ssoEmbed
        ]) { _, new in new }

        // Step 1: Initialize session with cookies
        _ = try await get(path: "/sso/embed", params: embedParams)

        // Step 2: Get CSRF token from signin page
        let (signinHTML, signinResponse) = try await get(path: "/sso/signin", params: signinParams)
        let csrfToken = try extractCSRF(from: signinHTML)
        
        // Get the actual URL we landed on (redirects resolved) to use as Referer
        let refererURL = signinResponse?.url?.absoluteString ?? "https://sso.\(domain)/sso/signin"

        // Step 3: Submit credentials
        let (loginResponseString, _) = try await post(
            path: "/sso/signin",
            params: signinParams,
            headers: ["Referer": refererURL],
            formData: [
                "username": email,
                "password": password,
                "embed": "true",
                "_csrf": csrfToken
            ]
        )

        var currentResponseString = loginResponseString
        var title = try extractTitle(from: currentResponseString)

        // Step 4: Handle MFA if required
        if title.contains("MFA") {
            guard let mfaHandler = mfaHandler else {
                throw GarthError.tokenExchangeFailed("MFA required but no handler provided")
            }

            let mfaCode = try await mfaHandler()
            let mfaCSRF = try extractCSRF(from: loginResponseString)

            let (mfaResponseString, _) = try await post(
                path: "/sso/verifyMFA/loginEnterMfaCode",
                params: signinParams,
                headers: ["Referer": refererURL],
                formData: [
                    "mfa-code": mfaCode,
                    "embed": "true",
                    "_csrf": mfaCSRF,
                    "fromPage": "setupEnterMfaCode"
                ]
            )

            currentResponseString = mfaResponseString
            title = try extractTitle(from: currentResponseString)
        }

        // Step 5: Extract ticket and complete login
        guard title == "Success" else {
            throw GarthError.tokenExchangeFailed("Login failed: \(title)")
        }

        let ticket = try extractTicket(from: currentResponseString)
        return try await completeLogin(ticket: ticket)
    }

    /// Completes login by exchanging ticket for OAuth tokens.
    private func completeLogin(ticket: String) async throws -> (OAuth1Token, OAuth2Token) {
        // Get OAuth consumer credentials
        let consumer = try await fetchOAuthConsumer()

        // Get OAuth1 token using ticket
        let oauth1 = try await getOAuth1Token(ticket: ticket, consumer: consumer)

        // Exchange OAuth1 for OAuth2
        let exchanger = OAuthTokenExchanger(
            domain: domain,
            consumerKey: consumer.key,
            consumerSecret: consumer.secret,
            session: session
        )
        let oauth2 = try await exchanger.exchange(oauth1Token: oauth1)

        return (oauth1, oauth2)
    }

    /// Fetches OAuth consumer credentials from S3.
    private func fetchOAuthConsumer() async throws -> OAuthConsumer {
        guard let url = URL(string: Self.oauthConsumerURL) else {
            throw GarthError.tokenExchangeFailed("Invalid OAuth consumer URL")
        }

        let (data, _) = try await session.data(from: url)

        struct ConsumerResponse: Decodable {
            let consumer_key: String
            let consumer_secret: String
        }

        let response = try JSONDecoder().decode(ConsumerResponse.self, from: data)
        return OAuthConsumer(key: response.consumer_key, secret: response.consumer_secret)
    }

    /// Gets OAuth1 token using the SSO ticket.
    private func getOAuth1Token(ticket: String, consumer: OAuthConsumer) async throws -> OAuth1Token {
        let loginURL = "https://sso.\(domain)/sso/embed"
        let baseURL = "https://connectapi.\(domain)/oauth-service/oauth/preauthorized"
        let urlString = "\(baseURL)?ticket=\(ticket)&login-url=\(loginURL.urlQueryEncoded)&accepts-mfa-tokens=true"

        guard let url = URL(string: urlString) else {
            throw GarthError.tokenExchangeFailed("Invalid OAuth1 URL")
        }

        // Build OAuth1 header for unsigned request (uses consumer credentials only)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Add OAuth1 authorization (consumer-only, no token yet)
        let authHeader = buildOAuth1ConsumerHeader(
            method: "GET",
            url: url,
            consumerKey: consumer.key,
            consumerSecret: consumer.secret
        )
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GarthError.tokenExchangeFailed("Failed to get OAuth1 token")
        }

        // Parse query string response
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw GarthError.tokenExchangeFailed("Invalid OAuth1 response")
        }

        let params = parseQueryString(responseString)

        guard let oauthToken = params["oauth_token"],
              let oauthTokenSecret = params["oauth_token_secret"] else {
            throw GarthError.tokenExchangeFailed("Missing OAuth1 tokens in response")
        }

        return OAuth1Token(
            oauthToken: oauthToken,
            oauthTokenSecret: oauthTokenSecret,
            mfaToken: params["mfa_token"],
            mfaExpirationTimestamp: params["mfa_expiration_timestamp"].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) },
            domain: domain
        )
    }

    // MARK: - HTTP Helpers

    private func get(path: String, params: [String: String]) async throws -> (String, HTTPURLResponse?) {
        var components = URLComponents(string: "https://sso.\(domain)\(path)")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw GarthError.tokenExchangeFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        return (html, response as? HTTPURLResponse)
    }

    private func post(
        path: String,
        params: [String: String],
        headers: [String: String] = [:],
        formData: [String: String]
    ) async throws -> (String, HTTPURLResponse?) {
        var components = URLComponents(string: "https://sso.\(domain)\(path)")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw GarthError.tokenExchangeFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let bodyString = formData.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        return (html, response as? HTTPURLResponse)
    }

    // MARK: - Parsing Helpers

    /// Safely extracts a regex capture group from HTML using NSString for correct UTF-16 handling.
    /// This avoids index mismatch crashes when the HTML contains multi-byte characters (emojis, etc.).
    private func extract(pattern: NSRegularExpression, from html: String, errorMessage: String) throws -> String {
        let nsString = html as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = pattern.firstMatch(in: html, options: [], range: range),
              match.range(at: 1).location != NSNotFound else {
            throw GarthError.tokenExchangeFailed(errorMessage)
        }
        return nsString.substring(with: match.range(at: 1))
    }

    private func extractCSRF(from html: String) throws -> String {
        try extract(pattern: Self.csrfPattern, from: html, errorMessage: "CSRF token not found")
    }

    private func extractTitle(from html: String) throws -> String {
        try extract(pattern: Self.titlePattern, from: html, errorMessage: "Title not found")
    }

    private func extractTicket(from html: String) throws -> String {
        try extract(pattern: Self.ticketPattern, from: html, errorMessage: "Ticket not found in response")
    }

    private func parseQueryString(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[key] = value
            }
        }
        return result
    }

    // MARK: - OAuth1 Consumer-Only Signature

    private func buildOAuth1ConsumerHeader(
        method: String,
        url: URL,
        consumerKey: String,
        consumerSecret: String
    ) -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let oauthParams: [(String, String)] = [
            ("oauth_consumer_key", consumerKey),
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

        // Create signature base string
        let sortedSignatureParams = signatureParams.sorted {
            if $0.0 == $1.0 { return $0.1 < $1.1 }
            return $0.0 < $1.0
        }
        let paramString = sortedSignatureParams
            .map { "\($0.0.oauthEncoded)=\($0.1.oauthEncoded)" }
            .joined(separator: "&")

        // For preauthorized endpoint, use the base URL without query params
        var baseURLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        baseURLComponents.query = nil
        let baseURLString = baseURLComponents.url!.absoluteString

        let baseString = [
            method.uppercased(),
            baseURLString.oauthEncoded,
            paramString.oauthEncoded
        ].joined(separator: "&")

        // Create signing key (consumer secret + empty token secret)
        let signingKey = "\(consumerSecret.oauthEncoded)&"

        // Generate HMAC-SHA1 signature
        let keyData = SymmetricKey(data: Data(signingKey.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(baseString.utf8),
            using: keyData
        )
        let signatureString = Data(signature).base64EncodedString()

        // Build Authorization header
        var headerParams = oauthParams
        headerParams.append(("oauth_signature", signatureString))

        let sortedHeaderParams = headerParams.sorted {
            if $0.0 == $1.0 { return $0.1 < $1.1 }
            return $0.0 < $1.0
        }
        let headerString = sortedHeaderParams
            .map { "\($0.0)=\"\($0.1.oauthEncoded)\"" }
            .joined(separator: ", ")

        return "OAuth \(headerString)"
    }
}

// MARK: - Supporting Types

private struct OAuthConsumer {
    let key: String
    let secret: String
}

// MARK: - String Extensions

private extension String {
    /// Encodes a string for use in application/x-www-form-urlencoded body.
    /// Uses RFC 3986 unreserved characters only, which properly encodes
    /// delimiters like &, =, + that would otherwise corrupt form data.
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    /// Encodes a string for use in URL query parameters.
    /// Note: This is less strict than formEncoded and used only for URL construction.
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    /// OAuth 1.0 percent encoding (RFC 3986 unreserved characters).
    var oauthEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

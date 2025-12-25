import Foundation

/// Errors that can occur during Garth operations
public enum GarthError: Error, LocalizedError {
    /// No OAuth1 token available for authentication
    case noOAuth1Token

    /// No OAuth2 token available for API requests
    case noOAuth2Token

    /// The OAuth2 refresh token has expired, requiring re-authentication
    case refreshTokenExpired

    /// Token exchange failed
    case tokenExchangeFailed(String)

    /// Network request failed
    case networkError(Error)

    /// Invalid response from the server
    case invalidResponse

    /// HTTP error with status code
    case httpError(statusCode: Int, message: String?)

    /// Failed to parse response data
    case parsingError(Error)

    public var errorDescription: String? {
        switch self {
        case .noOAuth1Token:
            return "No OAuth1 token available. Please log in first."
        case .noOAuth2Token:
            return "No OAuth2 token available. Please log in first."
        case .refreshTokenExpired:
            return "Refresh token has expired. Please log in again."
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            if let message = message {
                return "HTTP error \(statusCode): \(message)"
            }
            return "HTTP error \(statusCode)"
        case .parsingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

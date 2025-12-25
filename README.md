# Garth Swift

A Swift package for Garmin Connect API authentication, inspired by the Python [garth](https://github.com/matin/garth) library.

## Features

- **OAuth1 & OAuth2 Token Management** - Handles Garmin's two-token authentication system
- **Automatic Token Refresh** - OAuth2 tokens are automatically refreshed using the long-lived OAuth1 token
- **Secure Keychain Storage** - Tokens are stored securely in the system Keychain
- **SSO Login with MFA Support** - Built-in SSO flow with optional MFA handler
- **Modern Swift Concurrency** - Built with async/await and actors for thread safety
- **Thundering Herd Prevention** - Concurrent refresh requests are coalesced into a single network call
- **Multi-Domain Support** - Works with garmin.com, garmin.cn, and other regional domains
- **Testable Architecture** - Protocol-based design with dependency injection

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 17+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/divehub/garth-swift.git", from: "1.0.0")
]
```

Or add it via Xcode: File → Add Package Dependencies → Enter the repository URL.

## Quick Start

```swift
import Garth

// 1. Perform SSO login (handles MFA if needed)
let ssoClient = SSOClient()
let (oauth1Token, oauth2Token) = try await ssoClient.login(
    email: "you@example.com",
    password: "your-password",
    mfaHandler: {
        // Present UI and return the MFA code as a String
        return "123456"
    }
)

// 2. Create a client with OAuth consumer credentials
let client = GarthClient(
    consumerKey: "your_consumer_key",
    consumerSecret: "your_consumer_secret"
)

// 3. Save tokens (persisted to Keychain)
try await client.saveTokens(oauth1Token: oauth1Token, oauth2Token: oauth2Token)

// 4. Make API requests (auto-refreshes OAuth2 if needed)
let profileData = try await client.getUserProfile()
```

### MFA Handling

If Garmin requires MFA, `SSOClient.login` will call the `mfaHandler` you provide. The handler should prompt the user and return the code. If no handler is provided and MFA is required, the login call throws an error.

### OAuth Consumer Credentials

`GarthClient` needs the OAuth consumer key/secret to sign token refresh requests. The CLI loads these from:

```
https://thegarth.s3.amazonaws.com/oauth_consumer.json
```

You can use the same endpoint or provide your own credentials.

## Token Lifecycle

Garth uses a two-token system:

| Token      | Lifespan | Purpose                                            |
| ---------- | -------- | -------------------------------------------------- |
| **OAuth1** | ~1 year  | Long-lived credential that generates OAuth2 tokens |
| **OAuth2** | ~1 hour  | Short-lived token for API requests                 |

**Key insight:** The OAuth1 token can generate new OAuth2 tokens indefinitely until it expires (~1 year). This means users stay logged in for a year without re-authentication, even though OAuth2 tokens expire hourly.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Token Refresh Flow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  API Request ──▶ OAuth2 Valid? ──Yes──▶ Make Request            │
│                       │                                          │
│                      No (expired)                                │
│                       │                                          │
│                       ▼                                          │
│              Exchange OAuth1 ──▶ New OAuth2 ──▶ Make Request    │
│                                                                  │
│  (OAuth1 is valid for ~1 year, so this always succeeds)         │
└─────────────────────────────────────────────────────────────────┘
```

**Note:** If the OAuth2 token is missing but OAuth1 exists, `getValidOAuth2Token()` will also exchange OAuth1 and restore OAuth2 automatically.

## Usage

### Making API Requests

```swift
// Tokens are automatically loaded from Keychain and refreshed if needed
let profileData = try await client.getUserProfile()

// Generic API methods
let data = try await client.connectAPI("/userprofile-service/socialProfile")

// With automatic JSON decoding
struct UserProfile: Decodable {
    let displayName: String
    let profileImageUrl: String?
}
let profile: UserProfile = try await client.connectAPI(
    "/userprofile-service/socialProfile",
    responseType: UserProfile.self
)

// POST/PUT/DELETE
let response = try await client.postConnectAPI("/some/endpoint", body: jsonData)
```

### Checking Authentication Status

```swift
let status = try await client.getTokenStatus()

if status.isAuthenticated {
    print("Ready to make API calls")
} else if status.needsRefresh {
    print("Token expired but will refresh automatically")
} else if status.needsReauthentication {
    print("No OAuth1 token - please log in")
}
```

### Manual Token Refresh

```swift
// Force a token refresh (normally happens automatically)
let newToken = try await client.refreshToken()
```

### Logout

```swift
// Clears all tokens from Keychain
try await client.logout()
```

## Architecture

### Components

| Component             | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `GarthClient`         | Main actor for API interactions with automatic token refresh |
| `TokenManager`        | Manages token lifecycle, caching, and refresh coordination   |
| `KeychainManager`     | Secure token persistence using system Keychain               |
| `OAuthTokenExchanger` | Handles OAuth1→OAuth2 token exchange with HMAC-SHA1 signing  |
| `TokenStorage`        | Protocol for custom storage implementations                  |
| `TokenExchanger`      | Protocol for custom exchange implementations (testing)       |

### Concurrency Safety

- `GarthClient` and `TokenManager` are **actors** for thread-safe state management
- `KeychainManager` and `OAuthTokenExchanger` are **Sendable** value types
- Concurrent refresh requests are **coalesced** to prevent thundering herd

## Advanced Usage

### Custom Keychain Configuration

```swift
let keychainManager = KeychainManager(
    service: "com.myapp.garmin",
    accessGroup: "group.com.myapp.shared" // For app extensions
)

let tokenManager = TokenManager(storage: keychainManager)
let client = GarthClient(tokenManager: tokenManager)
```

### Custom Token Storage (for Testing)

```swift
// Implement TokenStorage protocol for in-memory or mock storage
class MockTokenStorage: TokenStorage {
    var oauth1Token: OAuth1Token?
    var oauth2Token: OAuth2Token?
    // ... implement protocol methods
}

let manager = TokenManager(storage: MockTokenStorage())
```

### Refresh Buffer Configuration

```swift
let tokenManager = TokenManager()
await tokenManager.refreshBuffer = 120 // Refresh 2 minutes before expiration
```

## Error Handling

```swift
do {
    let data = try await client.connectAPI("/some/endpoint")
} catch GarthError.noOAuth1Token {
    // No OAuth1 token - user needs to log in
} catch GarthError.httpError(let statusCode, let message) {
    if statusCode == 401 {
        // OAuth1 token expired on server (~1 year) - need to re-login
    }
    print("HTTP \(statusCode): \(message ?? "Unknown error")")
} catch GarthError.networkError(let error) {
    print("Network error: \(error.localizedDescription)")
} catch {
    print(error.localizedDescription)
}
```

## CLI Tool

The package includes a `GarminCLI` executable for testing:

```bash
# Build and run
swift run GarminCLI

# Commands
swift run GarminCLI login           # Login with username/password
swift run GarminCLI profile         # Fetch user profile
swift run GarminCLI refresh         # Force token refresh
swift run GarminCLI status          # Show auth status
swift run GarminCLI logout          # Clear stored credentials
```

## Testing

```bash
swift test
```

The test suite includes:

- Token model encoding/decoding
- Token expiration logic
- Auto-refresh behavior
- Thundering herd prevention
- Token storage operations

## License

MIT License

## Acknowledgments

- [garth](https://github.com/matin/garth) - The original Python implementation
- Garmin Connect API documentation

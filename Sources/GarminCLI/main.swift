import Foundation
import Garth

struct GarminCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let command = args.first ?? "help"

        do {
            switch command {
            case "login":
                try await loginCommand()
            case "profile":
                try await profileCommand()
            case "logout":
                try await logoutCommand()
            case "refresh":
                try await refreshCommand()
            case "status":
                try await statusCommand()
            case "list-dives":
                try await listDivesCommand()
            case "list-devices":
                try await listDevicesCommand()
            case "get-activity":
                try await getActivityCommand(args: Array(args.dropFirst()))
            case "decode-fit":
                try decodeFitCommand(args: Array(args.dropFirst()))
            case "help", "--help", "-h":
                printHelp()
            default:
                print("Unknown command: \(command)")
                printHelp()
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Commands

    static func loginCommand() async throws {
        let credentialManager = CredentialManager()

        // Check if already logged in
        let tokenManager = TokenManager()
        if try await tokenManager.hasTokens() {
            print("Already logged in. Use 'logout' first to login with different credentials.")
            print("Or use 'profile' to verify your login.")
            return
        }

        // Get credentials
        print("Garmin Connect Login")
        print("====================")

        let email: String
        let password: String

        // Check for saved credentials
        if let saved = try? credentialManager.getCredentials() {
            print("Found saved credentials for: \(saved.email)")
            print("Use saved credentials? (Y/n): ", terminator: "")
            let response = readLine()?.lowercased() ?? "y"
            if response == "y" || response.isEmpty {
                email = saved.email
                password = saved.password
            } else {
                (email, password) = promptCredentials()
            }
        } else {
            (email, password) = promptCredentials()
        }

        print("\nLogging in...")

        // Perform SSO login
        let ssoClient = SSOClient()
        let (oauth1, oauth2) = try await ssoClient.login(
            email: email,
            password: password,
            mfaHandler: {
                print("MFA code required.")
                print("Enter MFA code: ", terminator: "")
                guard let code = readLine(), !code.isEmpty else {
                    throw GarthError.tokenExchangeFailed("No MFA code provided")
                }
                return code
            }
        )

        // Save tokens
        try await tokenManager.saveTokens(oauth1Token: oauth1, oauth2Token: oauth2)

        // Save credentials
        try credentialManager.saveCredentials(email: email, password: password)

        print("Login successful!")
        print("Tokens saved to Keychain.")
    }

    static func refreshCommand() async throws {
        let tokenManager = TokenManager()
        
        guard try await tokenManager.hasTokens() else {
            print("Not logged in. Please run 'login' first.")
            return
        }

        // Fetch consumer credentials
        let consumer = try await fetchOAuthConsumer()

        // Create client with token exchanger
        let exchanger = OAuthTokenExchanger(
            consumerKey: consumer.key,
            consumerSecret: consumer.secret
        )
        await tokenManager.setTokenExchanger(exchanger)

        print("Forcing token refresh...")
        let newToken = try await tokenManager.refreshOAuth2Token()
        
        print("Token refresh successful!")
        print("New Access Token: \(newToken.accessToken.prefix(10))...")
        print("Expires At: \(Date(timeIntervalSince1970: newToken.expiresAt))")
    }

    static func profileCommand() async throws {
        let client = try await createGarthClient()

        // Get profile
        print("Fetching user profile...")

        let oauth2 = try await client.tokenManager.getValidOAuth2Token()

        // Make profile request
        let url = URL(string: "https://connectapi.garmin.com/userprofile-service/socialProfile")!
        var request = URLRequest(url: url)
        request.setValue(oauth2.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("GCM-iOS-5.7.2.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarthError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            print("Session expired. Please run 'login' again.")
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GarthError.httpError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        // Parse and display profile
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("\nUser Profile:")
            print("=============")
            if let displayName = json["displayName"] as? String {
                print("Display Name: \(displayName)")
            }
            if let fullName = json["fullName"] as? String {
                print("Full Name: \(fullName)")
            }
            if let userName = json["userName"] as? String {
                print("Username: \(userName)")
            }
            if let location = json["location"] as? String, !location.isEmpty {
                print("Location: \(location)")
            }
            if let profileImageUrl = json["profileImageUrlLarge"] as? String {
                print("Profile Image: \(profileImageUrl)")
            }
        } else {
            print("Raw response:")
            print(String(data: data, encoding: .utf8) ?? "Unable to decode response")
        }
    }

    static func logoutCommand() async throws {
        let tokenManager = TokenManager()
        let credentialManager = CredentialManager()

        try await tokenManager.clearTokens()
        try? credentialManager.deleteCredentials()

        print("Logged out successfully.")
        print("Tokens and credentials cleared from Keychain.")
    }

    static func statusCommand() async throws {
        let tokenManager = TokenManager()

        let status = try await tokenManager.getTokenStatus()

        print("Authentication Status")
        print("====================")
        print("OAuth1 Token: \(status.hasOAuth1Token ? "Present" : "Missing")")
        print("OAuth2 Token: \(status.hasOAuth2Token ? "Present" : "Missing")")

        if status.hasOAuth2Token {
            print("OAuth2 Expired: \(status.oauth2Expired ? "Yes" : "No")")
            if let expiresAt = status.oauth2ExpiresAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                print("OAuth2 Expires: \(formatter.string(from: expiresAt))")
            }
        }

        if let domain = status.domain {
            print("Domain: \(domain)")
        }

        print("")
        if status.isAuthenticated {
            print("Status: Authenticated (ready to make API calls)")
        } else if status.needsRefresh {
            print("Status: Token expired (will auto-refresh on next API call)")
        } else if status.needsReauthentication {
            print("Status: Not logged in (run 'login' command)")
        }
    }

    static func listDivesCommand() async throws {
        let client = try await createGarthClient()

        // Fetch dive logs and total count
        print("Fetching dive logs...")
        let diveFetcher = DiveLogFetcher(client: client)

        // Fetch total count and activities in parallel
        async let totalCount = diveFetcher.fetchTotalDiveCount()
        async let dives = diveFetcher.fetchDiveLogs(start: 0, limit: 20)

        let (total, activities) = try await (totalCount, dives)

        // Display results
        diveFetcher.printDiveLogs(activities, totalCount: total)
    }

    static func listDevicesCommand() async throws {
        let client = try await createGarthClient()

        print("Fetching registered devices...")
        let deviceFetcher = DeviceListFetcher(client: client)
        let devices = try await deviceFetcher.fetchDevices()
        deviceFetcher.printDevices(devices)
    }

    static func getActivityCommand(args: [String]) async throws {
        guard let activityId = args.first else {
            print("Error: Activity ID is required")
            print("Usage: GarminCLI get-activity <activityId>")
            exit(1)
        }

        let client = try await createGarthClient()

        // Download activity
        print("Downloading activity \(activityId)...")
        let activityDownloader = ActivityDownloader(client: client)
        try await activityDownloader.downloadActivity(activityId: activityId)
    }

    static func decodeFitCommand(args: [String]) throws {
        guard let filePath = args.first else {
            print("Error: FIT file path is required")
            print("Usage: GarminCLI decode-fit <path-to-fit-file>")
            exit(1)
        }

        // Resolve path
        let resolvedPath: String
        if filePath.hasPrefix("/") {
            resolvedPath = filePath
        } else {
            resolvedPath = FileManager.default.currentDirectoryPath + "/" + filePath
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("Error: File not found: \(resolvedPath)")
            exit(1)
        }

        print("Decoding FIT file: \(resolvedPath)")
        let decoder = FITFileDecoder(filePath: resolvedPath)
        try decoder.decode()
    }

    // MARK: - Helpers

    static func promptCredentials() -> (email: String, password: String) {
        print("Email: ", terminator: "")
        let email = readLine() ?? ""

        print("Password: ", terminator: "")
        // Note: In a real CLI, you'd want to hide password input
        let password = readLine() ?? ""

        return (email, password)
    }

    static func printHelp() {
        print("""
        GarminCLI - Garmin Connect Authentication Tool

        Usage: GarminCLI <command>

        Commands:
            login           Login to Garmin Connect with username/password
            profile         Fetch and display user profile
            list-dives      Fetch and display dive logs
            list-devices    List registered devices
            get-activity    Download activity FIT file by ID
            decode-fit      Decode and display FIT file data
            refresh         Force token refresh
            status          Show authentication status
            logout          Clear stored tokens and credentials
            help            Show this help message

        Examples:
            GarminCLI login
            GarminCLI profile
            GarminCLI list-dives
            GarminCLI list-devices
            GarminCLI get-activity 12345678901
            GarminCLI decode-fit 12345678901.fit
            GarminCLI logout
        """)
    }

    static func fetchOAuthConsumer() async throws -> (key: String, secret: String) {
        let url = URL(string: "https://thegarth.s3.amazonaws.com/oauth_consumer.json")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Consumer: Decodable {
            let consumer_key: String
            let consumer_secret: String
        }

        let consumer = try JSONDecoder().decode(Consumer.self, from: data)
        return (consumer.consumer_key, consumer.consumer_secret)
    }

    static func createGarthClient() async throws -> GarthClient {
        let tokenManager = TokenManager()

        guard try await tokenManager.hasTokens() else {
            print("Not logged in. Please run 'login' first.")
            exit(1)
        }

        // Fetch consumer credentials
        let consumer = try await fetchOAuthConsumer()

        // Create client with token exchanger
        let exchanger = OAuthTokenExchanger(
            consumerKey: consumer.key,
            consumerSecret: consumer.secret
        )
        await tokenManager.setTokenExchanger(exchanger)

        return GarthClient(tokenManager: tokenManager)
    }
}

// MARK: - Credential Manager

/// Manages username/password storage in Keychain
struct CredentialManager {
    private let service = "com.garth.credentials"

    struct Credentials {
        let email: String
        let password: String
    }

    func saveCredentials(email: String, password: String) throws {
        let data = "\(email):\(password)".data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "garmin_credentials",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GarthError.tokenExchangeFailed("Failed to save credentials: \(status)")
        }
    }

    func getCredentials() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "garmin_credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
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
            kSecAttrAccount as String: "garmin_credentials"
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// Entry point
await GarminCLI.main()

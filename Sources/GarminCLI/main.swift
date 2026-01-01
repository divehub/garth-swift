import Foundation
import Garth

struct GarminCLI {
    struct CLIOptions {
        var useFileStore = false
        var fileStorePath: String?
        var endpointURL: URL?
    }

    struct EndpointConfiguration {
        let domain: String
        let ssoBaseURL: URL?
        let connectAPIBaseURL: URL?
        let oauthConsumerURL: URL?
    }

    struct CLIContext {
        let credentialStore: CredentialStore
        let tokenStorage: TokenStorage
        let useFileStore: Bool
        let endpoint: EndpointConfiguration
    }

    struct ParsedArguments {
        let command: String
        let commandArgs: [String]
        let options: CLIOptions
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let parsed = parseArguments(args)
        let context = buildContext(options: parsed.options)
        let command = parsed.command

        do {
            switch command {
            case "login":
                try await loginCommand(context: context)
            case "profile":
                try await profileCommand(args: parsed.commandArgs, context: context)
            case "logout":
                try await logoutCommand(context: context)
            case "refresh":
                try await refreshCommand(context: context)
            case "status":
                try await statusCommand(context: context)
            case "list-dives":
                try await listDivesCommand(args: parsed.commandArgs, context: context)
            case "list-devices":
                try await listDevicesCommand(context: context)
            case "get-activity":
                try await getActivityCommand(args: parsed.commandArgs, context: context)
            case "decode-fit":
                try decodeFitCommand(args: parsed.commandArgs)
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

    static func loginCommand(context: CLIContext) async throws {
        let credentialStore = context.credentialStore
        let endpoint = context.endpoint

        // Check if already logged in
        let tokenManager = TokenManager(storage: context.tokenStorage)
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
        if let saved = try? credentialStore.getCredentials() {
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
        let ssoClient = SSOClient(
            domain: endpoint.domain,
            session: .shared,
            ssoBaseURL: endpoint.ssoBaseURL,
            connectAPIBaseURL: endpoint.connectAPIBaseURL,
            oauthConsumerURL: endpoint.oauthConsumerURL
        )
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
        try credentialStore.saveCredentials(email: email, password: password)

        print("Login successful!")
        let storeLabel = context.useFileStore ? "local file store" : "Keychain"
        print("Tokens saved to \(storeLabel).")
    }

    static func refreshCommand(context: CLIContext) async throws {
        let tokenManager = TokenManager(storage: context.tokenStorage)
        
        guard try await tokenManager.hasTokens() else {
            print("Not logged in. Please run 'login' first.")
            return
        }

        // Fetch consumer credentials
        let consumer = try await fetchOAuthConsumer(
            oauthConsumerURL: context.endpoint.oauthConsumerURL
        )

        // Create client with token exchanger
        let exchanger = OAuthTokenExchanger(
            domain: context.endpoint.domain,
            consumerKey: consumer.key,
            consumerSecret: consumer.secret,
            connectAPIBaseURL: context.endpoint.connectAPIBaseURL
        )
        await tokenManager.setTokenExchanger(exchanger)

        print("Forcing token refresh...")
        let newToken = try await tokenManager.refreshOAuth2Token()
        
        print("Token refresh successful!")
        print("New Access Token: \(newToken.accessToken.prefix(10))...")
        print("Expires At: \(Date(timeIntervalSince1970: newToken.expiresAt))")
    }

    static func profileCommand(args: [String], context: CLIContext) async throws {
        let outputPath = parseOutOption(args: args, usage: "Usage: GarminCLI profile [--out <path>]")
        let client = try await createGarthClient(
            tokenStorage: context.tokenStorage,
            endpoint: context.endpoint
        )

        // Get profile
        print("Fetching user profile...")

        let data: Data
        do {
            (data, _) = try await client.request(
                method: "GET",
                subdomain: "connectapi",
                path: "/userprofile-service/socialProfile"
            )
        } catch let GarthError.httpError(statusCode, _) where statusCode == 401 {
            print("Session expired. Please run 'login' again.")
            return
        }

        if let outputPath = outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("Saved raw response to \(outputPath)")
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

    static func logoutCommand(context: CLIContext) async throws {
        let tokenManager = TokenManager(storage: context.tokenStorage)
        let credentialStore = context.credentialStore

        try await tokenManager.clearTokens()
        try? credentialStore.deleteCredentials()

        print("Logged out successfully.")
        let storeLabel = context.useFileStore ? "local file store" : "Keychain"
        print("Tokens and credentials cleared from \(storeLabel).")
    }

    static func statusCommand(context: CLIContext) async throws {
        let tokenManager = TokenManager(storage: context.tokenStorage)

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

    static func listDivesCommand(args: [String], context: CLIContext) async throws {
        let outputPath = parseOutOption(args: args, usage: "Usage: GarminCLI list-dives [--out <path>]")
        let client = try await createGarthClient(
            tokenStorage: context.tokenStorage,
            endpoint: context.endpoint
        )

        // Fetch dive logs and total count
        print("Fetching dive logs...")
        let diveFetcher = DiveLogFetcher(client: client)

        // Fetch total count and activities in parallel
        async let totalCount = diveFetcher.fetchTotalDiveCount()
        async let dives = diveFetcher.fetchDiveLogs(start: 0, limit: 20, outputPath: outputPath)

        let (total, activities) = try await (totalCount, dives)

        // Display results
        if let outputPath = outputPath {
            print("Saved raw response to \(outputPath)")
        }
        diveFetcher.printDiveLogs(activities, totalCount: total)
    }

    static func listDevicesCommand(context: CLIContext) async throws {
        let client = try await createGarthClient(
            tokenStorage: context.tokenStorage,
            endpoint: context.endpoint
        )

        print("Fetching registered devices...")
        let deviceFetcher = DeviceListFetcher(client: client)
        let devices = try await deviceFetcher.fetchDevices()
        deviceFetcher.printDevices(devices)
    }

    static func getActivityCommand(args: [String], context: CLIContext) async throws {
        guard let activityId = args.first else {
            print("Error: Activity ID is required")
            print("Usage: GarminCLI get-activity <activityId>")
            exit(1)
        }

        let client = try await createGarthClient(
            tokenStorage: context.tokenStorage,
            endpoint: context.endpoint
        )

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

    static func parseArguments(_ args: [String]) -> ParsedArguments {
        var options = CLIOptions()
        var remainingArgs: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]

            if arg == "--file-store" {
                options.useFileStore = true
                index += 1
                continue
            }

            if arg == "--endpoint" {
                guard index + 1 < args.count else {
                    print("Error: --endpoint requires a base URL")
                    printHelp()
                    exit(1)
                }
                options.endpointURL = parseEndpointURL(args[index + 1], flag: "--endpoint")
                index += 2
                continue
            }

            if arg == "--file-store-path" {
                guard index + 1 < args.count else {
                    print("Error: --file-store-path requires a directory path")
                    printHelp()
                    exit(1)
                }
                options.useFileStore = true
                options.fileStorePath = args[index + 1]
                index += 2
                continue
            }

            if arg.hasPrefix("--file-store=") {
                let value = String(arg.dropFirst("--file-store=".count))
                guard !value.isEmpty else {
                    print("Error: --file-store requires a directory path")
                    printHelp()
                    exit(1)
                }
                options.useFileStore = true
                options.fileStorePath = value
                index += 1
                continue
            }

            if arg.hasPrefix("--endpoint=") {
                let value = String(arg.dropFirst("--endpoint=".count))
                guard !value.isEmpty else {
                    print("Error: --endpoint requires a base URL")
                    printHelp()
                    exit(1)
                }
                options.endpointURL = parseEndpointURL(value, flag: "--endpoint")
                index += 1
                continue
            }

            if arg.hasPrefix("--file-store-path=") {
                let value = String(arg.dropFirst("--file-store-path=".count))
                guard !value.isEmpty else {
                    print("Error: --file-store-path requires a directory path")
                    printHelp()
                    exit(1)
                }
                options.useFileStore = true
                options.fileStorePath = value
                index += 1
                continue
            }

            remainingArgs.append(arg)
            index += 1
        }

        let command = remainingArgs.first ?? "help"
        let commandArgs = Array(remainingArgs.dropFirst())
        return ParsedArguments(command: command, commandArgs: commandArgs, options: options)
    }

    static func buildContext(options: CLIOptions) -> CLIContext {
        let endpoint = resolveEndpointConfiguration(endpointURL: options.endpointURL)

        if options.useFileStore {
            let location = FileStoreLocation(path: options.fileStorePath)
            return CLIContext(
                credentialStore: FileCredentialStore(location: location),
                tokenStorage: FileTokenStorage(location: location),
                useFileStore: true,
                endpoint: endpoint
            )
        }

        return CLIContext(
            credentialStore: KeychainCredentialStore(),
            tokenStorage: KeychainManager.shared,
            useFileStore: false,
            endpoint: endpoint
        )
    }

    static func parseEndpointURL(_ value: String, flag: String) -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            print("Error: \(flag) requires a valid http(s) URL")
            printHelp()
            exit(1)
        }

        return url
    }

    static func resolveEndpointConfiguration(endpointURL: URL?) -> EndpointConfiguration {
        let defaultDomain = "garmin.com"
        guard let endpointURL = endpointURL else {
            return EndpointConfiguration(
                domain: defaultDomain,
                ssoBaseURL: nil,
                connectAPIBaseURL: nil,
                oauthConsumerURL: nil
            )
        }

        let scheme = endpointURL.scheme ?? "https"
        let host = endpointURL.host ?? defaultDomain
        let domain = extractDomain(from: host)

        if domain == "garmin.com" || domain == "garmin.cn" {
            let ssoBaseURL = URL(string: "\(scheme)://sso.\(domain)")!
            let connectAPIBaseURL = URL(string: "\(scheme)://connectapi.\(domain)")!
            return EndpointConfiguration(
                domain: domain,
                ssoBaseURL: ssoBaseURL,
                connectAPIBaseURL: connectAPIBaseURL,
                oauthConsumerURL: nil
            )
        }

        return EndpointConfiguration(
            domain: host,
            ssoBaseURL: endpointURL,
            connectAPIBaseURL: endpointURL,
            oauthConsumerURL: endpointURL.appendingPathComponent("oauth_consumer.json")
        )
    }

    static func extractDomain(from host: String) -> String {
        if host.hasPrefix("sso.") {
            return String(host.dropFirst("sso.".count))
        }
        if host.hasPrefix("connectapi.") {
            return String(host.dropFirst("connectapi.".count))
        }
        return host
    }

    static func parseOutOption(args: [String], usage: String) -> String? {
        var outputPath: String?
        var index = 0

        while index < args.count {
            let arg = args[index]
            if arg == "--out" {
                guard index + 1 < args.count else {
                    print("Error: --out requires a file path")
                    print(usage)
                    exit(1)
                }
                outputPath = args[index + 1]
                index += 2
                continue
            }

            if arg.hasPrefix("--out=") {
                let value = String(arg.dropFirst("--out=".count))
                guard !value.isEmpty else {
                    print("Error: --out requires a file path")
                    print(usage)
                    exit(1)
                }
                outputPath = value
                index += 1
                continue
            }

            if arg == "--help" || arg == "-h" {
                print(usage)
                exit(0)
            }

            print("Error: Unknown argument '\(arg)'")
            print(usage)
            exit(1)
        }

        if let outputPath = outputPath {
            return resolveOutputPath(outputPath)
        }

        return nil
    }

    static func resolveOutputPath(_ path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return expandedPath
        }

        return FileManager.default.currentDirectoryPath + "/" + expandedPath
    }

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

        Usage: GarminCLI [options] <command>

        Options:
            --file-store          Use local file-based credential and token storage (default: ~/.garmincli)
            --file-store-path <path>  Override file store directory (implies --file-store)
            --endpoint <url>      Use a mock base URL or Garmin domain (http(s)://host[:port])

        Commands:
            login           Login to Garmin Connect with username/password
            profile         Fetch and display user profile (use --out <path> to save JSON)
            list-dives      Fetch and display dive logs (use --out <path> to save JSON)
            list-devices    List registered devices
            get-activity    Download activity FIT file by ID
            decode-fit      Decode and display FIT file data
            refresh         Force token refresh
            status          Show authentication status
            logout          Clear stored tokens and credentials
            help            Show this help message

        Examples:
            GarminCLI login
            GarminCLI --file-store login
            GarminCLI --endpoint http://localhost:8080 login
            GarminCLI --endpoint https://garmin.cn login
            GarminCLI profile
            GarminCLI profile --out profile.json
            GarminCLI list-dives
            GarminCLI list-dives --out dives.json
            GarminCLI list-devices
            GarminCLI get-activity 12345678901
            GarminCLI decode-fit 12345678901.fit
            GarminCLI logout
        """)
    }

    static func fetchOAuthConsumer(oauthConsumerURL: URL? = nil) async throws -> (key: String, secret: String) {
        let url = oauthConsumerURL ?? URL(string: "https://thegarth.s3.amazonaws.com/oauth_consumer.json")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Consumer: Decodable {
            let consumer_key: String
            let consumer_secret: String
        }

        let consumer = try JSONDecoder().decode(Consumer.self, from: data)
        return (consumer.consumer_key, consumer.consumer_secret)
    }

    static func createGarthClient(tokenStorage: TokenStorage, endpoint: EndpointConfiguration) async throws -> GarthClient {
        let tokenManager = TokenManager(storage: tokenStorage)

        guard try await tokenManager.hasTokens() else {
            print("Not logged in. Please run 'login' first.")
            exit(1)
        }

        // Fetch consumer credentials
        let consumer = try await fetchOAuthConsumer(
            oauthConsumerURL: endpoint.oauthConsumerURL
        )

        // Create client with token exchanger
        let exchanger = OAuthTokenExchanger(
            domain: endpoint.domain,
            consumerKey: consumer.key,
            consumerSecret: consumer.secret,
            connectAPIBaseURL: endpoint.connectAPIBaseURL
        )
        await tokenManager.setTokenExchanger(exchanger)

        return GarthClient(
            domain: endpoint.domain,
            tokenManager: tokenManager,
            connectAPIBaseURL: endpoint.connectAPIBaseURL
        )
    }
}
// Entry point
await GarminCLI.main()

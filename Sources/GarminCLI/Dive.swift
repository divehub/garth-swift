import Foundation
import Garth
import ZIPFoundation

/// Dive activity data from Garmin Connect
struct DiveActivity: Codable {
    let activityId: Int
    let activityName: String?
    let startTimeLocal: String
    let duration: Double
    let distance: Double?
    let maxDepth: Double?  // unit is centimeters
    let avgDepth: Double?

    var formattedDuration: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

/// Response from Garmin Connect activity list endpoint
struct ActivityListResponse: Codable {
    let activities: [DiveActivity]?
}

/// Dive statistics response from fitness stats service
struct DiveStats: Codable {
    let date: String
    let countOfActivities: Int
    let stats: StatsData

    struct StatsData: Codable {
        let all: AllStats

        struct AllStats: Codable {
            let distance: DistanceStats

            struct DistanceStats: Codable {
                let count: Int
                let min: Double
                let max: Double
                let avg: Double
                let sum: Double
            }
        }
    }
}

/// Fetches dive logs from Garmin Connect
struct DiveLogFetcher {
    let client: GarthClient

    init(client: GarthClient) {
        self.client = client
    }

    /// Fetches total dive count from lifetime statistics
    /// - Returns: Total number of dives
    func fetchTotalDiveCount() async throws -> Int {
        let path =
            "/fitnessstats-service/activity?aggregation=lifetime&groupByParentActivityType=false&groupByEventType=false&activityType=diving&metric=distance&standardizedUnits=false"
        let data = try await client.connectAPI(path)

        let decoder = JSONDecoder()
        let stats = try decoder.decode([DiveStats].self, from: data)

        return stats.first?.countOfActivities ?? 0
    }

    /// Fetches dive activities from Garmin Connect
    /// - Parameters:
    ///   - start: Starting index for pagination (default: 0)
    ///   - limit: Maximum number of activities to fetch (default: 20)
    ///   - outputPath: Optional file path to save the raw JSON response
    /// - Returns: Array of dive activities
    func fetchDiveLogs(start: Int = 0, limit: Int = 20, outputPath: String? = nil) async throws -> [DiveActivity] {
        // Use GarthClient connectAPI convenience method
        let path =
            "/activitylist-service/activities/search/activities?activityType=diving&start=\(start)&limit=\(limit)"
        let data = try await client.connectAPI(path)

        if let outputPath = outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath))
        }

        // // Print raw JSON for debugging
        // if let jsonString = String(data: data, encoding: .utf8) {
        //     print("Raw JSON response:")
        //     print(jsonString)
        // }

        // The API returns an array directly, not wrapped in an object
        let decoder = JSONDecoder()
        let activities = try decoder.decode([DiveActivity].self, from: data)

        return activities
    }

    /// Prints dive logs in a formatted table
    /// - Parameters:
    ///   - activities: Array of dive activities to display
    ///   - totalCount: Total lifetime dive count (optional)
    func printDiveLogs(_ activities: [DiveActivity], totalCount: Int? = nil) {
        guard !activities.isEmpty else {
            print("No dive activities found.")
            return
        }

        if let total = totalCount {
            print("\nShowing \(activities.count) of \(total) total dive(s):\n")
        } else {
            print("\nFound \(activities.count) dive(s):\n")
        }
        print(String(repeating: "-", count: 100))

        // Print header
        let header = String(
            format: "%-12s %-30s %-20s %-12s %-12s",
            ("Activity ID" as NSString).utf8String!,
            ("Name" as NSString).utf8String!,
            ("Date" as NSString).utf8String!,
            ("Duration" as NSString).utf8String!,
            ("Max Depth" as NSString).utf8String!)
        print(header)
        print(String(repeating: "-", count: 100))

        for activity in activities {
            let activityIdStr = String(activity.activityId)
            let name = String((activity.activityName ?? "Unnamed Dive").prefix(30))
            let date = String(activity.startTimeLocal.prefix(19))
            let duration = activity.formattedDuration
            // Convert centimeters to meters
            let maxDepth = activity.maxDepth.map { String(format: "%.1f m", $0 / 100.0) } ?? "N/A"

            print(
                "\(activityIdStr.padding(toLength: 12, withPad: " ", startingAt: 0)) \(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(date.padding(toLength: 20, withPad: " ", startingAt: 0)) \(duration.padding(toLength: 12, withPad: " ", startingAt: 0)) \(maxDepth)"
            )
        }

        print(String(repeating: "-", count: 100))
    }
}

/// Downloads activity FIT files from Garmin Connect
struct ActivityDownloader {
    let client: GarthClient

    init(client: GarthClient) {
        self.client = client
    }

    /// Downloads an activity as a FIT file
    /// - Parameter activityId: The activity ID to download
    func downloadActivity(activityId: String) async throws {
        // Download the ZIP file from Garmin Connect
        let path = "/download-service/files/activity/\(activityId)"
        let zipData = try await client.connectAPI(path)

        print("Downloaded \(zipData.count) bytes")

        // Extract FIT file from ZIP archive in memory
        print("Extracting FIT file...")
        let archive = try Archive(data: zipData, accessMode: .read)

        // Find and extract the FIT file entry
        var fitData = Data()
        for entry in archive {
            if entry.path.lowercased().hasSuffix(".fit") {
                _ = try archive.extract(entry) { data in
                    fitData.append(data)
                }
                break
            }
        }

        guard !fitData.isEmpty else {
            throw GarthError.invalidResponse
        }

        // Write FIT file to current directory with activity ID as filename
        let outputFile = URL(fileURLWithPath: "\(activityId).fit")
        try fitData.write(to: outputFile)

        print("Activity saved to \(outputFile.path)")
    }
}

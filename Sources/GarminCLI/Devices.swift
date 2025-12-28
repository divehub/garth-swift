import Foundation
import Garth

/// Registered device info from Garmin Connect
struct RegisteredDevice: Decodable {
    let deviceId: String?
    let displayName: String?
    let serialNumber: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case displayName
        case serialNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = Self.decodeStringOrInt(container, key: .deviceId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        serialNumber = Self.decodeStringOrInt(container, key: .serialNumber)
    }

    private static func decodeStringOrInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? container.decode(Int64.self, forKey: key) {
            return String(intValue)
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }
        return nil
    }
}

/// Fetches registered devices from Garmin Connect
struct DeviceListFetcher {
    let client: GarthClient

    init(client: GarthClient) {
        self.client = client
    }

    func fetchDevices() async throws -> [RegisteredDevice] {
        let path = "/device-service/deviceregistration/devices"
        let data = try await client.connectAPI(path)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode([RegisteredDevice].self, from: data)
        } catch {
            if let wrapped = try? decoder.decode(DeviceListResponse.self, from: data) {
                return wrapped.devices
            }
            throw error
        }
    }

    func printDevices(_ devices: [RegisteredDevice]) {
        guard !devices.isEmpty else {
            print("No devices found.")
            return
        }

        print("\nDevices:\n")
        print(String(repeating: "-", count: 80))

        let header = String(
            format: "%-20s %-30s %-20s",
            ("Device ID" as NSString).utf8String!,
            ("Display Name" as NSString).utf8String!,
            ("Serial Number" as NSString).utf8String!)
        print(header)
        print(String(repeating: "-", count: 80))

        for device in devices {
            let id = String((device.deviceId ?? "N/A").prefix(20))
            let name = String((device.displayName ?? "Unknown").prefix(30))
            let serial = String((device.serialNumber ?? "N/A").prefix(20))

            print(
                "\(id.padding(toLength: 20, withPad: " ", startingAt: 0)) "
                    + "\(name.padding(toLength: 30, withPad: " ", startingAt: 0)) "
                    + "\(serial.padding(toLength: 20, withPad: " ", startingAt: 0))"
            )
        }

        print(String(repeating: "-", count: 80))
    }

    private struct DeviceListResponse: Decodable {
        let devices: [RegisteredDevice]
    }
}

import Foundation
import ContinuityProtocol

public struct PairedDevice: Identifiable, Codable, Sendable, Equatable {
    public var id: String { deviceId }
    public var deviceId: String
    public var name: String
    public var platform: DevicePlatform
    public var edition: DeviceEdition
    public var pairedAt: Date
    public var lastSeen: Date
    public var sessionToken: String
    public var isConnected: Bool
    public var batteryLevel: Int
    public var isCharging: Bool
    public var wifiSsid: String
    public var capabilities: CapabilityList?

    public init(
        deviceId: String,
        name: String,
        platform: DevicePlatform = .android,
        edition: DeviceEdition = .publicEdition,
        pairedAt: Date = Date(),
        lastSeen: Date = Date(),
        sessionToken: String = UUID().uuidString,
        isConnected: Bool = false,
        batteryLevel: Int = 100,
        isCharging: Bool = false,
        wifiSsid: String = "Wi-Fi",
        capabilities: CapabilityList? = nil
    ) {
        self.deviceId = deviceId
        self.name = name
        self.platform = platform
        self.edition = edition
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.sessionToken = sessionToken
        self.isConnected = isConnected
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.wifiSsid = wifiSsid
        self.capabilities = capabilities
    }
}

@MainActor
public final class DeviceRegistry: ObservableObject {
    public static let shared = DeviceRegistry()

    @Published public var pairedDevices: [PairedDevice] = []
    @Published public var activeDevice: PairedDevice?

    private let storageKey = "com.continuity.paired_devices"

    public init() {
        loadDevices()
    }

    public func addOrUpdateDevice(_ device: PairedDevice) {
        if let idx = pairedDevices.firstIndex(where: { $0.deviceId == device.deviceId }) {
            pairedDevices[idx] = device
        } else {
            pairedDevices.append(device)
        }
        if activeDevice?.deviceId == device.deviceId || activeDevice == nil {
            activeDevice = device
        }
        saveDevices()
    }

    public func removeDevice(deviceId: String) {
        pairedDevices.removeAll { $0.deviceId == deviceId }
        if activeDevice?.deviceId == deviceId {
            activeDevice = pairedDevices.first
        }
        saveDevices()
    }

    public func updateConnectionStatus(deviceId: String, isConnected: Bool) {
        if let idx = pairedDevices.firstIndex(where: { $0.deviceId == deviceId }) {
            pairedDevices[idx].isConnected = isConnected
            pairedDevices[idx].lastSeen = Date()
            if activeDevice?.deviceId == deviceId {
                activeDevice?.isConnected = isConnected
                activeDevice?.lastSeen = Date()
            }
        }
    }

    public func updateDeviceStatus(deviceId: String, status: DeviceStatus) {
        if let idx = pairedDevices.firstIndex(where: { $0.deviceId == deviceId }) {
            pairedDevices[idx].batteryLevel = Int(status.batteryPercentage)
            pairedDevices[idx].isCharging = status.isCharging
            pairedDevices[idx].wifiSsid = status.wifiSsid
            if activeDevice?.deviceId == deviceId {
                activeDevice?.batteryLevel = Int(status.batteryPercentage)
                activeDevice?.isCharging = status.isCharging
                activeDevice?.wifiSsid = status.wifiSsid
            }
        }
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(pairedDevices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let devices = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            self.pairedDevices = devices
            self.activeDevice = devices.first
        }
    }
}

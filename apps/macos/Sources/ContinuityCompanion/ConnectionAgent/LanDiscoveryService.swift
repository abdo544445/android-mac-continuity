import Foundation
import ContinuityProtocol
import Darwin

public struct DiscoveredPeer: Identifiable, Equatable, Sendable {
    public var id: String { deviceId }
    public let deviceId: String
    public var deviceName: String
    public var platform: String
    public var ip: String
    public var tcpPort: Int
    public var publicKeyBase64: String
    public var lastSeen: Date

    public init(
        deviceId: String,
        deviceName: String,
        platform: String,
        ip: String,
        tcpPort: Int,
        publicKeyBase64: String,
        lastSeen: Date = Date()
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.ip = ip
        self.tcpPort = tcpPort
        self.publicKeyBase64 = publicKeyBase64
        self.lastSeen = lastSeen
    }
}

private struct DiscoveryPacket: Codable {
    var type: String // "CONTINUITY_BEACON" or "CONTINUITY_PAIR_INVITE"
    var deviceId: String
    var deviceName: String
    var platform: String
    var ip: String
    var tcpPort: Int
    var publicKeyBase64: String
    var pairingPin: String?
}

@MainActor
public final class LanDiscoveryService: ObservableObject {
    public static let shared = LanDiscoveryService()

    @Published public var discoveredPeers: [DiscoveredPeer] = []

    public let discoveryPort: UInt16 = 52402
    private var sockFd: Int32 = -1
    private var isRunning = false
    private var broadcastTimer: Timer?
    private let ioQueue = DispatchQueue(label: "com.continuity.landiscovery.io", qos: .utility)

    public init() {}

    public func start(publicKeyBase64: String) {
        guard !isRunning else { return }
        isRunning = true

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            ConnectionAgent.shared.debugLog("LanDiscoveryService failed to create UDP socket")
            isRunning = false
            return
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = discoveryPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult < 0 {
            ConnectionAgent.shared.debugLog("LanDiscoveryService failed to bind UDP port \(discoveryPort)")
            close(fd)
            isRunning = false
            return
        }

        self.sockFd = fd
        ConnectionAgent.shared.debugLog("LanDiscoveryService listening & broadcasting on UDP port \(discoveryPort)")

        startReceiveLoop(fd: fd, publicKeyBase64: publicKeyBase64)

        // Immediately broadcast once, then every 2.0 seconds
        broadcastBeacon(publicKeyBase64: publicKeyBase64)
        broadcastTimer?.invalidate()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.broadcastBeacon(publicKeyBase64: publicKeyBase64)
                self.pruneStalePeers()
            }
        }
    }

    public func stop() {
        isRunning = false
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        if sockFd >= 0 {
            close(sockFd)
            sockFd = -1
        }
    }

    public func sendPairInvite(to peer: DiscoveredPeer, pin: String, publicKeyBase64: String) {
        let rawMacName = Host.current().localizedName ?? "MacBook Pro"
        let macId = "mac-\(rawMacName.replacingOccurrences(of: " ", with: "-").lowercased())"
        let localIp = ConnectionAgent.shared.getLocalIPAddress()

        let packet = DiscoveryPacket(
            type: "CONTINUITY_PAIR_INVITE",
            deviceId: macId,
            deviceName: rawMacName,
            platform: "PLATFORM_MACOS",
            ip: localIp,
            tcpPort: 52400,
            publicKeyBase64: publicKeyBase64,
            pairingPin: pin
        )
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendUdpPacket(data: data, host: peer.ip, port: discoveryPort)
        // Also send to broadcast in case peer IP is NATed
        sendUdpPacket(data: data, host: "255.255.255.255", port: discoveryPort)
        ConnectionAgent.shared.debugLog("Sent CONTINUITY_PAIR_INVITE to \(peer.deviceName) (\(peer.ip)) with PIN \(pin)")
    }

    public func broadcastBeacon(publicKeyBase64: String, targetHost: String? = nil) {
        guard sockFd >= 0 else { return }
        let rawMacName = Host.current().localizedName ?? "MacBook Pro"
        let macId = "mac-\(rawMacName.replacingOccurrences(of: " ", with: "-").lowercased())"
        let localIp = ConnectionAgent.shared.getLocalIPAddress()

        let packet = DiscoveryPacket(
            type: "CONTINUITY_BEACON",
            deviceId: macId,
            deviceName: rawMacName,
            platform: "PLATFORM_MACOS",
            ip: localIp,
            tcpPort: 52400,
            publicKeyBase64: publicKeyBase64,
            pairingPin: nil
        )
        guard let data = try? JSONEncoder().encode(packet) else { return }

        if let specificHost = targetHost {
            sendUdpPacket(data: data, host: specificHost, port: discoveryPort)
            return
        }

        // 1. Global broadcast
        sendUdpPacket(data: data, host: "255.255.255.255", port: discoveryPort)

        // 2. Directed subnet broadcast (e.g. 192.168.1.255)
        let parts = localIp.split(separator: ".")
        if parts.count == 4 {
            let subnetBroadcast = "\(parts[0]).\(parts[1]).\(parts[2]).255"
            sendUdpPacket(data: data, host: subnetBroadcast, port: discoveryPort)
        }
    }

    private func sendUdpPacket(data: Data, host: String, port: UInt16) {
        let fd = self.sockFd
        guard fd >= 0 else { return }

        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &destAddr.sin_addr)

        data.withUnsafeBytes { rawBuf in
            guard let baseAddress = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &destAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    _ = sendto(fd, baseAddress, data.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func startReceiveLoop(fd: Int32, publicKeyBase64: String) {
        ioQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                var senderAddr = sockaddr_in()
                var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let bytesRead = withUnsafeMutablePointer(to: &senderAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        recvfrom(fd, &buffer, buffer.count, 0, sockaddrPtr, &senderLen)
                    }
                }

                if bytesRead <= 0 {
                    break
                }

                let data = Data(bytes: buffer, count: bytesRead)
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addrCopy = senderAddr.sin_addr
                inet_ntop(AF_INET, &addrCopy, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                let senderIp = String(cString: ipBuffer)

                guard let packet = try? JSONDecoder().decode(DiscoveryPacket.self, from: data) else {
                    continue
                }

                // Ignore our own beacons
                if packet.platform == "PLATFORM_MACOS" {
                    continue
                }

                let resolvedIp = (packet.ip.isEmpty || packet.ip == "127.0.0.1" || packet.ip == "0.0.0.0") ? senderIp : packet.ip

                Task { @MainActor [weak self] in
                    guard let self = self, self.isRunning else { return }
                    let peer = DiscoveredPeer(
                        deviceId: packet.deviceId,
                        deviceName: packet.deviceName,
                        platform: packet.platform,
                        ip: resolvedIp,
                        tcpPort: packet.tcpPort,
                        publicKeyBase64: packet.publicKeyBase64,
                        lastSeen: Date()
                    )
                    self.upsertPeer(peer, replyBeaconWithKey: publicKeyBase64)
                }
            }
        }
    }

    private func upsertPeer(_ peer: DiscoveredPeer, replyBeaconWithKey pubKey: String) {
        let isNew: Bool
        if let idx = discoveredPeers.firstIndex(where: { $0.deviceId == peer.deviceId }) {
            discoveredPeers[idx] = peer
            isNew = false
        } else {
            discoveredPeers.append(peer)
            isNew = true
        }

        if isNew {
            ConnectionAgent.shared.debugLog("Auto-discovered Android device on LAN: \(peer.deviceName) at \(peer.ip)")
            // Send immediate unicast beacon reply so Android discovers us right away
            broadcastBeacon(publicKeyBase64: pubKey, targetHost: peer.ip)
        }
    }

    private func pruneStalePeers() {
        let cutoff = Date().addingTimeInterval(-12.0)
        discoveredPeers.removeAll { $0.lastSeen < cutoff }
    }
}

import Foundation

@MainActor
public final class AdvancedHostManager: ObservableObject {
    public static let shared = AdvancedHostManager()

    @Published public var isAdbAvailable: Bool = false
    @Published public var isScrcpyAvailable: Bool = false
    @Published public var adbPath: String = ""
    @Published public var scrcpyPath: String = ""
    @Published public var isMirroringActive: Bool = false
    @Published public var connectedAdbDevices: [String] = []
    @Published public var statusMessage: String = ""

    private var scrcpyProcess: Process?

    public init() {
        detectTooling()
    }

    private func buildProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/Library/Android/sdk/platform-tools"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(extraPaths):/usr/bin:/bin:/usr/sbin:/sbin"
        }
        if !adbPath.isEmpty {
            env["ADB"] = adbPath
        }
        return env
    }

    public func detectTooling() {
        let candidateAdbPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]

        for path in candidateAdbPaths {
            if FileManager.default.fileExists(atPath: path) {
                adbPath = path
                isAdbAvailable = true
                break
            }
        }

        let candidateScrcpyPaths = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy"
        ]

        for path in candidateScrcpyPaths {
            if FileManager.default.fileExists(atPath: path) {
                scrcpyPath = path
                isScrcpyAvailable = true
                break
            }
        }

        if isAdbAvailable {
            refreshDevices()
        }
    }

    public func refreshDevices() {
        guard isAdbAvailable else { return }
        let path = adbPath
        let env = buildProcessEnvironment()

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.environment = env
            process.arguments = ["devices"]

            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                var devices: [String] = []
                for line in lines.dropFirst() {
                    let parts = line.split(separator: "\t")
                    if parts.count >= 2 && parts[1] == "device" {
                        devices.append(String(parts[0]))
                    }
                }
                let finalDevices = devices
                await MainActor.run {
                    self.connectedAdbDevices = finalDevices
                    if !finalDevices.isEmpty {
                        _ = self.setupAdbReverseTunnel(port: 52400)
                    }
                }
            }
        }
    }

    public func setupAdbReverseTunnel(port: Int = 52400) -> Bool {
        guard isAdbAvailable else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.environment = buildProcessEnvironment()
        process.arguments = ["reverse", "tcp:\(port)", "tcp:\(port)"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Attempts to connect ADB wirelessly to a discovered LAN peer IP if no USB device is attached.
    public func connectWirelessAdbIfNeeded(peerIp: String?) async {
        guard isAdbAvailable, let ip = peerIp, !ip.isEmpty, ip != "127.0.0.1" else { return }
        let path = adbPath
        let env = buildProcessEnvironment()

        await Task.detached {
            // Enable tcpip 5555 if USB device is currently attached
            let tcpProc = Process()
            tcpProc.executableURL = URL(fileURLWithPath: path)
            tcpProc.environment = env
            tcpProc.arguments = ["tcpip", "5555"]
            try? tcpProc.run()
            tcpProc.waitUntilExit()

            // Connect to peer IP:5555
            let connProc = Process()
            connProc.executableURL = URL(fileURLWithPath: path)
            connProc.environment = env
            connProc.arguments = ["connect", "\(ip):5555"]
            try? connProc.run()
            connProc.waitUntilExit()
        }.value
    }

    public func startScrcpy(serial: String? = nil, fallbackWirelessIp: String? = nil) {
        guard isScrcpyAvailable else {
            statusMessage = "scrcpy not found on Mac."
            return
        }
        stopScrcpy()
        statusMessage = "Starting mirror window..."

        let sPath = scrcpyPath
        let env = buildProcessEnvironment()
        let peerIp = fallbackWirelessIp ?? LanDiscoveryService.shared.discoveredPeers.first?.ip

        Task { @MainActor in
            await connectWirelessAdbIfNeeded(peerIp: peerIp)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: sPath)
            process.environment = env

            var args = [
                "--stay-awake",
                "--show-touches",
                "--max-fps=60",
                "--window-title=Continuity Mirror"
            ]
            if let serial = serial {
                args.append(contentsOf: ["-s", serial])
            }
            process.arguments = args

            let errPipe = Pipe()
            process.standardError = errPipe

            process.terminationHandler = { [weak self] proc in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isMirroringActive = false
                    self.scrcpyProcess = nil
                    if proc.terminationStatus != 0 {
                        ConnectionAgent.shared.debugLog("scrcpy exited (\(proc.terminationStatus)): \(errStr)")
                        self.statusMessage = "USB/ADB Mirror unavailable — using Wireless In-App Mirror."
                        // Automatically request wireless in-app MediaProjection stream from Android!
                        ConnectionAgent.shared.requestWirelessMirrorFromAndroid()
                    } else {
                        self.statusMessage = ""
                    }
                }
            }

            do {
                try process.run()
                self.scrcpyProcess = process
                self.isMirroringActive = true
                self.statusMessage = "Interactive 60fps Mirror Window Open"
                ConnectionAgent.shared.debugLog("scrcpy started successfully (PID \(process.processIdentifier))")
            } catch {
                self.isMirroringActive = false
                self.statusMessage = "Failed to launch scrcpy: \(error.localizedDescription)"
            }
        }
    }

    public func stopScrcpy() {
        if let proc = scrcpyProcess, proc.isRunning {
            proc.terminate()
        }
        scrcpyProcess = nil
        isMirroringActive = false
    }

    /// Injects Android's native KEYCODE_PASTE (279) into the focused app on the mirrored phone/tablet.
    public func sendPasteKeyevent() {
        guard isAdbAvailable else { return }
        let path = adbPath
        let env = buildProcessEnvironment()
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.environment = env
            proc.arguments = ["shell", "input", "keyevent", "279"]
            try? proc.run()
            proc.waitUntilExit()
        }
    }
}

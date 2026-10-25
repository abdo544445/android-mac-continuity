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
    @Published public var isInstallingDependencies: Bool = false
    @Published public var dependencyInstallMessage: String = ""

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

    public func installDependenciesViaBrew() {
        guard !isInstallingDependencies else { return }
        isInstallingDependencies = true
        dependencyInstallMessage = "Checking Homebrew environment..."

        Task.detached {
            let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            var brewPath = ""
            for p in brewCandidates {
                if FileManager.default.fileExists(atPath: p) {
                    brewPath = p
                    break
                }
            }

            guard !brewPath.isEmpty else {
                await MainActor.run {
                    self.isInstallingDependencies = false
                    self.dependencyInstallMessage = "Homebrew not found. Please install Homebrew from brew.sh or use built-in wireless engine."
                }
                return
            }

            await MainActor.run {
                self.dependencyInstallMessage = "Installing scrcpy and android-platform-tools..."
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: brewPath)
            proc.arguments = ["install", "scrcpy", "android-platform-tools"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            proc.environment = env

            try? proc.run()
            proc.waitUntilExit()

            await MainActor.run {
                self.isInstallingDependencies = false
                self.detectTooling()
                if self.isScrcpyAvailable && self.isAdbAvailable {
                    self.dependencyInstallMessage = "All dependencies installed successfully!"
                } else {
                    self.dependencyInstallMessage = "Installation finished. Tools refreshed."
                }
            }
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
        var args = ["reverse", "tcp:\(port)", "tcp:\(port)"]
        if let target = connectedAdbDevices.first, !target.isEmpty {
            args = ["-s", target] + args
        }
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Attempts to connect ADB wirelessly to a discovered LAN peer IP if no device is attached.
    public func connectWirelessAdbIfNeeded(peerIp: String?) async {
        guard isAdbAvailable, let ip = peerIp, !ip.isEmpty, ip != "127.0.0.1" else { return }
        if !connectedAdbDevices.isEmpty { return }

        let path = adbPath
        let env = buildProcessEnvironment()

        await Task.detached {
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
            let targetSerial = serial ?? self.connectedAdbDevices.first
            if let s = targetSerial, !s.isEmpty {
                args.append(contentsOf: ["-s", s])
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

    public func executeAdbCommand(args: [String]) {
        guard isAdbAvailable else { return }
        let path = adbPath
        let env = buildProcessEnvironment()
        let target = connectedAdbDevices.first

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.environment = env
            var finalArgs = args
            if let t = target, !t.isEmpty, !finalArgs.contains("-s") {
                finalArgs = ["-s", t] + finalArgs
            }
            proc.arguments = finalArgs
            try? proc.run()
        }
    }

    /// Injects Android's native KEYCODE_PASTE (279) into the focused app on the mirrored phone/tablet.
    public func sendPasteKeyevent() {
        executeAdbCommand(args: ["shell", "input", "keyevent", "279"])
    }
}

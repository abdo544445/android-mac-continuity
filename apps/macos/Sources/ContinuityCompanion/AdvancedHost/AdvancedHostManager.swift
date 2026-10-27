import Foundation
import AppKit
import CoreImage

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

    @Published public var isKeepAliveEnabled: Bool = true
    @Published public var isAudioForwardingEnabled: Bool = true
    private var keepAliveTimer: Timer?

    // MARK: - Wireless ADB QR Code Pairing
    @Published public var qrImage: NSImage? = nil
    @Published public var qrServiceName: String = ""
    @Published public var qrPairingCode: String = ""
    @Published public var isQrPairingActive: Bool = false
    @Published public var qrStatusMessage: String = ""
    private var qrPollingTask: Task<Void, Never>? = nil

    private var scrcpyProcess: Process?

    public init() {
        detectTooling()
        startKeepAliveTimer()
    }

    public func buildProcessEnvironment() -> [String: String] {
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
                var offlineDevices: [String] = []
                for line in lines.dropFirst() {
                    let parts = line.split(separator: "\t")
                    if parts.count >= 2 {
                        let serial = String(parts[0])
                        let state = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if state == "device" {
                            devices.append(serial)
                        } else if state == "offline" && serial.contains(":") {
                            offlineDevices.append(serial)
                        }
                    }
                }
                // Prune any stale offline wireless endpoints
                for offline in offlineDevices {
                    let discProc = Process()
                    discProc.executableURL = URL(fileURLWithPath: path)
                    discProc.environment = env
                    discProc.arguments = ["disconnect", offline]
                    try? discProc.run()
                    discProc.waitUntilExit()
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

    public func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isKeepAliveEnabled, self.isAdbAvailable else { return }
                if self.connectedAdbDevices.isEmpty {
                    let peerIp = LanDiscoveryService.shared.discoveredPeers.first?.ip
                    if let ip = peerIp, !ip.isEmpty, ip != "127.0.0.1" {
                        await self.connectWirelessAdbIfNeeded(peerIp: ip)
                    }
                }
                self.refreshDevices()
            }
        }
    }

    // MARK: - QR Code Pairing Operations
    public func startQrPairing() {
        stopQrPairing()
        generateNewQrPairing()
    }

    public func generateNewQrPairing() {
        let randomSuffix = String(format: "%04x", Int.random(in: 0...0xFFFF))
        qrServiceName = "Continuity-\(randomSuffix)"
        qrPairingCode = String(format: "%06d", Int.random(in: 100000...999999))
        let payload = "WIFI:T:ADB;S:\(qrServiceName);P:\(qrPairingCode);;"

        qrImage = Self.generateQRCode(from: payload)
        isQrPairingActive = true
        qrStatusMessage = "Ready. Point your phone's 'Pair device with QR code' scanner at this code..."

        startQrPollingLoop()
    }

    public func stopQrPairing() {
        qrPollingTask?.cancel()
        qrPollingTask = nil
        isQrPairingActive = false
    }

    private func onQrPhoneDetected(target: String) {
        qrStatusMessage = "Phone detected on Wi-Fi (\(target))! Pairing..."
    }

    private func onQrPairingSuccess() {
        qrStatusMessage = "✅ Successfully paired with device! Mirror ready."
        statusMessage = "Paired with device via QR code!"
        refreshDevices()
        isQrPairingActive = false
    }

    private func onQrConnected(target: String) {
        qrStatusMessage = "✅ Connected to device (\(target))!"
        refreshDevices()
        isQrPairingActive = false
    }

    private func startQrPollingLoop() {
        qrPollingTask?.cancel()
        let path = adbPath
        let env = buildProcessEnvironment()
        let expectedCode = qrPairingCode

        qrPollingTask = Task { [weak self] in
            for _ in 0..<120 {
                if Task.isCancelled { break }

                let (pairingEndpoint, connectEndpoint) = await Task.detached {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: path)
                    proc.environment = env
                    proc.arguments = ["mdns", "services"]

                    let pipe = Pipe()
                    proc.standardOutput = pipe
                    try? proc.run()
                    proc.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    var pEndpoint: String? = nil
                    var cEndpoint: String? = nil

                    for line in output.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed.hasPrefix("List of") { continue }
                        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if let endpoint = tokens.first(where: { $0.contains(":") && ($0.contains(".") || $0.contains("[")) }) {
                            if trimmed.contains("_adb-tls-pairing") {
                                pEndpoint = endpoint
                            } else if trimmed.contains("_adb-tls-connect") {
                                cEndpoint = endpoint
                            }
                        }
                    }
                    return (pEndpoint, cEndpoint)
                }.value

                guard let self = self else { break }

                if let pairTarget = pairingEndpoint {
                    self.onQrPhoneDetected(target: pairTarget)

                    let pairSuccess = await Task.detached {
                        let pairProc = Process()
                        pairProc.executableURL = URL(fileURLWithPath: path)
                        pairProc.environment = env
                        pairProc.arguments = ["pair", pairTarget, expectedCode]

                        let pairPipe = Pipe()
                        pairProc.standardOutput = pairPipe
                        try? pairProc.run()
                        pairProc.waitUntilExit()

                        let pairData = pairPipe.fileHandleForReading.readDataToEndOfFile()
                        let pairOutput = String(data: pairData, encoding: .utf8) ?? ""
                        return pairOutput.contains("Successfully paired") || pairProc.terminationStatus == 0
                    }.value

                    if pairSuccess {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)

                        if let conn = connectEndpoint {
                            await Task.detached {
                                let connProc = Process()
                                connProc.executableURL = URL(fileURLWithPath: path)
                                connProc.environment = env
                                connProc.arguments = ["connect", conn]
                                try? connProc.run()
                                connProc.waitUntilExit()
                            }.value
                        } else {
                            let ip = pairTarget.split(separator: ":").first.map(String.init) ?? ""
                            if !ip.isEmpty {
                                await self.connectWirelessAdbIfNeeded(peerIp: ip)
                            }
                        }

                        self.onQrPairingSuccess()
                        break
                    }
                } else if let connTarget = connectEndpoint {
                    await Task.detached {
                        let connProc = Process()
                        connProc.executableURL = URL(fileURLWithPath: path)
                        connProc.environment = env
                        connProc.arguments = ["connect", connTarget]
                        try? connProc.run()
                        connProc.waitUntilExit()
                    }.value

                    self.onQrConnected(target: connTarget)
                    break
                }

                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    public static func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter?.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledCIImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    public func pairWirelessAdb(ip: String, pairPort: String, code: String, connectPort: String) {
        guard isAdbAvailable, !ip.isEmpty, !pairPort.isEmpty, !code.isEmpty else { return }
        statusMessage = "Pairing with \(ip):\(pairPort)..."
        let path = adbPath
        let env = buildProcessEnvironment()

        Task.detached {
            let pairProc = Process()
            pairProc.executableURL = URL(fileURLWithPath: path)
            pairProc.environment = env
            pairProc.arguments = ["pair", "\(ip):\(pairPort)", code]

            let pipe = Pipe()
            pairProc.standardOutput = pipe
            pairProc.standardError = pipe
            try? pairProc.run()
            pairProc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            await MainActor.run {
                if output.contains("Successfully paired") || pairProc.terminationStatus == 0 {
                    let cPort = connectPort.isEmpty ? pairPort : connectPort
                    self.statusMessage = "Pairing successful! Connecting to port \(cPort)..."
                    self.connectWirelessAdb(ip: ip, port: cPort)
                } else {
                    self.statusMessage = "Pairing failed: \(output)"
                }
            }
        }
    }

    public func connectWirelessAdb(ip: String, port: String) {
        guard isAdbAvailable, !ip.isEmpty, !port.isEmpty else { return }
        statusMessage = "Connecting ADB to \(ip):\(port)..."
        let path = adbPath
        let env = buildProcessEnvironment()

        Task.detached {
            let connProc = Process()
            connProc.executableURL = URL(fileURLWithPath: path)
            connProc.environment = env
            connProc.arguments = ["connect", "\(ip):\(port)"]

            let pipe = Pipe()
            connProc.standardOutput = pipe
            connProc.standardError = pipe
            try? connProc.run()
            connProc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            await MainActor.run {
                self.statusMessage = output
                self.refreshDevices()
            }
        }
    }

    public func lockToPermanentPort5555() {
        guard isAdbAvailable else { return }
        statusMessage = "Switching device to permanent wireless port 5555..."
        let path = adbPath
        let env = buildProcessEnvironment()

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.environment = env
            proc.arguments = ["tcpip", "5555"]

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            await MainActor.run {
                if output.contains("restarting in TCP mode port: 5555") || proc.terminationStatus == 0 {
                    self.statusMessage = "Port 5555 locked! You can unplug the USB cable now. Reconnecting wirelessly..."
                    let peerIp = LanDiscoveryService.shared.discoveredPeers.first?.ip ?? "192.168.1.28"
                    self.connectWirelessAdb(ip: peerIp, port: "5555")
                } else {
                    self.statusMessage = "Failed to set port 5555: \(output)"
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
            if self.isAudioForwardingEnabled {
                args.append("--audio-buffer=50")
            } else {
                args.append("--no-audio")
            }
            let targetSerial = serial ?? self.resolveActiveDevice()
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
                        let summary = errStr.isEmpty ? "No active device" : errStr
                        self.statusMessage = "60fps Mirror: \(summary). Falling back to in-app mirror..."
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

    public func resolveActiveDevice() -> String? {
        if !connectedAdbDevices.isEmpty {
            if let ipPort = connectedAdbDevices.first(where: { $0.contains(":") && !$0.contains("._tcp") }) {
                return ipPort
            }
            if let usb = connectedAdbDevices.first(where: { !$0.contains("._tcp") }) {
                return usb
            }
            return connectedAdbDevices.first
        }

        guard isAdbAvailable, !adbPath.isEmpty else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        proc.environment = buildProcessEnvironment()
        proc.arguments = ["devices"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        var list: [String] = []
        for line in output.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(separator: "\t")
            if parts.count >= 2 && parts[1] == "device" {
                list.append(String(parts[0]))
            }
        }
        self.connectedAdbDevices = list
        if let ipPort = list.first(where: { $0.contains(":") && !$0.contains("._tcp") }) {
            return ipPort
        }
        if let usb = list.first(where: { !$0.contains("._tcp") }) {
            return usb
        }
        return list.first
    }

    public func executeAdbCommand(args: [String]) {
        guard isAdbAvailable else { return }
        let path = adbPath
        let env = buildProcessEnvironment()
        let target = resolveActiveDevice()

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

    public func launchApp(packageName: String) {
        guard isAdbAvailable else { return }
        executeAdbCommand(args: ["shell", "monkey", "-p", packageName, "-c", "android.intent.category.LAUNCHER", "1"])
    }

    public func capturePhoneScreenshot() async -> URL? {
        guard isAdbAvailable else { return nil }
        let path = adbPath
        let env = buildProcessEnvironment()
        let target = resolveActiveDevice()
        let timestamp = Int(Date().timeIntervalSince1970)
        let remotePath = "/sdcard/Download/continuity_screenshot_\(timestamp).png"
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let localURL = downloads.appendingPathComponent("Screenshot_\(timestamp).png")

        return await Task.detached {
            let capProc = Process()
            capProc.executableURL = URL(fileURLWithPath: path)
            capProc.environment = env
            var capArgs = ["shell", "screencap", "-p", remotePath]
            if let t = target, !t.isEmpty { capArgs = ["-s", t] + capArgs }
            capProc.arguments = capArgs
            try? capProc.run()
            capProc.waitUntilExit()

            let pullProc = Process()
            pullProc.executableURL = URL(fileURLWithPath: path)
            pullProc.environment = env
            var pullArgs = ["pull", remotePath, localURL.path]
            if let t = target, !t.isEmpty { pullArgs = ["-s", t] + pullArgs }
            pullProc.arguments = pullArgs
            try? pullProc.run()
            pullProc.waitUntilExit()

            let rmProc = Process()
            rmProc.executableURL = URL(fileURLWithPath: path)
            rmProc.environment = env
            var rmArgs = ["shell", "rm", remotePath]
            if let t = target, !t.isEmpty { rmArgs = ["-s", t] + rmArgs }
            rmProc.arguments = rmArgs
            try? rmProc.run()

            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
            return nil
        }.value
    }

    public func installApk(fileURL: URL) async -> (success: Bool, message: String) {
        guard isAdbAvailable else { return (false, "ADB is not available") }
        let path = adbPath
        let env = buildProcessEnvironment()
        let target = resolveActiveDevice()

        return await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.environment = env
            var args = ["install", "-r", fileURL.path]
            if let t = target, !t.isEmpty { args = ["-s", t] + args }
            proc.arguments = args

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.contains("Success") || proc.terminationStatus == 0 {
                    return (true, "Installed successfully!")
                } else {
                    return (false, output.isEmpty ? "Install failed (exit code \(proc.terminationStatus))" : output)
                }
            } catch {
                return (false, error.localizedDescription)
            }
        }.value
    }
}

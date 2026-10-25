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

    private var scrcpyProcess: Process?

    public init() {
        detectTooling()
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

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: await self.adbPath)
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
        process.arguments = ["reverse", "tcp:\(port)", "tcp:\(port)"]
        do {
            try process.run()
            process.waitUntilExit()
            let success = process.terminationStatus == 0
            if success {
                print("[ADB Fast-Path] Reverse tunnel active: phone 127.0.0.1:\(port) ➔ Mac :\(port)")
            }
            return success
        } catch {
            print("[ADB Fast-Path] Failed: \(error)")
            return false
        }
    }

    public func startScrcpy(serial: String? = nil) {
        guard isScrcpyAvailable else { return }
        stopScrcpy()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpyPath)

        var args = [
            "--stay-awake",
            "--show-touches",
            "--max-fps=60"
        ]
        if let serial = serial {
            args.append(contentsOf: ["-s", serial])
        }
        process.arguments = args

        try? process.run()
        self.scrcpyProcess = process
        self.isMirroringActive = true
    }

    public func stopScrcpy() {
        if let proc = scrcpyProcess, proc.isRunning {
            proc.terminate()
        }
        scrcpyProcess = nil
        isMirroringActive = false
    }
}

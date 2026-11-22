import Foundation
import Network
import AppKit

public enum WebViewerStatus: String, Sendable {
    case pending = "Pending Approval"
    case approved = "Connected"
    case denied = "Denied"
}

public struct ConnectedWebViewer: Identifiable, Equatable, Sendable {
    public let id: String
    public var deviceLabel: String
    public var ipAddress: String
    public var userAgent: String
    public var status: WebViewerStatus
    public var connectedAt: Date
    public var lastSeen: Date
}

/// Native Swift implementation of Deskreen's Universal Web Display Streaming Server.
/// Serves an interactive HTML5 secondary-monitor viewer over local Wi-Fi (MJPEG + Remote Touch/Mouse + Flip/Fullscreen)
/// with Deskreen-style session QR code and device Allow/Deny security approval.
@MainActor
public final class DeskreenWebHost: ObservableObject {
    public static let shared = DeskreenWebHost()

    @Published public var isRunning: Bool = false
    @Published public var port: UInt16 = 52410
    @Published public var sessionCode: String = ""
    @Published public var shareURL: String = ""
    @Published public var autoApproveLAN: Bool = true
    @Published public var allowBrowserTouchInput: Bool = true
    @Published public var connectedViewers: [ConnectedWebViewer] = []
    @Published public var activeStreamCount: Int = 0
    @Published public var statusText: String = "Web Display Server Stopped"

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.continuity.deskreen.webhost", qos: .userInteractive)
    private let streamBroker = MJPEGStreamBroker()
    private var latestJpegData: Data?

    private init() {
        regenerateSessionCode()
    }

    public func regenerateSessionCode() {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        sessionCode = String((0..<6).compactMap { _ in chars.randomElement() })
        updateShareURL()
    }

    private func updateShareURL() {
        let ip = ConnectionAgent.shared.getLocalIPAddress()
        shareURL = "http://\(ip):\(port)/?session=\(sessionCode)"
    }

    public func toggleServer() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    public func start(preferredPort: UInt16 = 52410) {
        if isRunning { return }
        if sessionCode.isEmpty {
            regenerateSessionCode()
        }

        startListener(on: preferredPort, attemptsRemaining: 5)
    }

    private func startListener(on tryPort: UInt16, attemptsRemaining: Int) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: tryPort) else { return }
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.port = tryPort
                        self.isRunning = true
                        self.updateShareURL()
                        self.statusText = "Live at \(self.shareURL)"
                        ConnectionAgent.shared.debugLog("DeskreenWebHost listening on \(self.shareURL)")
                    case .failed(let error):
                        if attemptsRemaining > 0 {
                            newListener.cancel()
                            self.startListener(on: tryPort + 1, attemptsRemaining: attemptsRemaining - 1)
                        } else {
                            self.isRunning = false
                            self.statusText = "Failed to start: \(error.localizedDescription)"
                        }
                    case .cancelled:
                        self.isRunning = false
                        self.statusText = "Web Display Server Stopped"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            self.listener = newListener
            newListener.start(queue: serverQueue)
        } catch {
            if attemptsRemaining > 0 {
                startListener(on: tryPort + 1, attemptsRemaining: attemptsRemaining - 1)
            } else {
                statusText = "Error: \(error.localizedDescription)"
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        streamBroker.disconnectAll()
        connectedViewers.removeAll()
        activeStreamCount = 0
        isRunning = false
        statusText = "Web Display Server Stopped"
        ConnectionAgent.shared.debugLog("DeskreenWebHost stopped")
    }

    public func approveViewer(id: String) {
        if let idx = connectedViewers.firstIndex(where: { $0.id == id }) {
            connectedViewers[idx].status = .approved
        }
    }

    public func denyViewer(id: String) {
        if let idx = connectedViewers.firstIndex(where: { $0.id == id }) {
            connectedViewers[idx].status = .denied
        }
        streamBroker.disconnect(clientId: id)
        activeStreamCount = streamBroker.activeCount
    }

    public func disconnectViewer(id: String) {
        streamBroker.disconnect(clientId: id)
        connectedViewers.removeAll { $0.id == id }
        activeStreamCount = streamBroker.activeCount
    }

    public func broadcastFrame(_ jpegData: Data) {
        guard isRunning else { return }
        self.latestJpegData = jpegData
        streamBroker.broadcast(jpegData: jpegData)
    }

    public func copyShareURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareURL, forType: .string)
    }

    public func openInLocalBrowser() {
        if let url = URL(string: shareURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - HTTP Connection Handling

    private nonisolated func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveHTTPRequest(on: connection, buffer: Data())
    }

    private nonisolated func receiveHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data = content {
                accumulated.append(data)
            }
            // Wait until header separator \r\n\r\n arrives
            let separator = Data("\r\n\r\n".utf8)
            if let headerRange = accumulated.range(of: separator) {
                let headerData = accumulated.subdata(in: 0..<headerRange.lowerBound)
                let bodyStart = headerRange.upperBound
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength = Self.extractContentLength(from: headerStr)
                let currentBodyLen = accumulated.count - bodyStart
                if currentBodyLen >= contentLength || isComplete {
                    let bodyData = accumulated.subdata(in: bodyStart..<min(accumulated.count, bodyStart + contentLength))
                    self.routeHTTPRequest(headerStr: headerStr, body: bodyData, connection: connection)
                } else {
                    self.receiveHTTPRequest(on: connection, buffer: accumulated)
                }
            } else if isComplete || accumulated.count > 131072 {
                connection.cancel()
            } else {
                self.receiveHTTPRequest(on: connection, buffer: accumulated)
            }
        }
    }

    private nonisolated static func extractContentLength(from headerStr: String) -> Int {
        for line in headerStr.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(val) ?? 0
            }
        }
        return 0
    }

    private nonisolated func routeHTTPRequest(headerStr: String, body: Data, connection: NWConnection) {
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = parts[0]
        let rawTarget = parts[1]

        var userAgent = "Browser"
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("user-agent:") {
                userAgent = line.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespaces)
            }
        }

        let remoteIP: String
        if case let .hostPort(host, _) = connection.endpoint {
            remoteIP = "\(host)".replacingOccurrences(of: "::ffff:", with: "")
        } else {
            remoteIP = "LAN Device"
        }

        let comps = URLComponents(string: "http://localhost\(rawTarget)")
        let path = comps?.path ?? "/"
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        Task { @MainActor [weak self] in
            guard let self = self else {
                connection.cancel()
                return
            }
            self.dispatchRoute(
                method: method,
                path: path,
                query: query,
                userAgent: userAgent,
                remoteIP: remoteIP,
                body: body,
                connection: connection
            )
        }
    }

    private func dispatchRoute(
        method: String,
        path: String,
        query: [String: String],
        userAgent: String,
        remoteIP: String,
        body: Data,
        connection: NWConnection
    ) {
        let providedSession = query["session"] ?? ""
        let clientId = query["clientId"] ?? "viewer-\(remoteIP)"

        if path == "/" || path == "/index.html" {
            let html = Self.buildClientViewerHTML(sessionCode: sessionCode, hostName: Host.current().localizedName ?? "Mac")
            Self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
            return
        }

        // Validate session token for all API & stream endpoints
        guard providedSession.uppercased() == sessionCode.uppercased() || providedSession.isEmpty else {
            let err = Data("{\"error\":\"Invalid session code\"}".utf8)
            Self.sendHTTPResponse(connection: connection, status: "403 Forbidden", contentType: "application/json", body: err)
            return
        }

        if path == "/api/status" {
            let viewer = registerOrUpdateViewer(id: clientId, ip: remoteIP, userAgent: userAgent)
            let ext = ExtendedDisplayManager.shared
            let payload: [String: Any] = [
                "status": viewer.status == .approved ? "approved" : (viewer.status == .denied ? "denied" : "pending"),
                "clientId": viewer.id,
                "sourceLabel": ext.activeSourceDescription,
                "fps": ext.fps,
                "quality": Int(ext.quality * 100),
                "isCapturing": ext.isCaptureActive,
                "allowTouch": allowBrowserTouchInput,
                "macName": Host.current().localizedName ?? "Mac"
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            Self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: data)
            return
        }

        // Ensure viewer is registered and approved
        let viewer = registerOrUpdateViewer(id: clientId, ip: remoteIP, userAgent: userAgent)
        guard viewer.status == .approved else {
            let err = Data("{\"error\":\"Awaiting host approval\"}".utf8)
            Self.sendHTTPResponse(connection: connection, status: "403 Forbidden", contentType: "application/json", body: err)
            return
        }

        if path == "/stream" {
            // Ensure screen capture is running so the web viewer immediately sees live frames!
            if !ExtendedDisplayManager.shared.isCaptureActive {
                ExtendedDisplayManager.shared.startCaptureOnly()
            }
            let headers = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: multipart/x-mixed-replace; boundary=continuityframe\r\n" +
                "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
                "Pragma: no-cache\r\n" +
                "Connection: keep-alive\r\n" +
                "Access-Control-Allow-Origin: *\r\n\r\n"
            connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
                if error != nil {
                    connection.cancel()
                    return
                }
                guard let self = self else { return }
                self.streamBroker.add(clientId: clientId, connection: connection)
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.activeStreamCount = self.streamBroker.activeCount
                    if let last = self.latestJpegData {
                        self.streamBroker.broadcast(jpegData: last)
                    }
                }
            })
            return
        }

        if path == "/frame.jpg" {
            if !ExtendedDisplayManager.shared.isCaptureActive {
                ExtendedDisplayManager.shared.startCaptureOnly()
            }
            if let jpeg = latestJpegData {
                Self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "image/jpeg", body: jpeg)
            } else {
                Self.sendHTTPResponse(connection: connection, status: "503 Service Unavailable", contentType: "text/plain", body: Data("Warming up capture".utf8))
            }
            return
        }

        if path == "/api/input" && method == "POST" {
            if allowBrowserTouchInput,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let type = json["type"] as? String,
               let x = json["x"] as? Double,
               let y = json["y"] as? Double {
                let deltaY = (json["deltaY"] as? Double) ?? 0
                ExtendedDisplayManager.shared.handleWebInput(
                    type: type,
                    xRatio: Float(x),
                    yRatio: Float(y),
                    deltaY: Float(deltaY)
                )
            }
            Self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data("{\"ok\":true}".utf8))
            return
        }

        if path == "/api/quality" && method == "POST" {
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if let q = json["quality"] as? Double {
                    ExtendedDisplayManager.shared.quality = Float(max(0.35, min(0.95, q)))
                }
                if let f = json["fps"] as? Int {
                    ExtendedDisplayManager.shared.updateFPS(max(15, min(60, f)))
                }
            }
            Self.sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data("{\"ok\":true}".utf8))
            return
        }

        Self.sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
    }

    private func registerOrUpdateViewer(id: String, ip: String, userAgent: String) -> ConnectedWebViewer {
        if let idx = connectedViewers.firstIndex(where: { $0.id == id }) {
            connectedViewers[idx].lastSeen = Date()
            return connectedViewers[idx]
        }
        let friendlyLabel = Self.parseDeviceLabel(from: userAgent)
        let initialStatus: WebViewerStatus = autoApproveLAN ? .approved : .pending
        let viewer = ConnectedWebViewer(
            id: id,
            deviceLabel: friendlyLabel,
            ipAddress: ip,
            userAgent: userAgent,
            status: initialStatus,
            connectedAt: Date(),
            lastSeen: Date()
        )
        connectedViewers.append(viewer)
        return viewer
    }

    private static func parseDeviceLabel(from ua: String) -> String {
        let lower = ua.lowercased()
        let os: String
        if lower.contains("ipad") { os = "iPad" }
        else if lower.contains("iphone") { os = "iPhone" }
        else if lower.contains("android") { os = "Android Device" }
        else if lower.contains("mac os") || lower.contains("macintosh") { os = "macOS" }
        else if lower.contains("windows") { os = "Windows PC" }
        else if lower.contains("linux") { os = "Linux" }
        else { os = "Web Device" }

        let browser: String
        if lower.contains("edg/") { browser = "Edge" }
        else if lower.contains("chrome/") { browser = "Chrome" }
        else if lower.contains("firefox/") { browser = "Firefox" }
        else if lower.contains("safari/") { browser = "Safari" }
        else { browser = "Browser" }

        return "\(os) (\(browser))"
    }

    private nonisolated static func sendHTTPResponse(
        connection: NWConnection,
        status: String,
        contentType: String,
        body: Data
    ) {
        let header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Embedded Deskreen-Style Client Viewer Web App

    private static func buildClientViewerHTML(sessionCode: String, hostName: String) -> String {
        let escapedHost = hostName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
        <title>Continuity × Deskreen Display — \(escapedHost)</title>
        <style>
          :root {
            --bg: #07090f;
            --surface: rgba(18, 22, 34, 0.86);
            --border: rgba(255, 255, 255, 0.14);
            --accent: #3b82f6;
            --accent-2: #8b5cf6;
            --text: #f8fafc;
            --muted: #94a3b8;
          }
          * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
          html, body {
            margin: 0; padding: 0; width: 100%; height: 100%;
            background: var(--bg); color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
            overflow: hidden; user-select: none; touch-action: none;
          }
          #stage {
            position: fixed; inset: 0; display: flex; align-items: center; justify-content: center;
            background: #000;
          }
          #screen {
            width: 100%; height: 100%; object-fit: contain;
            transition: transform 0.2s ease;
            display: none;
          }
          #screen.fill { object-fit: cover; }
          #screen.stretch { object-fit: fill; }
          #overlay-status {
            position: fixed; inset: 0; display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 16px;
            background: radial-gradient(circle at top, #111936 0%, #07090f 70%);
            z-index: 20; text-align: center; padding: 24px;
          }
          .badge {
            padding: 6px 14px; border-radius: 999px; font-size: 12px; font-weight: 600;
            background: rgba(59, 130, 246, 0.18); border: 1px solid rgba(59, 130, 246, 0.45);
            color: #93c5fd;
          }
          .spinner {
            width: 44px; height: 44px; border-radius: 50%;
            border: 3px solid rgba(255,255,255,0.12); border-top-color: var(--accent);
            animation: spin 0.9s linear infinite;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
          #toolbar {
            position: fixed; top: 14px; left: 50%; transform: translateX(-50%);
            display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: center;
            padding: 8px 14px; border-radius: 999px;
            background: var(--surface); border: 1px solid var(--border);
            backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px);
            z-index: 30; transition: opacity 0.25s ease, transform 0.25s ease;
            max-width: 96vw;
          }
          #toolbar.hidden { opacity: 0; pointer-events: none; transform: translate(-50%, -18px); }
          .btn {
            background: rgba(255,255,255,0.08); color: var(--text);
            border: 1px solid rgba(255,255,255,0.12); border-radius: 999px;
            padding: 6px 12px; font-size: 12px; font-weight: 600; cursor: pointer;
            display: inline-flex; align-items: center; gap: 6px;
          }
          .btn:hover { background: rgba(255,255,255,0.16); }
          .btn.active { background: var(--accent); border-color: var(--accent); color: #fff; }
          select.btn { appearance: none; padding-right: 14px; }
          .pill-info { font-size: 11px; color: var(--muted); padding: 0 6px; white-space: nowrap; }
          #hud-reveal {
            position: fixed; top: 10px; right: 12px; z-index: 25;
            opacity: 0.45; transition: opacity 0.2s;
          }
          #hud-reveal:hover { opacity: 1; }
        </style>
        </head>
        <body>
          <div id="stage">
            <img id="screen" alt="Mac Extended Display" draggable="false" />
          </div>

          <div id="overlay-status">
            <div class="badge">Continuity × Deskreen × DeskPad</div>
            <div class="spinner" id="spinner"></div>
            <h2 id="status-title" style="margin:0;font-size:22px;">Connecting to \(escapedHost)…</h2>
            <p id="status-sub" style="margin:0;color:var(--muted);max-width:420px;font-size:14px;">
              Establishing direct local Wi-Fi display stream. If host approval is enabled, click Allow on your Mac.
            </p>
          </div>

          <div id="toolbar">
            <span class="pill-info" id="source-label">\(escapedHost)</span>
            <button class="btn active" id="btn-play">⏸ Pause</button>
            <button class="btn" id="btn-fit">📐 Fit</button>
            <button class="btn" id="btn-flip-h" title="Mirror Horizontal (Teleprompter)">⇄ Flip H</button>
            <button class="btn" id="btn-flip-v" title="Flip Vertical">⇅ Flip V</button>
            <button class="btn active" id="btn-touch" title="Control Mac cursor via Touch/Click">👆 Touch</button>
            <select class="btn" id="sel-quality" title="Stream Quality">
              <option value="0.85">HD High</option>
              <option value="0.72" selected>Balanced</option>
              <option value="0.52">Fast Wi-Fi</option>
            </select>
            <button class="btn" id="btn-fs">⛶ Fullscreen</button>
            <button class="btn" id="btn-hide" title="Hide toolbar">✕</button>
          </div>

          <button class="btn" id="hud-reveal" style="display:none;">⚙ Controls</button>

        <script>
        (function() {
          const params = new URLSearchParams(window.location.search);
          const session = params.get('session') || '\(sessionCode)';
          const clientId = localStorage.getItem('continuity_client_id') || ('web-' + Math.random().toString(36).slice(2, 10));
          localStorage.setItem('continuity_client_id', clientId);

          const img = document.getElementById('screen');
          const overlay = document.getElementById('overlay-status');
          const statusTitle = document.getElementById('status-title');
          const statusSub = document.getElementById('status-sub');
          const sourceLabel = document.getElementById('source-label');
          const toolbar = document.getElementById('toolbar');
          const hudReveal = document.getElementById('hud-reveal');

          let isPlaying = true;
          let isApproved = false;
          let flipH = false;
          let flipV = false;
          let touchEnabled = true;
          let fitModes = ['contain', 'fill', 'stretch'];
          let fitIdx = 0;

          function updateTransform() {
            const sx = flipH ? -1 : 1;
            const sy = flipV ? -1 : 1;
            img.style.transform = `scale(${sx}, ${sy})`;
          }

          function startStream() {
            if (!isPlaying || !isApproved) return;
            img.src = `/stream?session=${encodeURIComponent(session)}&clientId=${encodeURIComponent(clientId)}&t=${Date.now()}`;
            img.style.display = 'block';
            overlay.style.display = 'none';
          }

          async function pollStatus() {
            try {
              const res = await fetch(`/api/status?session=${encodeURIComponent(session)}&clientId=${encodeURIComponent(clientId)}`);
              if (!res.ok) throw new Error('Session rejected');
              const data = await res.json();
              sourceLabel.textContent = `${data.macName} · ${data.sourceLabel || 'Display'}`;
              if (data.status === 'approved') {
                if (!isApproved) {
                  isApproved = true;
                  startStream();
                }
              } else if (data.status === 'denied') {
                isApproved = false;
                img.src = '';
                img.style.display = 'none';
                overlay.style.display = 'flex';
                statusTitle.textContent = 'Connection Denied by Mac Host';
                statusSub.textContent = 'The Mac host declined this viewer session.';
              } else {
                isApproved = false;
                overlay.style.display = 'flex';
                statusTitle.textContent = 'Waiting for Host Approval…';
                statusSub.textContent = 'Click "Allow" next to your device in the Continuity Mac app.';
              }
            } catch (err) {
              statusTitle.textContent = 'Reconnecting to Mac…';
              statusSub.textContent = 'Ensure both devices are on the same Wi-Fi network.';
            }
          }

          img.onerror = () => {
            if (isApproved && isPlaying) {
              setTimeout(startStream, 1200);
            }
          };

          // Controls
          document.getElementById('btn-play').onclick = (e) => {
            isPlaying = !isPlaying;
            e.target.textContent = isPlaying ? '⏸ Pause' : '▶ Play';
            e.target.classList.toggle('active', isPlaying);
            if (isPlaying) startStream(); else img.src = '';
          };

          document.getElementById('btn-fit').onclick = (e) => {
            fitIdx = (fitIdx + 1) % fitModes.length;
            img.classList.remove('fill', 'stretch');
            if (fitModes[fitIdx] !== 'contain') img.classList.add(fitModes[fitIdx]);
            const labels = ['📐 Fit', '📐 Fill', '📐 Stretch'];
            e.target.textContent = labels[fitIdx];
          };

          document.getElementById('btn-flip-h').onclick = (e) => {
            flipH = !flipH;
            e.target.classList.toggle('active', flipH);
            updateTransform();
          };

          document.getElementById('btn-flip-v').onclick = (e) => {
            flipV = !flipV;
            e.target.classList.toggle('active', flipV);
            updateTransform();
          };

          document.getElementById('btn-touch').onclick = (e) => {
            touchEnabled = !touchEnabled;
            e.target.classList.toggle('active', touchEnabled);
          };

          document.getElementById('sel-quality').onchange = (e) => {
            fetch(`/api/quality?session=${encodeURIComponent(session)}&clientId=${encodeURIComponent(clientId)}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ quality: parseFloat(e.target.value) })
            }).catch(() => {});
          };

          document.getElementById('btn-fs').onclick = () => {
            if (!document.fullscreenElement) {
              document.documentElement.requestFullscreen?.().catch(() => {});
            } else {
              document.exitFullscreen?.().catch(() => {});
            }
          };

          document.getElementById('btn-hide').onclick = () => {
            toolbar.classList.add('hidden');
            hudReveal.style.display = 'inline-flex';
          };

          hudReveal.onclick = () => {
            toolbar.classList.remove('hidden');
            hudReveal.style.display = 'none';
          };

          // Remote Touch & Pointer Input back to Mac Virtual Display / Screen
          function normalizedCoords(clientX, clientY) {
            const rect = img.getBoundingClientRect();
            const nw = img.naturalWidth || rect.width;
            const nh = img.naturalHeight || rect.height;
            let renderW = rect.width, renderH = rect.height, offX = 0, offY = 0;
            if (fitModes[fitIdx] === 'contain' && nw > 0 && nh > 0) {
              const imgAspect = nw / nh;
              const boxAspect = rect.width / rect.height;
              if (imgAspect > boxAspect) {
                renderH = rect.width / imgAspect;
                offY = (rect.height - renderH) / 2;
              } else {
                renderW = rect.height * imgAspect;
                offX = (rect.width - renderW) / 2;
              }
            }
            let x = (clientX - rect.left - offX) / Math.max(1, renderW);
            let y = (clientY - rect.top - offY) / Math.max(1, renderH);
            x = Math.max(0, Math.min(1, flipH ? 1 - x : x));
            y = Math.max(0, Math.min(1, flipV ? 1 - y : y));
            return { x, y };
          }

          let pointerDown = false;
          let lastMoveTs = 0;

          function sendInput(type, x, y, deltaY = 0) {
            if (!touchEnabled || !isApproved) return;
            fetch(`/api/input?session=${encodeURIComponent(session)}&clientId=${encodeURIComponent(clientId)}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ type, x, y, deltaY })
            }).catch(() => {});
          }

          img.addEventListener('pointerdown', (e) => {
            if (!touchEnabled) return;
            pointerDown = true;
            const c = normalizedCoords(e.clientX, e.clientY);
            sendInput(e.button === 2 ? 'rightclick' : 'down', c.x, c.y);
          });

          img.addEventListener('pointermove', (e) => {
            if (!touchEnabled || !pointerDown) return;
            const now = performance.now();
            if (now - lastMoveTs < 30) return;
            lastMoveTs = now;
            const c = normalizedCoords(e.clientX, e.clientY);
            sendInput('move', c.x, c.y);
          });

          img.addEventListener('pointerup', (e) => {
            if (!touchEnabled || !pointerDown) return;
            pointerDown = false;
            const c = normalizedCoords(e.clientX, e.clientY);
            sendInput('up', c.x, c.y);
          });

          img.addEventListener('contextmenu', (e) => {
            if (touchEnabled) e.preventDefault();
          });

          img.addEventListener('wheel', (e) => {
            if (!touchEnabled) return;
            e.preventDefault();
            const c = normalizedCoords(e.clientX, e.clientY);
            sendInput('scroll', c.x, c.y, e.deltaY);
          }, { passive: false });

          pollStatus();
          setInterval(pollStatus, 2500);
        })();
        </script>
        </body>
        </html>
        """
    }
}

/// Thread-safe MJPEG broadcaster with per-client backpressure so slow Wi-Fi clients never cause lag buildup.
private final class MJPEGStreamBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [String: [ObjectIdentifier: NWConnection]] = [:]
    private var inFlight: Set<ObjectIdentifier> = []

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return streams.values.reduce(0) { $0 + $1.count }
    }

    func add(clientId: String, connection: NWConnection) {
        let oid = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.remove(clientId: clientId, oid: oid)
            default:
                break
            }
        }
        lock.lock()
        var map = streams[clientId] ?? [:]
        map[oid] = connection
        streams[clientId] = map
        lock.unlock()
    }

    func remove(clientId: String, oid: ObjectIdentifier) {
        lock.lock()
        streams[clientId]?.removeValue(forKey: oid)
        if streams[clientId]?.isEmpty == true {
            streams.removeValue(forKey: clientId)
        }
        inFlight.remove(oid)
        lock.unlock()
    }

    func disconnect(clientId: String) {
        lock.lock()
        let conns = streams.removeValue(forKey: clientId)?.values
        if let conns = conns {
            for c in conns {
                inFlight.remove(ObjectIdentifier(c))
            }
        }
        lock.unlock()
        conns?.forEach { $0.cancel() }
    }

    func disconnectAll() {
        lock.lock()
        let all = streams.values.flatMap { $0.values }
        streams.removeAll()
        inFlight.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }

    func broadcast(jpegData: Data) {
        let header = "--continuityframe\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(jpegData)
        packet.append(Data("\r\n".utf8))

        lock.lock()
        var targets: [(String, ObjectIdentifier, NWConnection)] = []
        for (cid, map) in streams {
            for (oid, conn) in map {
                if !inFlight.contains(oid) {
                    inFlight.insert(oid)
                    targets.append((cid, oid, conn))
                }
            }
        }
        lock.unlock()

        for (cid, oid, conn) in targets {
            conn.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                self.lock.lock()
                self.inFlight.remove(oid)
                self.lock.unlock()
                if error != nil {
                    conn.cancel()
                    self.remove(clientId: cid, oid: oid)
                }
            })
        }
    }
}

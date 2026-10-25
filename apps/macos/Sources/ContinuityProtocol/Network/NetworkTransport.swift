import Foundation
import Network

public protocol NetworkSessionDelegate: AnyObject, Sendable {
    func sessionDidConnect(_ session: ContinuityNetworkSession)
    func sessionDidDisconnect(_ session: ContinuityNetworkSession, error: Error?)
    func session(_ session: ContinuityNetworkSession, didReceiveEnvelope envelope: ContinuityEnvelope)
    func session(_ session: ContinuityNetworkSession, didReceiveBinaryChunk chunk: RawBinaryChunk)
}

public extension NetworkSessionDelegate {
    func session(_ session: ContinuityNetworkSession, didReceiveBinaryChunk chunk: RawBinaryChunk) {}
}

public final class ContinuityNetworkSession: @unchecked Sendable {
    public let id: String
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let frameEncoder = FrameEncoder()
    private let frameDecoder = FrameDecoder()
    public weak var delegate: NetworkSessionDelegate?
    private var strongDelegate: NetworkSessionDelegate?

    public func setRetainedDelegate(_ delegate: NetworkSessionDelegate) {
        self.strongDelegate = delegate
        self.delegate = delegate
    }

    public init(connection: NWConnection, id: String = UUID().uuidString) {
        self.id = id
        self.connection = connection
        self.queue = DispatchQueue(label: "com.continuity.session.\(id)")
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.delegate?.sessionDidConnect(self)
                self.receiveNext()
            case .failed(let error):
                self.delegate?.sessionDidDisconnect(self, error: error)
                self.strongDelegate = nil
            case .cancelled:
                self.delegate?.sessionDidDisconnect(self, error: nil)
                self.strongDelegate = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(envelope: ContinuityEnvelope, completion: (@Sendable (Error?) -> Void)? = nil) {
        do {
            let data = try frameEncoder.encode(envelope: envelope)
            connection.send(content: data, completion: .contentProcessed { error in
                completion?(error)
            })
        } catch {
            completion?(error)
        }
    }

    public func send(binaryChunk: RawBinaryChunk, completion: (@Sendable (Error?) -> Void)? = nil) {
        let data = frameEncoder.encode(binaryChunk: binaryChunk)
        connection.send(content: data, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    private func receiveNext() {
        // High-speed 4MB read window for saturated line-rate streaming
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.frameDecoder.append(data: data)
                do {
                    while let frame = try self.frameDecoder.nextFrame() {
                        switch frame {
                        case .envelope(let envelope):
                            self.delegate?.session(self, didReceiveEnvelope: envelope)
                        case .binaryChunk(let chunk):
                            self.delegate?.session(self, didReceiveBinaryChunk: chunk)
                        }
                    }
                } catch {
                    self.delegate?.sessionDidDisconnect(self, error: error)
                    return
                }
            }

            if isComplete {
                self.delegate?.sessionDidDisconnect(self, error: nil)
            } else if let error = error {
                self.delegate?.sessionDidDisconnect(self, error: error)
            } else {
                self.receiveNext()
            }
        }
    }

    public func stop() {
        connection.cancel()
    }
}

public final class ContinuityNetworkListener: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.continuity.listener")
    public let serviceType = "_continuity._tcp"
    public let port: UInt16
    public var onNewSession: (@Sendable (ContinuityNetworkSession) -> Void)?

    public init(port: UInt16 = 52400) {
        self.port = port
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
        }

        let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(52400)
        let listener = try NWListener(using: params, on: nwPort)

        listener.service = NWListener.Service(name: Host.current().localizedName ?? "MacBook Pro", type: serviceType)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("[ContinuityListener] Listening on port \(self.port), advertising Bonjour \(self.serviceType)")
            case .failed(let error):
                print("[ContinuityListener] Failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            let session = ContinuityNetworkSession(connection: connection)
            self.onNewSession?(session)
            session.start()
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}

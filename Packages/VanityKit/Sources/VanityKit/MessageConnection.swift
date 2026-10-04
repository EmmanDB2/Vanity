import Foundation
import Network

extension NWParameters {
    /// TCP tuned for live video on a home network: no Nagle delay, and keepalives so a camera
    /// that walks out of Wi-Fi range is noticed within a few seconds.
    public static var vanity: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVideo
        return params
    }
}

/// Sends and receives `WireMessage`s over an `NWConnection`. All callbacks run on `queue`.
public final class MessageConnection: @unchecked Sendable {
    public let connection: NWConnection
    public let queue: DispatchQueue

    public var onMessage: ((WireMessage) -> Void)?
    public var onReady: (() -> Void)?
    /// Called once, when the connection fails or is cancelled.
    public var onClose: (() -> Void)?

    private var parser = WireParser()
    private var pendingSends = 0
    private var closed = false

    /// Video frames are dropped rather than queued once this many sends are in flight.
    public var maxPendingVideoSends = 3

    public init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?()
            case .failed, .cancelled:
                self.close()
            case .waiting:
                // No route (e.g. Wi-Fi dropped). Give up and let the owner reconnect fresh.
                self.connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    public func cancel() {
        connection.cancel()
    }

    public func send(_ message: WireMessage) {
        pendingSends += 1
        connection.send(content: WireCodec.encode(message), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pendingSends -= 1
            if error != nil { self.connection.cancel() }
        })
    }

    /// Sends a frame unless the network is backed up. Returns false if the frame was dropped,
    /// in which case the sender should start again from a keyframe.
    @discardableResult
    public func sendVideo(_ frame: VideoFrame) -> Bool {
        guard pendingSends < maxPendingVideoSends || frame.isKeyframe else { return false }
        send(.videoFrame(frame))
        return true
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.parser.append(data) {
                        self.onMessage?(message)
                    }
                } catch {
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}

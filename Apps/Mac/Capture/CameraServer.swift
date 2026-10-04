import Foundation
import Network
import Observation
import VanityKit

/// Advertises the Mac on the local network so Vanity Cam (iPad/iPhone) finds it with no setup,
/// and turns each incoming stream into a tile.
@MainActor
@Observable
final class CameraServer {
    /// Shown in onboarding so she knows which Mac to look for.
    let advertisedName = Host.current().localizedName ?? "Vanity Mirror"
    private(set) var isListening = false

    @ObservationIgnored private let hub: FeedHub
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var sessions: [UUID: RemoteCameraSession] = [:]
    /// The newest session for each device, so a stale connection closing late doesn't mark a
    /// reconnected camera as gone.
    @ObservationIgnored private var activeSession: [String: UUID] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "vanity.server", qos: .userInteractive)

    init(hub: FeedHub) {
        self.hub = hub
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .vanity)
            listener.service = NWListener.Service(name: advertisedName, type: VanityService.bonjourType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            retryLater()
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
        case .failed:
            isListening = false
            listener?.cancel()
            listener = nil
            retryLater()
        default:
            break
        }
    }

    private func retryLater() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            start()
        }
    }

    private func accept(_ connection: NWConnection) {
        let sessionID = UUID()
        let session = RemoteCameraSession(connection: MessageConnection(connection: connection, queue: queue))
        sessions[sessionID] = session

        session.onHello = { [weak self, weak session] hello in
            Task { @MainActor in
                guard let self, let session else { return }
                self.activeSession[hello.deviceID] = sessionID
                let feed = self.hub.addFeed(id: hello.deviceID, kind: .remote, deviceName: hello.deviceName)
                self.hub.markConnected(id: hello.deviceID)
                session.attach(router: feed.router)
            }
        }
        session.onClose = { [weak self] deviceID in
            Task { @MainActor in
                guard let self else { return }
                self.sessions.removeValue(forKey: sessionID)
                if let deviceID, self.activeSession[deviceID] == sessionID {
                    self.activeSession.removeValue(forKey: deviceID)
                    self.hub.markDisconnected(id: deviceID)
                }
            }
        }
        session.start()
    }
}

/// One connected Vanity Cam. Everything except `attach` runs on the server queue.
final class RemoteCameraSession: @unchecked Sendable {
    var onHello: ((CameraHello) -> Void)?
    var onClose: ((String?) -> Void)?

    private let connection: MessageConnection
    private let decoder = H264Decoder()
    private let lock = NSLock()
    private var router: FrameRouter?
    private var deviceID: String?
    private var lastKeyframeRequest = Date.distantPast

    init(connection: MessageConnection) {
        self.connection = connection
    }

    func start() {
        decoder.onFrame = { [weak self] buffer in
            guard let self else { return }
            self.lock.withLock { self.router }?.ingest(buffer)
        }
        decoder.onNeedsKeyframe = { [weak self] in
            self?.requestKeyframe()
        }
        connection.onMessage = { [weak self] message in
            self?.handle(message)
        }
        connection.onClose = { [weak self] in
            guard let self else { return }
            self.decoder.invalidate()
            self.onClose?(self.deviceID)
        }
        connection.start()
    }

    func attach(router: FrameRouter) {
        lock.withLock { self.router = router }
        connection.queue.async { [weak self] in
            self?.requestKeyframe(force: true)
        }
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case .hello(let hello):
            deviceID = hello.deviceID
            onHello?(hello)
        case .parameterSets(let sets):
            decoder.setParameterSets(sets)
        case .videoFrame(let frame):
            decoder.decode(frame)
        case .requestKeyframe:
            break
        }
    }

    private func requestKeyframe(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastKeyframeRequest) > 0.5 else { return }
        lastKeyframeRequest = Date()
        connection.send(.requestKeyframe)
    }
}

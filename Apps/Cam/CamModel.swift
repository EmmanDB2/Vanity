import AVFoundation
import Network
import Observation
import UIKit
import VanityKit

/// Finds the Mac, connects, and streams the camera. Reconnects on its own forever.
@MainActor
@Observable
final class CamModel {
    enum Status: Equatable {
        case searching
        case connecting(String)
        case streaming(String)
        case localNetworkDenied
        case cameraDenied
    }

    private(set) var status: Status = .searching
    private(set) var macs: [String] = []
    private(set) var batteryLow = false
    var useFrontCamera = false {
        didSet { camera.setPosition(useFrontCamera ? .front : .back) }
    }

    let camera = CameraCapture()

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var results: [NWBrowser.Result] = []
    @ObservationIgnored private var connection: MessageConnection?
    @ObservationIgnored private let networkQueue = DispatchQueue(label: "vanitycam.network", qos: .userInteractive)
    @ObservationIgnored private let streamer = Streamer()

    /// Remembered so that with two Macs at home it goes back to the one she used last.
    @ObservationIgnored private var preferredMac: String? {
        get { UserDefaults.standard.string(forKey: "preferredMac") }
        set { UserDefaults.standard.set(newValue, forKey: "preferredMac") }
    }

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }

    init() {
        camera.onFrame = { [streamer] buffer, time in
            streamer.encode(buffer, time: time)
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBattery() }
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBattery() }
        }
        updateBattery()
    }

    // MARK: Lifecycle

    func resume() async {
        UIApplication.shared.isIdleTimerDisabled = true
        guard await camera.start(position: useFrontCamera ? .front : .back) else {
            status = .cameraDenied
            return
        }
        startBrowsing()
    }

    func pause() {
        UIApplication.shared.isIdleTimerDisabled = false
        camera.stop()
        browser?.cancel()
        browser = nil
        disconnect()
        status = .searching
    }

    func choose(mac name: String) {
        preferredMac = name
        disconnect()
        connectIfNeeded()
    }

    // MARK: Finding the Mac

    private func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: VanityService.bonjourType, domain: nil), using: .vanity)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.resultsChanged(Array(results)) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.browserChanged(state) }
        }
        browser.start(queue: networkQueue)
        self.browser = browser
    }

    /// kDNSServiceErr_PolicyDenied: she tapped "Don't Allow" on the Local Network prompt.
    private static let policyDenied: Int32 = -65570

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error), .failed(let error):
            if case .dns(let code) = error, code == Self.policyDenied {
                status = .localNetworkDenied
            }
            if case .failed = state {
                browser?.cancel()
                browser = nil
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    startBrowsing()
                }
            }
        case .ready:
            if status == .localNetworkDenied { status = .searching }
        default:
            break
        }
    }

    private func resultsChanged(_ results: [NWBrowser.Result]) {
        self.results = results
        macs = results.compactMap(Self.name(of:))
        connectIfNeeded()
    }

    private func connectIfNeeded() {
        guard connection == nil else { return }
        let target = results.first { Self.name(of: $0) == preferredMac } ?? results.first
        guard let target, let name = Self.name(of: target) else {
            if status != .localNetworkDenied && status != .cameraDenied { status = .searching }
            return
        }
        connect(to: target.endpoint, name: name)
    }

    private static func name(of result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    // MARK: Connection

    private func connect(to endpoint: NWEndpoint, name: String) {
        status = .connecting(name)
        let connection = MessageConnection(connection: NWConnection(to: endpoint, using: .vanity), queue: networkQueue)
        let hello = CameraHello(deviceID: deviceID, deviceName: UIDevice.current.name, deviceModel: UIDevice.current.model)
        let streamer = streamer

        connection.onReady = { [weak self] in
            connection.send(.hello(hello))
            streamer.attach(connection)
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.preferredMac = name
                self.status = .streaming(name)
            }
        }
        connection.onMessage = { message in
            if case .requestKeyframe = message { streamer.requestKeyframe() }
        }
        connection.onClose = { [weak self] in
            streamer.detach(connection)
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.connection = nil
                self.status = .searching
                try? await Task.sleep(for: .seconds(1))
                self.connectIfNeeded()
            }
        }
        self.connection = connection
        connection.start()
    }

    private func disconnect() {
        if let connection {
            streamer.detach(connection)
            connection.cancel()
        }
        connection = nil
    }

    private func updateBattery() {
        let device = UIDevice.current
        batteryLow = device.batteryState == .unplugged && device.batteryLevel >= 0 && device.batteryLevel < 0.2
    }
}

/// Encodes camera frames and sends them to whichever Mac is connected.
/// Drops frames when Wi-Fi can't keep up, then restarts cleanly from a keyframe.
final class Streamer: @unchecked Sendable {
    private let encoder = H264Encoder(bitrate: 6_000_000, frameRate: 30)
    private let lock = NSLock()
    private var connection: MessageConnection?
    private var needsKeyframe = true

    init() {
        encoder.onOutput = { [weak self] output in
            self?.send(output)
        }
    }

    func attach(_ connection: MessageConnection) {
        lock.withLock {
            self.connection = connection
            needsKeyframe = true
        }
        encoder.requestKeyframe()
    }

    func detach(_ connection: MessageConnection) {
        lock.withLock {
            if self.connection === connection { self.connection = nil }
        }
    }

    func requestKeyframe() {
        lock.withLock { needsKeyframe = true }
        encoder.requestKeyframe()
    }

    func encode(_ buffer: CVPixelBuffer, time: CMTime) {
        guard lock.withLock({ connection != nil }) else { return }
        encoder.encode(buffer, presentationTime: time)
    }

    private func send(_ output: H264Encoder.Output) {
        guard let connection = lock.withLock({ connection }) else { return }
        connection.queue.async { [self] in
            let skip: Bool = lock.withLock {
                if needsKeyframe && !output.frame.isKeyframe { return true }
                if output.frame.isKeyframe { needsKeyframe = false }
                return false
            }
            if skip {
                encoder.requestKeyframe()
                return
            }
            if let sets = output.parameterSets {
                connection.send(.parameterSets(sets))
            }
            if !connection.sendVideo(output.frame) {
                lock.withLock { needsKeyframe = true }
                encoder.requestKeyframe()
            }
        }
    }
}

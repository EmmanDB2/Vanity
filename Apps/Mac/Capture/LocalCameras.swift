import AVFoundation
import Observation

/// Finds cameras attached to the Mac (built-in, Continuity Camera iPhone, USB webcams) and keeps
/// one capture session running per camera, adding and removing tiles as they come and go.
@MainActor
@Observable
final class LocalCameras {
    private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    @ObservationIgnored private let hub: FeedHub
    @ObservationIgnored private let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
        mediaType: .video,
        position: .unspecified
    )
    @ObservationIgnored private var sources: [String: LocalCameraSource] = [:]
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(hub: FeedHub) {
        self.hub = hub
    }

    func start() async {
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard authorization == .authorized, observation == nil else { return }

        observation = discovery.observe(\.devices, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private func sync() {
        let devices = discovery.devices
        let currentIDs = Set(devices.map(\.uniqueID))

        for (id, source) in sources where !currentIDs.contains(id) {
            source.stop()
            sources.removeValue(forKey: id)
            hub.removeFeed(id: id)
        }

        for device in devices where sources[device.uniqueID] == nil {
            let feed = hub.addFeed(id: device.uniqueID, kind: kind(of: device), deviceName: device.localizedName)
            let source = LocalCameraSource(device: device, router: feed.router)
            sources[device.uniqueID] = source
            source.start()
        }
    }

    private func kind(of device: AVCaptureDevice) -> Feed.Kind {
        switch device.deviceType {
        case .builtInWideAngleCamera: .builtIn
        case .continuityCamera: .continuity
        default: .external
        }
    }
}

final class LocalCameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let router: FrameRouter
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "vanity.camera", qos: .userInteractive)

    init(device: AVCaptureDevice, router: FrameRouter) {
        self.device = device
        self.router = router
    }

    func start() {
        queue.async { [self] in
            configure()
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        router.ingest(pixelBuffer)
    }
}

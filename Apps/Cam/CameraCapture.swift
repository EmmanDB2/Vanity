import AVFoundation
import UIKit

/// Runs the iPad/iPhone camera, keeping frames upright as the device is turned.
/// On the Simulator, which has no camera, it produces a moving test pattern instead.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "vanitycam.capture", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var testPattern: TestPattern?

    /// Set by the preview so the rotation coordinator can keep it level too.
    weak var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { queue.async { [self] in updateRotationCoordinator() } }
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Returns false if camera access was refused.
    func start(position: AVCaptureDevice.Position) async -> Bool {
        if Self.isSimulator {
            startTestPattern()
            return true
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return false }

        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.inputs.isEmpty {
                    configure(position: position)
                }
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
        return true
    }

    func stop() {
        testPattern?.stop()
        testPattern = nil
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setPosition(_ position: AVCaptureDevice.Position) {
        guard !Self.isSimulator else { return }
        queue.async { [self] in
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            addInput(position: position)
            session.commitConfiguration()
            updateRotationCoordinator()
        }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        addInput(position: position)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        updateRotationCoordinator()
    }

    private func addInput(position: AVCaptureDevice.Position) {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        self.input = input

        // Steady 30 fps keeps the stream smooth and the iPad cool.
        if (try? device.lockForConfiguration()) != nil {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
    }

    /// Keeps the picture upright whichever way the iPad is propped.
    private func updateRotationCoordinator() {
        guard let device = input?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            guard let self else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self.queue.async {
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            let previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let connection = self.previewLayer?.connection, connection.isVideoRotationAngleSupported(previewAngle) {
                    connection.videoRotationAngle = previewAngle
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func startTestPattern() {
        guard testPattern == nil else { return }
        let pattern = TestPattern()
        pattern.onFrame = { [weak self] buffer, time in self?.onFrame?(buffer, time) }
        pattern.start()
        testPattern = pattern
    }
}

/// Moving color bars with a clock, so streaming can be tested on the Simulator.
final class TestPattern: @unchecked Sendable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    private var frameIndex: Int64 = 0
    private let width = 1280
    private let height = 720

    func start() {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "vanitycam.testpattern"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let pool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            let colors: [UIColor] = [.systemPink, .systemPurple, .systemTeal, .systemYellow, .systemOrange, .systemMint]
            let barWidth = CGFloat(width) / CGFloat(colors.count)
            let offset = CGFloat(frameIndex * 4 % Int64(width))
            for (index, color) in colors.enumerated() {
                context.setFillColor(color.cgColor)
                var x = CGFloat(index) * barWidth + offset
                if x >= CGFloat(width) { x -= CGFloat(width) }
                context.fill(CGRect(x: x, y: 0, width: barWidth, height: CGFloat(height)))
                context.fill(CGRect(x: x - CGFloat(width), y: 0, width: barWidth, height: CGFloat(height)))
            }
            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            let text = "Vanity Cam test · \(Date().formatted(date: .omitted, time: .standard))" as NSString
            text.draw(at: CGPoint(x: 40, y: 40), withAttributes: [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white,
            ])
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        onFrame?(buffer, CMTime(value: frameIndex, timescale: 30))
        frameIndex += 1
    }
}

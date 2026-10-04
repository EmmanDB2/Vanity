import CoreVideo
import QuartzCore
import VanityKit
import VideoToolbox

/// The per-camera frame path: every source pushes frames in, and the router decides what the
/// screen shows: live, delayed, or nothing new (frozen). Thread-safe; sources call `ingest`
/// from their own capture queues.
final class FrameRouter: @unchecked Sendable {
    typealias Sink = (CVPixelBuffer) -> Void

    private let lock = NSLock()
    private var sinks: [UUID: Sink] = [:]
    private var frozen = false
    private var delay: DelayBuffer<CVPixelBuffer>?
    private var lastShown: CVPixelBuffer?
    private var lastFrameTime: Double = 0
    private let copier = FrameCopier()

    /// The frame currently on screen (the frozen or delayed one, if those are on). Used for snapshots.
    var currentFrame: CVPixelBuffer? {
        lock.withLock { lastShown }
    }

    var secondsSinceLastFrame: Double {
        let last = lock.withLock { lastFrameTime }
        return last == 0 ? .infinity : CACurrentMediaTime() - last
    }

    /// 0…1 while the delay buffer is filling up after being switched on; nil when delay is off.
    var delayFill: Double? {
        lock.withLock {
            guard let delay else { return nil }
            return min(1, delay.bufferedSeconds / max(delay.delay, 0.1))
        }
    }

    func ingest(_ buffer: CVPixelBuffer, time: Double = CACurrentMediaTime()) {
        var output: CVPixelBuffer?
        let currentSinks: [Sink] = lock.withLock {
            lastFrameTime = time
            if delay != nil {
                if delay!.wantsFrame(at: time), let copy = copier.copy(buffer) {
                    delay!.push(copy, at: time)
                }
                output = delay!.pop(now: time)
            } else {
                output = buffer
            }
            guard !frozen, let output else { return [] }
            lastShown = output
            return Array(sinks.values)
        }
        if let output {
            currentSinks.forEach { $0(output) }
        }
    }

    func setFrozen(_ isFrozen: Bool) {
        lock.withLock { frozen = isFrozen }
    }

    /// Pass nil to go back to live.
    func setDelay(seconds: Double?) {
        lock.withLock {
            if let seconds {
                if delay?.delay != seconds {
                    delay = DelayBuffer(delay: seconds, maxFrameRate: 15, maxFrames: Int(seconds * 15) + 15)
                }
            } else {
                delay = nil
            }
        }
    }

    @discardableResult
    func addSink(_ sink: @escaping Sink) -> UUID {
        let id = UUID()
        let frame: CVPixelBuffer? = lock.withLock {
            sinks[id] = sink
            return lastShown
        }
        // Show the latest picture right away instead of a black tile until the next frame.
        if let frame { sink(frame) }
        return id
    }

    func removeSink(_ id: UUID) {
        _ = lock.withLock { sinks.removeValue(forKey: id) }
    }
}

/// Makes small private copies of camera frames for the delay buffer. Holding on to the camera's
/// own buffers would starve its pool and stall the live feed.
final class FrameCopier {
    private let maxWidth = 1280
    private var session: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)

    func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        if session == nil {
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        }
        guard let session else { return nil }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let scale = min(1, Double(maxWidth) / Double(width))
        let size = (width: Int(Double(width) * scale) & ~1, height: Int(Double(height) * scale) & ~1)

        if pool == nil || size != poolSize {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey: size.width,
                kCVPixelBufferHeightKey: size.height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            poolSize = size
        }
        guard let pool else { return nil }

        var destination: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination)
        guard let destination,
              VTPixelTransferSessionTransferImage(session, from: source, to: destination) == noErr
        else { return nil }
        return destination
    }
}

import Foundation

/// Holds recent frames so a view can play a few seconds behind live.
///
/// Timing only — callers decide what a "frame" is (a downscaled pixel buffer in the app, an Int in tests).
public struct DelayBuffer<Frame> {
    /// How far behind live the output plays, in seconds.
    public var delay: Double {
        didSet { if delay != oldValue { reset() } }
    }
    /// Frames closer together than this are skipped, which caps memory use.
    public var minInterval: Double
    public var maxFrames: Int

    private var frames: [(time: Double, frame: Frame)] = []
    private var head = 0

    public init(delay: Double, maxFrameRate: Double = 15, maxFrames: Int = 15 * 12) {
        self.delay = delay
        self.minInterval = 1 / maxFrameRate
        self.maxFrames = maxFrames
    }

    public var count: Int { frames.count - head }

    /// Seconds of history currently held, used to show a "filling up" state.
    public var bufferedSeconds: Double {
        guard let first = frames[safe: head]?.time, let last = frames.last?.time else { return 0 }
        return last - first
    }

    /// Whether a frame arriving at `time` should be stored, before paying to copy it.
    public func wantsFrame(at time: Double) -> Bool {
        guard let last = frames.last?.time, count > 0 else { return true }
        return time - last >= minInterval * 0.9
    }

    public mutating func push(_ frame: Frame, at time: Double) {
        frames.append((time, frame))
        while count > maxFrames { head += 1 }
        compact()
    }

    /// The newest frame that is at least `delay` seconds old, dropping anything older.
    public mutating func pop(now: Double) -> Frame? {
        let cutoff = now - delay + 1e-6
        var result: Frame?
        while head < frames.count, frames[head].time <= cutoff {
            result = frames[head].frame
            head += 1
        }
        compact()
        return result
    }

    public mutating func reset() {
        frames.removeAll()
        head = 0
    }

    private mutating func compact() {
        if head > 64, head * 2 > frames.count {
            frames.removeFirst(head)
            head = 0
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

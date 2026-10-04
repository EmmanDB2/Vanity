import CoreMedia
import Foundation
import VideoToolbox

/// Decodes the camera app's H.264 stream back into pixel buffers.
public final class H264Decoder: @unchecked Sendable {
    /// Called with each decoded frame, on a VideoToolbox thread.
    public var onFrame: ((CVPixelBuffer) -> Void)?
    /// Called when the decoder can't continue until it sees a fresh keyframe.
    public var onNeedsKeyframe: (() -> Void)?

    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var waitingForKeyframe = true

    public init() {}

    deinit {
        invalidate()
    }

    public func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    public func setParameterSets(_ sets: [Data]) {
        guard let newFormat = Self.makeFormat(sets) else {
            onNeedsKeyframe?()
            return
        }
        if let format, CMFormatDescriptionEqual(format, otherFormatDescription: newFormat) {
            return
        }
        format = newFormat
        invalidate()
        session = makeSession(format: newFormat)
        waitingForKeyframe = true
    }

    public func decode(_ frame: VideoFrame) {
        guard let session, let format else {
            onNeedsKeyframe?()
            return
        }
        if waitingForKeyframe {
            guard frame.isKeyframe else { return }
            waitingForKeyframe = false
        }

        guard let sample = makeSampleBuffer(frame, format: format) else { return }
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            if status == noErr, let imageBuffer {
                self?.onFrame?(imageBuffer)
            }
        }
        if status != noErr {
            waitingForKeyframe = true
            onNeedsKeyframe?()
        }
    }

    private func makeSession(format: CMVideoFormatDescription) -> VTDecompressionSession? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        if let session {
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        }
        return status == noErr ? session : nil
    }

    private func makeSampleBuffer(_ frame: VideoFrame, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        let length = frame.data.count
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else { return nil }

        let copyStatus = frame.data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length)
        }
        guard copyStatus == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: frame.timestampNanos, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = length
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }

    static func makeFormat(_ sets: [Data]) -> CMVideoFormatDescription? {
        guard !sets.isEmpty, sets.allSatisfy({ !$0.isEmpty }) else { return nil }
        let pointers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: pointer, count: set.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }

        let constPointers = pointers.map { UnsafePointer($0) }
        let sizes = sets.map(\.count)
        var format: CMVideoFormatDescription?
        let status = constPointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: sets.count,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &format
                )
            }
        }
        return status == noErr ? format : nil
    }
}

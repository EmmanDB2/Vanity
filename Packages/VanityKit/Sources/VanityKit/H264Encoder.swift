import CoreMedia
import Foundation
import VideoToolbox

/// Low-latency H.264 encoder. Recreates its session when the input size changes (e.g. the iPad rotates).
public final class H264Encoder: @unchecked Sendable {
    public struct Output {
        /// SPS + PPS, present on keyframes.
        public var parameterSets: [Data]?
        public var frame: VideoFrame
    }

    public var onOutput: ((Output) -> Void)?

    private let bitrate: Int
    private let frameRate: Int
    private var session: VTCompressionSession?
    private var width: Int32 = 0
    private var height: Int32 = 0
    private var forceKeyframe = true
    private let lock = NSLock()

    public init(bitrate: Int = 6_000_000, frameRate: Int = 30) {
        self.bitrate = bitrate
        self.frameRate = frameRate
    }

    deinit {
        invalidate()
    }

    public func requestKeyframe() {
        lock.withLock { forceKeyframe = true }
    }

    public func invalidate() {
        lock.withLock {
            if let session {
                VTCompressionSessionInvalidate(session)
            }
            session = nil
        }
    }

    public func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let w = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let h = Int32(CVPixelBufferGetHeight(pixelBuffer))

        let (session, keyframe): (VTCompressionSession?, Bool) = lock.withLock {
            if self.session == nil || w != width || h != height {
                if let old = self.session { VTCompressionSessionInvalidate(old) }
                self.session = makeSession(width: w, height: h)
                width = w
                height = h
                forceKeyframe = true
            }
            let keyframe = forceKeyframe
            forceKeyframe = false
            return (self.session, keyframe)
        }
        guard let session else { return }

        let properties: CFDictionary? = keyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
            : nil

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: properties,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer, let self else {
                self?.requestKeyframe()
                return
            }
            self.emit(sampleBuffer)
        }
    }

    private func makeSession(width: Int32, height: Int32) -> VTCompressionSession? {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { return nil }

        let set = { (key: CFString, value: CFTypeRef) -> Void in
            _ = VTSessionSetProperty(session, key: key, value: value)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, frameRate as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (frameRate * 2) as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }

    private func emit(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKeyframe = !notSync
        }

        var parameterSets: [Data]?
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSets = Self.parameterSets(of: format)
        }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard status == noErr else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let nanos = pts.isValid ? Int64(pts.seconds * 1_000_000_000) : 0
        onOutput?(Output(parameterSets: parameterSets, frame: VideoFrame(isKeyframe: isKeyframe, timestampNanos: nanos, data: data)))
    }

    static func parameterSets(of format: CMFormatDescription) -> [Data] {
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        var sets: [Data] = []
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if status == noErr, let pointer {
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        return sets
    }
}

import CoreVideo
import XCTest
@testable import VanityKit

final class WireTests: XCTestCase {
    let messages: [WireMessage] = [
        .hello(CameraHello(deviceID: "abc", deviceName: "Her iPad", deviceModel: "iPad")),
        .parameterSets([Data([0x67, 1, 2, 3]), Data([0x68, 4])]),
        .videoFrame(VideoFrame(isKeyframe: true, timestampNanos: 123_456_789, data: Data(repeating: 7, count: 5000))),
        .videoFrame(VideoFrame(isKeyframe: false, timestampNanos: -1, data: Data())),
        .requestKeyframe,
    ]

    func testRoundTripInOneChunk() throws {
        var parser = WireParser()
        let stream = messages.map(WireCodec.encode).reduce(Data(), +)
        XCTAssertEqual(try parser.append(stream), messages)
    }

    func testRoundTripByteByByte() throws {
        var parser = WireParser()
        let stream = messages.map(WireCodec.encode).reduce(Data(), +)
        var decoded: [WireMessage] = []
        for byte in stream {
            decoded += try parser.append(Data([byte]))
        }
        XCTAssertEqual(decoded, messages)
    }

    func testRejectsUnknownType() {
        var parser = WireParser()
        XCTAssertThrowsError(try parser.append(Data([99, 0, 0, 0, 0]))) { error in
            XCTAssertEqual(error as? WireError, .unknownType(99))
        }
    }

    func testRejectsOversizedPayload() {
        var parser = WireParser()
        XCTAssertThrowsError(try parser.append(Data([3, 0xFF, 0xFF, 0xFF, 0xFF])))
    }

    func testRejectsTruncatedParameterSets() {
        var parser = WireParser()
        // Claims one 10-byte set but carries 2 bytes.
        XCTAssertThrowsError(try parser.append(Data([2, 0, 0, 0, 5, 1, 0, 10, 1, 2])))
    }
}

final class DelayBufferTests: XCTestCase {
    func testPlaysBackAfterDelay() {
        var buffer = DelayBuffer<Int>(delay: 2, maxFrameRate: 10)
        for i in 0..<30 {
            let t = Double(i) * 0.1
            if buffer.wantsFrame(at: t) { buffer.push(i, at: t) }
        }
        // At t=2.9 the newest frame at least 2s old is the one from t=0.9.
        XCTAssertEqual(buffer.pop(now: 2.9), 9)
        XCTAssertNil(buffer.pop(now: 2.9))
        XCTAssertEqual(buffer.pop(now: 3.05), 10)
    }

    func testNothingBeforeBufferFills() {
        var buffer = DelayBuffer<Int>(delay: 5)
        buffer.push(1, at: 0)
        XCTAssertNil(buffer.pop(now: 4.9))
        XCTAssertEqual(buffer.pop(now: 5), 1)
    }

    func testThrottlesFrameRate() {
        let buffer = DelayBuffer<Int>(delay: 1, maxFrameRate: 15)
        var copy = buffer
        copy.push(0, at: 0)
        XCTAssertFalse(copy.wantsFrame(at: 1.0 / 30))
        XCTAssertTrue(copy.wantsFrame(at: 1.0 / 15))
    }

    func testCapsMemory() {
        var buffer = DelayBuffer<Int>(delay: 100, maxFrameRate: 1000, maxFrames: 10)
        for i in 0..<500 { buffer.push(i, at: Double(i)) }
        XCTAssertEqual(buffer.count, 10)
        XCTAssertEqual(buffer.pop(now: 10_000), 499)
    }

    func testChangingDelayResets() {
        var buffer = DelayBuffer<Int>(delay: 1)
        buffer.push(1, at: 0)
        buffer.delay = 3
        XCTAssertEqual(buffer.count, 0)
    }
}

final class CodecTests: XCTestCase {
    /// Encodes synthetic frames and decodes them again, the same path the iPad → Mac stream takes.
    func testEncodeDecodeRoundTrip() throws {
        let encoder = H264Encoder(bitrate: 2_000_000)
        let decoder = H264Decoder()
        let decoded = expectation(description: "decoded frames")
        decoded.assertForOverFulfill = false
        var decodedSize: (Int, Int)?
        var parser = WireParser()

        decoder.onFrame = { buffer in
            decodedSize = (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer))
            decoded.fulfill()
        }

        let lock = NSLock()
        encoder.onOutput = { output in
            lock.withLock {
                var wire = Data()
                if let sets = output.parameterSets { wire += WireCodec.encode(.parameterSets(sets)) }
                wire += WireCodec.encode(.videoFrame(output.frame))
                for message in (try? parser.append(wire)) ?? [] {
                    switch message {
                    case .parameterSets(let sets): decoder.setParameterSets(sets)
                    case .videoFrame(let frame): decoder.decode(frame)
                    default: break
                    }
                }
            }
        }

        for i in 0..<10 {
            encoder.encode(try makeBuffer(width: 640, height: 480, shade: UInt8(i * 20)), presentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        wait(for: [decoded], timeout: 10)
        XCTAssertEqual(decodedSize?.0, 640)
        XCTAssertEqual(decodedSize?.1, 480)
    }

    private func makeBuffer(width: Int, height: Int, shade: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        memset(CVPixelBufferGetBaseAddress(pixelBuffer), Int32(shade), CVPixelBufferGetDataSize(pixelBuffer))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}

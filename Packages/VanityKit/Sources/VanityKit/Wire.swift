import Foundation

/// Bonjour + protocol constants shared by the Mac app and the camera app.
public enum VanityService {
    public static let bonjourType = "_vanitymirror._tcp"
    public static let protocolVersion = 1
}

/// Sent by a camera right after it connects.
public struct CameraHello: Codable, Equatable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var deviceModel: String
    public var protocolVersion: Int

    public init(deviceID: String, deviceName: String, deviceModel: String, protocolVersion: Int = VanityService.protocolVersion) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.protocolVersion = protocolVersion
    }
}

/// One encoded H.264 access unit, NAL units in AVCC form (4-byte big-endian length prefixes).
public struct VideoFrame: Equatable, Sendable {
    public var isKeyframe: Bool
    public var timestampNanos: Int64
    public var data: Data

    public init(isKeyframe: Bool, timestampNanos: Int64, data: Data) {
        self.isKeyframe = isKeyframe
        self.timestampNanos = timestampNanos
        self.data = data
    }
}

public enum WireMessage: Equatable, Sendable {
    case hello(CameraHello)
    /// H.264 SPS + PPS. Sent before the first keyframe and whenever the stream format changes.
    case parameterSets([Data])
    case videoFrame(VideoFrame)
    case requestKeyframe
}

public enum WireError: Error, Equatable {
    case unknownType(UInt8)
    case tooLarge(Int)
    case malformed
}

/// Framing: `[type: UInt8][length: UInt32 BE][payload]`.
public enum WireCodec {
    public static let headerSize = 5
    public static let maxPayload = 16 * 1024 * 1024

    enum Kind: UInt8 {
        case hello = 1
        case parameterSets = 2
        case videoFrame = 3
        case requestKeyframe = 4
    }

    public static func encode(_ message: WireMessage) -> Data {
        let kind: Kind
        var payload = Data()
        switch message {
        case .hello(let hello):
            kind = .hello
            payload = (try? JSONEncoder().encode(hello)) ?? Data()
        case .parameterSets(let sets):
            kind = .parameterSets
            payload.append(UInt8(sets.count))
            for set in sets {
                payload.appendBigEndian(UInt16(set.count))
                payload.append(set)
            }
        case .videoFrame(let frame):
            kind = .videoFrame
            payload.append(frame.isKeyframe ? 1 : 0)
            payload.appendBigEndian(UInt64(bitPattern: frame.timestampNanos))
            payload.append(frame.data)
        case .requestKeyframe:
            kind = .requestKeyframe
        }

        var out = Data(capacity: headerSize + payload.count)
        out.append(kind.rawValue)
        out.appendBigEndian(UInt32(payload.count))
        out.append(payload)
        return out
    }

    static func decode(kind rawKind: UInt8, payload: Data) throws -> WireMessage {
        guard let kind = Kind(rawValue: rawKind) else { throw WireError.unknownType(rawKind) }
        var reader = ByteReader(payload)
        switch kind {
        case .hello:
            guard let hello = try? JSONDecoder().decode(CameraHello.self, from: payload) else { throw WireError.malformed }
            return .hello(hello)
        case .parameterSets:
            let count = Int(try reader.readUInt8())
            var sets: [Data] = []
            for _ in 0..<count {
                let length = Int(try reader.readUInt16())
                sets.append(try reader.readBytes(length))
            }
            return .parameterSets(sets)
        case .videoFrame:
            let flags = try reader.readUInt8()
            let timestamp = Int64(bitPattern: try reader.readUInt64())
            return .videoFrame(VideoFrame(isKeyframe: flags & 1 == 1, timestampNanos: timestamp, data: reader.remaining()))
        case .requestKeyframe:
            return .requestKeyframe
        }
    }
}

/// Incrementally splits a TCP byte stream into messages.
public struct WireParser {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [WireMessage] {
        buffer.append(data)
        var messages: [WireMessage] = []
        var offset = buffer.startIndex

        while buffer.endIndex - offset >= WireCodec.headerSize {
            let kind = buffer[offset]
            var length = 0
            for i in 1...4 { length = length << 8 | Int(buffer[offset + i]) }
            guard length <= WireCodec.maxPayload else { throw WireError.tooLarge(length) }
            let payloadStart = offset + WireCodec.headerSize
            guard buffer.endIndex - payloadStart >= length else { break }
            let payload = Data(buffer[payloadStart..<payloadStart + length])
            messages.append(try WireCodec.decode(kind: kind, payload: payload))
            offset = payloadStart + length
        }

        if offset > buffer.startIndex {
            buffer = Data(buffer[offset...])
        }
        return messages
    }
}

struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, data.endIndex - offset >= count else { throw WireError.malformed }
        defer { offset += count }
        return Data(data[offset..<offset + count])
    }

    mutating func readUInt8() throws -> UInt8 {
        try readBytes(1).first!
    }

    mutating func readUInt16() throws -> UInt16 {
        try readBytes(2).reduce(0) { $0 << 8 | UInt16($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        try readBytes(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    func remaining() -> Data {
        Data(data[offset...])
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

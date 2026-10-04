import Foundation
import Observation

/// Per-camera choices that are remembered between launches.
struct FeedSettings: Codable, Equatable {
    var label: String
    var mirrored: Bool
    var quarterTurns: Int = 0
    var delayOn = false

    private static func key(_ feedID: String) -> String { "feed.settings.\(feedID)" }

    static func load(for feedID: String) -> FeedSettings? {
        guard let data = UserDefaults.standard.data(forKey: key(feedID)) else { return nil }
        return try? JSONDecoder().decode(FeedSettings.self, from: data)
    }

    func save(for feedID: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key(feedID))
    }
}

/// One camera view on the mirror: the MacBook camera, a Continuity Camera iPhone, a USB webcam,
/// or an iPad/iPhone running Vanity Cam.
@Observable
final class Feed: Identifiable {
    enum Kind {
        case builtIn, continuity, external, remote
    }

    enum Status {
        case starting, live, reconnecting
    }

    let id: String
    let kind: Kind
    var deviceName: String
    var status: Status = .starting
    /// 0…1 while the delay buffer fills; nil when delay is off.
    var delayFill: Double?

    var settings: FeedSettings {
        didSet { settings.save(for: id) }
    }

    var isFrozen = false {
        didSet { router.setFrozen(isFrozen) }
    }

    // Zoom and pan reset each launch; they're for a quick close look, not a setting.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    @ObservationIgnored let router = FrameRouter()

    init(id: String, kind: Kind, deviceName: String, settings: FeedSettings) {
        self.id = id
        self.kind = kind
        self.deviceName = deviceName
        self.settings = settings
    }

    var symbol: String {
        switch kind {
        case .builtIn: "laptopcomputer"
        case .continuity: "iphone"
        case .external: "web.camera"
        case .remote: deviceName.localizedCaseInsensitiveContains("iphone") ? "iphone" : "ipad"
        }
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
    }
}

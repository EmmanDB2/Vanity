import Foundation
import Observation

/// Every camera currently on the mirror, plus mirror-wide choices like delay length.
@MainActor
@Observable
final class FeedHub {
    private(set) var feeds: [Feed] = []
    var spotlightID: String?

    var delaySeconds: Double = UserDefaults.standard.object(forKey: "delaySeconds") as? Double ?? 5 {
        didSet {
            UserDefaults.standard.set(delaySeconds, forKey: "delaySeconds")
            feeds.forEach(applyDelay)
        }
    }

    @ObservationIgnored private var removalTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var statusTimer: Timer?

    init() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    var spotlight: Feed? {
        feeds.first { $0.id == spotlightID }
    }

    var anyDelayOn: Bool {
        feeds.contains { $0.settings.delayOn }
    }

    func feed(id: String) -> Feed? {
        feeds.first { $0.id == id }
    }

    // MARK: Adding and removing cameras

    @discardableResult
    func addFeed(id: String, kind: Feed.Kind, deviceName: String) -> Feed {
        if let existing = feed(id: id) {
            removalTasks.removeValue(forKey: id)?.cancel()
            existing.deviceName = deviceName
            return existing
        }
        let settings = FeedSettings.load(for: id) ?? defaultSettings(kind: kind, deviceName: deviceName)
        let feed = Feed(id: id, kind: kind, deviceName: deviceName, settings: settings)
        applyDelay(feed)
        // Front camera first, then in the order they arrived.
        if kind == .builtIn {
            feeds.insert(feed, at: 0)
        } else {
            feeds.append(feed)
        }
        return feed
    }

    func removeFeed(id: String) {
        removalTasks.removeValue(forKey: id)?.cancel()
        feeds.removeAll { $0.id == id }
        if spotlightID == id { spotlightID = nil }
    }

    /// A Vanity Cam device dropped off. Keep its tile ("Reconnecting…") for a while in case it's
    /// just a Wi-Fi blip, then tidy it away.
    func markDisconnected(id: String) {
        guard let feed = feed(id: id) else { return }
        feed.status = .reconnecting
        removalTasks[id]?.cancel()
        removalTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.removeFeed(id: id)
        }
    }

    func markConnected(id: String) {
        removalTasks.removeValue(forKey: id)?.cancel()
        feed(id: id)?.status = .starting
    }

    private func defaultSettings(kind: Feed.Kind, deviceName: String) -> FeedSettings {
        let used = Set(feeds.map(\.settings.label))
        let preferred: [String] = switch kind {
        case .builtIn: ["Front"]
        case .continuity: ["Back", "Left", "Right"]
        case .external, .remote: ["Left", "Right", "Back", "Top"]
        }
        let label = preferred.first { !used.contains($0) } ?? deviceName
        // A mirror should act like a mirror when you face it; side and back views show the truth.
        return FeedSettings(label: label, mirrored: kind == .builtIn)
    }

    // MARK: Mirror-wide controls

    func toggleSpotlight(_ feed: Feed) {
        spotlightID = spotlightID == feed.id ? nil : feed.id
    }

    func setDelay(_ on: Bool, for feed: Feed) {
        feed.settings.delayOn = on
        applyDelay(feed)
    }

    func toggleDelayForAll() {
        let turnOn = !anyDelayOn
        feeds.forEach { setDelay(turnOn, for: $0) }
    }

    func toggleFreezeForAll() {
        let freeze = feeds.contains { !$0.isFrozen }
        feeds.forEach { $0.isFrozen = freeze }
    }

    /// Shortcut targets: the spotlighted camera if there is one, otherwise all of them.
    var focusedFeeds: [Feed] {
        spotlight.map { [$0] } ?? feeds
    }

    private func applyDelay(_ feed: Feed) {
        feed.router.setDelay(seconds: feed.settings.delayOn ? delaySeconds : nil)
    }

    private func refreshStatus() {
        for feed in feeds {
            let fill = feed.router.delayFill
            if feed.delayFill != fill { feed.delayFill = fill }

            guard feed.status != .reconnecting else { continue }
            let status: Feed.Status = feed.router.secondsSinceLastFrame < 2 ? .live : .starting
            if feed.status != status { feed.status = status }
        }
    }
}

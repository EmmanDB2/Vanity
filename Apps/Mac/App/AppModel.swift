import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Mode: String, CaseIterable, Identifiable {
        case mirror, lookbook
        var id: String { rawValue }
    }

    var mode: Mode = .mirror {
        didSet { updateDisplaySleep() }
    }

    let hub = FeedHub()
    let store = LookStore()
    let cameras: LocalCameras
    let server: CameraServer

    // Snapshot flow
    private(set) var countdown: Int?
    private(set) var flash = false
    var pendingShots: [CapturedShot]?

    /// Lookbook navigation.
    var openLookID: Look.ID?
    /// A saved look shown beside the live views ("Recreate this look").
    var referenceLookID: Look.ID?

    var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingDone")

    @ObservationIgnored private var awakeActivity: NSObjectProtocol?

    init() {
        cameras = LocalCameras(hub: hub)
        server = CameraServer(hub: hub)
    }

    var referenceLook: Look? {
        referenceLookID.flatMap(store.look(id:))
    }

    func start() async {
        server.start()
        updateDisplaySleep()
        await cameras.start()
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        showOnboarding = false
    }

    // MARK: Capture

    /// 3-2-1 so her hands can get back in place, then a photo from every camera at once.
    func captureLook() async {
        guard countdown == nil, !hub.feeds.isEmpty else { return }
        for count in stride(from: 3, through: 1, by: -1) {
            countdown = count
            try? await Task.sleep(for: .seconds(1))
        }
        countdown = nil

        let shots = hub.feeds.compactMap(Snapshotter.capture)
        flash = true
        NSSound(named: "Tink")?.play()
        try? await Task.sleep(for: .milliseconds(180))
        flash = false

        if !shots.isEmpty {
            pendingShots = shots
        }
    }

    /// Saves captured photos as a brand new look and opens it.
    func saveShotsAsNewLook(_ shots: [CapturedShot], name: String) {
        var look = Look(name: name.isEmpty ? Self.defaultLookName() : name)
        look.photos = shots.compactMap { store.addPhoto(jpeg: $0.jpeg, angle: $0.angle) }
        store.add(look)
        pendingShots = nil
        openLookID = look.id
        mode = .lookbook
    }

    func addShots(_ shots: [CapturedShot], to lookID: Look.ID) {
        guard var look = store.look(id: lookID) else { return }
        look.photos += shots.compactMap { store.addPhoto(jpeg: $0.jpeg, angle: $0.angle) }
        store.update(look)
        pendingShots = nil
    }

    func recreate(_ look: Look) {
        referenceLookID = look.id
        mode = .mirror
    }

    static func defaultLookName() -> String {
        "Look · " + Date().formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Keep the screen on

    /// The display shouldn't dim halfway through an install.
    private func updateDisplaySleep() {
        if mode == .mirror, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Showing the mirror")
        } else if mode != .mirror, let activity = awakeActivity {
            ProcessInfo.processInfo.endActivity(activity)
            awakeActivity = nil
        }
    }
}

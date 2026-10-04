import AppKit
import Observation

/// Saves looks as one JSON file plus a folder of JPEG photos in Application Support.
@MainActor
@Observable
final class LookStore {
    /// Newest first.
    private(set) var looks: [Look] = []

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let imageCache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    private var indexURL: URL { directory.appending(path: "looks.json") }
    private var photosURL: URL { directory.appending(path: "Photos", directoryHint: .isDirectory) }

    init(directory: URL = LookStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        load()
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Vanity", directoryHint: .isDirectory)
    }

    func look(id: Look.ID) -> Look? {
        looks.first { $0.id == id }
    }

    var allTags: [String] {
        Array(Set(looks.flatMap(\.tags))).sorted()
    }

    // MARK: Changes

    func add(_ look: Look) {
        looks.insert(look, at: 0)
        save()
    }

    func update(_ look: Look) {
        guard let index = looks.firstIndex(where: { $0.id == look.id }) else { return }
        guard looks[index] != look else { return }
        looks[index] = look
        scheduleSave()
    }

    func delete(_ look: Look) {
        looks.removeAll { $0.id == look.id }
        for photo in look.photos {
            try? FileManager.default.removeItem(at: url(for: photo))
        }
        save()
    }

    /// Stores JPEG data and returns the photo record to attach to a look.
    func addPhoto(jpeg: Data, angle: String) -> LookPhoto? {
        let photo = LookPhoto(angle: angle, fileName: "\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: url(for: photo), options: .atomic)
            return photo
        } catch {
            return nil
        }
    }

    func removePhoto(_ photo: LookPhoto, from look: inout Look) {
        look.photos.removeAll { $0.id == photo.id }
        try? FileManager.default.removeItem(at: url(for: photo))
    }

    func url(for photo: LookPhoto) -> URL {
        photosURL.appending(path: photo.fileName)
    }

    func image(for photo: LookPhoto) -> NSImage? {
        let key = photo.fileName as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url(for: photo)) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            looks = try Self.decoder.decode([Look].self, from: data)
        } catch {
            // Never silently lose her lookbook: set the unreadable file aside before starting fresh.
            let backup = directory.appending(path: "looks-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: indexURL, to: backup)
        }
    }

    /// Edits arrive per keystroke; batch them into one write.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func flush() {
        if pendingSave != nil { save() }
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let data = try? Self.encoder.encode(looks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

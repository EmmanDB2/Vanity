import XCTest
@testable import Vanity

@MainActor
final class LookStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "VanityTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLookSurvivesRelaunch() throws {
        let store = LookStore(directory: directory)
        var look = Look(name: "Birthday curls")
        look.hair = [
            HairUsed(texture: .bodyWave, colorName: "1B", lengthInches: 22, bundles: 2),
            HairUsed(texture: .bodyWave, colorName: "27", swatchHex: "#B8834A", lengthInches: 24, bundles: 1),
        ]
        look.closure = ClosureInfo(kind: .frontal, size: "13×4", lengthInches: 18, lace: "HD")
        look.partingChart.top = [ChartStroke(kind: .part, points: [ChartPoint(x: 0.5, y: 0.1), ChartPoint(x: 0.5, y: 0.5)], colorHex: "#FFFFFF", width: 0.012)]
        look.partingChart.back = [ChartStroke(kind: .color, points: [ChartPoint(x: 0.3, y: 0.3)], hairID: look.hair[1].id, colorHex: "#B8834A", width: 0.1)]
        look.photos = [try XCTUnwrap(store.addPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]), angle: "Back"))]
        store.add(look)
        store.flush()

        let reopened = LookStore(directory: directory)
        XCTAssertEqual(reopened.looks, [look])
        XCTAssertEqual(reopened.looks.first?.totalBundles, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.url(for: look.photos[0]).path))
    }

    func testEditsAreSavedAfterFlush() {
        let store = LookStore(directory: directory)
        var look = Look(name: "Draft")
        store.add(look)
        look.notes = "Used mousse on the leave-out"
        store.update(look)
        store.flush()

        XCTAssertEqual(LookStore(directory: directory).looks.first?.notes, "Used mousse on the leave-out")
    }

    func testDeleteRemovesPhotos() throws {
        let store = LookStore(directory: directory)
        var look = Look(name: "Gone")
        let photo = try XCTUnwrap(store.addPhoto(jpeg: Data([1, 2, 3]), angle: "Front"))
        look.photos = [photo]
        store.add(look)
        store.delete(look)

        XCTAssertTrue(store.looks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: photo).path))
    }

    func testUnreadableFileIsKeptAside() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "looks.json"))

        let store = LookStore(directory: directory)
        XCTAssertTrue(store.looks.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("looks-unreadable-") })
    }

    func testOlderLooksMissingNewFieldsStillOpen() throws {
        let json = #"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","name":"Old look"}]"#
        let looks = try JSONDecoder().decode([Look].self, from: Data(json.utf8))
        XCTAssertEqual(looks.first?.name, "Old look")
        XCTAssertEqual(looks.first?.hair, [])
        XCTAssertTrue(looks.first?.partingChart.isEmpty ?? false)
    }
}

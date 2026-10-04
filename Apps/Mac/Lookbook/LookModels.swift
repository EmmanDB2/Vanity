import Foundation

/// One saved hairstyle: photos from every angle plus the "recipe" to recreate it.
struct Look: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var isFavorite = false
    var rating = 0
    var tags: [String] = []
    var photos: [LookPhoto] = []

    var installMethod: InstallMethod = .sewIn
    var totalLengthInches: Int?
    var hair: [HairUsed] = []
    var closure: ClosureInfo?
    var partingChart = PartingChart()
    var products = ""
    var notes = ""

    var totalBundles: Int {
        hair.reduce(0) { $0 + $1.bundles }
    }

    var coverPhoto: LookPhoto? {
        photos.first { $0.angle == "Front" } ?? photos.first
    }

    init(name: String) {
        self.name = name
    }

    // Decode field by field with defaults so looks saved by an older version still open after
    // new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled look"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        photos = try c.decodeIfPresent([LookPhoto].self, forKey: .photos) ?? []
        installMethod = try c.decodeIfPresent(InstallMethod.self, forKey: .installMethod) ?? .other
        totalLengthInches = try c.decodeIfPresent(Int.self, forKey: .totalLengthInches)
        hair = try c.decodeIfPresent([HairUsed].self, forKey: .hair) ?? []
        closure = try c.decodeIfPresent(ClosureInfo.self, forKey: .closure)
        partingChart = try c.decodeIfPresent(PartingChart.self, forKey: .partingChart) ?? PartingChart()
        products = try c.decodeIfPresent(String.self, forKey: .products) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct LookPhoto: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "Front", "Left", "Back"… the camera label when it was taken.
    var angle: String
    var fileName: String
}

/// One kind of hair used in a look, e.g. 3 bundles of 22" body wave in 1B.
struct HairUsed: Codable, Identifiable, Hashable {
    var id = UUID()
    var texture: HairTexture = .bodyWave
    var brand = ""
    var colorName = "1B"
    var swatchHex = "#2B1D17"
    var lengthInches = 18
    var bundles = 1
}

enum HairTexture: String, Codable, CaseIterable, Identifiable {
    case straight, bodyWave, looseWave, deepWave, waterWave, looseDeep, kinkyStraight, kinkyCurly, yaki, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .straight: "Straight"
        case .bodyWave: "Body wave"
        case .looseWave: "Loose wave"
        case .deepWave: "Deep wave"
        case .waterWave: "Water wave"
        case .looseDeep: "Loose deep"
        case .kinkyStraight: "Kinky straight"
        case .kinkyCurly: "Kinky curly"
        case .yaki: "Yaki"
        case .other: "Other"
        }
    }
}

enum InstallMethod: String, Codable, CaseIterable, Identifiable {
    case sewIn, quickWeave, wig, frontalInstall, closureInstall, leaveOut, ponytail, braids, natural, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sewIn: "Sew-in"
        case .quickWeave: "Quick weave"
        case .wig: "Wig"
        case .frontalInstall: "Frontal install"
        case .closureInstall: "Closure install"
        case .leaveOut: "Leave-out"
        case .ponytail: "Ponytail"
        case .braids: "Braids"
        case .natural: "Natural"
        case .other: "Other"
        }
    }
}

struct ClosureInfo: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case closure, frontal
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    static let sizes = ["2×6", "4×4", "5×5", "6×6", "7×7", "13×4", "13×6", "360"]

    var kind: Kind = .closure
    var size = "4×4"
    var lengthInches = 16
    var lace = "HD"
}

// MARK: - Parting chart

/// Drawings on a head diagram: part lines, and painted areas showing where each hair color goes.
struct PartingChart: Codable, Hashable {
    var top: [ChartStroke] = []
    var back: [ChartStroke] = []

    var isEmpty: Bool { top.isEmpty && back.isEmpty }

    subscript(view: HeadView) -> [ChartStroke] {
        get { view == .top ? top : back }
        set { if view == .top { top = newValue } else { back = newValue } }
    }
}

enum HeadView: String, CaseIterable, Identifiable {
    case top, back
    var id: String { rawValue }
    var displayName: String { self == .top ? "From above" : "From behind" }
}

struct ChartStroke: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case part, color
    }

    var id = UUID()
    var kind: Kind
    /// Points in 0…1 diagram space, so charts look the same at any size.
    var points: [ChartPoint]
    /// The `HairUsed` this color belongs to, for the legend.
    var hairID: UUID?
    var colorHex: String
    var width: Double
}

struct ChartPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

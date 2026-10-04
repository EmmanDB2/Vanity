import SwiftUI

struct MirrorView: View {
    @Environment(AppModel.self) private var model

    private var hub: FeedHub { model.hub }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if hub.feeds.isEmpty && model.referenceLook == nil {
                    EmptyMirrorView()
                } else if let spotlight = hub.spotlight {
                    spotlightLayout(spotlight)
                } else {
                    TileGrid(count: tileCount) { index in
                        tile(at: index, compact: false)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MirrorToolbar()
        }
        .overlay { CountdownOverlay() }
        .background(shortcuts)
    }

    private var tileCount: Int {
        hub.feeds.count + (model.referenceLook == nil ? 0 : 1)
    }

    @ViewBuilder
    private func tile(at index: Int, compact: Bool) -> some View {
        if index < hub.feeds.count {
            FeedTile(feed: hub.feeds[index], compact: compact)
        } else if let look = model.referenceLook {
            ReferenceTile(look: look, compact: compact)
        }
    }

    private func spotlightLayout(_ spotlight: Feed) -> some View {
        VStack(spacing: 12) {
            FeedTile(feed: spotlight)
            let others = hub.feeds.filter { $0.id != spotlight.id }
            if !others.isEmpty || model.referenceLook != nil {
                HStack(spacing: 12) {
                    ForEach(others) { feed in
                        FeedTile(feed: feed, compact: true)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }
                    if let look = model.referenceLook {
                        ReferenceTile(look: look, compact: true)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .frame(height: 130)
            }
        }
    }

    /// Invisible buttons that give the mirror its single-key shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { model.hub.toggleDelayForAll() }.keyboardShortcut("d", modifiers: [])
            Button("") { model.hub.toggleFreezeForAll() }.keyboardShortcut("f", modifiers: [])
            Button("") { model.hub.focusedFeeds.forEach { $0.settings.mirrored.toggle() } }.keyboardShortcut("m", modifiers: [])
            Button("") { withAnimation { model.hub.spotlightID = nil } }.keyboardShortcut(.escape, modifiers: [])
            ForEach(0..<4) { index in
                Button("") {
                    if index < hub.feeds.count {
                        withAnimation(.spring(duration: 0.35)) { hub.toggleSpotlight(hub.feeds[index]) }
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

/// Lays out tiles in whatever grid makes each 16:9 tile as big as possible.
struct TileGrid<Tile: View>: View {
    let count: Int
    @ViewBuilder let tile: (Int) -> Tile
    private let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let (columns, size) = bestFit(in: geometry.size)
            let rows = Int(ceil(Double(count) / Double(columns)))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < count {
                                tile(index).frame(width: size.width, height: size.height)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bestFit(in area: CGSize) -> (Int, CGSize) {
        var best = (1, CGSize.zero)
        for columns in 1...max(count, 1) {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let maxWidth = (area.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let maxHeight = (area.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let width = min(maxWidth, maxHeight * 16 / 9)
            if width > best.1.width {
                best = (columns, CGSize(width: width, height: width * 9 / 16))
            }
        }
        return best
    }
}

struct MirrorToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var hub = model.hub
        HStack(spacing: 14) {
            Label(cameraSummary, systemImage: "camera.fill")
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.softInk)

            Spacer()

            Button {
                hub.toggleDelayForAll()
            } label: {
                Label(hub.anyDelayOn ? "Delay on" : "Delay", systemImage: "timer")
            }
            .buttonStyle(PillButtonStyle(prominent: hub.anyDelayOn))
            .disabled(hub.feeds.isEmpty)
            .help("Play the views a few seconds late, so you can turn around and watch (D)")

            if hub.anyDelayOn {
                Stepper(value: $hub.delaySeconds, in: 2...10, step: 1) {
                    Text("\(Int(hub.delaySeconds)) sec")
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .transition(.opacity)
            }

            Button {
                Task { await model.captureLook() }
            } label: {
                Label("Capture look", systemImage: "camera.aperture")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .keyboardShortcut(.space, modifiers: [])
            .disabled(hub.feeds.isEmpty || model.countdown != nil)
            .help("Takes a photo from every camera after a 3-second countdown (Space)")

            Spacer()

            if hub.spotlightID != nil {
                Button {
                    withAnimation(.spring(duration: 0.35)) { hub.spotlightID = nil }
                } label: {
                    Label("Show all", systemImage: "square.grid.2x2")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .animation(.easeOut(duration: 0.2), value: hub.anyDelayOn)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.7))
    }

    private var cameraSummary: String {
        switch model.hub.feeds.count {
        case 0: "No cameras yet"
        case 1: "1 camera"
        case let n: "\(n) cameras"
        }
    }
}

/// A saved look pinned beside the live views while she recreates it.
struct ReferenceTile: View {
    @Environment(AppModel.self) private var model
    let look: Look
    var compact = false
    @State private var index = 0

    var body: some View {
        ZStack {
            Theme.surface
            if let photo = look.photos[safe: index], let image = model.store.image(for: photo) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Label("No photos yet", systemImage: "photo")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.softInk)
            }

            VStack {
                HStack {
                    Label("\(look.name)\(angleSuffix)", systemImage: "heart.fill")
                        .font(Theme.font(compact ? 11 : 13, .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.deepRose))
                    Spacer()
                    if !compact {
                        Button { model.referenceLookID = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(BubbleButtonStyle())
                            .help("Stop showing this look")
                    }
                }
                Spacer()
                if look.photos.count > 1, !compact {
                    HStack {
                        Button { index = (index - 1 + look.photos.count) % look.photos.count } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(BubbleButtonStyle())
                        Spacer()
                        Button { index = (index + 1) % look.photos.count } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(BubbleButtonStyle())
                    }
                }
            }
            .padding(compact ? 8 : 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: compact ? 14 : Theme.cornerRadius).strokeBorder(Theme.lavender, lineWidth: 3))
    }

    private var angleSuffix: String {
        look.photos[safe: index].map { " · \($0.angle)" } ?? ""
    }
}

struct CountdownOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let count = model.countdown {
                Text("\(count)")
                    .font(.system(size: 160, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.deepRose.opacity(0.6), radius: 20)
                    .id(count)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
            if model.flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.3), value: model.countdown)
        .animation(.easeOut(duration: 0.25), value: model.flash)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

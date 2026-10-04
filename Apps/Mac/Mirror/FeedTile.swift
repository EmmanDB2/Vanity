import SwiftUI

/// One camera on the mirror, with its name, status and hover controls.
struct FeedTile: View {
    @Environment(AppModel.self) private var model
    @Bindable var feed: Feed
    var compact = false

    @State private var hovering = false
    @State private var renaming = false

    private var hub: FeedHub { model.hub }
    private var isSpotlight: Bool { hub.spotlightID == feed.id }

    var body: some View {
        ZStack {
            VideoLayerView(
                router: feed.router,
                mirrored: feed.settings.mirrored,
                quarterTurns: feed.settings.quarterTurns,
                zoom: $feed.zoom,
                pan: $feed.pan,
                onClick: { withAnimation(.spring(duration: 0.35)) { hub.toggleSpotlight(feed) } }
            )

            statusOverlay

            VStack {
                HStack(alignment: .top) {
                    nameTag
                    Spacer()
                    badges
                }
                Spacer()
                if (hovering || feed.zoom > 1) && !compact {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(compact ? 8 : 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : Theme.cornerRadius)
                .strokeBorder(isSpotlight ? Theme.rose : Theme.blush, lineWidth: compact ? 2 : 3)
        )
        .shadow(color: Theme.deepRose.opacity(0.15), radius: 10, y: 4)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .contextMenu { menu }
        .popover(isPresented: $renaming) { RenamePopover(feed: feed) }
    }

    // MARK: Pieces

    private var nameTag: some View {
        Label(feed.settings.label, systemImage: feed.symbol)
            .font(Theme.font(compact ? 11 : 13, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.ink)
            .background(Capsule().fill(Theme.surface.opacity(0.9)))
            .onTapGesture(count: 2) { renaming = true }
            .help("Double-click to rename")
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if feed.settings.delayOn {
                badge("⏱ \(Int(hub.delaySeconds))s behind")
            }
            if feed.isFrozen {
                badge("❄︎ Paused")
            }
            if feed.zoom > 1 {
                badge(String(format: "%.1f×", feed.zoom))
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(compact ? 10 : 12, .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(Capsule().fill(Theme.deepRose.opacity(0.9)))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { feed.settings.mirrored.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(BubbleButtonStyle(isOn: feed.settings.mirrored))
            .help("Mirror flip")

            Button { feed.settings.quarterTurns = (feed.settings.quarterTurns + 1) % 4 } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(BubbleButtonStyle())
            .help("Rotate")

            Button { feed.isFrozen.toggle() } label: {
                Image(systemName: feed.isFrozen ? "play.fill" : "pause.fill")
            }
            .buttonStyle(BubbleButtonStyle(isOn: feed.isFrozen))
            .help(feed.isFrozen ? "Go live" : "Freeze this view")

            Button { hub.setDelay(!feed.settings.delayOn, for: feed) } label: {
                Image(systemName: "timer")
            }
            .buttonStyle(BubbleButtonStyle(isOn: feed.settings.delayOn))
            .help("Delay: watch yourself a few seconds later")

            if feed.zoom > 1 {
                Button { withAnimation { feed.resetZoom() } } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(BubbleButtonStyle())
                .help("Zoom back out")
            }

            Button { withAnimation(.spring(duration: 0.35)) { hub.toggleSpotlight(feed) } } label: {
                Image(systemName: isSpotlight ? "square.grid.2x2" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(BubbleButtonStyle())
            .help(isSpotlight ? "Show all views" : "Make this view big")
        }
        .padding(8)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if feed.status != .live {
            VStack(spacing: 10) {
                ProgressView().controlSize(compact ? .small : .regular)
                if !compact {
                    Text(feed.status == .reconnecting ? "Looking for \(feed.deviceName)…" : "Waking up the camera…")
                        .font(Theme.font(14, .medium))
                    if feed.status == .reconnecting {
                        Text("Make sure Vanity Cam is open and on Wi-Fi")
                            .font(Theme.font(12))
                            .opacity(0.8)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.45))
        } else if let fill = feed.delayFill, fill < 1, !compact {
            VStack(spacing: 10) {
                ProgressView(value: fill)
                    .progressViewStyle(.circular)
                    .tint(Theme.rose)
                Text("Starting delay… turn around and your replay will appear")
                    .font(Theme.font(13, .medium))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.5)))
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename…") { renaming = true }
        Toggle("Mirror flip", isOn: $feed.settings.mirrored)
        Button("Rotate") { feed.settings.quarterTurns = (feed.settings.quarterTurns + 1) % 4 }
        Toggle("Freeze", isOn: $feed.isFrozen)
        Toggle("Delay", isOn: Binding(get: { feed.settings.delayOn }, set: { hub.setDelay($0, for: feed) }))
        if feed.zoom > 1 {
            Button("Reset zoom") { feed.resetZoom() }
        }
    }
}

private struct RenamePopover: View {
    @Bindable var feed: Feed
    @Environment(\.dismiss) private var dismiss
    private let suggestions = ["Front", "Back", "Left", "Right", "Top", "Crown", "Nape"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name this view").font(Theme.font(14, .bold))
            TextField("Name", text: $feed.settings.label)
                .textFieldStyle(.roundedBorder)
                .onSubmit { dismiss() }
            FlowRow(spacing: 6) {
                ForEach(suggestions, id: \.self) { name in
                    Button(name) { feed.settings.label = name; dismiss() }
                        .buttonStyle(PillButtonStyle())
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// Simple wrapping row for chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

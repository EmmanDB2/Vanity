import SwiftUI

/// Head outlines in 0…1 space. The top view has the face at the top of the page, so her left is on the left.
enum HeadDiagram {
    static func hairArea(_ view: HeadView, in rect: CGRect) -> Path {
        switch view {
        case .top:
            Path(ellipseIn: unit(CGRect(x: 0.18, y: 0.1, width: 0.64, height: 0.84), in: rect))
        case .back:
            Path(ellipseIn: unit(CGRect(x: 0.17, y: 0.06, width: 0.66, height: 0.72), in: rect))
        }
    }

    static func draw(_ view: HeadView, in context: inout GraphicsContext, rect: CGRect, skin: Color, line: Color, label: Color) {
        let stroke = StrokeStyle(lineWidth: max(1.5, rect.width * 0.012))
        switch view {
        case .top:
            for ear in [CGRect(x: 0.12, y: 0.44, width: 0.08, height: 0.16), CGRect(x: 0.80, y: 0.44, width: 0.08, height: 0.16)] {
                let path = Path(ellipseIn: unit(ear, in: rect))
                context.fill(path, with: .color(skin))
                context.stroke(path, with: .color(line), style: stroke)
            }
            let nose = Path(ellipseIn: unit(CGRect(x: 0.45, y: 0.04, width: 0.1, height: 0.1), in: rect))
            context.fill(nose, with: .color(skin))
            context.stroke(nose, with: .color(line), style: stroke)

            let head = hairArea(.top, in: rect)
            context.fill(head, with: .color(skin))
            context.stroke(head, with: .color(line), style: stroke)

            // Faint centerline and crown guide.
            var center = Path()
            center.move(to: point(0.5, 0.12, in: rect))
            center.addLine(to: point(0.5, 0.92, in: rect))
            context.stroke(center, with: .color(line.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            context.fill(Path(ellipseIn: unit(CGRect(x: 0.485, y: 0.6, width: 0.03, height: 0.03), in: rect)), with: .color(line.opacity(0.3)))

            context.draw(Text("FRONT").font(.system(size: max(8, rect.width * 0.045), weight: .bold, design: .rounded)).foregroundColor(label), at: point(0.5, 0.015, in: rect), anchor: .top)
            context.draw(Text("BACK").font(.system(size: max(8, rect.width * 0.045), weight: .bold, design: .rounded)).foregroundColor(label), at: point(0.5, 0.995, in: rect), anchor: .bottom)

        case .back:
            let neck = Path(roundedRect: unit(CGRect(x: 0.36, y: 0.66, width: 0.28, height: 0.3), in: rect), cornerRadius: rect.width * 0.05)
            context.fill(neck, with: .color(skin))
            context.stroke(neck, with: .color(line), style: stroke)
            for ear in [CGRect(x: 0.11, y: 0.36, width: 0.08, height: 0.17), CGRect(x: 0.81, y: 0.36, width: 0.08, height: 0.17)] {
                let path = Path(ellipseIn: unit(ear, in: rect))
                context.fill(path, with: .color(skin))
                context.stroke(path, with: .color(line), style: stroke)
            }
            let head = hairArea(.back, in: rect)
            context.fill(head, with: .color(skin))
            context.stroke(head, with: .color(line), style: stroke)

            context.draw(Text("LEFT").font(.system(size: max(8, rect.width * 0.04), weight: .bold, design: .rounded)).foregroundColor(label), at: point(0.02, 0.22, in: rect), anchor: .leading)
            context.draw(Text("RIGHT").font(.system(size: max(8, rect.width * 0.04), weight: .bold, design: .rounded)).foregroundColor(label), at: point(0.98, 0.22, in: rect), anchor: .trailing)
            context.draw(Text("NAPE").font(.system(size: max(8, rect.width * 0.04), weight: .bold, design: .rounded)).foregroundColor(label), at: point(0.5, 0.995, in: rect), anchor: .bottom)
        }
    }

    static func point(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    static func unit(_ r: CGRect, in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + r.minX * rect.width, y: rect.minY + r.minY * rect.height, width: r.width * rect.width, height: r.height * rect.height)
    }

    /// The largest 15:17 box that fits, centered, so the head never looks squashed.
    static func diagramRect(in size: CGSize) -> CGRect {
        let aspect: CGFloat = 15 / 17
        let width = min(size.width, size.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// Draws a head diagram with its strokes. Used for both the small preview and the editor.
struct PartingChartCanvas: View {
    var strokes: [ChartStroke]
    var view: HeadView
    var inProgress: ChartStroke?

    var body: some View {
        Canvas { context, size in
            let rect = HeadDiagram.diagramRect(in: size)
            HeadDiagram.draw(view, in: &context, rect: rect, skin: Color(hexString: "#F3D9C9"), line: Theme.softInk, label: Theme.softInk)

            let all = strokes + (inProgress.map { [$0] } ?? [])

            // Colors stay inside the hair area; part lines draw on top.
            context.drawLayer { layer in
                layer.clip(to: HeadDiagram.hairArea(view, in: rect))
                for stroke in all where stroke.kind == .color {
                    layer.stroke(path(stroke, in: rect), with: .color(Color(hexString: stroke.colorHex).opacity(0.85)),
                                 style: StrokeStyle(lineWidth: stroke.width * rect.width, lineCap: .round, lineJoin: .round))
                }
            }
            for stroke in all where stroke.kind == .part {
                let path = path(stroke, in: rect)
                let width = max(2, stroke.width * rect.width)
                context.stroke(path, with: .color(Theme.ink), style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func path(_ stroke: ChartStroke, in rect: CGRect) -> Path {
        var path = Path()
        guard let first = stroke.points.first else { return path }
        path.move(to: HeadDiagram.point(first.x, first.y, in: rect))
        if stroke.points.count == 1 {
            path.addLine(to: HeadDiagram.point(first.x + 0.0001, first.y, in: rect))
        }
        for point in stroke.points.dropFirst() {
            path.addLine(to: HeadDiagram.point(point.x, point.y, in: rect))
        }
        return path
    }
}

/// Which swatch is which hair.
struct ChartLegend: View {
    let chart: PartingChart
    let hair: [HairUsed]

    var body: some View {
        let used = Set((chart.top + chart.back).compactMap(\.hairID))
        let items = hair.filter { used.contains($0.id) }
        if !items.isEmpty {
            FlowRow(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 5) {
                        Circle().fill(Color(hexString: item.swatchHex)).frame(width: 12, height: 12)
                        Text("\(item.colorName) · \(item.lengthInches)\" \(item.texture.displayName.lowercased())")
                    }
                    .font(Theme.font(11, .medium))
                    .foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

// MARK: - Editor

struct PartingChartEditor: View {
    @Binding var chart: PartingChart
    let hair: [HairUsed]
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable, Identifiable {
        case straightPart, freehandPart, color, eraser
        var id: String { rawValue }

        var title: String {
            switch self {
            case .straightPart: "Straight part"
            case .freehandPart: "Curved part"
            case .color: "Color brush"
            case .eraser: "Eraser"
            }
        }

        var symbol: String {
            switch self {
            case .straightPart: "line.diagonal"
            case .freehandPart: "scribble"
            case .color: "paintbrush.pointed.fill"
            case .eraser: "eraser"
            }
        }
    }

    /// Swatches offered when no hair has been added to the recipe yet.
    private static let fallbackSwatches: [(String, String)] = [("1B", "#2B1D17"), ("Brown", "#6B4226"), ("Honey", "#B8834A"), ("Blonde", "#E3C27A"), ("Red", "#9E2B25"), ("Pink", "#E58FB0")]

    @State private var view: HeadView = .top
    @State private var tool: Tool = .straightPart
    @State private var brushSize = 0.08
    @State private var swatch: (hairID: UUID?, hex: String) = (nil, "#2B1D17")
    @State private var inProgress: ChartStroke?
    @State private var undoStack: [PartingChart] = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .padding(18)
                .background(Theme.surface)

            VStack(spacing: 12) {
                Picker("", selection: $view) {
                    ForEach(HeadView.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                GeometryReader { geometry in
                    PartingChartCanvas(strokes: chart[view], view: view, inProgress: inProgress)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(in: geometry.size))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))

                HStack {
                    Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(undoStack.isEmpty)
                    Button { record(); chart[view] = [] } label: { Label("Clear this view", systemImage: "trash") }
                        .buttonStyle(PillButtonStyle())
                        .disabled(chart[view].isEmpty)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 860, height: 640)
        .background(Theme.background)
        .onAppear {
            if let first = hair.first { swatch = (first.id, first.swatchHex) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Parting chart").font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Tool.allCases) { option in
                    Button { tool = option } label: {
                        Label(option.title, systemImage: option.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PillButtonStyle(prominent: tool == option))
                }
            }

            if view == .top {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick parts").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
                    HStack {
                        presetButton("Middle", [(0.5, 0.11), (0.5, 0.55)])
                        presetButton("Left", [(0.38, 0.12), (0.36, 0.5)])
                        presetButton("Right", [(0.62, 0.12), (0.64, 0.5)])
                    }
                }
            }

            if tool == .color {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paint with").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if hair.isEmpty {
                                Text("Tip: add hair to the recipe to paint with its exact colors.")
                                    .font(Theme.font(11)).foregroundStyle(Theme.softInk)
                                ForEach(Self.fallbackSwatches, id: \.1) { name, hex in
                                    swatchButton(name: name, hex: hex, hairID: nil)
                                }
                            } else {
                                ForEach(hair) { item in
                                    swatchButton(name: "\(item.colorName) · \(item.lengthInches)\"", hex: item.swatchHex, hairID: item.id)
                                }
                            }
                        }
                    }
                    Text("Brush size").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
                    Slider(value: $brushSize, in: 0.03...0.2)
                        .tint(Theme.deepRose)
                }
            }

            Spacer()
            Text(hint).font(Theme.font(12)).foregroundStyle(Theme.softInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        switch tool {
        case .straightPart: "Drag from where the part starts to where it ends."
        case .freehandPart: "Draw the part like you would with a rat-tail comb."
        case .color: "Paint over the areas where this color goes."
        case .eraser: "Drag over a line or color to remove it."
        }
    }

    private func presetButton(_ title: String, _ points: [(Double, Double)]) -> some View {
        Button(title) {
            record()
            chart[.top].append(ChartStroke(kind: .part, points: points.map { ChartPoint(x: $0.0, y: $0.1) }, colorHex: "#FFFFFF", width: 0.012))
        }
        .buttonStyle(PillButtonStyle())
        .controlSize(.small)
    }

    private func swatchButton(name: String, hex: String, hairID: UUID?) -> some View {
        let selected = swatch.hex == hex && swatch.hairID == hairID
        return Button { swatch = (hairID, hex) } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(hexString: hex)).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(selected ? Theme.deepRose : Theme.blush, lineWidth: selected ? 3 : 1))
                Text(name).font(Theme.font(12, selected ? .bold : .regular)).foregroundStyle(Theme.ink)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Drawing

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let rect = HeadDiagram.diagramRect(in: size)
                let point = ChartPoint(
                    x: Double((value.location.x - rect.minX) / rect.width),
                    y: Double((value.location.y - rect.minY) / rect.height)
                )
                switch tool {
                case .eraser:
                    erase(near: point)
                case .straightPart:
                    let start = inProgress?.points.first ?? point
                    inProgress = ChartStroke(kind: .part, points: [start, point], colorHex: "#FFFFFF", width: 0.012)
                case .freehandPart:
                    if inProgress == nil { inProgress = ChartStroke(kind: .part, points: [], colorHex: "#FFFFFF", width: 0.012) }
                    inProgress?.points.append(point)
                case .color:
                    if inProgress == nil { inProgress = ChartStroke(kind: .color, points: [], hairID: swatch.hairID, colorHex: swatch.hex, width: brushSize) }
                    inProgress?.points.append(point)
                }
            }
            .onEnded { _ in
                if let stroke = inProgress {
                    record()
                    chart[view].append(stroke)
                }
                inProgress = nil
                erasedDuringDrag = false
            }
    }

    @State private var erasedDuringDrag = false

    private func erase(near point: ChartPoint) {
        let threshold = 0.03
        let hit = chart[view].lastIndex { stroke in
            let reach = threshold + (stroke.kind == .color ? stroke.width / 2 : 0)
            return zip(stroke.points, stroke.points.dropFirst().isEmpty ? stroke.points : Array(stroke.points.dropFirst())).contains { a, b in
                distance(from: point, toSegment: a, b) < reach
            }
        }
        if let hit {
            if !erasedDuringDrag {
                record()
                erasedDuringDrag = true
            }
            chart[view].remove(at: hit)
        }
    }

    private func distance(from p: ChartPoint, toSegment a: ChartPoint, _ b: ChartPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let cx = a.x + t * dx, cy = a.y + t * dy
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }

    private func record() {
        undoStack.append(chart)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func undo() {
        if let previous = undoStack.popLast() { chart = previous }
    }
}

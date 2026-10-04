import SwiftUI

/// Two looks side by side: photos from the same angle, plus their recipes.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lookIDs: [Look.ID]
    @State private var angle: String?

    private var looks: [Look] {
        lookIDs.compactMap(model.store.look(id:))
    }

    private var angles: [String] {
        var seen: [String] = []
        for photo in looks.flatMap(\.photos) where !seen.contains(photo.angle) {
            seen.append(photo.angle)
        }
        return seen
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Compare").font(Theme.font(24, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                if angles.count > 1 {
                    Picker("Angle", selection: $angle) {
                        ForEach(angles, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }

            HStack(alignment: .top, spacing: 18) {
                ForEach(looks) { look in
                    column(look)
                }
            }
        }
        .padding(24)
        .frame(width: 980, height: 720)
        .background(Theme.background)
        .onAppear { angle = angles.first }
    }

    private func column(_ look: Look) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(look.name).font(Theme.font(18, .bold)).foregroundStyle(Theme.ink)
                let photo = look.photos.first { $0.angle == angle } ?? look.coverPhoto
                Group {
                    if let photo, let image = model.store.image(for: photo) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Theme.blush.overlay(Text("No \(angle ?? "") photo").font(Theme.font(13)).foregroundStyle(Theme.softInk))
                            .frame(height: 260)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Card(title: "Recipe", systemImage: "list.bullet.rectangle") {
                    Text("\(look.installMethod.displayName) · \(look.totalBundles) bundles")
                        .font(Theme.font(13, .semibold))
                    ForEach(look.hair) { hair in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hexString: hair.swatchHex)).frame(width: 12, height: 12)
                            Text("\(hair.bundles)× \(hair.lengthInches)\" \(hair.texture.displayName) · \(hair.colorName)")
                            if !hair.brand.isEmpty {
                                Text(hair.brand).foregroundStyle(Theme.softInk)
                            }
                        }
                        .font(Theme.font(13))
                    }
                    if let closure = look.closure {
                        Text("\(closure.size) \(closure.kind.displayName.lowercased()), \(closure.lengthInches)\", \(closure.lace) lace")
                            .font(Theme.font(13))
                    }
                }

                if !look.partingChart.isEmpty {
                    HStack {
                        ForEach(HeadView.allCases) { view in
                            PartingChartCanvas(strokes: look.partingChart[view], view: view)
                                .frame(width: 140, height: 160)
                        }
                    }
                }

                if !look.notes.isEmpty {
                    Text(look.notes).font(Theme.font(13)).foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

/// Shown after "Capture look": save the photos as a new look, add them to an existing one, or toss them.
struct SnapshotSheet: View {
    @Environment(AppModel.self) private var model
    @State var shots: [CapturedShot]
    @State private var name = AppModel.defaultLookName()
    @State private var existingLookID: Look.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Gorgeous! 📸").font(Theme.font(24, .bold)).foregroundStyle(Theme.ink)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach($shots) { $shot in
                        VStack(spacing: 6) {
                            Image(nsImage: shot.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            TextField("Angle", text: $shot.angle)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.center)
                                .font(Theme.font(13, .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 200)
                        }
                    }
                }
            }

            Card(title: "Save as a new look", systemImage: "sparkles") {
                HStack {
                    TextField("Name this look", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.font(14))
                    Button("Save") { model.saveShotsAsNewLook(shots, name: name) }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }

            if !model.store.looks.isEmpty {
                Card(title: "…or add to a look you already saved", systemImage: "heart.text.square") {
                    HStack {
                        Picker("Look", selection: $existingLookID) {
                            Text("Choose a look").tag(Look.ID?.none)
                            ForEach(model.store.looks) { look in
                                Text(look.name).tag(Look.ID?.some(look.id))
                            }
                        }
                        .labelsHidden()
                        Button("Add photos") {
                            if let existingLookID { model.addShots(shots, to: existingLookID) }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(existingLookID == nil)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Discard") { model.pendingShots = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 640)
        .background(Theme.background)
        .onAppear { existingLookID = model.referenceLookID }
    }
}

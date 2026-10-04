import SwiftUI

struct LookDetailView: View {
    @Environment(AppModel.self) private var model
    let lookID: Look.ID

    @State private var look = Look(name: "")
    @State private var loaded = false
    @State private var selectedPhotoID: LookPhoto.ID?
    @State private var editingChart = false
    @State private var confirmingDelete = false

    private var store: LookStore { model.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                photos
                Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                    GridRow {
                        HairRecipeCard(hair: $look.hair).gridCellColumns(2)
                    }
                    GridRow(alignment: .top) {
                        StyleCard(look: $look, allTags: store.allTags)
                        ClosureCard(closure: $look.closure)
                    }
                    GridRow(alignment: .top) {
                        partingCard
                        notesCard
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            if let stored = store.look(id: lookID) {
                look = stored
                selectedPhotoID = stored.coverPhoto?.id
            }
            loaded = true
        }
        .onChange(of: look) { _, newValue in
            if loaded { store.update(newValue) }
        }
        .sheet(isPresented: $editingChart) {
            PartingChartEditor(chart: $look.partingChart, hair: look.hair)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                store.flush()
                model.openLookID = nil
            } label: {
                Label("Lookbook", systemImage: "chevron.left")
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Name this look", text: $look.name)
                    .textFieldStyle(.plain)
                    .font(Theme.font(28, .bold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    Text(look.createdAt.formatted(date: .long, time: .omitted))
                        .font(Theme.font(13)).foregroundStyle(Theme.softInk)
                    HeartRating(rating: $look.rating)
                }
            }

            Spacer()

            Button { look.isFavorite.toggle() } label: {
                Image(systemName: look.isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(BubbleButtonStyle(isOn: look.isFavorite))
            .help("Favorite")

            Button {
                store.flush()
                model.recreate(look)
            } label: {
                Label("Recreate this look", systemImage: "wand.and.stars")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .help("Opens the mirror with these photos beside your live views")

            Menu {
                Button("Delete look…", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .confirmationDialog("Delete \"\(look.name)\"?", isPresented: $confirmingDelete) {
                Button("Delete look and photos", role: .destructive) {
                    loaded = false
                    model.openLookID = nil
                    store.delete(look)
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: Photos

    @ViewBuilder
    private var photos: some View {
        if look.photos.isEmpty {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "camera.aperture").font(.system(size: 28)).foregroundStyle(Theme.rose)
                    VStack(alignment: .leading) {
                        Text("No photos yet").font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                        Text("Press Recreate this look, then Capture look in the mirror. The photos can be added right here.")
                            .font(Theme.font(13)).foregroundStyle(Theme.softInk)
                    }
                }
            }
        } else {
            let selected = look.photos.first { $0.id == selectedPhotoID } ?? look.photos[0]
            VStack(spacing: 10) {
                if let image = store.image(for: selected) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .overlay(alignment: .topLeading) {
                            Text(selected.angle)
                                .font(Theme.font(13, .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Theme.surface.opacity(0.9)))
                                .padding(12)
                        }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(look.photos) { photo in
                            thumbnail(photo, isSelected: photo.id == selected.id)
                        }
                    }
                }
            }
        }
    }

    private func thumbnail(_ photo: LookPhoto, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image = store.image(for: photo) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Theme.blush
                }
            }
            .frame(width: 110, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Theme.deepRose : Color.clear, lineWidth: 3))
            Text(photo.angle).font(Theme.font(11, .medium)).foregroundStyle(Theme.softInk)
        }
        .onTapGesture { selectedPhotoID = photo.id }
        .contextMenu {
            Button("Use as cover") {
                look.photos.removeAll { $0.id == photo.id }
                look.photos.insert(photo, at: 0)
            }
            Button("Delete photo", role: .destructive) {
                store.removePhoto(photo, from: &look)
            }
        }
    }

    // MARK: Cards

    private var partingCard: some View {
        Card(title: "Parting & color placement", systemImage: "scribble.variable") {
            if look.partingChart.isEmpty {
                Text("Draw your parts and show where each color goes.")
                    .font(Theme.font(13)).foregroundStyle(Theme.softInk)
            }
            HStack(spacing: 10) {
                ForEach(HeadView.allCases) { view in
                    VStack(spacing: 4) {
                        PartingChartCanvas(strokes: look.partingChart[view], view: view)
                            .frame(width: 150, height: 170)
                        Text(view.displayName).font(Theme.font(11)).foregroundStyle(Theme.softInk)
                    }
                }
            }
            ChartLegend(chart: look.partingChart, hair: look.hair)
            Button(look.partingChart.isEmpty ? "Draw chart" : "Edit chart") { editingChart = true }
                .buttonStyle(PillButtonStyle())
        }
    }

    private var notesCard: some View {
        Card(title: "Products & notes", systemImage: "note.text") {
            Text("Products used").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
            TextEditor(text: $look.products)
                .font(Theme.font(13))
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
            Text("Notes").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
            TextEditor(text: $look.notes)
                .font(Theme.font(13))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
        }
    }
}

struct HeartRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "heart.fill" : "heart")
                    .foregroundStyle(Theme.rose)
                    .onTapGesture { rating = rating == value ? 0 : value }
            }
        }
        .font(.system(size: 12))
        .help("How much did you love it?")
    }
}

// MARK: - Hair recipe

struct HairRecipeCard: View {
    @Binding var hair: [HairUsed]

    var body: some View {
        Card(title: "Hair recipe", systemImage: "list.bullet.rectangle") {
            if hair.isEmpty {
                Text("Add each kind of hair you used: texture, length, color and how many bundles.")
                    .font(Theme.font(13)).foregroundStyle(Theme.softInk)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        ForEach(["Color", "Shade", "Texture", "Length", "Bundles", "Brand / vendor", ""], id: \.self) { title in
                            Text(title).font(Theme.font(11, .semibold)).foregroundStyle(Theme.softInk)
                        }
                    }
                    ForEach($hair) { $item in
                        GridRow {
                            ColorPicker("", selection: Binding(
                                get: { Color(hexString: item.swatchHex) },
                                set: { item.swatchHex = $0.hexString }
                            ), supportsOpacity: false)
                            .labelsHidden()

                            TextField("1B", text: $item.colorName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            Picker("", selection: $item.texture) {
                                ForEach(HairTexture.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)

                            Stepper(value: $item.lengthInches, in: 6...40, step: 2) {
                                Text("\(item.lengthInches)\"").monospacedDigit().frame(width: 34, alignment: .trailing)
                            }

                            Stepper(value: $item.bundles, in: 0...10) {
                                Text("\(item.bundles)").monospacedDigit().frame(width: 20, alignment: .trailing)
                            }

                            TextField("Optional", text: $item.brand)
                                .textFieldStyle(.roundedBorder)

                            Button { hair.removeAll { $0.id == item.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.rose)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                        .font(Theme.font(13))
                    }
                }
            }

            HStack {
                Button {
                    var next = HairUsed()
                    if let last = hair.last {
                        next.texture = last.texture
                        next.brand = last.brand
                        next.lengthInches = last.lengthInches
                    }
                    hair.append(next)
                } label: {
                    Label("Add hair", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())

                Spacer()

                if !hair.isEmpty {
                    let total = hair.reduce(0) { $0 + $1.bundles }
                    Text("Total: \(total) bundle\(total == 1 ? "" : "s")")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.deepRose)
                }
            }
        }
    }
}

// MARK: - Style

struct StyleCard: View {
    @Binding var look: Look
    let allTags: [String]
    @State private var newTag = ""

    var body: some View {
        Card(title: "Style", systemImage: "comb") {
            LabeledContent("Install") {
                Picker("", selection: $look.installMethod) {
                    ForEach(InstallMethod.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            LabeledContent("Longest length") {
                HStack {
                    if let length = look.totalLengthInches {
                        Stepper(value: Binding(get: { length }, set: { look.totalLengthInches = $0 }), in: 4...40, step: 2) {
                            Text("\(length)\"").monospacedDigit()
                        }
                        Button { look.totalLengthInches = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.softInk)
                    } else {
                        Button("Add") { look.totalLengthInches = look.hair.map(\.lengthInches).max() ?? 18 }
                    }
                }
            }

            Text("Tags").font(Theme.font(12, .semibold)).foregroundStyle(Theme.softInk)
            FlowRow(spacing: 6) {
                ForEach(look.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        Button { look.tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                    }
                    .font(Theme.font(12, .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.lavender))
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit(addTag)
            }
            let suggestions = allTags.filter { !look.tags.contains($0) }.prefix(6)
            if !suggestions.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(suggestions), id: \.self) { tag in
                        Button("+ \(tag)") { look.tags.append(tag) }
                            .buttonStyle(.plain)
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.softInk)
                    }
                }
            }
        }
        .font(Theme.font(13))
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        if !tag.isEmpty, !look.tags.contains(tag) {
            look.tags.append(tag)
        }
        newTag = ""
    }
}

// MARK: - Closure / frontal

struct ClosureCard: View {
    @Binding var closure: ClosureInfo?

    var body: some View {
        Card(title: "Closure / frontal", systemImage: "rectangle.portrait.on.rectangle.portrait") {
            Toggle("I used a closure or frontal", isOn: Binding(
                get: { closure != nil },
                set: { closure = $0 ? ClosureInfo() : nil }
            ))
            .toggleStyle(.switch)
            .tint(Theme.deepRose)

            if let value = closure {
                let binding = Binding(get: { closure ?? value }, set: { closure = $0 })
                Picker("Type", selection: binding.kind) {
                    ForEach(ClosureInfo.Kind.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Size") {
                    Picker("", selection: binding.size) {
                        ForEach(ClosureInfo.sizes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                LabeledContent("Length") {
                    Stepper(value: binding.lengthInches, in: 8...30, step: 2) {
                        Text("\(value.lengthInches)\"").monospacedDigit()
                    }
                }
                LabeledContent("Lace") {
                    TextField("HD, transparent…", text: binding.lace)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
            }
        }
        .font(Theme.font(13))
    }
}

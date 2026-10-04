import SwiftUI

struct LookbookView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var selectedTag: String?
    @State private var favoritesOnly = false
    @State private var comparing = false
    @State private var compareSelection: [Look.ID] = []
    @State private var showCompare = false

    private var store: LookStore { model.store }

    var body: some View {
        if let id = model.openLookID, store.look(id: id) != nil {
            LookDetailView(lookID: id)
                .id(id)
        } else {
            grid
        }
    }

    private var filtered: [Look] {
        store.looks.filter { look in
            (!favoritesOnly || look.isFavorite)
                && (selectedTag.map { look.tags.contains($0) } ?? true)
                && (search.isEmpty || matches(look, search))
        }
    }

    private func matches(_ look: Look, _ text: String) -> Bool {
        let haystack = ([look.name, look.notes, look.products, look.installMethod.displayName] + look.tags
            + look.hair.flatMap { [$0.texture.displayName, $0.brand, $0.colorName] }).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(text)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !store.allTags.isEmpty {
                tagFilter
            }
            if store.looks.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Text("No looks match that search.")
                    .font(Theme.font(15)).foregroundStyle(Theme.softInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18)], spacing: 18) {
                        ForEach(filtered) { look in
                            LookCard(look: look, selectionIndex: comparing ? compareSelection.firstIndex(of: look.id) : nil)
                                .onTapGesture { open(look) }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $showCompare, onDismiss: { compareSelection = []; comparing = false }) {
            CompareView(lookIDs: compareSelection)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lookbook").font(Theme.font(30, .bold)).foregroundStyle(Theme.ink)
                Text(comparing ? "Pick two looks to compare" : "\(store.looks.count) saved looks")
                    .font(Theme.font(13)).foregroundStyle(Theme.softInk)
            }
            Spacer()
            TextField("Search hair, colors, notes…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Toggle(isOn: $favoritesOnly) { Image(systemName: "heart.fill") }
                .toggleStyle(.button)
                .help("Favorites only")
            if store.looks.count >= 2 {
                Button(comparing ? "Cancel" : "Compare") {
                    comparing.toggle()
                    compareSelection = []
                }
                .buttonStyle(PillButtonStyle())
            }
            Button {
                let look = Look(name: AppModel.defaultLookName())
                store.add(look)
                model.openLookID = look.id
            } label: {
                Label("New look", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
        }
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selectedTag == nil) { selectedTag = nil }
                ForEach(store.allTags, id: \.self) { tag in
                    chip("#\(tag)", selected: selectedTag == tag) { selectedTag = selectedTag == tag ? nil : tag }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .background(Capsule().fill(selected ? Theme.deepRose : Theme.blush.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("💇🏾‍♀️").font(.system(size: 54))
            Text("Your Lookbook is empty").font(Theme.font(22, .bold)).foregroundStyle(Theme.ink)
            Text("Press Capture look in the mirror to save photos from every angle,\nthen add your hair, bundles and parting here.")
                .font(Theme.font(14)).foregroundStyle(Theme.softInk).multilineTextAlignment(.center)
            Button("Go to the mirror") { model.mode = .mirror }
                .buttonStyle(PillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ look: Look) {
        guard comparing else {
            model.openLookID = look.id
            return
        }
        if let index = compareSelection.firstIndex(of: look.id) {
            compareSelection.remove(at: index)
        } else if compareSelection.count < 2 {
            compareSelection.append(look.id)
        }
        if compareSelection.count == 2 {
            showCompare = true
        }
    }
}

struct LookCard: View {
    @Environment(AppModel.self) private var model
    let look: Look
    var selectionIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                cover
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if look.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.deepRose)
                        .padding(8)
                        .background(Circle().fill(Theme.surface))
                        .padding(10)
                }
                if let selectionIndex {
                    Text("\(selectionIndex + 1)")
                        .font(Theme.font(15, .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.deepRose))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(look.name).font(Theme.font(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(look.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if look.totalBundles > 0 {
                        Text("·")
                        Text("\(look.totalBundles) bundle\(look.totalBundles == 1 ? "" : "s")")
                    }
                    Text("·")
                    Text(look.installMethod.displayName)
                }
                .font(Theme.font(12)).foregroundStyle(Theme.softInk).lineLimit(1)
                if !look.hair.isEmpty {
                    HStack(spacing: -4) {
                        ForEach(look.hair) { hair in
                            Circle().fill(Color(hexString: hair.swatchHex))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(selectionIndex != nil ? Theme.deepRose : Color.clear, lineWidth: 3))
        .shadow(color: Theme.deepRose.opacity(0.1), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    @ViewBuilder
    private var cover: some View {
        if let photo = look.coverPhoto, let image = model.store.image(for: photo) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Theme.blush, Theme.lavender], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.white))
        }
    }
}

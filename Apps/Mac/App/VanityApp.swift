import SwiftUI

@main
struct VanityApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mirror") {
                Button("Capture Look") { Task { await model.captureLook() } }
                Button("Toggle Delay") { model.hub.toggleDelayForAll() }
                Button("Freeze / Unfreeze") { model.hub.toggleFreezeForAll() }
                Divider()
                Button("Show Setup Guide") { model.showOnboarding = true }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.mode {
            case .mirror: MirrorView()
            case .lookbook: LookbookView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModeSwitcher(mode: $model.mode)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
        }
        .sheet(item: Binding(
            get: { model.pendingShots.map(ShotBatch.init) },
            set: { model.pendingShots = $0?.shots }
        )) { batch in
            SnapshotSheet(shots: batch.shots)
        }
    }
}

private struct ShotBatch: Identifiable {
    let shots: [CapturedShot]
    var id: UUID { shots.first?.id ?? UUID() }
}

struct ModeSwitcher: View {
    @Binding var mode: AppModel.Mode

    var body: some View {
        HStack(spacing: 4) {
            segment(.mirror, title: "Mirror", symbol: "sparkles")
            segment(.lookbook, title: "Lookbook", symbol: "heart.text.square")
        }
        .padding(4)
        .background(Capsule().fill(Theme.blush.opacity(0.6)))
    }

    private func segment(_ value: AppModel.Mode, title: String, symbol: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { mode = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(Theme.font(13, .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .foregroundStyle(mode == value ? Color.white : Theme.ink)
                .background(Capsule().fill(mode == value ? Theme.deepRose : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(value == .mirror ? "1" : "2", modifiers: .command)
    }
}

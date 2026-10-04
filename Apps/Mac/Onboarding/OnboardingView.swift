import AVFoundation
import SwiftUI

/// The three setup steps, used in the first-run guide and in the empty mirror.
struct SetupSteps: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(
                number: 1, symbol: "laptopcomputer",
                title: "Your MacBook is the front view",
                detail: "It works automatically. Sit facing the screen like a mirror."
            )
            step(
                number: 2, symbol: "iphone.gen3",
                title: "Put your iPhone on a stand behind you",
                detail: "Turn it sideways, lock it, and keep it near the Mac. It appears by itself (that's Continuity Camera ✨)."
            )
            step(
                number: 3, symbol: "ipad.landscape",
                title: "Open Vanity Cam on your iPad",
                detail: "Point it at the other side of your head. It finds \"\(model.server.advertisedName)\" by itself, so just keep both on the same Wi-Fi."
            )
        }
    }

    private func step(number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.blush).frame(width: 52, height: 52)
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Theme.deepRose)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.font(13)).foregroundStyle(Theme.softInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("✨").font(.system(size: 44))
                Text("Welcome to Vanity").font(Theme.font(28, .bold)).foregroundStyle(Theme.ink)
                Text("See every side of your hair at once.").font(Theme.font(15)).foregroundStyle(Theme.softInk)
            }

            SetupSteps()
                .padding(20)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))

            VStack(alignment: .leading, spacing: 6) {
                tip("Click any view to make it big. Pinch or scroll to zoom in.")
                tip("Turn on Delay, then turn around and watch the back of your head a few seconds later.")
                tip("Press Capture look to save photos from every angle in your Lookbook.")
            }

            Button("Let's go ✨") { model.finishOnboarding() }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 560)
        .background(Theme.background)
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "heart.fill")
            .font(Theme.font(13))
            .foregroundStyle(Theme.ink)
            .symbolRenderingMode(.multicolor)
    }
}

/// What the mirror shows before any camera is found.
struct EmptyMirrorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            if model.cameras.authorization == .denied || model.cameras.authorization == .restricted {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash").font(.system(size: 40)).foregroundStyle(Theme.deepRose)
                    Text("Vanity needs permission to use the camera").font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
                    Text("Open System Settings → Privacy & Security → Camera and switch on Vanity.")
                        .font(Theme.font(14)).foregroundStyle(Theme.softInk)
                    Button("Open Camera Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                }
            } else {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking for cameras…").font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
                }
                SetupSteps()
                    .padding(22)
                    .frame(maxWidth: 520)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

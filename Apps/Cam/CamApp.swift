import AVFoundation
import SwiftUI

@main
struct VanityCamApp: App {
    @State private var model = CamModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CamView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: Task { await model.resume() }
                    case .background: model.pause()
                    default: break
                    }
                }
        }
    }
}

private enum Palette {
    static let blush = Color(red: 0.97, green: 0.84, blue: 0.88)
    static let deepRose = Color(red: 0.76, green: 0.39, blue: 0.56)
    static let ink = Color(red: 0.29, green: 0.23, blue: 0.28)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct CamView: View {
    @Environment(CamModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            Color.black.ignoresSafeArea()

            if CameraCapture.isSimulator {
                LinearGradient(colors: [.pink, .purple, .teal], startPoint: .leading, endPoint: .trailing)
                    .overlay(Text("Simulator test pattern").font(Palette.font(22, .bold)).foregroundStyle(.white))
                    .ignoresSafeArea()
            } else {
                CameraPreview(capture: model.camera).ignoresSafeArea()
            }

            VStack {
                HStack(alignment: .top) {
                    StatusPill(status: model.status)
                    Spacer()
                    if model.macs.count > 1 {
                        Menu {
                            ForEach(model.macs, id: \.self) { name in
                                Button(name) { model.choose(mac: name) }
                            }
                        } label: {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }
                    if !CameraCapture.isSimulator {
                        Button {
                            model.useFrontCamera.toggle()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .accessibilityLabel("Switch camera")
                    }
                }
                .foregroundStyle(Palette.ink)

                Spacer()

                if let help = helpText {
                    Text(help)
                        .font(Palette.font(15, .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                        .padding(.bottom, 8)
                }

                if model.batteryLow {
                    Label("Battery is low. Plug me in 🔌", systemImage: "battery.25")
                        .font(Palette.font(14, .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.blush))
                }
            }
            .padding(20)
        }
    }

    private var helpText: String? {
        switch model.status {
        case .searching:
            "Open Vanity on the Mac and make sure both are on the same Wi-Fi."
        case .connecting:
            nil
        case .streaming:
            nil
        case .localNetworkDenied:
            "Vanity Cam needs Local Network access to find the Mac.\nGo to Settings → Vanity Cam and turn on Local Network."
        case .cameraDenied:
            "Vanity Cam needs the camera.\nGo to Settings → Vanity Cam and turn on Camera."
        }
    }
}

private struct StatusPill: View {
    let status: CamModel.Status

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .streaming(let name):
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("✨ Showing on \(name)")
            case .connecting(let name):
                ProgressView().controlSize(.small)
                Text("Connecting to \(name)…")
            case .searching:
                ProgressView().controlSize(.small)
                Text("Looking for your Mac…")
            case .localNetworkDenied, .cameraDenied:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.deepRose)
                Text("Needs permission")
            }
        }
        .font(Palette.font(16, .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Palette.blush.opacity(0.95)))
        .animation(.easeInOut, value: status)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let capture: CameraCapture

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = capture.session
        view.previewLayer.videoGravity = .resizeAspectFill
        capture.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

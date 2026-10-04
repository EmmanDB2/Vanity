import AppKit
import SwiftUI

/// Blush / cream / lavender palette, with dark-mode twins.
enum Theme {
    static let background = dynamic(light: 0xFFF8F3, dark: 0x221B21)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x30262E)
    static let blush = dynamic(light: 0xF7D6E0, dark: 0x5A3A4A)
    static let rose = dynamic(light: 0xE59BBB, dark: 0xE59BBB)
    static let deepRose = dynamic(light: 0xC2648F, dark: 0xF0A9C8)
    static let lavender = dynamic(light: 0xDCCDF2, dark: 0x4A3F63)
    static let ink = dynamic(light: 0x4A3B47, dark: 0xF5E9EF)
    static let softInk = dynamic(light: 0x8C7787, dark: 0xBCA8B6)

    static let cornerRadius: CGFloat = 22

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// Parses "#RRGGBB" (used for hair swatches saved in the lookbook).
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(nsColor: NSColor(hex: UInt32(cleaned, radix: 16) ?? 0x3B2A20))
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}

/// Big rounded pill button used throughout the app.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .background(Capsule().fill(prominent ? Theme.deepRose : Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.blush, lineWidth: prominent ? 0 : 1))
            .shadow(color: Theme.deepRose.opacity(0.15), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Round icon button for overlays on top of video.
struct BubbleButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(isOn ? Color.white : Theme.ink)
            .background(Circle().fill(isOn ? Theme.deepRose : Theme.surface.opacity(0.92)))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "sparkle")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.deepRose)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        .shadow(color: Theme.deepRose.opacity(0.08), radius: 10, y: 3)
    }
}

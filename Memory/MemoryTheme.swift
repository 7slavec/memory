import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "norka.appAppearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Система"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var details: String {
        switch self {
        case .system: "Как на устройстве"
        case .light: "Всегда светлая"
        case .dark: "Всегда тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MemoryTheme {
    static let accent = adaptive(light: 0x171717, dark: 0xF4F4F4)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x141414)
    static let accentSoft = adaptive(light: 0xE8E8E8, dark: 0x343434)
    static let warm = accent
    static let highlight = Color(red: 231/255, green: 243/255, blue: 99/255)
    static let onHighlight = Color(red: 28/255, green: 33/255, blue: 16/255)
    static let background = adaptive(light: 0xFFFFFF, dark: 0x131313)
    static let card = adaptive(light: 0xF2F2F2, dark: 0x242424)
    static let raised = adaptive(light: 0xE8E8E8, dark: 0x343434)
    static let secondaryText = adaptive(light: 0x626262, dark: 0xB6B6B6)
    static let danger = adaptive(light: 0xAB3826, dark: 0xFFAC99)
    static let cardRadius: CGFloat = 20
    static let pageInset: CGFloat = 20
    static let motion = Animation.spring(response: 0.48, dampingFraction: 0.92)

    private static func adaptive(light: UInt, dark: UInt) -> Color {
#if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
#else
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
#endif
    }
}

/// Shared neutral control: geometry stays stable on hover and press.
struct MemoryActionStyle: ButtonStyle {
    var prominent = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(prominent ? MemoryTheme.onAccent : MemoryTheme.accent)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(prominent ? MemoryTheme.accent : (hovered ? MemoryTheme.raised : MemoryTheme.card), in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.78 : hovered ? 0.9 : 1)
            .onHover { hovered = $0 }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

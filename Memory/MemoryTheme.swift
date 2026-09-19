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
    static let accent = Color(red: 0.38, green: 0.36, blue: 0.92)
    static let accentSoft = Color(red: 0.88, green: 0.87, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.69, blue: 0.37)

    static var background: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }

    static var card: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }
}

struct MemoryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MemoryTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 16, y: 7)
    }
}

extension View {
    func memoryCard() -> some View {
        modifier(MemoryCardModifier())
    }
}

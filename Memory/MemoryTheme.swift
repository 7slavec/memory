import SwiftUI

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

import SwiftUI

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

struct MemoryEntryCardModifier: ViewModifier {
    let isEvent: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isEvent {
                    LinearGradient(
                        colors: [
                            MemoryTheme.warm.opacity(0.22),
                            MemoryTheme.warm.opacity(0.08),
                            MemoryTheme.card
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    MemoryTheme.card
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isEvent ? MemoryTheme.warm.opacity(0.28) : Color.primary.opacity(0.045),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isEvent ? MemoryTheme.warm.opacity(0.08) : Color.black.opacity(0.045),
                radius: 16,
                y: 7
            )
    }
}

extension View {
    func memoryCard() -> some View {
        modifier(MemoryCardModifier())
    }

    func memoryEntryCard(isEvent: Bool) -> some View {
        modifier(MemoryEntryCardModifier(isEvent: isEvent))
    }
}

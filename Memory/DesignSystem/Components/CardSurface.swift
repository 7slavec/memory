import SwiftUI

struct MemoryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MemoryTheme.card, in: RoundedRectangle(cornerRadius: MemoryTheme.cardRadius))
    }
}

struct MemoryEntryCardModifier: ViewModifier {
    let isEvent: Bool
    func body(content: Content) -> some View {
        content.modifier(MemoryCardModifier())
    }
}

extension View {
    func memoryCard() -> some View { modifier(MemoryCardModifier()) }
    func memoryEntryCard(isEvent: Bool) -> some View {
        modifier(MemoryEntryCardModifier(isEvent: isEvent))
    }
}

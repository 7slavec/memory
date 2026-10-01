import SwiftUI

struct MemoryCardModifier: ViewModifier {
    var cornerRadius: CGFloat = MemoryTheme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(MemoryTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct MemoryEntryCardModifier: ViewModifier {
    let isEvent: Bool
    func body(content: Content) -> some View {
        content.modifier(MemoryCardModifier())
    }
}

extension View {
    func memoryCard(cornerRadius: CGFloat = MemoryTheme.cardRadius) -> some View { modifier(MemoryCardModifier(cornerRadius: cornerRadius)) }
    func memoryEntryCard(isEvent: Bool) -> some View {
        modifier(MemoryEntryCardModifier(isEvent: isEvent))
    }
}

import SwiftUI

struct MemorySearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Что ищем?", text: $text).textFieldStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity)
            Button { text = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Очистить поиск")
            .opacity(text.isEmpty ? 0 : 1).disabled(text.isEmpty).accessibilityHidden(text.isEmpty)
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 4)
        .memoryCard()
    }
}

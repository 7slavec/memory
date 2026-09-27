#if DEBUG
import SwiftUI

struct CatalogSearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 22)).frame(width: 40)
                .foregroundStyle(palette.secondary.color).accessibilityHidden(true)
            TextField("Что ищем?", text: $text)
                .textFieldStyle(.plain).font(CatalogType.body).lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityIdentifier("catalog-search")
            CatalogIconButton(symbol: "xmark", label: "Очистить поиск") { text = "" }
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty).accessibilityHidden(text.isEmpty)
        }
        .padding(CatalogMetrics.fieldInset)
        .frame(maxWidth: .infinity)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain).accessibilityIdentifier("catalog-search-container")
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

struct CatalogComposerField: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    let onSend: () -> Void
    let onExpand: () -> Void
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CatalogIconButton(symbol: "arrow.up", label: "Отправить пример", tone: .primary, action: onSend)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("catalog-send")
            TextField("Написать напоминание", text: $text, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.plain).font(CatalogType.body)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: CatalogControlSize.medium.visual)
                .accessibilityIdentifier("catalog-composer")
            CatalogIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Развернуть пример", action: onExpand)
                .accessibilityIdentifier("catalog-expand")
        }
        .padding(CatalogMetrics.fieldInset)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 20))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

struct CatalogChoiceControl: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: String
    @State private var presented = false
    let options: [String]
    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 8) {
                Text(selection).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(palette.text.color)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(palette.inset.color, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Когда напомнить").accessibilityValue(selection)
        .accessibilityIdentifier("catalog-reminder-choice")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option; presented = false } label: {
                        HStack {
                            Text(option)
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark").opacity(option == selection ? 1 : 0).accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CatalogButtonStyle(tone: option == selection ? .primary : .neutral))
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                }
            }
            .padding(8).frame(width: 248)
            .environment(\.colorScheme, scheme)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(palette.surface.color)
        }
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}
#endif

#if os(macOS)
import SwiftUI

struct MacWidgetReview: View {
    @ObservedObject var session: VoiceBatchReviewSession
    let onEdit: (VoiceReviewEntry) -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void
    let maximumHeight: CGFloat
    @State private var contentHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: MemoryWidgetMetrics.gap) {
            Text(VoiceEntryCountLabel.short(session.entries.count))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: MemoryWidgetMetrics.gap) {
                    ForEach(session.entries) { entry in
                        MemoryItemRow(item: session.item(for: entry), onEdit: { onEdit(entry) }, showsContextMenu: false)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(maximumHeight - 96, max(60, contentHeight)))
            if !session.canSave {
                Text("Откройте запись и проверьте название и даты.")
                    .font(.system(size: 12)).foregroundStyle(MemoryTheme.danger)
            }
            HStack(spacing: MemoryWidgetMetrics.gap) {
                Button(action: onDiscard) { Image(systemName: "trash") }
                    .buttonStyle(MemoryWidgetActionStyle(iconOnly: true, destructive: true))
                    .accessibilityLabel("Отменить создание группы")
                if session.hasDraftLinks {
                    Button(action: session.unlinkDrafts) { MemoryUnlinkSymbol(surface: MemoryTheme.card) }
                        .buttonStyle(MemoryWidgetActionStyle(iconOnly: true, destructive: true))
                        .accessibilityLabel("Не связывать записи")
                }
                Button(action: onSave) { Text("Сохранить").frame(maxWidth: .infinity) }
                    .buttonStyle(MemoryWidgetActionStyle(prominent: true))
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!session.canSave)
            }
        }
        .padding(MemoryWidgetMetrics.inset)
    }
}
#endif

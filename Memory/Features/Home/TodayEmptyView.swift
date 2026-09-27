import SwiftUI

struct TodayEmptyView: View {
    let hasUpcomingItems: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(MemoryTheme.accent)
                .frame(width: 44, height: 44)
                .background(MemoryTheme.accent.opacity(0.11))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("На сегодня всё спокойно")
                    .font(.body.weight(.semibold))
                Text(
                    hasUpcomingItems
                        ? "Будущие записи находятся в разделе «Все»."
                        : "Добавьте задачу, когда появится что-то важное."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .memoryCard()
    }
}

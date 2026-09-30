import SwiftUI

struct MemoryLinkBadge: View {
    /// Number of other records in the shared group.
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
            if count > 1 { Text("\(count + 1)").monospacedDigit() }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(MemoryTheme.accent.opacity(count > 0 ? 0.16 : 0.08), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 0 ? "Связать запись" : "Связанные записи: \(count + 1)")
    }
}

/// Card accessory: fixed circular silhouette; the count never widens the card.
struct MemoryLinkCircle: View {
    let count: Int
    var onColor = false

    var body: some View {
        Image(systemName: "link")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(onColor ? MemoryTheme.onEventCard : MemoryTheme.accent)
            .frame(width: 32, height: 32)
            .background((onColor ? MemoryTheme.onEventCard : MemoryTheme.accent).opacity(0.14), in: Circle())
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text(count + 1 > 99 ? "99+" : "\(count + 1)")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(MemoryTheme.background, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
            .frame(width: MemoryDensity.recordLinkTarget, height: MemoryDensity.recordLinkTarget)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Связанные записи: \(count + 1)")
    }
}

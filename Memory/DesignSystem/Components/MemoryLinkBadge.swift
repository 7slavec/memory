import SwiftUI

struct MemoryLinkBadge: View {
    /// Number of other records linked to this record.
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

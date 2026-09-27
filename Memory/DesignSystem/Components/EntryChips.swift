import SwiftUI

struct MemoryEntryKindBadge: View {
    let kind: EntryKind

    var body: some View {
        let color = kind == .event ? MemoryTheme.warm : MemoryTheme.accent
        return Text(kind.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.16), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct MemoryEntryKindChip: View {
    let kind: EntryKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MemoryEntryKindBadge(kind: kind)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Тип записи: \(kind.title)")
        .accessibilityHint("Меняет тип записи")
    }
}

struct MemoryScheduleValueBadge: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MemoryTheme.accent)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(MemoryTheme.accent.opacity(0.09))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct MemoryScheduleValueChip: View {
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MemoryScheduleValueBadge(value: value)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

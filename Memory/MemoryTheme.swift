import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "norka.appAppearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Система"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var details: String {
        switch self {
        case .system: "Как на устройстве"
        case .light: "Всегда светлая"
        case .dark: "Всегда тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MemoryTheme {
    static let accent = Color(red: 0.38, green: 0.36, blue: 0.92)
    static let accentSoft = Color(red: 0.88, green: 0.87, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.69, blue: 0.37)

    static var background: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }

    static var card: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }
}

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

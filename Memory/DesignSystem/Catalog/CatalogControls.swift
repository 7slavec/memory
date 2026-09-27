#if DEBUG
import SwiftUI

enum CatalogTone { case primary, neutral, accent, event, danger }

struct CatalogButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    let tone: CatalogTone
    var size: CatalogControlSize = .medium
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        CatalogButtonFace(label: configuration.label, tone: tone, size: size,
                          iconOnly: iconOnly, enabled: enabled, pressed: configuration.isPressed,
                          palette: CatalogPalette(dark: scheme == .dark))
    }
}

private struct CatalogButtonFace<Label: View>: View {
    @State private var hovered = false
    let label: Label
    let tone: CatalogTone
    let size: CatalogControlSize
    let iconOnly: Bool
    let enabled: Bool
    let pressed: Bool
    let palette: CatalogPalette

    private var foreground: Color {
        guard enabled else { return palette.secondary.color }
        switch tone {
        case .primary: return palette.onPrimary.color
        case .neutral: return palette.text.color
        case .accent: return palette.accent.color
        case .event: return palette.event.color
        case .danger: return palette.danger.color
        }
    }
    private var fill: Color {
        guard enabled else { return palette.inset.color }
        switch tone {
        case .primary: return palette.primaryFill.color
        case .neutral: return palette.inset.color
        case .accent: return palette.accentSurface.color
        case .event: return palette.eventSurface.color
        case .danger: return palette.dangerSurface.color
        }
    }
    var body: some View {
        label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : 16)
            .frame(width: iconOnly ? size.visual : nil)
            .frame(minHeight: size.visual)
            .background(fill, in: Capsule())
            .overlay {
                Capsule().fill(foreground.opacity(enabled ? (pressed ? 0.14 : hovered ? 0.07 : 0) : 0))
                    .allowsHitTesting(false)
            }
            .frame(minWidth: size.hit, minHeight: size.hit)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

struct CatalogIconButton: View {
    let symbol: String
    let label: String
    var size: CatalogControlSize = .medium
    var tone: CatalogTone = .neutral
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).accessibilityHidden(true) }
            .buttonStyle(CatalogButtonStyle(tone: tone, size: size, iconOnly: true))
            .accessibilityLabel(label)
    }
}

struct CatalogChip: View {
    let title: String
    var icon: String? = nil
    var tone: CatalogTone = .accent
    let action: () -> Void
    var onRemove: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).accessibilityHidden(true) }
                    Text(title)
                }
            }
            .buttonStyle(CatalogButtonStyle(tone: tone, size: .small))
            if let onRemove {
                CatalogIconButton(symbol: "xmark", label: "Убрать \(title)", size: .small, tone: tone, action: onRemove)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CatalogSettingsRow<Control: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var icon: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(systemName: icon).foregroundStyle(palette.accent.color).accessibilityHidden(true) }
            Text(title).font(CatalogType.body)
            Spacer(minLength: 12)
            control
        }
        .foregroundStyle(palette.text.color)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 16))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

struct CatalogRecordCard: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var details: String? = nil
    var schedule: String? = nil
    var isEvent = false
    var completed = false
    let onOpen: () -> Void
    var onToggle: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 8) {
            if !isEvent, let onToggle {
                Button(action: onToggle) {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(completed ? palette.accent.color : palette.secondary.color)
                .accessibilityLabel(completed ? "Вернуть в активные" : "Выполнить \(title)")
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(CatalogType.body.weight(.medium)).strikethrough(completed)
                    if let details, !details.isEmpty {
                        Text(details).font(.subheadline).foregroundStyle(palette.secondary.color).lineLimit(2)
                    }
                    if let schedule {
                        Text(schedule).font(CatalogType.caption.weight(.medium)).foregroundStyle(palette.accent.color)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isEvent ? "Событие. Открыть запись" : "Напоминание. Открыть запись")
        }
        .foregroundStyle(completed ? palette.secondary.color : palette.text.color)
        .padding(CatalogMetrics.cardInset)
        .background(isEvent ? palette.eventSurface.color : palette.surface.color,
                    in: RoundedRectangle(cornerRadius: CatalogMetrics.cardRadius))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}
#endif

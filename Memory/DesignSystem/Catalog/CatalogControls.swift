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
        return palette.foreground(for: tone).color
    }
    private var fill: Color {
        guard enabled else { return palette.inset.color }
        return palette.fill(for: tone).color
    }
    var body: some View {
        label
            .font(iconOnly ? .system(size: size.symbol, weight: .medium) : .system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : 16)
            .frame(width: iconOnly ? size.visual : nil)
            .frame(minHeight: size.visual)
            .background(fill, in: Capsule())
            .overlay {
                Capsule().fill(Color.black.opacity(enabled ? (pressed ? 0.14 : hovered ? 0.07 : 0) : 0))
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
                CatalogPillLabel(title: title, icon: icon, tone: tone)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(CatalogPressStyle())
            if let onRemove {
                Button(action: onRemove) {
                    CatalogPillLabel(title: "", icon: "xmark", tone: tone)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(CatalogPressStyle()).accessibilityLabel("Убрать \(title)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A value label, not a nested button. Also used for metadata inside a record's open action.
struct CatalogPillLabel: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 13
    let title: String
    var icon: String? = nil
    var tone: CatalogTone = .accent
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            if !title.isEmpty { Text(title) }
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.foreground(for: tone).color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: CatalogMetrics.chipHeight)
        .background(palette.fill(for: tone).color, in: Capsule())
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

struct CatalogPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
    }
}

struct CatalogSettingsRow<Control: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var icon: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(systemName: icon).font(.title3).accessibilityHidden(true) }
            Text(title).font(CatalogType.body)
            Spacer(minLength: 12)
            control
        }
        .foregroundStyle(palette.text.color)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 16))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}

struct CatalogRecordCard: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var descriptionSize: CGFloat = 14
    let title: String
    var details: String? = nil
    var schedule: String? = nil
    var isEvent = false
    var completed = false
    let onOpen: () -> Void
    var onToggle: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: titleSize, weight: .semibold, design: .rounded)).strikethrough(completed)
                    if let details, !details.isEmpty {
                        Text(details)
                            .font(.system(size: descriptionSize, design: .rounded))
                            .foregroundStyle(isEvent ? palette.eventSecondary.color : palette.secondary.color)
                            .lineLimit(2)
                    }
                    if let schedule, !schedule.isEmpty {
                        CatalogPillLabel(title: schedule)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isEvent ? "Событие. Открыть запись" : "Напоминание. Открыть запись")
            if !isEvent, let onToggle {
                Button(action: onToggle) {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .regular)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text.color)
                .accessibilityLabel(completed ? "Вернуть в активные" : "Выполнить \(title)")
            }
        }
        .foregroundStyle(isEvent ? palette.onEvent.color : completed ? palette.secondary.color : palette.text.color)
        .padding(CatalogMetrics.cardInset)
        .background {
            RoundedRectangle(cornerRadius: CatalogMetrics.cardRadius)
                .fill(LinearGradient(colors: isEvent ? [palette.eventSurface.color, palette.eventEnd.color] : [palette.surface.color, palette.surface.color], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
}
#endif

import SwiftUI

/// Motion belongs to the live event only; ordinary cards never start an animation.
struct ActiveEventPulse: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(MemoryTheme.onEventCard.opacity(bright && !reduceMotion ? 0.10 : 0.015))
            .onAppear(perform: begin)
            .onChange(of: scenePhase) { _, _ in begin() }
            .onDisappear { bright = false }
            .accessibilityHidden(true)
    }

    private func begin() {
        bright = false
        guard !reduceMotion, scenePhase == .active else { return }
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            bright = true
        }
    }
}

struct ActiveEventCounterPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var bright = false

    func body(content: Content) -> some View {
        content
            .opacity(bright && !reduceMotion ? 0.76 : 1)
            .onAppear(perform: begin)
            .onChange(of: scenePhase) { _, _ in begin() }
            .onDisappear { bright = false }
    }

    private func begin() {
        bright = false
        guard !reduceMotion, scenePhase == .active else { return }
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
            bright = true
        }
    }
}

struct ActiveEventBadge: View {
    let start: Date
    let end: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if EventActivity.isActive(kind: .event, start: start, end: end,
                                      isCompleted: false, at: context.date),
               let remaining = EventActivity.remaining(until: end, at: context.date) {
                HStack(spacing: compact ? 8 : 12) {
                    Circle().fill(MemoryTheme.onEventCard)
                        .frame(width: 7, height: 7)
                        .modifier(ActiveEventCounterPulse())
                    Text("Сейчас идёт")
                        .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(remaining.display)
                        .font(.system(size: compact ? 16 : 21, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .modifier(ActiveEventCounterPulse())
                }
                .foregroundStyle(MemoryTheme.onEventCard)
                .padding(.horizontal, compact ? 12 : 16)
                .frame(minHeight: compact ? 38 : 48)
                .background(MemoryTheme.eventCard,
                            in: RoundedRectangle(cornerRadius: compact ? 13 : 17))
                .overlay {
                    ActiveEventPulse(cornerRadius: compact ? 13 : 17)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Событие идёт. \(remaining.accessibilityText)")
            }
        }
    }
}

struct ActiveEventFinishStyle: ButtonStyle {
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(MemoryTheme.onEventCard)
            .frame(minHeight: compact ? 36 : 44)
            .padding(.horizontal, compact ? 12 : 18)
            .background(MemoryTheme.eventCard, in: Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

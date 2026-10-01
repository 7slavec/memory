import SwiftUI

/// Three clipped waves expand from the top trailing corner without changing layout.
/// Only visible, active events ask SwiftUI for animation frames.
struct ActiveEventRings: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        let isMoving = isVisible && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isMoving)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let origin = CGPoint(x: size.width - 8, y: 8)
                let reach = hypot(size.width + 8, size.height + 8)
                for index in 0..<3 {
                    let progress: Double = isMoving
                        ? (timeline.date.timeIntervalSinceReferenceDate / 4.5
                           + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        : 0.25 + Double(index) * 0.22
                    let easedProgress = progress * progress * (3 - 2 * progress)
                    let radius = 5 + easedProgress * reach
                    let fade = min(progress / 0.14, 1) * pow(1 - progress, 1.1)
                    let ring = Path(ellipseIn: CGRect(x: origin.x - radius,
                                                      y: origin.y - radius,
                                                      width: radius * 2,
                                                      height: radius * 2))
                    context.fill(ring, with: .color(MemoryTheme.onEventCard.opacity(0.05 * fade)))
                    context.stroke(ring, with: .color(MemoryTheme.onEventCard.opacity(0.45 * fade)),
                                   lineWidth: 1.7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

struct ActiveEventCounterPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let isMoving = isVisible && !reduceMotion && scenePhase == .active
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isMoving)) { timeline in
            let wave = isMoving
                ? (1 + sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 1.1)) / 2
                : 0.5
            content
                .foregroundStyle(MemoryTheme.onEventCard)
                .opacity(0.84 + 0.16 * wave)
                .scaleEffect(0.985 + 0.03 * wave)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
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
                        .font(.system(size: compact ? 16 : 21, weight: .regular))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        .contentTransition(.identity)
                        .animation(nil, value: remaining.display)
                        .modifier(ActiveEventCounterPulse())
                }
                .foregroundStyle(MemoryTheme.onEventCard)
                .padding(.horizontal, compact ? 12 : 16)
                .frame(minHeight: compact ? 38 : 48)
                .background {
                    RoundedRectangle(cornerRadius: compact ? 13 : 17)
                        .fill(MemoryTheme.eventCard)
                        .overlay {
                            ActiveEventRings(cornerRadius: compact ? 13 : 17)
                                .allowsHitTesting(false)
                        }
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

import SwiftUI

/// Stable particle identities morph between states; only this small canvas ticks.
struct GlassVoiceOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let isListening: Bool
    let isProcessing: Bool
    let isPulsing: Bool
    let size: CGFloat
    var isVisible = true
    var animatesInBackground = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
                                paused: !isVisible || reduceMotion || (!animatesInBackground && scenePhase != .active) || !(isListening || isProcessing))) { context in
            VoiceParticleField(
                listening: isListening ? 1 : 0,
                processing: isProcessing ? 1 : 0,
                time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: isListening)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: isProcessing)
        }
        .frame(width: size + 30, height: size + 30)
        .accessibilityHidden(true)
    }
}

private struct VoiceParticleField: View, Animatable {
    var listening: Double
    var processing: Double
    let time: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(listening, processing) }
        set { listening = newValue.first; processing = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.39
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<144 {
                let i = Double(index)
                let angle = i * 2.3999632297
                let depth = sqrt((i + 0.5) / 144)
                // Keep phase continuous through the fade-out; only the animated
                // weights change. Resetting phase on stop makes the clusters jump.
                let phase = time * 0.65
                let wave = sin(angle * 3) * 0.018 + sin(angle * 3 + phase) * listening * 0.055
                let drift = sin(phase * 1.8 + i) * listening * 0.018
                let circleX = cos(angle) * depth * (1 + wave + drift)
                let circleY = sin(angle) * depth * (1 - wave + drift)
                let cluster = Double(index % 3)
                let orbit = cluster * .pi * 2 / 3 + phase
                let clusterDepth = sqrt(Double(index / 3 + 1) / 48) * 0.34
                let processX = cos(orbit) * 0.55 + cos(angle) * clusterDepth
                let processY = sin(orbit) * 0.55 + sin(angle) * clusterDepth
                let x = circleX + (processX - circleX) * processing
                let y = circleY + (processY - circleY) * processing
                let diameter = 2.3 + (1 - depth) * 1.6
                let rect = CGRect(x: center.x + x * radius - diameter / 2,
                                  y: center.y + y * radius - diameter / 2,
                                  width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.4 + depth * 0.6)))
            }
        }
    }
}

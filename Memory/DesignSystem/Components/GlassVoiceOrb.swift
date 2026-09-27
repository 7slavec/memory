import SwiftUI

struct GlassVoiceOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    let isListening: Bool
    let isProcessing: Bool
    let isPulsing: Bool
    let size: CGFloat

    private var isActive: Bool { isListening || isProcessing }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.33).opacity(0.82),
                            Color(red: 1.0, green: 0.32, blue: 0.58).opacity(0.78),
                            MemoryTheme.accent.opacity(0.74),
                            Color.cyan.opacity(0.44),
                            Color(red: 1.0, green: 0.78, blue: 0.33).opacity(0.82)
                        ],
                        center: .center
                    )
                )
                .frame(width: size + 22, height: size + 22)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .blur(radius: isActive ? 19 : 15)
                .opacity(isActive ? 0.7 : 0.42)
                .scaleEffect(isActive && isPulsing ? 1.08 : 1)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.33),
                            Color(red: 1.0, green: 0.36, blue: 0.58),
                            MemoryTheme.accent.opacity(0.94)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.cyan.opacity(0.28),
                            Color.clear,
                            Color.purple.opacity(0.46),
                            Color.white.opacity(0.64)
                        ],
                        center: .center
                    )
                )
                .frame(width: size - 2, height: size - 2)
                .opacity(isActive ? 0.92 : 0.72)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .mask {
                    ZStack {
                        Circle()
                        Circle()
                            .inset(by: 7)
                            .fill(.black)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.42 : 0.32),
                            Color(red: 1.0, green: 0.63, blue: 0.24).opacity(0.32),
                            Color.pink.opacity(0.08),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.58, y: 0.38),
                        startRadius: 2,
                        endRadius: size * 0.58
                    )
                )
                .frame(width: size - 14, height: size - 14)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.46), Color.clear],
                        center: UnitPoint(x: 0.38, y: 0.8),
                        startRadius: 0,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size - 10, height: size - 10)
                .blendMode(.plusLighter)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.78), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.52, height: size * 0.22)
                .blur(radius: 7)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.17, y: -size * 0.27)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.76), Color.white.opacity(0.08), Color.white.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: size, height: size)
        }
        .frame(width: size + 30, height: size + 30)
        .compositingGroup()
        .shadow(
            color: MemoryTheme.accent.opacity(isActive ? 0.3 : 0.16),
            radius: isActive ? 34 : 24,
            y: 12
        )
        .scaleEffect(isActive && isPulsing ? 1.025 : 1)
        .animation(.easeInOut(duration: 1.5), value: isPulsing)
        .onAppear { updateRotation(isActive: isActive) }
        .onChange(of: isActive) { _, active in
            updateRotation(isActive: active)
        }
        .accessibilityHidden(true)
    }

    private func updateRotation(isActive: Bool) {
        guard !reduceMotion, isActive else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isRotating = false
            }
            return
        }

        isRotating = false
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            isRotating = true
        }
    }
}

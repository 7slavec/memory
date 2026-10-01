import SwiftUI
import Testing
@testable import Memory

struct ActiveEventCornerGeometryTests {
    @Test func cornerPulsePeaksWhenEachRingBegins() {
        for cycle in [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0] {
            #expect(abs(ActiveEventCornerGeometry.pulse(cycle: cycle) - 1) < 0.0001)
        }
        #expect(ActiveEventCornerGeometry.pulse(cycle: 1.0 / 6.0) < 0.0001)
    }

    @Test func animatedCornerStaysInsideOriginalFrame() {
        for size in [CGSize(width: 120, height: 38), CGSize(width: 330, height: 150)] {
            let rect = CGRect(origin: .zero, size: size)
            for cornerRadius: CGFloat in [13, 16, 20] {
                for pulse in [CGFloat.zero, 0.5, 1] {
                    let bounds = ActiveEventCornerGeometry.outline(
                        in: rect, cornerRadius: cornerRadius, pulse: pulse).boundingRect
                    #expect(rect.contains(bounds))
                }
            }
        }
    }

    @Test func strongerCornerPulseKeepsCompactCornerRounded() {
        #expect(ActiveEventCornerGeometry.topTrailingRadius(cornerRadius: 20, pulse: 0) == 20)
        #expect(ActiveEventCornerGeometry.topTrailingRadius(cornerRadius: 20, pulse: 1) == 10)
        #expect(ActiveEventCornerGeometry.topTrailingRadius(cornerRadius: 16, pulse: 1) > 7)
        #expect(ActiveEventCornerGeometry.topTrailingRadius(cornerRadius: 13, pulse: 1) > 5)
    }
}

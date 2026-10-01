import SwiftUI

struct MemoryUnlinkSymbol: View {
    var surface: Color = MemoryTheme.raised
    var body: some View {
        Image(systemName: "link")
            .overlay {
                UnlinkSlash().stroke(surface, lineWidth: 5)
                UnlinkSlash().stroke(MemoryTheme.danger, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
    }
}

private struct UnlinkSlash: Shape {
    func path(in rect: CGRect) -> Path {
        Path {
            $0.move(to: CGPoint(x: rect.minX, y: rect.minY))
            $0.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

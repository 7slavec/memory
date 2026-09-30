import SwiftUI

/// Static, resolution-independent faces. No image downloads or continuous rendering.
struct AnimalFace: View {
    let animal: ProfileAnimal
    let fur: ProfileFur

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let ink = Color(red: 0.13, green: 0.16, blue: 0.14)
            let coat = Color(red: Double((fur.hex >> 16) & 255) / 255,
                             green: Double((fur.hex >> 8) & 255) / 255, blue: Double(fur.hex & 255) / 255)
            var head = Path()
            switch animal {
            case .cat:
                head.move(to: CGPoint(x: 17, y: 47))
                head.addLine(to: CGPoint(x: 16, y: 13))
                head.addQuadCurve(to: CGPoint(x: 39, y: 30), control: CGPoint(x: 30, y: 15))
                head.addQuadCurve(to: CGPoint(x: 61, y: 30), control: CGPoint(x: 50, y: 25))
                head.addQuadCurve(to: CGPoint(x: 84, y: 13), control: CGPoint(x: 74, y: 15))
                head.addLine(to: CGPoint(x: 83, y: 47))
                head.addCurve(to: CGPoint(x: 50, y: 89), control1: CGPoint(x: 96, y: 74), control2: CGPoint(x: 78, y: 89))
                head.addCurve(to: CGPoint(x: 17, y: 47), control1: CGPoint(x: 22, y: 89), control2: CGPoint(x: 4, y: 74))
            case .dog:
                head.addRoundedRect(in: CGRect(x: 17, y: 25, width: 66, height: 65), cornerSize: CGSize(width: 28, height: 28))
                head.addEllipse(in: CGRect(x: 5, y: 26, width: 24, height: 43))
                head.addEllipse(in: CGRect(x: 71, y: 26, width: 24, height: 43))
            case .rabbit:
                head.addEllipse(in: CGRect(x: 25, y: 1, width: 19, height: 54))
                head.addEllipse(in: CGRect(x: 56, y: 1, width: 19, height: 54))
                head.addRoundedRect(in: CGRect(x: 16, y: 35, width: 68, height: 55), cornerSize: CGSize(width: 30, height: 28))
            }
            head.closeSubpath()
            // Filter only the silhouette, never the facial features or the background.
            var silhouette = context
            silhouette.addFilter(.shadow(color: ink.opacity(0.20), radius: 3, x: 0, y: 3))
            silhouette.fill(head, with: .color(coat))
            let features = fur == .cream ? ink : Color(red: 1, green: 0.97, blue: 0.89)
            for x in [34.0, 61.0] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 51, width: 5, height: 7)), with: .color(features))
            }
            var nose = Path()
            nose.move(to: CGPoint(x: 46, y: 64))
            nose.addQuadCurve(to: CGPoint(x: 54, y: 64), control: CGPoint(x: 50, y: 62))
            nose.addLine(to: CGPoint(x: 50, y: 69)); nose.closeSubpath()
            context.fill(nose, with: .color(features))
            var mouth = Path()
            mouth.move(to: CGPoint(x: 50, y: 68))
            mouth.addLine(to: CGPoint(x: 50, y: 73))
            mouth.addQuadCurve(to: CGPoint(x: 43, y: 76), control: CGPoint(x: 48, y: 79))
            mouth.move(to: CGPoint(x: 50, y: 73))
            mouth.addQuadCurve(to: CGPoint(x: 57, y: 76), control: CGPoint(x: 52, y: 79))
            context.stroke(mouth, with: .color(features), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

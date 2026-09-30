import SwiftUI

struct MemorySectionHeader: View {
    let title: String
    let subtitle: String?
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: MemoryDensity.sectionTitle, weight: .semibold))
            Text("\(count)").font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

#if os(macOS)
/// Scroll-local state keeps pinning updates out of the root's record grouping and queries.
struct DesktopRecordsPage<Heading: View, Search: View, Records: View>: View {
    let allowsCapture: Bool
    let onCreate: () -> Void
    @ViewBuilder var heading: () -> Heading
    @ViewBuilder var search: () -> Search
    @ViewBuilder var records: () -> Records
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerHeight: CGFloat = 0
    @State private var isHeaderHidden = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                HStack(spacing: 12) {
                    heading()
                    if allowsCapture {
                        Button(action: onCreate) { Label("Новая запись", systemImage: "plus") }
                            .buttonStyle(MemoryActionStyle(prominent: true))
                            .fixedSize()
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

                Section {
                    VStack(alignment: .leading, spacing: 20) { records() }
                        .frame(maxWidth: 820, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.top, 12)
                        .padding(.bottom, allowsCapture ? 130 : 40)
                        .frame(maxWidth: .infinity)
                } header: {
                    HStack(spacing: 12) {
                        search().frame(maxWidth: .infinity)
                        if allowsCapture && isHeaderHidden {
                            Button(action: onCreate) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(MemoryTheme.background)
                                    .background(MemoryTheme.accent, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Новая запись")
                            .accessibilityIdentifier("pinnedNewRecord")
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(MemoryTheme.background)
                    .zIndex(1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHeaderHidden)
                }
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            headerHeight > 0 && geometry.contentOffset.y + geometry.contentInsets.top >= headerHeight
        } action: { _, hidden in
            isHeaderHidden = hidden
        }
    }
}
#endif

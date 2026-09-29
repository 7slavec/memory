import SwiftUI

struct ScheduleFieldAnchors: PreferenceKey {
    static var defaultValue: [SchedulePickerTarget: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [SchedulePickerTarget: Anchor<CGRect>],
                       nextValue: () -> [SchedulePickerTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Uses the editor's safe content region, not the physical screen.
struct SchedulePanelPlacement {
    let frame: CGRect
    let isBottomPanel: Bool

    init(container: CGSize, source: CGRect, preferredSize: CGSize) {
        let margin: CGFloat = 12
        let width = min(preferredSize.width, max(0, container.width - margin * 2))
        let height = min(preferredSize.height, max(0, container.height - margin * 2))
        let x = min(max(margin, source.midX - width / 2), max(margin, container.width - width - margin))
        if source.minY - margin * 2 >= height {
            frame = CGRect(x: x, y: source.minY - margin - height, width: width, height: height)
            isBottomPanel = false
        } else if container.height - source.maxY - margin * 2 >= height {
            frame = CGRect(x: x, y: source.maxY + margin, width: width, height: height)
            isBottomPanel = false
        } else {
            frame = CGRect(x: (container.width - width) / 2,
                           y: max(margin, container.height - height - margin), width: width, height: height)
            isBottomPanel = true
        }
    }
}

#if os(iOS)
/// One local presentation avoids a UIKit popover squeezing away the month header.
struct MemoryMobileSchedulePanel: ViewModifier {
    @Binding var active: SchedulePickerTarget?
    @Binding var selection: Date
    let minimumDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presented: Binding<Bool> {
        Binding(get: { active != nil }, set: { if !$0 { active = nil } })
    }

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ScheduleFieldAnchors.self) { anchors in
            GeometryReader { geometry in
                if let target = active, let anchor = anchors[target] {
                    let placement = SchedulePanelPlacement(
                        container: geometry.size, source: geometry[anchor],
                        preferredSize: CGSize(width: target.editsDate ? 340 : 316,
                                              height: target.editsDate ? 416 : 226))
                    ZStack(alignment: .topLeading) {
                        Button { active = nil } label: {
                            Color.black.opacity(placement.isBottomPanel ? 0.22 : 0.06)
                                .contentShape(Rectangle()).ignoresSafeArea()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Закрыть выбор даты и времени")

                        ScrollView(.vertical) {
                            Group {
                                if target.editsDate {
                                    MemoryCalendarPicker(selection: $selection, isPresented: presented,
                                                         minimumDate: minimumDate, width: placement.frame.width)
                                } else {
                                    MemoryTimePicker(selection: $selection, isPresented: presented)
                                }
                            }
                            .id(target)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: placement.frame.width, height: placement.frame.height)
                        .background(MemoryTheme.card, in: RoundedRectangle(cornerRadius: 22))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                        .position(x: placement.frame.midX, y: placement.frame.midY)
                        .accessibilityIdentifier("schedulePanel")
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { active = nil }
                        .transition(.opacity.combined(with: .offset(y: placement.isBottomPanel ? 24 : 6)))
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}
#endif

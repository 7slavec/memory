import SwiftUI

/// One anchored presentation for the editor on both platforms.
struct MemorySchedulePopover: ViewModifier {
    @Binding var active: SchedulePickerTarget?
    @Binding var selection: Date
    let minimumDate: Date?
    var availableWidth: CGFloat = 390

    private var presented: Binding<Bool> {
        Binding(get: { active != nil }, set: { if !$0 { active = nil } })
    }

    func body(content: Content) -> some View {
        content.popover(isPresented: presented, arrowEdge: .bottom) {
            Group {
                if let target = active {
                    Group {
                        if target.editsDate {
                            MemoryCalendarPicker(selection: $selection, isPresented: presented, minimumDate: minimumDate,
                                                 width: min(340, max(280, availableWidth - 32)))
                        } else {
                            MemoryTimePicker(selection: $selection, isPresented: presented)
                        }
                    }
                    .id(target)
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(MemoryTheme.card)
            .accessibilityAction(.escape) { active = nil }
            .accessibilityIdentifier("schedulePanel")
        }
    }
}

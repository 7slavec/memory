import SwiftUI

/// One anchored presentation for the editor on both platforms.
struct MemorySchedulePopover: ViewModifier {
    let target: SchedulePickerTarget
    @Binding var active: SchedulePickerTarget?
    @Binding var selection: Date
    let minimumDate: Date?
    var availableWidth: CGFloat = 390

    private var presented: Binding<Bool> {
        Binding(get: { active == target }, set: { if !$0 && active == target { active = nil } })
    }

    func body(content: Content) -> some View {
        content.popover(isPresented: presented, arrowEdge: .bottom) {
            Group {
                if target.editsDate {
                    MemoryCalendarPicker(selection: $selection, isPresented: presented, minimumDate: minimumDate,
                                         width: min(340, max(280, availableWidth - 32)))
                } else {
                    MemoryTimePicker(selection: $selection, isPresented: presented)
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(MemoryTheme.card)
            .accessibilityAction(.escape) { active = nil }
        }
    }
}

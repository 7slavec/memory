import SwiftUI

struct MemoryTimePicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var hour: String
    @State private var minute: String

    init(selection: Binding<Date>, isPresented: Binding<Bool>) {
        _selection = selection
        _isPresented = isPresented
        let parts = Calendar.current.dateComponents([.hour, .minute], from: selection.wrappedValue)
        _hour = State(initialValue: String(format: "%02d", parts.hour ?? 9))
        _minute = State(initialValue: String(format: "%02d", parts.minute ?? 0))
    }

    var body: some View {
#if os(iOS)
        DatePicker("Время", selection: $selection, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel).labelsHidden()
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .frame(width: 300, height: 210).clipped()
            .padding(8).background(MemoryTheme.card)
#else
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                timeField("Часы", value: $hour)
                Text(":").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                timeField("Минуты", value: $minute)
            }
            .onChange(of: hour) { _, _ in apply() }
            .onChange(of: minute) { _, _ in apply() }
            HStack(spacing: 8) {
                ForEach([9, 12, 18, 21], id: \.self) { value in
                    Button(String(format: "%02d:00", value)) {
                        hour = String(format: "%02d", value); minute = "00"
                        apply(); isPresented = false
                    }
                    .font(.system(size: 14).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(MemoryTheme.raised, in: Capsule())
                    .buttonStyle(.plain)
                }
            }
            if !valid {
                Text("Часы 0–23, минуты 0–59").font(.caption).foregroundStyle(MemoryTheme.danger)
            }
        }
        .padding(20).frame(width: 320).background(MemoryTheme.card)
#endif
    }

    private var valid: Bool {
        guard let h = Int(hour), let m = Int(minute) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    private func timeField(_ name: String, value: Binding<String>) -> some View {
        TextField(name, text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 48, weight: .regular).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 108, height: 92)
            .background(MemoryTheme.raised, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel(name)
            .onSubmit { if valid { apply(); isPresented = false } }
    }

    private func apply() {
        guard valid, let h = Int(hour), let m = Int(minute) else { return }
        selection = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: selection) ?? selection
    }
}

import SwiftUI

#if os(macOS)
struct MemoryTimePicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var typedTime: String
    @State private var hasInvalidTime = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let timeOptions = [
        8 * 60, 9 * 60, 9 * 60 + 30, 10 * 60,
        12 * 60, 13 * 60, 14 * 60, 15 * 60,
        17 * 60, 18 * 60, 19 * 60, 20 * 60,
        21 * 60, 22 * 60, 23 * 60, 23 * 60 + 30
    ]

    init(selection: Binding<Date>, isPresented: Binding<Bool>) {
        _selection = selection
        _isPresented = isPresented
        _typedTime = State(initialValue: Self.timeString(from: selection.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выберите время")
                        .font(.headline)
                    Text("Одним нажатием или введите точное")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Быстрый выбор")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(timeOptions, id: \.self) { minutes in
                        timeButton(minutes)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Точное время")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("ЧЧ:ММ", text: $typedTime)
                        .textFieldStyle(.plain)
                        .font(.body.monospacedDigit())
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(hasInvalidTime ? Color.red : Color.primary.opacity(0.07), lineWidth: 1)
                        }
                        .onSubmit(applyTypedTime)
                        .onChange(of: typedTime) { _, _ in hasInvalidTime = false }

                    Button("Применить") {
                        applyTypedTime()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MemoryTheme.accent)
                }

                if hasInvalidTime {
                    Text("Введите время в формате 09:30")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(MemoryTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 30, y: 16)
    }

    private func timeButton(_ minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes

        return Button {
            apply(minutes: minutes)
            isPresented = false
        } label: {
            Text(Self.timeString(minutes: minutes))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isSelected ? MemoryTheme.accent : Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedMinutes: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selection)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func applyTypedTime() {
        let parts = typedTime
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            hasInvalidTime = true
            return
        }

        apply(minutes: hour * 60 + minute)
        isPresented = false
    }

    private func apply(minutes: Int) {
        let calendar = Calendar.current
        selection = calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: selection
        ) ?? selection
        typedTime = Self.timeString(minutes: minutes)
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return timeString(minutes: (components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func timeString(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
#endif

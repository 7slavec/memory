import SwiftUI

struct AvatarEditor: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: ProfileAvatar
    @State private var isSaving = false
    @State private var error: String?

    init(avatar: ProfileAvatar) { _selection = State(initialValue: avatar) }

    var body: some View {
        VStack(spacing: 16) {
            ProfileAvatarView(avatar: selection, size: 80)
            HStack(spacing: 12) {
                ForEach(ProfileAnimal.allCases) { animal in
                    Button { selection.select(animal) } label: {
                        AnimalFace(animal: animal, fur: selection.fur)
                            .frame(width: 36, height: 36)
                            .frame(width: 64, height: 56)
                            .background(selection.animal == animal ? MemoryTheme.raised : .clear,
                                        in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain).accessibilityLabel(animal.title)
                    .accessibilityAddTraits(selection.animal == animal ? .isSelected : [])
                    .accessibilityHint("Повторное нажатие меняет цвет персонажа")
                    .accessibilityValue(selection.animal == animal ? selection.fur.title : "")
                }
            }
            Text("Повторное нажатие — другой цвет")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { colorOptions }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
                    colorOptions
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(MemoryTheme.danger) }
            Button {
                isSaving = true
                Task {
                    do { try await account.setAvatar(selection); dismiss() }
                    catch { self.error = "Не удалось сохранить аватар. Попробуйте ещё раз." }
                    isSaving = false
                }
            } label: {
                HStack {
                    if isSaving { ProgressView().controlSize(.small) }
                    Text("Готово")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(MemoryActionStyle(prominent: true))
        }
        .disabled(isSaving).padding(16).frame(idealWidth: 320, maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : MemoryMotion.panel, value: selection)
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("avatarEditor")
    }

    private var colorOptions: some View {
        ForEach(ProfileTint.allCases) { tint in
            Button { selection.tint = tint } label: {
                Circle().fill(tint.color).frame(width: 30, height: 30)
                    .overlay {
                        if selection.tint == tint {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        }
                    }
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel(tint.title)
            .accessibilityAddTraits(selection.tint == tint ? .isSelected : [])
        }
    }
}

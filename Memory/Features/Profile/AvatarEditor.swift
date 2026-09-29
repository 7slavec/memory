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
        VStack(spacing: 20) {
            ProfileAvatarView(avatar: selection, size: 96)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            HStack(spacing: 16) {
                ForEach(ProfileAnimal.allCases) { animal in
                    Button { selection.animal = animal } label: {
                        Image(systemName: animal.symbol).font(.system(size: 24))
                            .frame(width: 56, height: 52)
                            .background(selection.animal == animal ? MemoryTheme.raised : .clear,
                                        in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain).accessibilityLabel(animal.title)
                    .accessibilityAddTraits(selection.animal == animal ? .isSelected : [])
                }
            }
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
        .disabled(isSaving).padding(24).frame(idealWidth: 336, maxWidth: 336)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
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

import SwiftUI

/// A small anchored palette; the profile avatar itself is the live preview.
struct AvatarEditor: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selection: ProfileAvatar { account.personalization.avatar }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(ProfileAnimal.allCases) { animal in
                    Button {
                        var updated = selection
                        updated.select(animal)
                        account.selectAvatar(updated)
                    } label: {
                        AnimalFace(animal: animal, fur: selection.fur)
                            .frame(width: 52, height: 52)
                            .frame(width: 68, height: 68)
                            .background(selection.animal == animal ? selection.tint.color.opacity(0.22) : .clear,
                                        in: Circle())
                            .overlay {
                                Circle().strokeBorder(selection.animal == animal ? Color.primary : .clear,
                                                      lineWidth: 1.5)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(animal.title)
                    .accessibilityAddTraits(selection.animal == animal ? .isSelected : [])
                    .accessibilityHint("Повторное нажатие меняет цвет персонажа")
                    .accessibilityValue(selection.animal == animal ? selection.fur.title : "")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { colorOptions }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
                    colorOptions
                }
            }
            if let error = account.avatarSaveError {
                Text(error).font(.caption).foregroundStyle(MemoryTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Повторить синхронизацию", action: account.retryAvatarSave)
                    .buttonStyle(.plain).font(.caption.weight(.medium))
                    .frame(minHeight: 44)
            }
        }
        .padding(12).frame(idealWidth: 288, maxWidth: 288)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : MemoryMotion.panel, value: selection)
        .accessibilityIdentifier("avatarEditor")
    }

    private var colorOptions: some View {
        ForEach(ProfileTint.allCases) { tint in
            Button {
                var updated = selection
                updated.tint = tint
                account.selectAvatar(updated)
            } label: {
                Circle().fill(tint.color).frame(width: 34, height: 34)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle().strokeBorder(selection.tint == tint ? Color.primary : .clear, lineWidth: 1.5)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(tint.title)
            .accessibilityAddTraits(selection.tint == tint ? .isSelected : [])
        }
    }
}

import SwiftUI

struct ProfileAvatarView: View {
    let avatar: ProfileAvatar
    var size: CGFloat = 88
    var body: some View {
        AnimalFace(animal: avatar.animal, fur: avatar.fur)
            .padding(size * 0.17)
            .frame(width: size, height: size)
            .background(avatar.tint.color, in: Circle())
            .accessibilityLabel("\(avatar.animal.title), \(avatar.fur.title), фон \(avatar.tint.title)")
    }
}

extension ProfileTint {
    var color: Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct ProfileSettingsRow<Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: () -> Accessory
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: MemoryDensity.rowIcon, weight: .regular))
                .frame(width: 24).accessibilityHidden(true)
            Text(title).font(.system(size: MemoryDensity.rowTitle, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
        .foregroundStyle(MemoryTheme.accent)
        .padding(.horizontal, MemoryDensity.rowPadding).padding(.vertical, MemoryDensity.rowVerticalPadding)
        .frame(minHeight: MemoryDensity.rowHeight)
        .contentShape(Rectangle())
    }
}

struct ProfileNavigationRow: View {
    @State private var isHovered = false
    let title: String
    let icon: String
    var value: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ProfileSettingsRow(title: title, icon: icon) {
                if let value { Text(value).font(.system(size: 14)).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .background(isHovered ? MemoryTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 18))
        .onHover { isHovered = $0 }
    }
}

struct ProfileThemePicker: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    var body: some View {
        ProfileSettingsRow(title: "Тема", icon: "circle.lefthalf.filled") {
            HStack(spacing: 4) {
                ForEach(AppAppearance.allCases) { option in
                    Button { appearance = option } label: {
                        ZStack {
                            Circle().fill(option == .dark ? Color(white: 0.13) : .white)
                            if option == .system {
                                Rectangle().fill(Color(white: 0.13))
                                    .frame(width: MemoryDensity.themeCircle / 2).offset(x: MemoryDensity.themeCircle / 4)
                            }
                            if appearance == option {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(option == .dark ? .white : .black)
                                    .padding(3).background(option == .system ? Color.white : .clear, in: Circle())
                            }
                        }
                        .frame(width: MemoryDensity.themeCircle, height: MemoryDensity.themeCircle).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.gray.opacity(0.4), lineWidth: 1))
                        .padding(4)
                        .overlay(Circle().strokeBorder(appearance == option ? MemoryTheme.accent : .clear, lineWidth: 1.5))
                        .frame(width: MemoryDensity.themeTarget, height: MemoryDensity.themeTarget)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Тема: \(option.title)")
                    .accessibilityAddTraits(appearance == option ? .isSelected : [])
                    .help(option.title)
                }
            }
        }
    }
}

import CoreText
import SwiftUI

// First rollout is deliberately limited to All Records. The old appearance remains
// available for comparison and a data-independent rollback during this trial.
enum FigmaRecordsRollout {
    static var isEnabled: Bool {
#if DEBUG
        !ProcessInfo.processInfo.arguments.contains("--legacy-records")
#else
        true
#endif
    }
}

enum FigmaRecordsTokens {
    static let pageInset: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let listGap: CGFloat = 8
    static let sectionGap: CGFloat = 24
    static let background = Color("FigmaRecordsBackground")
    static let surface = Color("FigmaRecordsSurface")
    static let primary = Color("FigmaRecordsPrimary")
    static let secondary = Color("FigmaRecordsSecondary")
    static let muted = Color("FigmaRecordsMuted")
    static let reminder = Color("FigmaRecordsReminder")
    static let event = Color("FigmaRecordsEvent")
    static let control = Color("FigmaRecordsControl")

    private static let registeredFonts: Void = {
        for name in ["Inter", "InstrumentSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func font(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registeredFonts
        return .custom("Inter-Regular", size: size, relativeTo: style).weight(weight)
    }

    static var brandFont: Font {
        _ = registeredFonts
        return .custom("InstrumentSans-Regular", size: 32, relativeTo: .title).weight(.bold)
    }
}

struct FigmaIconButton: View {
    let asset: String
    let label: String
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(asset)
                .renderingMode(.template)
                .frame(width: 24, height: 24)
                .foregroundStyle(FigmaRecordsTokens.primary)
                .frame(width: large ? 56 : 44, height: large ? 56 : 44)
                .background(FigmaRecordsTokens.control, in: RoundedRectangle(cornerRadius: large ? 24 : 16))
                .contentShape(RoundedRectangle(cornerRadius: large ? 24 : 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct FigmaRecordsHeading: View {
    let inboxCount: Int
    let onInbox: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Text("Все записи")
                .font(FigmaRecordsTokens.font(24, weight: .medium, relativeTo: .title2))
                .foregroundStyle(FigmaRecordsTokens.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            FigmaIconButton(asset: "FigmaInbox", label: "Входящие", action: onInbox)
                .accessibilityValue("Записей без срока: \(inboxCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FigmaRecordsPrimaryHeader: View {
    let onHome: () -> Void
    let onProfile: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            FigmaIconButton(asset: "FigmaList", label: "На главный экран", large: true, action: onHome)
            Spacer(minLength: 12)
            Text("norka")
                .font(FigmaRecordsTokens.brandFont)
                .foregroundStyle(FigmaRecordsTokens.primary)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            FigmaIconButton(asset: "FigmaProfile", label: "Профиль", large: true, action: onProfile)
        }
        .frame(height: 56)
        .padding(.horizontal, FigmaRecordsTokens.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

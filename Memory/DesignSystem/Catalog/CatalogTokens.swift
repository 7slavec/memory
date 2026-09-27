#if DEBUG
import SwiftUI

// Proposal v2. Deliberately not wired into MemoryTheme or persisted settings.
struct CatalogRGB {
    let hex: UInt32
    var channels: [Double] {
        [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)].map { $0 / 255 }
    }
    var color: Color { Color(red: channels[0], green: channels[1], blue: channels[2]) }
    var luminance: Double {
        zip(channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }, [0.2126, 0.7152, 0.0722])
            .reduce(0) { $0 + $1.0 * $1.1 }
    }
    func contrast(on background: Self) -> Double {
        (max(luminance, background.luminance) + 0.05) / (min(luminance, background.luminance) + 0.05)
    }
}

struct CatalogPalette {
    let dark: Bool
    var background: CatalogRGB { .init(hex: dark ? 0x0E0E12 : 0xF3F3F7) }
    var surface: CatalogRGB { .init(hex: dark ? 0x24242C : 0xFFFFFF) }
    var inset: CatalogRGB { .init(hex: dark ? 0x35353F : 0xE3E3EC) }
    var text: CatalogRGB { .init(hex: dark ? 0xFAFAFC : 0x15151B) }
    var secondary: CatalogRGB { .init(hex: dark ? 0xC0C0CC : 0x60606C) }
    var accent: CatalogRGB { primaryFill }
    var accentSurface: CatalogRGB { primaryFill }
    var primaryFill: CatalogRGB { .init(hex: 0x6438EE) }
    var onPrimary: CatalogRGB { .init(hex: 0xFFFFFF) }
    var event: CatalogRGB { eventSurface }
    var eventSurface: CatalogRGB { .init(hex: 0xFFD12F) }
    var eventEnd: CatalogRGB { .init(hex: 0xFFAE24) }
    var onEvent: CatalogRGB { .init(hex: 0x15151B) }
    var eventSecondary: CatalogRGB { .init(hex: 0x39393F) }
    var danger: CatalogRGB { dangerSurface }
    var dangerSurface: CatalogRGB { .init(hex: 0xD92344) }
    var border: CatalogRGB { .init(hex: dark ? 0x484852 : 0xD3D3E0) }

    func foreground(for tone: CatalogTone) -> CatalogRGB {
        switch tone {
        case .primary, .accent, .danger: onPrimary
        case .event: onEvent
        case .neutral: text
        }
    }
    func fill(for tone: CatalogTone) -> CatalogRGB {
        switch tone {
        case .primary: primaryFill
        case .accent: accentSurface
        case .event: eventSurface
        case .danger: dangerSurface
        case .neutral: inset
        }
    }
}

enum CatalogMetrics {
    static let controlGap: CGFloat = 8
    static let cardInset: CGFloat = 16
    static let pageInset: CGFloat = 24
    static let sectionGap: CGFloat = 32
    static let cardRadius: CGFloat = 20
    static let headerHeight: CGFloat = 72
    static let fieldInset: CGFloat = 8
    static let chipHeight: CGFloat = 32
}

enum CatalogControlSize: String, CaseIterable, Identifiable {
    case small = "S", medium = "M", large = "L"
    var id: Self { self }
    var visual: CGFloat {
        switch self { case .small: 40; case .medium: 48; case .large: 56 }
    }
    var hit: CGFloat { max(44, visual) }
    var symbol: CGFloat {
        switch self { case .small: 18; case .medium: 22; case .large: 26 }
    }
}

enum CatalogType {
    static let largeTitle: Font = .system(.largeTitle, design: .rounded, weight: .medium)
    static let h1: Font = .system(.title, design: .rounded, weight: .medium)
    static let h2: Font = .system(.title3, design: .rounded, weight: .semibold)
    static let body: Font = .system(.body, design: .rounded)
    static let caption: Font = .system(.caption, design: .rounded)
}
#endif

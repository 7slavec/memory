#if DEBUG
import SwiftUI

// Proposal v1. Deliberately not wired into MemoryTheme or persisted settings.
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
    var background: CatalogRGB { .init(hex: dark ? 0x101014 : 0xF5F4F9) }
    var surface: CatalogRGB { .init(hex: dark ? 0x1E1E25 : 0xFFFFFF) }
    var inset: CatalogRGB { .init(hex: dark ? 0x2B2B35 : 0xECEBF3) }
    var text: CatalogRGB { .init(hex: dark ? 0xF7F6FC : 0x1B1925) }
    var secondary: CatalogRGB { .init(hex: dark ? 0xB7B3C7 : 0x646071) }
    var accent: CatalogRGB { .init(hex: dark ? 0xB9ACFF : 0x5941C8) }
    var accentSurface: CatalogRGB { .init(hex: dark ? 0x302747 : 0xEEE9FF) }
    var primaryFill: CatalogRGB { .init(hex: 0x6149D8) }
    var onPrimary: CatalogRGB { .init(hex: 0xFFFFFF) }
    var event: CatalogRGB { .init(hex: dark ? 0xEFBB70 : 0x805015) }
    var eventSurface: CatalogRGB { .init(hex: dark ? 0x30261D : 0xFFF2DE) }
    var danger: CatalogRGB { .init(hex: dark ? 0xFFABB2 : 0xB3263C) }
    var dangerSurface: CatalogRGB { .init(hex: dark ? 0x3B232B : 0xFCE9ED) }
    var border: CatalogRGB { .init(hex: dark ? 0x41404E : 0xD8D4E3) }
}

enum CatalogMetrics {
    static let controlGap: CGFloat = 8
    static let cardInset: CGFloat = 16
    static let pageInset: CGFloat = 24
    static let sectionGap: CGFloat = 32
    static let cardRadius: CGFloat = 20
    static let headerHeight: CGFloat = 72
}

enum CatalogControlSize: String, CaseIterable, Identifiable {
    case small = "S", medium = "M", large = "L"
    var id: Self { self }
    var visual: CGFloat {
        switch self { case .small: 32; case .medium: 44; case .large: 52 }
    }
    var hit: CGFloat { max(44, visual) }
}

enum CatalogType {
    static let largeTitle: Font = .system(.largeTitle, design: .rounded, weight: .medium)
    static let h1: Font = .system(.title, design: .rounded, weight: .medium)
    static let h2: Font = .system(.title3, design: .rounded, weight: .semibold)
    static let body: Font = .system(.body, design: .rounded)
    static let caption: Font = .system(.caption, design: .rounded)
}
#endif

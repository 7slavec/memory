import SwiftUI

/// Platform density for records and account screens only. Search, capture and
/// empty states deliberately keep their existing metrics.
enum MemoryDensity {
#if os(macOS)
    static let recordTitle: CGFloat = 15
    static let recordTime: CGFloat = 24
    static let recordBody: CGFloat = 13
    static let recordPadding: CGFloat = 14
    static let recordCopyGap: CGFloat = 6
    static let recordRadius: CGFloat = 16
    static let recordGap: CGFloat = 8
    static let recordLinkTarget: CGFloat = 32
    static let sectionTitle: CGFloat = 16
    static let profileWidth: CGFloat = 480
    static let profileGap: CGFloat = 12
    static let profileTop: CGFloat = 16
    static let avatar: CGFloat = 72
    static let profileTitle: CGFloat = 18
    static let rowTitle: CGFloat = 14
    static let rowIcon: CGFloat = 16
    static let rowPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 6
    static let rowHeight: CGFloat = 44
    static let themeCircle: CGFloat = 24
    static let themeTarget: CGFloat = 32
    static let profileControl: CGFloat = 32
    static let compactActions = true
#else
    static let recordTitle: CGFloat = 18
    static let recordTime: CGFloat = 30
    static let recordBody: CGFloat = 14
    static let recordPadding: CGFloat = 18
    static let recordCopyGap: CGFloat = 8
    static let recordRadius = MemoryTheme.cardRadius
    static let recordGap: CGFloat = 12
    static let recordLinkTarget: CGFloat = 44
    static let sectionTitle: CGFloat = 20
    static let profileWidth: CGFloat = 560
    static let profileGap: CGFloat = 16
    static let profileTop: CGFloat = 24
    static let avatar: CGFloat = 96
    static let profileTitle: CGFloat = 22
    static let rowTitle: CGFloat = 16
    static let rowIcon: CGFloat = 18
    static let rowPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 8
    static let rowHeight: CGFloat = 60
    static let themeCircle: CGFloat = 34
    static let themeTarget: CGFloat = 44
    static let profileControl: CGFloat = 44
    static let compactActions = false
#endif
}

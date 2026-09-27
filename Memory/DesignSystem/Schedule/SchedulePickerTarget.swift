import Foundation

enum SchedulePickerTarget: String, Identifiable {
    case startDate
    case startTime
    case endDate
    case endTime

    var id: String { rawValue }
    var editsEnd: Bool { self == .endDate || self == .endTime }
    var editsDate: Bool { self == .startDate || self == .endDate }
}

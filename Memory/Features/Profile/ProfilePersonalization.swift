import Foundation

enum ProfileAnimal: String, CaseIterable, Codable, Identifiable {
    case cat, dog, rabbit
    var id: Self { self }
    var title: String { switch self { case .cat: "Кот"; case .dog: "Пёс"; case .rabbit: "Заяц" } }
    var symbol: String { switch self { case .cat: "cat.fill"; case .dog: "dog.fill"; case .rabbit: "hare.fill" } }
}

enum ProfileTint: String, CaseIterable, Codable, Identifiable {
    case citrus, mint, sky, lilac, peach, sand
    var id: Self { self }
    var title: String {
        switch self {
        case .citrus: "Цитрус"; case .mint: "Мята"; case .sky: "Небо"
        case .lilac: "Сирень"; case .peach: "Персик"; case .sand: "Песок"
        }
    }
    var hex: UInt32 {
        switch self {
        case .citrus: 0xE7F363; case .mint: 0x9EDBB9; case .sky: 0xA6CDF4
        case .lilac: 0xC8B8EE; case .peach: 0xF5B397; case .sand: 0xE8D5A7
        }
    }
}

struct ProfileAvatar: Codable, Equatable {
    var animal: ProfileAnimal = .cat
    var tint: ProfileTint = .citrus
    static let standard = ProfileAvatar()

    init(animal: ProfileAnimal = .cat, tint: ProfileTint = .citrus) {
        self.animal = animal
        self.tint = tint
    }

    init(animal: String?, tint: String?) {
        self.animal = animal.flatMap(ProfileAnimal.init(rawValue:)) ?? .cat
        self.tint = tint.flatMap(ProfileTint.init(rawValue:)) ?? .citrus
    }
}

struct ProfilePersonalization: Codable, Equatable {
    var avatar = ProfileAvatar.standard
    var eventReminderMinutes: Int?

    func reminderMinutes(for kind: EntryKind, fallback: Int) -> Int {
        guard kind == .event, let value = eventReminderMinutes,
              ReminderLeadTime(rawValue: value) != nil else { return fallback }
        return value
    }
}

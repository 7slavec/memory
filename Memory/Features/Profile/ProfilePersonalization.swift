import Foundation

enum ProfileAnimal: String, CaseIterable, Codable, Identifiable {
    case cat, dog, rabbit
    var id: Self { self }
    var title: String { switch self { case .cat: "Кот"; case .dog: "Пёс"; case .rabbit: "Заяц" } }
}

enum ProfileFur: String, CaseIterable, Codable {
    case ink, cocoa, cream
    var title: String { switch self { case .ink: "Графит"; case .cocoa: "Какао"; case .cream: "Кремовый" } }
    var hex: UInt32 { switch self { case .ink: 0x242A27; case .cocoa: 0x704735; case .cream: 0xFFF6DF } }
    var next: Self { switch self { case .ink: .cocoa; case .cocoa: .cream; case .cream: .ink } }
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
    var fur: ProfileFur = .ink
    static let standard = ProfileAvatar()

    init(animal: ProfileAnimal = .cat, tint: ProfileTint = .citrus, fur: ProfileFur = .ink) {
        self.animal = animal
        self.tint = tint
        self.fur = fur
    }

    init(animal: String?, tint: String?, fur: String? = nil) {
        self.animal = animal.flatMap(ProfileAnimal.init(rawValue:)) ?? .cat
        self.tint = tint.flatMap(ProfileTint.init(rawValue:)) ?? .citrus
        self.fur = fur.flatMap(ProfileFur.init(rawValue:)) ?? .ink
    }

    mutating func select(_ animal: ProfileAnimal) {
        if self.animal == animal { fur = fur.next }
        else { self.animal = animal }
    }

    private enum CodingKeys: String, CodingKey { case animal, tint, fur }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(animal: try values.decodeIfPresent(String.self, forKey: .animal),
                  tint: try values.decodeIfPresent(String.self, forKey: .tint),
                  fur: try values.decodeIfPresent(String.self, forKey: .fur))
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

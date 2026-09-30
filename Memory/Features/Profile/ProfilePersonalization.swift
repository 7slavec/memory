import Foundation

enum ProfileAnimal: String, CaseIterable, Codable, Identifiable {
    case cat, dog, rabbit
    var id: Self { self }
    var title: String { switch self { case .cat: "Кот"; case .dog: "Пёс"; case .rabbit: "Заяц" } }
}

enum ProfileFur: String, CaseIterable, Codable {
    case ink, cobalt, cream
    var title: String { switch self { case .ink: "Графит"; case .cobalt: "Кобальт"; case .cream: "Кремовый" } }
    var hex: UInt32 { switch self { case .ink: 0x242A27; case .cobalt: 0x2855D9; case .cream: 0xFFF6DF } }
    var next: Self { switch self { case .ink: .cobalt; case .cobalt: .cream; case .cream: .ink } }
}

enum ProfileTint: String, CaseIterable, Codable, Identifiable {
    case citrus, mint, sky, lilac, peach, sand
    var id: Self { self }
    var title: String {
        switch self {
        case .citrus: "Цитрус"; case .mint: "Мята"; case .sky: "Небо"
        case .lilac: "Сирень"; case .peach: "Персик"; case .sand: "Солнечный"
        }
    }
    var hex: UInt32 {
        switch self {
        case .citrus: 0xE7F363; case .mint: 0x62DFAD; case .sky: 0x79C7FF
        case .lilac: 0xB8A0FF; case .peach: 0xFFAD8E; case .sand: 0xFFD86B
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
        // Upgrade the retired brown without losing the saved animal or background.
        self.fur = fur == "cocoa" ? .cobalt : fur.flatMap(ProfileFur.init(rawValue:)) ?? .ink
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

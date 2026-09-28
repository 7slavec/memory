import Foundation

/// Evaluates the saved local corpus only, never implies cloud-model accuracy.
struct VoiceLabStatistics {
    let total: Int
    let exact: Int
    let titles: Int
    let details: Int
    let dates: Int

    init(examples: [VoiceLabExample]) {
        let evaluations = examples.map { $0.evaluation(using: LocalVoiceIntentInterpreter()) }
        total = evaluations.count
        titles = evaluations.filter(\.titleMatches).count
        details = evaluations.filter(\.detailsMatch).count
        dates = evaluations.filter(\.dateMatches).count
        exact = evaluations.filter { $0.titleMatches && $0.detailsMatch && $0.dateMatches }.count
    }

    func percentage(_ matches: Int) -> Int? {
        guard total > 0 else { return nil }
        return Int((Double(matches) / Double(total) * 100).rounded())
    }
}

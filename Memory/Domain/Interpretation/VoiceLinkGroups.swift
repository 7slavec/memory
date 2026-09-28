import Foundation

/// Optional semantic metadata must never make otherwise valid records unusable.
struct VoiceLinkGroups: Decodable {
    struct Proposal: Decodable {
        let members: [Int]
        let confidence: String
        let evidence: String
    }

    let proposals: [Proposal]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        proposals = (try? container.decode([Proposal].self)) ?? []
    }

    func membership(entryCount: Int, transcript: String) -> [Int: Int] {
        guard (2...6).contains(entryCount), proposals.count <= 3 else { return [:] }
        let speech = Self.normalized(transcript)
        var result: [Int: Int] = [:]
        for (group, proposal) in proposals.enumerated() {
            let members = Set(proposal.members)
            let evidence = Self.normalized(proposal.evidence)
            guard proposal.confidence == "high", members.count >= 2,
                  members.count == proposal.members.count,
                  members.allSatisfy({ (0..<entryCount).contains($0) }),
                  evidence.count >= 8, speech.contains(evidence) else { continue }
            // Conflicting groups are ambiguous: do not guess which one to merge.
            guard members.allSatisfy({ result[$0] == nil }) else { return [:] }
            for member in members { result[member] = group }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

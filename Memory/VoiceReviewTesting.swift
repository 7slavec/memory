import Foundation

// A launch-only fixture exercises the real page composition without speech,
// account access, notifications, or writes to the user's records.
enum VoiceReviewTesting {
    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-voice-review") || isRecordsEnabled
#else
        false
#endif
    }

    static var isRecordsEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-records-design")
#else
        false
#endif
    }

#if DEBUG
    @MainActor static func session() -> VoiceBatchReviewSession {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let values: [(String, EntryKind, Date)] = [
            ("Собрание", .event, start),
            ("Сходить за покупками", .reminder, start.addingTimeInterval(3_600))
        ]
        let entries = values.map { title, kind, date in
            let draft = ReminderDraft(
                transcript: title, title: title, details: nil, dueDate: date,
                reminderOffsets: [], confidence: .high, ambiguities: []
            )
            var entry = VoiceReviewEntry(VoiceCaptureEntry(
                sourceText: title, draft: draft, kind: kind, endDate: nil
            ))
            entry.persistedItemID = UUID()
            return entry
        }
        return VoiceBatchReviewSession(batch: VoiceBatchReview(referenceDate: .now, entries: entries))
    }
#endif
}

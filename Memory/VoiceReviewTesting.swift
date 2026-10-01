import Foundation
import SwiftData

// A launch-only fixture exercises the real page composition without speech,
// account access, notifications, or writes to the user's records.
enum VoiceReviewTesting {
    static var isUnitTestHost: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !isEnabled
#else
        false
#endif
    }

    static var usesIsolatedStorage: Bool { isEnabled || isUnitTestHost }

    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-voice-review") || isLinksEnabled
            || isProfileEnabled || isQuickCaptureEnabled || isActiveEventEnabled
#else
        false
#endif
    }

    static var isQuickCaptureEnabled: Bool {
#if DEBUG && os(macOS)
        ProcessInfo.processInfo.arguments.contains("--uitest-quick-capture")
#else
        false
#endif
    }

    static var isLinksEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-links")
#else
        false
#endif
    }

    static var isProfileEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-profile")
#else
        false
#endif
    }

    static var isActiveEventEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-active-event")
#else
        false
#endif
    }

#if DEBUG
    @MainActor static func session(context: ModelContext? = nil) -> VoiceBatchReviewSession {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let values: [(String, EntryKind, Date)] = [
            ("Собрание", .event, start),
            ("Сходить за покупками", .reminder, start.addingTimeInterval(3_600))
        ]
        var entries = values.map { title, kind, date in
            let draft = ReminderDraft(
                transcript: title, title: title, details: nil, dueDate: date,
                reminderOffsets: [], confidence: .high, ambiguities: []
            )
            var entry = VoiceReviewEntry(VoiceCaptureEntry(
                sourceText: title, draft: draft, kind: kind, endDate: nil, linkGroup: 0
            ))
            entry.persistedItemID = UUID()
            return entry
        }
        if let context {
            for index in entries.indices { entries[index].persistedItemID = nil }
            if let items = try? VoiceBatchPersistence.create(entries, ownerID: nil, context: context) {
                for index in entries.indices { entries[index].persistedItemID = items[index].id }
            }
        }
        return VoiceBatchReviewSession(batch: VoiceBatchReview(referenceDate: .now, entries: entries))
    }
#endif
}

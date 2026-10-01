#if os(macOS)
import AppKit
import Carbon
import Testing
import SwiftData
@testable import Memory

@MainActor
@Suite(.serialized)
struct MacQuickCaptureTests {
    @Test func widgetGroupWaitsForConfirmationAndUnlinkKeepsDrafts() throws {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let source = VoiceReviewTesting.session()
        var entries = source.entries
        for i in entries.indices { entries[i].persistedItemID = nil }
        let session = VoiceBatchReviewSession(batch: VoiceBatchReview(referenceDate: .now, entries: entries))
        #expect(session.hasDraftLinks)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        let ids = session.entries.map(\.id)
        session.unlinkDrafts()
        #expect(!session.hasDraftLinks)
        #expect(session.entries.map(\.id) == ids)
        #expect(session.canSave)
        let saved = try VoiceBatchPersistence.create(session.entries, ownerID: nil, context: context)
        #expect(saved.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<RecordLink>()) == 0)
    }

    @Test func transcriptGrowthIsBoundedAndStableWithinOneLine() {
        #expect(MemoryWidgetMetrics.transcriptHeight(0) == 20)
        #expect(MemoryWidgetMetrics.transcriptHeight(38.3) == 39)
        #expect(MemoryWidgetMetrics.transcriptHeight(140) == 140)
        #expect(MemoryWidgetMetrics.transcriptHeight(1200) == MemoryWidgetMetrics.transcriptLimit)
    }
    @Test func receiptOnlyAutoHidesWhenSafe() {
        let ready = MacCaptureAutoHidePolicy(count: 1, interacting: false, hasError: false, isVisible: true, usesVoiceOver: false)
        #expect(ready.shouldHide)
        var policy = ready; policy.count = 2; #expect(!policy.shouldHide)
        policy = ready; policy.count = 0; #expect(!policy.shouldHide)
        policy = ready; policy.interacting = true; #expect(!policy.shouldHide)
        policy = ready; policy.hasError = true; #expect(!policy.shouldHide)
        policy = ready; policy.isVisible = false; #expect(!policy.shouldHide)
        policy = ready; policy.usesVoiceOver = true; #expect(!policy.shouldHide)
    }

    @Test func allNineAnchorsPreserveTheirEdgeWhenWidgetChangesSize() {
        #expect(MacCapturePosition.allCases.count == 9)
        let area = NSRect(x: -1200, y: -900, width: 1200, height: 900)
        for position in MacCapturePosition.allCases {
            let small = NSSize(width: 264, height: 264), large = NSSize(width: 440, height: 540)
            let a = NSRect(origin: position.origin(size: small, in: area), size: small)
            let b = NSRect(origin: position.origin(size: large, in: area), size: large)
            #expect(area.contains(a) && area.contains(b))
            if position.column == 0 { #expect(a.minX == b.minX) }
            if position.column == 1 { #expect(a.midX == b.midX) }
            if position.column == 2 { #expect(a.maxX == b.maxX) }
            if position.row == 0 { #expect(a.maxY == b.maxY) }
            if position.row == 1 { #expect(a.midY == b.midY) }
            if position.row == 2 { #expect(a.minY == b.minY) }
        }
    }
    @Test func cancelWhilePermissionIsPendingNeverStartsMicrophone() async throws {
        var continuation: CheckedContinuation<Bool, Never>?
        var microphoneRequests = 0
        let voice = VoiceInputController(speechAuthorization: {
            await withCheckedContinuation { continuation = $0 }
        }, microphoneAuthorization: { microphoneRequests += 1; return false })
        let task = Task { await voice.toggle(currentText: "Черновик") }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        voice.stop()
        pending.resume(returning: true)
        await task.value
        #expect(microphoneRequests == 0)
        #expect(!voice.isListening)
        #expect(voice.errorMessage == nil)
    }

    @Test func repeatedStartAndSecondWindowCannotOpenAnotherPermissionRequest() async throws {
        var continuation: CheckedContinuation<Bool, Never>?
        var speechRequests = 0
        let voice = VoiceInputController(speechAuthorization: {
            speechRequests += 1
            return await withCheckedContinuation { continuation = $0 }
        }, microphoneAuthorization: { false })
        let task = Task { await voice.toggle(currentText: "") }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        await voice.toggle(currentText: "")
        let other = VoiceInputController(speechAuthorization: { speechRequests += 1; return false })
        await other.toggle(currentText: "")
        #expect(speechRequests == 1)
        #expect(other.errorMessage != nil)
        voice.stop()
        pending.resume(returning: false)
        await task.value
        #expect(!other.isListening && !voice.isListening)
    }

    @Test func defaultsAreDistinctAndRequireDeliberateModifiers() {
        let text = MacCaptureAction.text.defaultShortcut
        let voice = MacCaptureAction.voice.defaultShortcut
        #expect(text.isValid && voice.isValid)
        #expect(!text.matches(voice))
        #expect(text.label == "⌃⌥N")
        #expect(voice.label == "⌃⌥Пробел")
        #expect(!MacCaptureShortcut(keyCode: 45, modifiers: 0, key: "N").isValid)
        #expect(!MacCaptureShortcut(keyCode: 45, modifiers: UInt32(cmdKey), key: "N").isValid)
        #expect(!MacCaptureShortcut(keyCode: 53, modifiers: text.modifiers, key: "Escape").isValid)
    }

    @Test func samePhysicalChordCannotBeAssignedTwiceAndFailurePreservesOldValue() throws {
        let defaults = try #require(UserDefaults(suiteName: "norka.capture.test.\(UUID())"))
        let shortcuts = MacCaptureShortcuts(defaults: defaults)
        let original = shortcuts.shortcuts[.text]
        let duplicate = MacCaptureAction.voice.defaultShortcut
        #expect(!shortcuts.assign(duplicate, to: .text))
        #expect(shortcuts.shortcuts[.text] == original)
        #expect(shortcuts.errors[.text] != nil)
        let translated = MacCaptureShortcut(keyCode: duplicate.keyCode, modifiers: duplicate.modifiers, key: "Space")
        #expect(translated.matches(duplicate))
    }

    @Test func disablingPersistsWithoutRegisteringAnyHotkeys() throws {
        let name = "norka.capture.test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let shortcuts = MacCaptureShortcuts(defaults: defaults)
        #expect(shortcuts.assign(nil, to: .voice))
        #expect(MacCaptureShortcuts(defaults: defaults).shortcuts[.voice] == nil)
        #expect(shortcuts.shortcuts[.text] != nil)
    }

    @Test func positionsRespectVisibleAreaIncludingNegativeMonitorCoordinates() {
        let screen = NSRect(x: -1440, y: 40, width: 1440, height: 860)
        let size = NSSize(width: 460, height: 220)
        for position in MacCapturePosition.allCases {
            #expect(screen.contains(NSRect(origin: position.origin(size: size, in: screen), size: size)))
        }
        #expect(MacCapturePosition.topRight.origin(size: size, in: screen) == NSPoint(x: -480, y: 660))
        let full = NSSize(width: screen.width, height: screen.height)
        #expect(MacCapturePosition.topRight.origin(size: full, in: screen) == screen.origin)
    }
}
#endif

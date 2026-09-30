#if os(macOS)
import AppKit
import Carbon
import Testing
@testable import Memory

@MainActor
@Suite(.serialized)
struct MacQuickCaptureTests {
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

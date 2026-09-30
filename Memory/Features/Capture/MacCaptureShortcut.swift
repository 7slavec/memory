#if os(macOS)
import AppKit
import Carbon
import Combine

enum MacCaptureAction: UInt32, CaseIterable, Identifiable {
    case text = 1, voice = 2
    var id: Self { self }
    var title: String { self == .text ? "Ввести текст" : "Сразу диктовать" }
    var icon: String { self == .text ? "keyboard" : "mic" }
    var defaultShortcut: MacCaptureShortcut {
        .init(keyCode: self == .text ? 45 : 49,
              modifiers: UInt32(controlKey | optionKey), key: self == .text ? "N" : "Пробел")
    }
}

struct MacCaptureShortcut: Codable, Equatable {
    static let keyNames: [UInt32: String] = [0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5",
        25:"9", 26:"7", 28:"8", 29:"0", 31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Пробел"]
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String
    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }
    func matches(_ other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    var isValid: Bool {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return modifiers & ~supported == 0 && modifiers.nonzeroBitCount >= 2
            && modifiers & UInt32(controlKey | optionKey) != 0
            && Self.keyNames[keyCode] != nil && !key.isEmpty
    }
    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey),
                               (.shift, shiftKey), (.command, cmdKey)] where event.modifierFlags.contains(flag) {
            flags |= UInt32(carbon)
        }
        modifiers = flags
        key = Self.keyNames[keyCode] ?? ""
    }
}

/// Registers only two explicit system hotkeys. No global keystroke monitor or Accessibility access.
@MainActor
final class MacCaptureShortcuts: ObservableObject {
    static let shared = MacCaptureShortcuts()
    @Published private(set) var shortcuts: [MacCaptureAction: MacCaptureShortcut] = [:]
    @Published private(set) var errors: [MacCaptureAction: String] = [:]
    var onInvoke: ((MacCaptureAction) -> Void)?
    private var refs: [MacCaptureAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var started = false
    private var recording = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in MacCaptureAction.allCases {
            let key = "mac.capture.shortcut.\(action.rawValue)"
            if defaults.bool(forKey: key + ".disabled") { continue }
            shortcuts[action] = defaults.data(forKey: key).flatMap {
                try? JSONDecoder().decode(MacCaptureShortcut.self, from: $0)
            } ?? action.defaultShortcut
        }
    }

    func start() {
        guard !started else { return }
        started = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x4E4F524B,
                  let action = MacCaptureAction(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<MacCaptureShortcuts>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in if !owner.recording { owner.onInvoke?(action) } }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else {
            for action in MacCaptureAction.allCases { errors[action] = "Не удалось подключить горячие клавиши." }
            return
        }
        for action in MacCaptureAction.allCases {
            if let shortcut = shortcuts[action] { _ = assign(shortcut, to: action) }
        }
    }

    func setRecording(_ value: Bool) {
        guard recording != value else { return }
        recording = value
        if value {
            refs.values.forEach { UnregisterEventHotKey($0) }
            refs.removeAll()
        } else if started {
            for action in MacCaptureAction.allCases {
                if let shortcut = shortcuts[action] { _ = assign(shortcut, to: action) }
            }
        }
    }

    @discardableResult
    func assign(_ shortcut: MacCaptureShortcut?, to action: MacCaptureAction) -> Bool {
        if let shortcut {
            guard shortcut.isValid else {
                errors[action] = "Используйте два модификатора (например ⌃⌥) и букву, цифру или пробел."
                return false
            }
            guard !shortcuts.contains(where: { $0.key != action && shortcut.matches($0.value) }) else {
                errors[action] = "Это сочетание уже назначено второму действию."
                return false
            }
            var systemKeys: Unmanaged<CFArray>?
            if CopySymbolicHotKeys(&systemKeys) == noErr,
               let keys = systemKeys?.takeRetainedValue() as? [[String: Any]],
               keys.contains(where: {
                   ($0[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true
                       && ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode
                       && ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.modifiers
               }) {
                errors[action] = "Это системное сочетание macOS. Выберите другое."
                return false
            }
            if refs[action] != nil, shortcuts[action]?.matches(shortcut) == true {
                errors[action] = nil
                return true
            }
            // Register the replacement first. A conflict must not remove the working shortcut.
            var newRef: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                            EventHotKeyID(signature: 0x4E4F524B, id: action.rawValue),
                                            GetApplicationEventTarget(), 0, &newRef)
            guard status == noErr, let newRef else {
                errors[action] = "Сочетание занято или недоступно. Выберите другое."
                return false
            }
            if let old = refs[action] { UnregisterEventHotKey(old) }
            refs[action] = newRef
        } else if let old = refs.removeValue(forKey: action) { UnregisterEventHotKey(old) }
        shortcuts[action] = shortcut
        errors[action] = nil
        let key = "mac.capture.shortcut.\(action.rawValue)"
        defaults.set(shortcut == nil, forKey: key + ".disabled")
        if let shortcut { defaults.set(try? JSONEncoder().encode(shortcut), forKey: key) }
        else { defaults.removeObject(forKey: key) }
        return true
    }
}
#endif

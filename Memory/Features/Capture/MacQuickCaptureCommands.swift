#if os(macOS)
import SwiftUI

struct MacQuickCaptureCommands: Commands {
    @ObservedObject private var shortcuts = MacCaptureShortcuts.shared
    var body: some Commands {
        CommandMenu("Быстрый ввод") {
            ForEach(MacCaptureAction.allCases) { action in
                Button(action.title + (shortcuts.shortcuts[action].map { "    " + $0.label } ?? "")) {
                    MacQuickCaptureController.shared.show(action)
                }
            }
        }
    }
}
#endif

import Foundation

/// A command, not a view identity: bringing a retained composer back never resets its draft.
struct CaptureActivation: Equatable {
    enum Mode { case text, voice, suspend }
    let id = UUID()
    let mode: Mode
}

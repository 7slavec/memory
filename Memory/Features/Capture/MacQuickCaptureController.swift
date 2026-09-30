#if os(macOS)
import AppKit
import SwiftUI
import SwiftData
import Combine

enum MacCapturePosition: String, CaseIterable, Identifiable {
    case topRight, topLeft, center
    var id: Self { self }
    var title: String {
        switch self { case .topRight: "Справа сверху"; case .topLeft: "Слева сверху"; case .center: "По центру" }
    }
    func origin(size: NSSize, in area: NSRect) -> NSPoint {
        let x = self == .topRight ? area.maxX - size.width - 20 : self == .topLeft ? area.minX + 20 : area.midX - size.width / 2
        let y = self == .center ? area.midY - size.height / 2 : area.maxY - size.height - 20
        return NSPoint(x: max(area.minX, min(x, area.maxX - size.width)),
                       y: max(area.minY, min(y, area.maxY - size.height)))
    }
}

private final class CapturePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class MacQuickCaptureController: ObservableObject {
    static let shared = MacQuickCaptureController()
    @Published private(set) var activation: CaptureActivation?
    @Published private(set) var editorHeight: CGFloat = 540
    private var panel: CapturePanel?
    private var container: ModelContainer?
    private var account: AccountSyncController?
    private var previousApp: NSRunningApplication?
    private var screen: NSScreen?
    private var presentationID = UUID()

    func configure(container: ModelContainer, account: AccountSyncController) {
        guard self.container == nil, !VoiceReviewTesting.isEnabled, !DesignCatalogMode.isEnabled,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        self.container = container
        self.account = account
        MacCaptureShortcuts.shared.onInvoke = { [weak self] in self?.show($0) }
        MacCaptureShortcuts.shared.start()
    }

    func show(_ action: MacCaptureAction) {
        guard let container, let account else { return }
        guard UserDefaults.standard.bool(forKey: "hasCompletedInitialAccessChoice") else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if panel == nil {
            let window = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Быстрый ввод Norka"
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.onEscape = { [weak self] in self?.hide() }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            window.contentView = NSHostingView(rootView:
                MacQuickCaptureView(controller: self)
                    .environmentObject(account).modelContext(context))
            panel = window
        }
        guard let panel else { return }
        presentationID = UUID()
        if !panel.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
            screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
            editorHeight = min(540, max(160, (screen?.visibleFrame.height ?? 800) - 150))
            resize(height: panel.frame.height)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MemoryMotion.panelDuration
                panel.animator().alphaValue = 1
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MemoryMotion.panelDuration
                panel.animator().alphaValue = 1
            }
        }
        // Focus/voice command follows hosting-view attachment, not an arbitrary sleep.
        let id = presentationID
        Task { @MainActor in
            await Task.yield()
            guard self.presentationID == id, panel.isVisible else { return }
            self.activation = CaptureActivation(mode: action == .voice ? .voice : .text)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        activation = CaptureActivation(mode: .suspend)
        presentationID = UUID()
        let id = presentationID
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MemoryMotion.panelDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [self] in
            Task { @MainActor in
                guard self.presentationID == id else { return }
                panel.orderOut(nil)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier,
                   let previous = self.previousApp, previous.processIdentifier != NSRunningApplication.current.processIdentifier {
                    previous.activate()
                }
            }
        })
    }

    func resize(height: CGFloat) {
        guard let panel, let screen = screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = NSSize(width: min(460, area.width - 24), height: min(max(150, height), area.height - 40))
        let position = MacCapturePosition(rawValue: UserDefaults.standard.string(forKey: "mac.capture.position") ?? "") ?? .topRight
        panel.setFrame(NSRect(origin: position.origin(size: size, in: area), size: size), display: true)
    }

    func resetForAccountChange() {
        activation = CaptureActivation(mode: .suspend)
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        presentationID = UUID()
    }
}
#endif

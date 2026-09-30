#if os(macOS)
import SwiftUI
import AppKit

struct MacQuickCaptureSettings: View {
    @ObservedObject private var shortcuts = MacCaptureShortcuts.shared
    @AppStorage("mac.capture.position") private var position = MacCapturePosition.topRight
    @State private var recording: MacCaptureAction?

    var body: some View {
        VStack(spacing: MemoryDensity.profileGap) {
            VStack(spacing: 0) {
                ForEach(MacCaptureAction.allCases) { action in
                    ProfileSettingsRow(title: action.title, icon: action.icon) {
                        HStack(spacing: 6) {
                            if recording == action {
                                ShortcutRecorder(onKey: { shortcut in
                                    if shortcuts.assign(shortcut, to: action) { recording = nil }
                                }, onCancel: { recording = nil })
                                .frame(width: 150, height: 32)
                            } else {
                                Button(shortcuts.shortcuts[action]?.label ?? "Назначить") { recording = action }
                                    .buttonStyle(MemoryActionStyle(compact: true))
                                    .accessibilityLabel("Сочетание: \(action.title)")
                            }
                            if shortcuts.shortcuts[action] != nil {
                                Button { _ = shortcuts.assign(nil, to: action); recording = nil } label: {
                                    Image(systemName: "xmark").frame(width: 32, height: 32)
                                }.buttonStyle(.plain).accessibilityLabel("Отключить: \(action.title)")
                            }
                        }
                    }
                    if let error = shortcuts.errors[action] {
                        Text(error).font(.system(size: 12)).foregroundStyle(MemoryTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
                    }
                }
            }.memoryCard()
            ProfileSettingsRow(title: "Положение окна", icon: "macwindow") {
                MacCapturePositionPicker(selection: $position)
            }.memoryCard()
            Text("Сочетания работают, пока Norka запущена — даже если основное окно закрыто. Escape скрывает окно и оставляет черновик до выхода из приложения. Для диктовки нужен доступ к микрофону и распознаванию речи.")
                .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Button { recording = nil; MacQuickCaptureController.shared.show(.text) } label: {
                Label("Попробовать быстрый ввод", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(MemoryActionStyle(prominent: true, compact: true))
        }
        .onChange(of: recording) { _, value in shortcuts.setRecording(value != nil) }
        .onDisappear { recording = nil; shortcuts.setRecording(false) }
    }
}

private struct MacCapturePositionPicker: View {
    @Binding var selection: MacCapturePosition
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 5), count: 3), spacing: 5) {
            ForEach(MacCapturePosition.allCases) { position in
                Button { selection = position } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selection == position ? MemoryTheme.accent : MemoryTheme.accent.opacity(0.2))
                        .frame(width: 12, height: 9)
                        .frame(width: 32, height: 26)
                        .background(selection == position ? MemoryTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).help(position.title).accessibilityLabel(position.title)
                .accessibilityAddTraits(selection == position ? .isSelected : [])
            }
        }
        .padding(8).background(MemoryTheme.background, in: RoundedRectangle(cornerRadius: 14))
        .fixedSize().padding(.vertical, 6)
        .accessibilityElement(children: .contain).accessibilityLabel("Положение виджета")
    }
}

/// Receives only keys directed at this focused control. No event monitoring outside settings.
private struct ShortcutRecorder: NSViewRepresentable {
    let onKey: (MacCaptureShortcut) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onKey = onKey; view.onCancel = onCancel
        return view
    }
    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.onKey = onKey; view.onCancel = onCancel
    }
}

private final class ShortcutRecorderView: NSView {
    var onKey: ((MacCaptureShortcut) -> Void)?
    var onCancel: (() -> Void)?
    private let label = NSTextField(labelWithString: "Нажмите сочетание…")
    private var windowObserver: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        addSubview(label)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Нажмите сочетание. Escape — отмена.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: bounds.width, height: 16)
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        guard let window else { return }
        window.makeFirstResponder(self)
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCancel?() }
            }
    }
    deinit { if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) } }
    override func resignFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.onCancel?() }
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { onCancel?() }
        else { onKey?(MacCaptureShortcut(event: event)) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }
}
#endif

// CrannyAppShell/Input/KeyboardRouter.swift — keys while one panel is key (ARCHITECTURE.md §4.10, DESIGN.md §6.5,
// §7.5, §16). Local NSEvent monitors only (the panel receives keys only while it is key, so no Accessibility
// permission is involved). Esc: an input method composing keeps it; NotchUI, which owns the Esc chain (§4.10:
// `.keyboardShortcut(.cancelAction)`), gets it next as a key equivalent; only when nothing in the panel takes it
// does the shell run the machine's chain (palette / edit / focus → grid, else close), so exactly one of them
// handles each press and Esc works whatever NotchUI binds. Type-to-capture sends the first printable keys of a
// keyboard-opened, unfocused panel to the chosen `CaptureTarget` while its widget is on a page (then shown there);
// holding ⌘ for 0.5 s shows the key-cap hints; keys and clicks switch the focus rings on and off. The rest of the
// keyboard map is NotchUI's.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

@MainActor final class KeyboardRouter {
    /// DESIGN.md §6.5: hold ⌘ this long before the hints appear.
    static let hintDelay: Duration = .milliseconds(500)

    private weak var panel: NSPanel?
    private let viewModel: NotchViewModel
    private let registry: ModuleRegistry
    private var monitors: [Any] = []
    private var hintTask: Task<Void, Never>?
    /// Type-to-capture fires once per keyboard open.
    private var capturedThisOpen = false

    init(panel: NSPanel, viewModel: NotchViewModel, registry: ModuleRegistry) {
        self.panel = panel; self.viewModel = viewModel; self.registry = registry
    }

    func start() {
        stop()
        // Local monitors run on the main thread for events this app receives.
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.flagsChanged(event)
            return event
        }
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window === self.panel { self.viewModel.setKeyboardNavigation(false) }
            return event
        }
        monitors = [keys, flags, clicks].compactMap { $0 }
        // Esc that a text field let through travels up the responder chain to the panel.
        (panel as? NotchPanel)?.onCancel = { [weak self] in self?.viewModel.send(.escape) }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        (panel as? NotchPanel)?.onCancel = nil
        hintTask?.cancel()
    }

    /// The panel closed: hints off, type-to-capture armed for the next keyboard open.
    func panelClosed() {
        hintTask?.cancel()
        hintTask = nil
        capturedThisOpen = false
        viewModel.setCommandHints(false)
    }

    // MARK: Keys

    /// A key-down this app received (the local monitor): nil = consumed.
    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let panel, event.window === panel else { return event }
        if event.keyCode == 53 {                                                 // kVK_Escape
            if Self.isComposing(panel.firstResponder) { return event }           // Esc cancels the marked text first
            // A text field being edited (a field editor: the Notes rename field, a to-do title, the palette's
            // search) ends its edit first; the next Esc runs the chain (§4.10). If the field does not
            // handle it, the panel's `cancelOperation` runs the chain instead (`NotchPanel.onCancel`).
            if Self.isEditingText(panel.firstResponder) { return event }
            if panel.contentView?.performKeyEquivalent(with: event) == true { return nil }   // NotchUI's chain took it
            viewModel.send(.escape)
            return nil
        }
        if Self.isNavigationKey(event.keyCode) { viewModel.setKeyboardNavigation(true) }
        if let characters = captureCharacters(event), let target = captureTarget() {
            capturedThisOpen = true
            viewModel.focus(target.capture(characters))
            viewModel.setKeyboardNavigation(true)
            return nil
        }
        return event
    }

    /// Characters for type-to-capture: opened by the keyboard, nothing focused, no text field editing, a plain
    /// printable key (Shift allowed; ⌘ ⌃ ⌥ shortcuts and whitespace are left to the Nook).
    private func captureCharacters(_ event: NSEvent) -> String? {
        guard !capturedThisOpen, let open = viewModel.state.openState, open.reason == .keyboard, open.mode == .grid,
              open.focus == nil, viewModel.scene.focusedWidget == nil,
              !(panel?.firstResponder is NSText) else { return nil }
        return Self.printable(event.characters, modifiers: event.modifierFlags)
    }

    /// The chosen target, while what it creates would be seen: a target whose widget is on no page (the default Home
    /// has no Notes) gets nothing, and the key stays with the panel instead of creating a hidden item.
    func captureTarget() -> CaptureTarget? {
        guard let id = registry.services.settings[CoreSettings.typeToCapture],
              let target = registry.captureTargets.first(where: { $0.id == id }) else { return nil }
        if let widget = target.widget, viewModel.page(containing: widget) == nil { return nil }
        return target
    }

    // MARK: Hold ⌘ (DESIGN.md §6.5)

    private func flagsChanged(_ event: NSEvent) {
        guard let panel, event.window === panel || panel.isKeyWindow else { return }
        let commandOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        hintTask?.cancel()
        hintTask = nil
        guard commandOnly, viewModel.state.isOpen else { viewModel.setCommandHints(false); return }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hintDelay)
            guard !Task.isCancelled, let self, self.viewModel.state.isOpen else { return }
            self.viewModel.setCommandHints(true)
        }
    }

    // MARK: Pure helpers (unit-tested)

    /// A string type-to-capture may take: printable, not whitespace, no ⌘ ⌃ ⌥ (Shift is fine).
    nonisolated static func printable(_ characters: String?, modifiers: NSEvent.ModifierFlags) -> String? {
        let blocked: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard modifiers.intersection(blocked).isEmpty, let characters, !characters.isEmpty else { return nil }
        let scalars = characters.unicodeScalars
        guard !scalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              // Arrow and function keys arrive as private-use scalars (NSUpArrowFunctionKey …).
              !scalars.contains(where: { (0xF700...0xF8FF).contains($0.value) }) else { return nil }
        return characters
    }

    /// Tab and the arrows: the user navigates with the keyboard, so focus rings show (DESIGN.md §16).
    nonisolated static func isNavigationKey(_ keyCode: UInt16) -> Bool {
        [48, 123, 124, 125, 126].contains(keyCode)                               // Tab, ←, →, ↓, ↑
    }

    /// The first responder is a field editor (a text field being edited): Esc belongs to it. The Notes editor is a
    /// plain NSTextView, not a field editor, so Esc there leaves focus mode through the chain.
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextView)?.isFieldEditor ?? false
    }

    /// An input method is composing in the first responder: Esc belongs to it.
    static func isComposing(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextView)?.hasMarkedText() ?? false
    }
}

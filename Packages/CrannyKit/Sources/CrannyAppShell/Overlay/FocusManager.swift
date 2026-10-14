// CrannyAppShell/Overlay/FocusManager.swift — key focus of one panel (ARCHITECTURE.md §4.5, §4.10, §5.8).
// The non-activating panel becomes key without activating Cranny (a clicked text field, the hot key,
// `requestKeyboardFocus`, a Tray tile selected); every close hands key status back with `orderOut` +
// `orderFrontRegardless`, which returns it to the previous app's window (R1 §3.5). Key status taken for typing and
// popovers shown from the panel are holds; key status taken for a selection is not (`KeyHold`).
// Who is frontmost is read from `NSWorkspace.frontmostApplication`, never `NSApp.isActive` (true while key).
import AppKit
import Foundation

@MainActor final class FocusManager {
    private weak var panel: NSPanel?
    private var observers: [any NSObjectProtocol] = []
    /// Popovers shown from this panel (they nest: a popover can open another).
    private var popovers: Set<ObjectIdentifier> = []
    /// Called with a hold reason and whether it is on (`typing`, `popover`).
    var onHold: (String, Bool) -> Void = { _, _ in }
    /// Whether key status holds the panel open (the `typing` hold).
    private var keyHold = KeyHold()

    init(panel: NSPanel) { self.panel = panel }

    func start() {
        stop()
        let center = NotificationCenter.default
        for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            observers.append(center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {                                                      // queue: .main
                    self?.updateKeyHold { if isKey { $0.becameKey() } else { $0.resignedKey() } }
                }
            })
        }
        (panel as? NotchPanel)?.onFirstResponderChange = { [weak self] responder in
            if Self.isTextEditing(responder) { self?.updateKeyHold { $0.editingBegan() } }
        }
        for (name, shown) in [(NSPopover.didShowNotification, true), (NSPopover.didCloseNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let popover = note.object as? NSPopover
                MainActor.assumeIsolated { self?.popover(popover, shown: shown) }                // queue: .main
            })
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        (panel as? NotchPanel)?.onFirstResponderChange = nil
        keyHold = KeyHold()
        if !popovers.isEmpty { popovers.removeAll(); onHold(NotchMachineState.popoverHold, false) }
    }

    /// Makes the panel key without activating the app. Only an open panel takes focus. `forTyping` false: for a
    /// selection (a Tray tile), which does not hold the panel open (`KeyHold`).
    func makeKey(forTyping: Bool = true) {
        guard let panel, panel.isVisible else { return }
        updateKeyHold { $0.request(forTyping: forTyping) }
        defer { updateKeyHold { $0.requestEnded() } }
        panel.makeKey()
        if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }              // already front: only takes key
    }

    /// Field editors (text fields) and text views: their first responder status means typing.
    static func isTextEditing(_ responder: NSResponder?) -> Bool { responder is NSText }

    /// Applies `change` and sends the `typing` hold when it flips.
    private func updateKeyHold(_ change: (inout KeyHold) -> Void) {
        let held = keyHold.holdsOpen
        change(&keyHold)
        if keyHold.holdsOpen != held { onHold(NotchMachineState.typingHold, keyHold.holdsOpen) }
    }

    /// Hand key status back to the previously focused window (R1 §3.5): invisible, same run-loop turn.
    func relinquishKeyIfNeeded() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Popovers (§4.5: "an NSPopover is shown inside the panel")

    private func popover(_ popover: NSPopover?, shown: Bool) {
        guard let popover else { return }
        let id = ObjectIdentifier(popover)
        if shown {
            guard let panel, belongs(popover, to: panel) else { return }
            let wasEmpty = popovers.isEmpty
            popovers.insert(id)
            if wasEmpty { onHold(NotchMachineState.popoverHold, true) }
        } else if popovers.remove(id) != nil, popovers.isEmpty {
            onHold(NotchMachineState.popoverHold, false)
        }
    }

    /// A popover's window is a child of the window it was shown from (directly, or through another popover).
    private func belongs(_ popover: NSPopover, to panel: NSWindow) -> Bool {
        var window = popover.contentViewController?.view.window?.parent
        while let current = window {
            if current === panel { return true }
            window = current.parent
        }
        return false
    }
}

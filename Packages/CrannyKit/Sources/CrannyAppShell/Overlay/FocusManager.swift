// CrannyAppShell/Overlay/FocusManager.swift — key focus of one panel (ARCHITECTURE.md §4.5, §4.10, §5.8).
// The non-activating panel becomes key without activating Cranny (a clicked text field, the hot key,
// `requestKeyboardFocus`); every close hands key status back with `orderOut` + `orderFrontRegardless`, which
// returns it to the previous app's window (R1 §3.5). Key status and popovers shown from the panel are holds.
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

    init(panel: NSPanel) { self.panel = panel }

    func start() {
        stop()
        let center = NotificationCenter.default
        for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            observers.append(center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onHold(NotchMachineState.typingHold, isKey) }   // queue: .main
            })
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
        if !popovers.isEmpty { popovers.removeAll(); onHold(NotchMachineState.popoverHold, false) }
    }

    /// Makes the panel key without activating the app (typing). Only an open panel takes focus.
    func makeKey() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
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

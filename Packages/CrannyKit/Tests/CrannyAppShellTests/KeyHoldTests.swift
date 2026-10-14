// Key status for typing holds the open panel; key status for a selection (a Tray tile click) does not, so the panel
// still closes on pointer leave and the close hands key status back (ARCHITECTURE.md §4.5, §4.10; DESIGN.md §3.6).
// `KeyHold` is pure; the panel checks below need no window server (nothing is ordered on screen).
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell

@MainActor @Suite struct KeyHoldTests {
    // MARK: KeyHold

    @Test func typingKeyStatusHoldsThePanelOpen() {
        var hot = KeyHold()                                    // the hot key, `requestKeyboardFocus()`
        hot.request(forTyping: true)
        hot.becameKey()
        hot.requestEnded()
        #expect(hot.isKey && hot.holdsOpen)
        var clicked = KeyHold()                                // a text view clicked: AppKit makes the panel key
        clicked.becameKey()
        #expect(clicked.holdsOpen)
        clicked.resignedKey()
        #expect(!clicked.isKey && !clicked.holdsOpen)
    }

    @Test func selectionKeyStatusDoesNotHoldThePanelOpen() {
        var key = KeyHold()
        key.request(forTyping: false)
        key.becameKey()
        key.requestEnded()
        #expect(key.isKey && !key.holdsOpen)
        key.resignedKey()
        #expect(!key.isKey && !key.holdsOpen)
    }

    @Test func typingAfterASelectionHoldsAfterAll() {
        var edited = KeyHold()
        edited.request(forTyping: false); edited.becameKey(); edited.requestEnded()
        edited.editingBegan()                                  // a text field clicked while the panel was key already
        #expect(edited.holdsOpen)
        var asked = KeyHold()
        asked.request(forTyping: false); asked.becameKey(); asked.requestEnded()
        asked.request(forTyping: true); asked.requestEnded()   // ⌘K, a to-do being edited
        #expect(asked.holdsOpen)
        edited.request(forTyping: false); edited.requestEnded()
        #expect(edited.holdsOpen)                              // a selection never downgrades a typing hold
    }

    @Test func aSelectionRequestThatNeverMadeThePanelKeyIsForgotten() {
        var key = KeyHold()
        key.request(forTyping: false)
        key.requestEnded()                                     // the panel could not become key (locked screen)
        key.becameKey()                                        // later: a text view clicked
        #expect(key.holdsOpen)
        var idle = KeyHold()
        idle.editingBegan()                                    // not key: nothing to hold
        #expect(!idle.holdsOpen)
    }

    // MARK: The close decision

    /// The machine with the holds `KeyHold` produces: pointer leave → grace → closed (and key handed back) for a
    /// selection, but not for typing.
    @Test func aPanelKeyForASelectionClosesWhenThePointerLeaves() {
        for forTyping in [false, true] {
            var key = KeyHold()
            key.request(forTyping: forTyping); key.becameKey(); key.requestEnded()
            var inputs: [NotchInput] = [.pointerEntered, .dwellElapsed(shouldOpen: true)]        // hover-open
            if key.holdsOpen { inputs.append(.hold(NotchMachineState.typingHold, true)) }
            inputs += [.pointerLeft, .timerElapsed(.grace)]
            var state = NotchMachineState()
            var effects: [NotchEffect] = []
            for (i, input) in inputs.enumerated() {
                let (next, fx) = NotchMachine.reduce(state, input, now: Double(i), config: NotchMachineConfig())
                state = next
                effects += fx
            }
            if forTyping {
                #expect(state.isOpen && !effects.contains(.relinquishKey), "typing keeps the panel open")
            } else {
                #expect(state.isClosed && effects.contains(.relinquishKey), "a selection lets it close and hands key back")
            }
        }
    }

    // MARK: Panel glue

    @Test func textViewsAndFieldEditorsCountAsTyping() {
        #expect(FocusManager.isTextEditing(NSTextView()))      // field editors are NSTextViews too
        #expect(!FocusManager.isTextEditing(NSView()))
        #expect(!FocusManager.isTextEditing(nil))
    }

    @Test func thePanelReportsFirstResponderChanges() {
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        defer { panel.close() }
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        panel.contentView?.addSubview(text)
        var seen: [NSResponder?] = []
        panel.onFirstResponderChange = { seen.append($0) }
        #expect(panel.makeFirstResponder(text))
        #expect(seen.count == 1 && seen.first! === text)
    }

    @Test func keyNotificationsDriveTheTypingHold() {
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        defer { panel.close() }
        let focus = FocusManager(panel: panel)
        var holds: [String] = []
        focus.onHold = { reason, on in holds.append("\(reason):\(on)") }
        focus.start()
        defer { focus.stop() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)   // a text view clicked
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)   // no second hold
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        panel.contentView?.addSubview(text)
        _ = panel.makeFirstResponder(text)                                                       // already held
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
        #expect(holds == ["typing:true", "typing:false"])
    }
}

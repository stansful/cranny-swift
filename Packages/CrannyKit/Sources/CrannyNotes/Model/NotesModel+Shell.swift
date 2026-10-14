// CrannyNotes/Model/NotesModel+Shell.swift — the Notes widget's side of the `NotchControl` port: holding the
// panel open while editing or focused, focus mode, and opening the panel at the Notes widget (⌘K, shortcut).
import CrannyCore
import Foundation

extension NotesModel {
    /// Hold reasons (ARCHITECTURE.md §4.5; module reasons are namespaced).
    static let editingHold = "notes.editing"
    static let focusHold = "notes.focus"

    /// The editor became (or stopped being) first responder of a key panel.
    func editorEditingChanged(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
        setHold(editing, Self.editingHold)
    }

    /// The widget is (or stopped being) shown in focus mode: `WidgetContext.rows` went to 3 or back to 2.
    /// Leaving it any way (Esc, ⌘↩, the button, closing) releases the hold.
    func focusPresentationChanged(_ presented: Bool) {
        guard isFocusPresented != presented else { return }
        isFocusPresented = presented
        setHold(presented, Self.focusHold)
    }

    /// ⌘↩ or ⤢: asks the shell for focus mode (or to leave it) and keeps typing in the note.
    func toggleFocusMode() {
        if isFocusPresented {
            notch.setFocusMode(nil)
        } else {
            notch.setFocusMode(.notes)
            requestFocus()
        }
    }

    /// The widget in the Nook (never a stage) is shown live or not: while layout editing or demo redaction
    /// replace the editor it holds nothing (the shell may drop focus mode meanwhile, and a non-live widget
    /// would otherwise never see it); live, the "notes.focus" hold follows focus mode (`rows >= 3`).
    func widgetPresentationChanged(isLive: Bool, isFocusPresented presented: Bool) {
        if isLive { focusPresentationChanged(presented) } else { widgetDisappeared() }
    }

    /// The widget left the screen (the panel closed, the page changed): no hold may outlive it.
    func widgetDisappeared() {
        editorEditingChanged(false)
        focusPresentationChanged(false)
        if renamingID != nil { renamingID = nil }
        if pendingDeletion != nil { dismissDeleteConfirmation() }
    }

    /// The Nook opened (`NotchEvent.opened`): after a failed save, try again now (one attempt per opening).
    func panelOpened() {
        if saveFailed { retrySave() }
    }

    /// The panel closed (`NotchEvent.closed`): a focus request that no editor took (the widget was on another
    /// page) must not make the panel key the next time it opens by hover.
    func panelClosed() {
        if focusRequested { consumeFocusRequest() }
        widgetDisappeared()
    }

    /// Makes the panel key without activating the app, so typing reaches the editor (new note from a button).
    func requestKeyboardFocus() { notch.requestKeyboardFocus() }

    /// Opens the panel on the page that holds the Notes widget, focused on it, with keyboard focus.
    func reveal() {
        let page = settings[CoreSettings.pages].first { $0.items.contains { $0.widget == .notes } }?.id
        notch.open(page: page, focus: .notes, reason: .keyboard)
    }

    /// ⌘K "Open ‹title›".
    func open(_ id: UUID) {
        select(id)
        requestFocus()
        reveal()
    }

    /// The New note shortcut and ⌘K "New note".
    func createAndReveal() {
        newNote()
        reveal()
    }

    private func setHold(_ hold: Bool, _ reason: String) {
        guard hold != heldReasons.contains(reason) else { return }
        if hold { heldReasons.insert(reason) } else { heldReasons.remove(reason) }
        notch.setHoldOpen(hold, reason: reason)
    }
}

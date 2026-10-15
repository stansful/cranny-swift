// CrannyNotes/Editor/NotesTextView.swift — the TextKit 2 `NSTextView` of the Notes editor (DESIGN.md §7.5).
// It reports focus (for the "notes.editing" hold), typed characters (typing effect), pastes (syntax styler) and
// Notes shortcuts, does code-mode niceties (auto-indent, soft tabs) and leaves file drags to the shell (the Tray
// takes them).
// Never touch `layoutManager` here: it would switch the view to TextKit 1.
import AppKit

final class NotesTextView: NSTextView {
    /// Notes shortcuts (⌘N, ⌘R, ⌘[, ⌘], ⌘↩, ⌘/). Return true when handled.
    var onCommand: ((NoteKeyCommand) -> Bool)?
    /// First responder of a key window, or not any more.
    var onEditingChanged: ((Bool) -> Void)?
    /// Characters the user typed (not pasted, not undone), after the insertion.
    var onTyped: ((NSRange) -> Void)?
    /// The view joined a window (a pending focus request can now be honoured).
    var onWindowChange: (() -> Void)?
    /// Code mode: Return keeps the line's indentation, Tab inserts four spaces.
    var isCodeMode = false
    /// A paste or drop is inserting text from a pasteboard (code mode then colours the whole note again).
    private(set) var isReadingPasteboard = false

    /// Key-status observers of the current window; removed when the view leaves it (the panel closes).
    private var windowObservers: [any NSObjectProtocol] = []
    private var reportedEditing = false

    // MARK: Focus

    var isEditing: Bool { window?.isKeyWindow == true && window?.firstResponder === self }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { reportEditingSoon() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { reportEditingSoon() }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.reportEditing() }                // queue: .main
                })
            }
        }
        reportEditing()
        onWindowChange?()
    }

    /// The first responder changes after `become/resignFirstResponder` return: read the result on the next turn.
    private func reportEditingSoon() {
        Task { @MainActor [weak self] in self?.reportEditing() }
    }

    private func reportEditing() {
        let editing = isEditing
        guard editing != reportedEditing else { return }
        reportedEditing = editing
        onEditingChanged?(editing)
    }

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let command = NoteKeyCommand(event: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if command.isTextCommand { return performTextCommand(command) }
        return onCommand?(command) ?? super.performKeyEquivalent(with: event)
    }

    /// ⌘A/C/X/V/Z/⇧⌘Z on the editor itself (the panel never activates the app, so no menu bar is guaranteed).
    @discardableResult func performTextCommand(_ command: NoteKeyCommand) -> Bool {
        switch command {
        case .selectAll: selectAll(nil)
        case .copy: copy(nil)
        case .cut: cut(nil)
        case .paste: paste(nil)
        case .undo:
            guard let undo = undoManager, undo.canUndo else { return true }
            undo.undo()
        case .redo:
            guard let undo = undoManager, undo.canRedo else { return true }
            undo.redo()
        default: return false
        }
        return true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let length = (string as? String)?.utf16.count ?? (string as? NSAttributedString)?.length ?? 0
        let caret = selectedRange().location
        if length > 0 && caret >= length && !hasMarkedText() {
            onTyped?(NSRange(location: caret - length, length: length))
        }
    }

    override func insertNewline(_ sender: Any?) {
        // Read only, before the insertion: the storage's own string, no copy of the note.
        guard isCodeMode, let text = textStorage?.mutableString else { return super.insertNewline(sender) }
        let caret = selectedRange().location
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        var indentEnd = line.location
        while indentEnd < caret, let c = UnicodeScalar(text.character(at: indentEnd)), c == " " || c == "\t" { indentEnd += 1 }
        let indent = text.substring(with: NSRange(location: line.location, length: indentEnd - line.location))
        insertText("\n" + indent, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        guard isCodeMode else { return super.insertTab(sender) }
        insertText("    ", replacementRange: selectedRange())
    }

    /// Paste, Paste and Match Style and drops all read the pasteboard here.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        isReadingPasteboard = true
        defer { isReadingPasteboard = false }
        return super.readSelection(from: pboard, type: type)
    }

    // MARK: Drags

    /// Text only: file drags belong to the shell's drop zones (Tray, AirDrop), never to the note.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        let files = dragInfo.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return files ? [] : super.dragOperation(for: dragInfo, type: type)
    }
}

// CrannyNotes/Editor/EditorCoordinator.swift — owns the editor's AppKit side: builds the scroll view and the TextKit 2
// text view, loads the selected note into the storage, keeps one undo history per note, reports text and focus to
// the model and drives the syntax styler (code mode), the typing effect and line numbers. Per keystroke it does
// O(edit) work only: no language detection (the model's entry carries it), no full-text scans, and code mode
// re-tokenizes only the lines the keystroke can have changed (a paste, drop, undo or redo tokenizes the note whole).
import AppKit
import CrannyCore
import Foundation

/// Everything the editor shows, as one comparable value (built by `NoteTextView` from the model and the theme).
struct EditorConfiguration: Equatable {
    var noteID: UUID
    var entry: NotesModel.Entry
    var style: EditorStyle
    var typingEffect: Bool
    var showsLineNumbers: Bool
    var focusRequested: Bool
    var externalRevision: Int
}

@MainActor final class EditorCoordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    private let model: NotesModel
    private(set) var textView: NotesTextView?
    private(set) var scrollView: NSScrollView?
    private var ruler: LineNumberRuler?
    private(set) var configuration: EditorConfiguration?
    private var attributes: EditorAttributes?
    let styler = SyntaxStyler()
    private var seenExternalRevision = Int.min
    private var isLoadingText = false
    private var undoManagers: [UUID: UndoManager] = [:]
    private var clipObserver: (any NSObjectProtocol)?
    let typingEffect = TypingEffectRenderer()

    init(model: NotesModel) { self.model = model }

    // MARK: Building

    func makeView() -> NSScrollView {
        let textView = NotesTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero                                     // lines start at the editor's top
        textView.focusRingType = .none
        textView.usesFindBar = false
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.setAccessibilityPlaceholderValue(NotesStrings.placeholder)    // VoiceOver: "Start typing" in an empty note
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.onCommand = { [weak self] in self?.perform($0) ?? false }
        textView.onEditingChanged = { [weak self] in self?.model.editorEditingChanged($0) }
        textView.onTyped = { [weak self] in self?.typingEffect.typed($0) }
        textView.onWindowChange = { [weak self] in self?.windowChanged() }
        typingEffect.attach(to: textView)
        if let storage = textView.textStorage { styler.attach(to: storage) }

        let scroll = NSScrollView()
        scroll.clipsToBounds = true                                              // macOS 14+ views draw outside by default
        scroll.contentView.clipsToBounds = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                              object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ruler?.needsDisplay = true }          // queue: .main
        }
        self.textView = textView
        self.scrollView = scroll
        return scroll
    }

    /// The view left the hierarchy: no hold, display link or observer may outlive it.
    func dismantle() {
        if let id = configuration?.noteID, let textView { model.selections[id] = textView.selectedRange() }
        styler.cancel()
        typingEffect.stop()
        model.editorEditingChanged(false)
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
    }

    // MARK: Updating

    func update(_ new: EditorConfiguration) {
        let old = configuration
        configuration = new
        guard let textView, let storage = textView.textStorage else { return }
        if old?.style != new.style || attributes == nil { applyChrome(new.style, to: textView) }
        let noteChanged = old?.noteID != new.noteID
        if noteChanged, let previous = old?.noteID {
            model.selections[previous] = textView.selectedRange()
            textView.breakUndoCoalescing()
        }
        var reloaded = false
        if noteChanged || new.externalRevision != seenExternalRevision {
            seenExternalRevision = new.externalRevision
            if noteChanged || storage.string != model.text(of: new.noteID) {
                loadText(of: new.noteID, into: textView)
                reloaded = true
            }
        }
        if reloaded || old?.style != new.style || old?.entry != new.entry { restyleAll() }
        typingEffect.isEnabled = new.typingEffect
        typingEffect.setAccent(new.style.accent)
        textView.setAccessibilityLabel(new.entry.title)
        updateRuler(visible: new.showsLineNumbers && new.entry.mode == .code)
        if new.focusRequested { Task { @MainActor [weak self] in self?.focusNow() } }
        applyQAHooks()
    }

    /// Visual QA (`--qa-notes typing`): freeze the typing effect once the editor is in a window.
    private func applyQAHooks() {
        #if DEBUG
        if NotesQAHooks.freezesTypingEffect && textView?.window != nil && typingEffect.state.isIdle {
            typingEffect.freezeForQA()
        }
        #endif
    }

    private func applyChrome(_ style: EditorStyle, to textView: NotesTextView) {
        attributes = EditorAttributes(style: style)
        let code = style.mode == .code
        textView.isCodeMode = code
        textView.insertionPointColor = style.accentColor
        textView.selectedTextAttributes = [.backgroundColor: style.selectionColor]
        textView.isAutomaticQuoteSubstitutionEnabled = !code
        textView.isAutomaticDashSubstitutionEnabled = !code
        textView.isAutomaticTextReplacementEnabled = !code
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = !code
        textView.smartInsertDeleteEnabled = !code
        ruler?.apply(style: style)
    }

    private func loadText(of id: UUID, into textView: NotesTextView) {
        guard let storage = textView.textStorage, let attributes else { return }
        typingEffect.clearAll()
        let text = model.text(of: id)
        isLoadingText = true
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.setAttributes(attributes.base, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        isLoadingText = false
        let length = storage.length
        // Where the caret was in this session, else the start, so a note opens showing its first lines.
        let saved = model.selections[id] ?? NSRange(location: 0, length: 0)
        let selection = NSMaxRange(saved) <= length ? saved : NSRange(location: length, length: 0)
        textView.setSelectedRange(selection)
        if selection.location == 0 { textView.scroll(.zero) } else { textView.scrollRangeToVisible(selection) }
        ruler?.textDidChange()
    }

    /// Restyles the whole note (note switch, mode/language/title change, theme change, a new Automatic result).
    func restyleAll() {
        guard let configuration, let attributes else { return }
        let entry = configuration.entry
        styler.restyleAll(code: entry.mode == .code, language: entry.effectiveLanguage, attributes: attributes)
        textView?.typingAttributes = attributes.base
    }

    // MARK: Line numbers

    private func updateRuler(visible: Bool) {
        guard let scrollView, let textView else { return }
        if visible && ruler == nil {
            let ruler = LineNumberRuler(scrollView: scrollView, textView: textView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            self.ruler = ruler
            if let style = configuration?.style { ruler.apply(style: style) }
        }
        guard scrollView.rulersVisible != visible else { return }
        scrollView.rulersVisible = visible
        if visible { ruler?.textDidChange() }                                    // edits while hidden were not tracked
    }

    // MARK: Focus

    private func windowChanged() {
        if configuration?.focusRequested == true { focusNow() }
        applyQAHooks()
    }

    /// Makes the panel key (without activating the app) and the editor first responder, caret where it was.
    private func focusNow() {
        guard model.focusRequested, let textView, let window = textView.window else { return }
        model.consumeFocusRequest()
        model.requestKeyboardFocus()
        window.makeFirstResponder(textView)
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // MARK: Commands

    private func perform(_ command: NoteKeyCommand) -> Bool {
        switch command {
        case .newNote: model.newNote()
        case .rename: model.beginRename()
        case .previousNote: model.selectNext(false)
        case .nextNote: model.selectNext(true)
        case .toggleFocus: model.toggleFocusMode()
        case .toggleCodeMode: model.toggleCodeMode()
        default: return false
        }
        return true
    }

    // MARK: NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? {
        guard let id = configuration?.noteID else { return nil }
        if let manager = undoManagers[id] { return manager }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }

    // MARK: NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isLoadingText, let configuration else { return }
        // Every change of the characters lands here — typing, paste, drop, undo and redo alike.
        let edit = TextEdit(range: editedRange, delta: delta)
        model.setText(textStorage.string, for: configuration.noteID)           // never compared with the old text
        if scrollView?.rulersVisible == true { ruler?.textDidChange(edit) }
        typingEffect.textChanged(edited: editedRange, delta: delta)
        // A paste, drop, undo or redo is coloured by a whole pass; typing only re-tokenizes the lines it touched.
        let undo = undoManagers[configuration.noteID]
        let replaced = textView?.isReadingPasteboard == true || undo?.isUndoing == true || undo?.isRedoing == true
        styler.textChanged(edit, wholePass: replaced)
    }
}

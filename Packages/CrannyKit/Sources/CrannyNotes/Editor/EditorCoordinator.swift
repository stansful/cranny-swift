// CrannyNotes/Editor/EditorCoordinator.swift — owns the editor's AppKit side: builds the scroll view and the TextKit 2
// text view, loads the selected note into the storage, restyles only what an edit changed (code mode), keeps one
// undo history per note, reports text and focus to the model and drives the typing effect and line numbers.
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
    /// Tokens currently applied to the storage (code mode), for incremental restyling.
    private(set) var tokens: [SyntaxToken] = []
    private var language: CodeLanguage?
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
        textView.textContainerInset = NSSize(width: 0, height: Space.xxs)
        textView.focusRingType = .none
        textView.usesFindBar = false
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.onCommand = { [weak self] in self?.perform($0) ?? false }
        textView.onEditingChanged = { [weak self] in self?.model.editorEditingChanged($0) }
        textView.onTyped = { [weak self] in self?.typingEffect.typed($0) }
        textView.onWindowChange = { [weak self] in self?.windowChanged() }
        typingEffect.attach(to: textView)

        let scroll = NSScrollView()
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
        tokens = []
        let length = storage.length
        let saved = model.selections[id] ?? NSRange(location: length, length: 0)
        let selection = NSMaxRange(saved) <= length ? saved : NSRange(location: length, length: 0)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        ruler?.textDidChange()
    }

    /// Restyles the whole note (note switch, mode/language/title change, theme change).
    func restyleAll() {
        guard let configuration, let storage = textView?.textStorage, let attributes else { return }
        let text = storage.string
        language = configuration.entry.mode == .code
            ? configuration.entry.language ?? LanguageDetector.detect(title: configuration.entry.title, text: text) : nil
        tokens = configuration.entry.mode == .code ? SyntaxHighlighter.tokens(in: text, language: language) : []
        storage.beginEditing()
        apply(tokens, in: NSRange(location: 0, length: storage.length), to: storage, attributes)
        storage.endEditing()
        textView?.typingAttributes = attributes.base
    }

    private func apply(_ tokens: [SyntaxToken], in span: NSRange, to storage: NSTextStorage, _ attributes: EditorAttributes) {
        guard span.length > 0 else { return }
        storage.setAttributes(attributes.base, range: span)
        var low = 0, high = tokens.count                                         // first token ending after span start
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(tokens[mid].range) <= span.location { low = mid + 1 } else { high = mid }
        }
        var i = low
        while i < tokens.count && tokens[i].range.location < NSMaxRange(span) {
            let range = NSIntersectionRange(tokens[i].range, span)
            if range.length > 0 { storage.addAttributes(attributes.attributes(for: tokens[i].kind), range: range) }
            i += 1
        }
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
            ruler.textDidChange()
        }
        if scrollView.rulersVisible != visible { scrollView.rulersVisible = visible }
    }

    // MARK: Focus

    private func windowChanged() {
        if configuration?.focusRequested == true { focusNow() }
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
        guard editedMask.contains(.editedCharacters), !isLoadingText, let configuration, let attributes else { return }
        // Every change of the characters lands here — typing, paste, drop, undo and redo alike.
        let text = textStorage.string
        model.setText(text, for: configuration.noteID)
        if scrollView?.rulersVisible == true { ruler?.textDidChange() }
        typingEffect.textChanged(edited: editedRange, delta: delta)
        guard configuration.entry.mode == .code else {
            textStorage.setAttributes(attributes.base, range: editedRange)
            return
        }
        let detected = configuration.entry.language ?? LanguageDetector.detect(title: configuration.entry.title, text: text)
        let fresh = SyntaxHighlighter.tokens(in: text, language: detected)
        let span = detected == language
            ? SyntaxHighlighter.changedRange(old: tokens, new: fresh, edited: editedRange, delta: delta, length: textStorage.length)
            : NSRange(location: 0, length: textStorage.length)
        language = detected
        tokens = fresh
        apply(fresh, in: span, to: textStorage, attributes)
    }
}

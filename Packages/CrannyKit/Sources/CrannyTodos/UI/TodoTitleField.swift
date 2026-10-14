// CrannyTodos/UI/TodoTitleField.swift — the in-place title editor: a borderless single-line `NSTextField`.
// AppKit rather than SwiftUI's `TextField` because the field editor's key-binding selectors are the reliable way
// to see ↩, Esc, ⌫ on an empty field, ↑ ↓ and ⌘↑ ⌘↓ before it consumes them (`TodoEditorCommand`), and
// because the insertion point can take the accent (DESIGN.md §7.5). It exists only for the row being edited and
// takes focus as soon as it is in a window.
import AppKit
import CrannyCore
import SwiftUI

struct TodoTitleField: NSViewRepresentable {
    struct Style: Equatable {
        var font: NSFont
        var text: NSColor
        var placeholder: NSColor
        var caret: NSColor
    }

    let text: String
    let placeholder: String
    let style: Style
    let onChange: @MainActor (String) -> Void
    let onCommand: @MainActor (TodoEditorCommand) -> Bool
    let onBegin: @MainActor () -> Void
    let onEnd: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TitleTextField {
        let field = TitleTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        field.stringValue = text
        apply(style, placeholder: placeholder, to: field)
        return field
    }

    func updateNSView(_ field: TitleTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.appliedStyle != style || field.placeholderString != placeholder { apply(style, placeholder: placeholder, to: field) }
    }

    static func dismantleNSView(_ field: TitleTextField, coordinator: Coordinator) {
        // Leaving the hierarchy is not the user leaving the field (SwiftUI may rebuild a row, the page may change):
        // editing ends by Esc, ↩, a click elsewhere, a page change or the panel closing — never by teardown.
        coordinator.end(notify: false)
        field.delegate = nil
        field.coordinator = nil
    }

    private func apply(_ style: Style, placeholder: String, to field: TitleTextField) {
        field.appliedStyle = style
        field.font = style.font
        field.textColor = style.text
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: style.font, .foregroundColor: style.placeholder])
        (field.currentEditor() as? NSTextView)?.insertionPointColor = style.caret
    }

    // MARK: Coordinator

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoTitleField
        private(set) var isEditing = false

        init(_ parent: TodoTitleField) { self.parent = parent }

        func begin(_ editor: NSTextView?) {
            editor?.insertionPointColor = parent.style.caret
            guard !isEditing else { return }
            isEditing = true
            parent.onBegin()
        }

        func end(notify: Bool = true) {
            guard isEditing else { return }
            isEditing = false
            if notify { parent.onEnd() }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let command = TodoEditorCommand(selector: selector) else { return false }
            return parent.onCommand(command)
        }
    }

    // MARK: Field

    /// Takes focus once it is in a window and reports when its field editor starts and stops.
    final class TitleTextField: NSTextField {
        weak var coordinator: Coordinator?
        var appliedStyle: Style?
        /// Set while the field is being taken out of its window: the resulting end of editing is not the user's.
        private var isLeavingWindow = false

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            isLeavingWindow = newWindow == nil
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // After the current SwiftUI update: the previous row's field may still be the first responder.
            // A hidden copy (an outgoing transition) never takes focus.
            Task { @MainActor [weak self] in
                guard let self, let window = self.window, self.currentEditor() == nil,
                      !self.isHiddenOrHasHiddenAncestor else { return }
                guard window.makeFirstResponder(self) else { return }
                let end = (self.stringValue as NSString).length
                self.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
            }
        }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { coordinator?.begin(currentEditor() as? NSTextView) }
            return became
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            coordinator?.end(notify: !isLeavingWindow)
        }
    }
}

extension TodoTitleField.Style {
    /// `body` at the current Text size, white text, `quaternaryLabel` placeholder, accent caret.
    @MainActor init(theme: CrannyTheme) {
        let size = CrannyTextStyle.body.pointSize(textSize: theme.textSize, notchUnit: theme.notchUnit)
        let palette = theme.palette.spec
        self.init(font: .systemFont(ofSize: size, weight: .regular),
                  text: NSColor(white: 1, alpha: palette.label),
                  placeholder: NSColor(white: 1, alpha: palette.quaternary),
                  caret: theme.accent.nsColor)
    }
}

#Preview("Title field") {
    TodoTitleField(text: "Water the plants", placeholder: "New to-do", style: .init(theme: CrannyTheme()),
                   onChange: { _ in }, onCommand: { _ in false }, onBegin: {}, onEnd: {})
        .frame(width: 160, height: 22)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

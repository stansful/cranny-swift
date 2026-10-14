// CrannyNotes/UI/NotePreviewView.swift — a read-only Notes card for the Settings and onboarding stages and for
// layout editing (no editor, no first responder, no writes; ImageRenderer can draw it), and the redacted card of
// demo mode (no note text or title on screen).
import CrannyCore
import SwiftUI

struct NotePreviewView: View {
    @Environment(\.cranny) private var theme
    let note: Note

    /// Shown on stages when there are no notes yet: the anatomy example of DESIGN.md §7.5.
    static var sample: Note {
        Note(title: "deploy.md", text: "## Release\nlet build = \"1.4.2\"\nretry(3) // flaky CI\n", mode: .code)
    }

    /// The first part of the text only: a stage never shows more than a few lines.
    private static let maximumPreviewLength = 1_500

    var body: some View {
        let style = EditorStyle(theme: theme, mode: note.mode)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 0) {
                Text(note.title)
                    .crannyFont(.headline)
                    .foregroundStyle(theme.palette.label)
                    .lineLimit(1)
                PreviewGlyph(symbol: "chevron.down", tint: theme.palette.tertiaryLabel)
                Spacer(minLength: Space.xs)
                PreviewGlyph(symbol: "chevron.left.forwardslash.chevron.right",
                             tint: note.mode == .code ? theme.accentColor : theme.palette.secondaryLabel,
                             isOn: note.mode == .code)
                PreviewGlyph(symbol: "arrow.up.left.and.arrow.down.right", tint: theme.palette.secondaryLabel)
                PreviewGlyph(symbol: "plus", tint: theme.palette.secondaryLabel)
            }
            .frame(height: HitTarget.nook.height)
            Text(Self.attributed(note, style: style))
                .lineSpacing(max(0, style.lineHeight - style.fontSize * 1.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .accessibilityElement(children: .combine)
    }

    /// The note's text with code mode's colours and fonts, as SwiftUI attributes.
    static func attributed(_ note: Note, style: EditorStyle) -> AttributedString {
        let text = String(note.text.prefix(maximumPreviewLength))
        var result = AttributedString(text)
        result.font = style.font(for: nil)
        result.foregroundColor = style.color(for: nil)
        guard note.mode == .code else { return result }
        let language = note.language ?? LanguageDetector.detect(title: note.title, text: text)
        for token in SyntaxHighlighter.tokens(in: text, language: language) {
            let lower = String.Index(utf16Offset: token.range.location, in: text)
            let upper = String.Index(utf16Offset: NSMaxRange(token.range), in: text)
            guard let from = AttributedString.Index(lower, within: result),
                  let to = AttributedString.Index(upper, within: result), from < to else { continue }
            result[from..<to].font = style.font(for: token.kind)
            result[from..<to].foregroundColor = style.color(for: token.kind)
        }
        return result
    }
}

/// A header glyph without a button (stages are not interactive).
private struct PreviewGlyph: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let tint: Color
    var isOn = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: (HitTarget.nook.height * 0.48).rounded(), weight: .semibold))   // as CrannyIconButtonStyle
            .foregroundStyle(tint)
            .frame(width: HitTarget.nook.height, height: HitTarget.nook.height)
            .background { if isOn { CrannyButtonShape(theme.buttonShape).fill(theme.palette.control) } }
            .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
            .accessibilityHidden(true)
    }
}

/// Demo mode with redaction: the card keeps its shape, the title and text become neutral bars.
struct RedactedNoteView: View {
    @Environment(\.cranny) private var theme

    var body: some View {
        let bar = theme.palette.control
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: Space.m) {
                Capsule(style: .continuous).fill(bar)
                    .frame(width: geometry.size.width * 0.35, height: Space.m)
                    .padding(.vertical, Space.s)
                ForEach([0.92, 0.74, 0.84], id: \.self) { fraction in
                    Capsule(style: .continuous).fill(bar).frame(width: geometry.size.width * fraction, height: Space.s)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(NotesStrings.notes))
    }
}

#Preview("Stage card · code") {
    NotesPreviewFrame(width: 224) { NotePreviewView(note: NotePreviewView.sample).frame(height: 96) }
}

#Preview("Demo redaction") {
    NotesPreviewFrame(width: 224) { RedactedNoteView().frame(height: 96) }
}

// CrannyNotes/Editor/EditorStyle.swift — what the editor looks like, derived from the theme (DESIGN.md §2.1,
// §2.2, §7.5): SF Pro 13 / line 17 for prose, SF Mono 12 / line 16 for code (both scaled by Text size), white
// text at the palette's opacities, `SyntaxPalette` colours, comments tertiary italic, headings semibold, an
// accent caret and selection. `EditorAttributes` caches the AppKit attribute dictionaries for one style.
import AppKit
import CrannyCore
import SwiftUI

struct EditorStyle: Equatable {
    var mode: NoteMode
    var textSize: CrannyTextSize
    var palette: CrannyPalette.Spec
    var accent: RGB

    init(theme: CrannyTheme, mode: NoteMode) {
        self.mode = mode
        textSize = theme.textSize
        palette = theme.palette.spec
        accent = theme.accent
    }

    var textStyle: CrannyTextStyle { mode == .code ? .code : .body }
    var fontSize: CGFloat { textStyle.pointSize(textSize: textSize, notchUnit: 1) }
    /// DESIGN.md §7.5 "line height 1.3": the style's line height scaled with the text size (17 / 16 at Standard).
    var lineHeight: CGFloat { (textStyle.spec.lineHeight * fontSize / textStyle.spec.size).rounded() }

    // MARK: Colours (white at the palette's opacities; syntax colours are audited ≥ 4.5:1 on the card)

    func rgba(for kind: SyntaxKind?) -> (rgb: RGB, alpha: Double) {
        switch kind {
        case .keyword?: (SyntaxPalette.keyword, 1)
        case .type?: (SyntaxPalette.type, 1)
        case .string?, .code?: (SyntaxPalette.string, 1)
        case .number?: (SyntaxPalette.number, 1)
        case .function?: (SyntaxPalette.function, 1)
        case .link?: (SyntaxPalette.link, 1)
        case .comment?, .marker?: (.white, palette.tertiary)
        case .heading?, .emphasis?, .strong?, nil: (.white, palette.label)
        }
    }

    func nsColor(for kind: SyntaxKind?) -> NSColor {
        let c = rgba(for: kind)
        return NSColor(srgbRed: c.rgb.r, green: c.rgb.g, blue: c.rgb.b, alpha: c.alpha)
    }

    func color(for kind: SyntaxKind?) -> Color {
        let c = rgba(for: kind)
        return c.rgb.color(c.alpha)
    }

    var accentColor: NSColor { accent.nsColor }
    /// Selected text sits on `controlPressed` (the accent is for the caret only, DESIGN.md §2.1, §7.5).
    var selectionColor: NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: palette.controlPressed) }
    var placeholderColor: Color { Color(.sRGB, white: 1, opacity: palette.quaternary) }
    var lineNumberColor: NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: palette.quaternary) }

    // MARK: Fonts

    func nsFont(for kind: SyntaxKind?) -> NSFont {
        let size = fontSize
        let weight: NSFont.Weight = kind == .heading || kind == .strong ? .semibold : .regular
        let base = mode == .code ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                                 : NSFont.systemFont(ofSize: size, weight: weight)
        guard kind == .comment || kind == .emphasis else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? base
    }

    func font(for kind: SyntaxKind?) -> Font {
        let weight: Font.Weight = kind == .heading || kind == .strong ? .semibold : .regular
        let font = Font.system(size: fontSize, weight: weight, design: mode == .code ? .monospaced : .default)
        return kind == .comment || kind == .emphasis ? font.italic() : font
    }

    /// Fixed line height, the glyphs centred in it (TextKit puts extra line height above the text).
    func baselineOffset(for font: NSFont) -> CGFloat { max(0, (lineHeight - (font.ascender - font.descender)) / 2) }
}

/// The attribute dictionaries for one `EditorStyle`, built once per style change.
@MainActor final class EditorAttributes {
    let style: EditorStyle
    let base: [NSAttributedString.Key: Any]
    private let byKind: [SyntaxKind: [NSAttributedString.Key: Any]]

    init(style: EditorStyle) {
        self.style = style
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight
        paragraph.maximumLineHeight = style.lineHeight
        let regular = style.nsFont(for: nil)
        if style.mode == .code {
            let space = (" " as NSString).size(withAttributes: [.font: regular]).width
            paragraph.defaultTabInterval = space * 4
            paragraph.tabStops = []
        }
        func attributes(_ kind: SyntaxKind?) -> [NSAttributedString.Key: Any] {
            let font = style.nsFont(for: kind)
            return [.font: font, .foregroundColor: style.nsColor(for: kind), .paragraphStyle: paragraph,
                    .baselineOffset: style.baselineOffset(for: font)]
        }
        base = attributes(nil)
        byKind = Dictionary(uniqueKeysWithValues: SyntaxKind.allCases.map { ($0, attributes($0)) })
    }

    func attributes(for kind: SyntaxKind) -> [NSAttributedString.Key: Any] { byKind[kind] ?? base }
}

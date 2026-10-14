// CrannyNotes/Editor/LineNumberRuler.swift — line numbers in code mode at 6 cells and wider (DESIGN.md §6.7,
// §7.5): quaternary, right-aligned, one per logical line (wrapped lines are not numbered), read from TextKit 2
// layout fragments of the visible part only. Transparent: the text sits directly on the card. Per keystroke it only
// updates the line starts around the edit: the digit width and the drawing attributes are worked out once per style.
import AppKit
import CrannyCore

final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    /// UTF-16 offsets where each logical line starts (always contains 0).
    private var lineStarts: [Int] = [0]
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private var color = NSColor.clear                                          // set by `apply(style:)`
    private var lineHeight: CGFloat = 16
    /// The width of one digit in `font` (measuring text is a CoreText layout: done once per style).
    private var digitWidth: CGFloat = 0
    /// What the numbers are drawn with (`font`, `color`, right-aligned), built once per style.
    private var labelAttributes: [NSAttributedString.Key: Any] = [:]

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = nil
        clipsToBounds = true                                                    // macOS 14+ views draw outside by default
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        updateMetrics()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        updateMetrics()
    }

    override var isFlipped: Bool { true }

    /// Numbers are two points smaller than the code, never below 10 pt (DESIGN.md §2.2).
    static func font(for style: EditorStyle) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: max(style.fontSize - 2, 10), weight: .regular)
    }

    /// Width of the ruler for `digits` digits plus a gap before the text.
    static func thickness(digits: Int, font: NSFont) -> CGFloat {
        thickness(digits: digits, digitWidth: digitWidth(of: font))
    }

    private static func thickness(digits: Int, digitWidth: CGFloat) -> CGFloat {
        (CGFloat(max(digits, 2)) * digitWidth + Space.m).rounded(.up)
    }

    private static func digitWidth(of font: NSFont) -> CGFloat {
        ("8" as NSString).size(withAttributes: [.font: font]).width
    }

    func apply(style: EditorStyle) {
        font = Self.font(for: style)
        color = style.lineNumberColor
        lineHeight = style.lineHeight
        updateMetrics()
        updateThickness()
        needsDisplay = true
    }

    /// The digit width and the drawing attributes of the current font and colour.
    private func updateMetrics() {
        digitWidth = Self.digitWidth(of: font)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        labelAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    /// Updates the line starts after `edit` (only while the ruler is shown): the edited stretch is scanned, the
    /// other starts are kept or shifted, so typing in a long note never rescans its text. nil = recompute from the
    /// whole text (a note loaded, the ruler shown again).
    func textDidChange(_ edit: TextEdit? = nil) {
        guard let text = textView?.textStorage?.mutableString else { return }      // read only: no copy of the note
        lineStarts = edit.map { Self.lineStarts(lineStarts, after: $0, in: text) } ?? Self.lineStarts(in: text)
        updateThickness()
        needsDisplay = true
    }

    /// Offsets where lines start: 0 and every index after a line break (CRLF counts once).
    nonisolated static func lineStarts(in text: String) -> [Int] { lineStarts(in: text as NSString) }

    nonisolated static func lineStarts(in text: NSString) -> [Int] {
        let units = SourceText(text)
        return [0] + (1..<(units.count + 1)).filter { startsLine(units, at: $0) }
    }

    /// `starts` (of the text before `edit`) for the text after it. A start depends only on the units just before
    /// and at it, so starts before the edit stay, starts well after it move by `delta`, and the edited stretch
    /// (plus two units, for a CR LF pair cut or joined by the edit) is scanned again.
    nonisolated static func lineStarts(_ starts: [Int], after edit: TextEdit, in text: NSString) -> [Int] {
        let start = edit.range.location
        let scanEnd = min(NSMaxRange(edit.range) + 2, text.length + 1)          // new starts in start..<scanEnd
        let keptBefore = starts.prefix { $0 < max(start, 1) }                   // always holds 0
        let movedAfter = starts.drop { $0 < edit.oldEnd + 2 }.map { $0 + edit.delta }
        var fresh: [Int] = []
        if max(start, 1) < scanEnd {
            let lower = max(start, 1) - 1
            let window = SourceText(text.substring(with: NSRange(location: lower, length: min(scanEnd, text.length) - lower)) as NSString)
            fresh = (max(start, 1)..<scanEnd).filter { startsLine(window, at: $0 - lower) }   // the window reaches past every s
        }
        return Array(keptBefore) + fresh + movedAfter
    }

    /// A line starts at `offset` (≥ 1) when a break precedes it, except between the CR and LF of one CR LF
    /// (`units` reads 0 past its end: the end of the text, or of a window that reaches the text's end).
    private nonisolated static func startsLine(_ units: SourceText, at offset: Int) -> Bool {
        let before = units[offset - 1]
        return SourceText.isNewline(before) && !(before == 0x0D && units[offset] == 0x0A)
    }

    /// 1-based line number of the line containing `offset`.
    nonisolated static func lineNumber(at offset: Int, lineStarts: [Int]) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    private func updateThickness() {
        let thickness = Self.thickness(digits: String(lineStarts.count).count, digitWidth: digitWidth)
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)                                   // no background, no border
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.textLayoutManager, let content = textView.textContentStorage else { return }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let attributes = labelAttributes
        let start = layout.textViewportLayoutController.viewportRange?.location ?? layout.documentRange.location
        layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let top = frame.minY + origin.y
            if top > visible.maxY { return false }
            if top + frame.height < visible.minY { return true }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let number = Self.lineNumber(at: offset, lineStarts: self.lineStarts)
            let y = self.convert(NSPoint(x: 0, y: top), from: textView).y
            let height = self.font.ascender - self.font.descender
            let rect = NSRect(x: 0, y: y + (self.lineHeight - height) / 2, width: self.ruleThickness - Space.s, height: height)
            (String(number) as NSString).draw(in: rect, withAttributes: attributes)
            return true
        }
    }
}

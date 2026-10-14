// CrannyNotes/Editor/LineNumberRuler.swift — line numbers in code mode at 6 cells and wider (DESIGN.md §6.7,
// §7.5): quaternary, right-aligned, one per logical line (wrapped lines are not numbered), read from TextKit 2
// layout fragments of the visible part only. Transparent: the text sits directly on the card.
import AppKit
import CrannyCore

final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    /// UTF-16 offsets where each logical line starts (always contains 0).
    private var lineStarts: [Int] = [0]
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private var color = NSColor.clear                                          // set by `apply(style:)`
    private var lineHeight: CGFloat = 16

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = nil
        clipsToBounds = true                                                    // macOS 14+ views draw outside by default
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    /// Numbers are two points smaller than the code, never below 10 pt (DESIGN.md §2.2).
    static func font(for style: EditorStyle) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: max(style.fontSize - 2, 10), weight: .regular)
    }

    /// Width of the ruler for `digits` digits plus a gap before the text.
    static func thickness(digits: Int, font: NSFont) -> CGFloat {
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        return (CGFloat(max(digits, 2)) * digitWidth + Space.m).rounded(.up)
    }

    func apply(style: EditorStyle) {
        font = Self.font(for: style)
        color = style.lineNumberColor
        lineHeight = style.lineHeight
        updateThickness()
        needsDisplay = true
    }

    /// Recomputes the line starts after an edit (only while the ruler is shown).
    func textDidChange() {
        guard let text = textView?.textStorage?.string else { return }
        lineStarts = Self.lineStarts(in: text)
        updateThickness()
        needsDisplay = true
    }

    /// Offsets where lines start: 0 and every index after a line break (CRLF counts once).
    nonisolated static func lineStarts(in text: String) -> [Int] {
        var starts = [0]
        var previousWasCR = false
        for (offset, unit) in text.utf16.enumerated() {
            if unit == 0x0A {
                if previousWasCR { starts[starts.count - 1] = offset + 1 } else { starts.append(offset + 1) }
            } else if unit == 0x0D || unit == 0x2028 || unit == 0x2029 {
                starts.append(offset + 1)
            }
            previousWasCR = unit == 0x0D
        }
        return starts
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
        let thickness = Self.thickness(digits: String(lineStarts.count).count, font: font)
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
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

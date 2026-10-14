// CrannyNotes/Editor/TextEdit.swift — one change of a note's characters, as `NSTextStorage` reports it, and how
// several of them merge into one. The syntax styler restyles long notes after the edits of a burst have been
// merged; the line-number ruler updates its line starts from them. Pure value, unit-tested.
import Foundation

nonisolated struct TextEdit: Equatable, Sendable, CustomStringConvertible {
    /// The edited range in the text AFTER the edit.
    var range: NSRange
    /// The change in length (inserted minus removed UTF-16 units).
    var delta: Int

    /// End of the replaced range in the text BEFORE the edit.
    var oldEnd: Int { NSMaxRange(range) - delta }

    /// This edit followed by `next` (whose range is in the text after this edit), as one edit of the text before
    /// both: everything before `range.location` and after the merged end is unchanged (the latter shifted).
    func followed(by next: TextEdit) -> TextEdit {
        let end = NSMaxRange(range)                                             // in the text between both edits
        let mappedEnd = end <= next.range.location ? end : (end >= next.oldEnd ? end + next.delta : NSMaxRange(next.range))
        let start = min(range.location, next.range.location)
        let upper = max(mappedEnd, NSMaxRange(next.range))
        return TextEdit(range: NSRange(location: start, length: upper - start), delta: delta + next.delta)
    }

    var description: String { "edit@\(range.location)+\(range.length)Δ\(delta)" }
}

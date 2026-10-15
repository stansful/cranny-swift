// CrannyNotes/Editor/Syntax/LexState.swift — where the code-mode tokenizers can pick up again (DESIGN.md §7.5).
// Every tokenizer consumes a multi-line construct (block comment, multi-line string, tag) in one step, so at a line
// start its loop carries only a small value: a fence, a YAML block scalar, CSS braces. A pass records one
// `LexCheckpoint` per line start; `SyntaxCache` resumes from one after an edit and stops at the first line start
// past the edit whose state equals the one the old pass had there. Pure values: no AppKit, no main actor.
import Foundation

/// One tokenizer's loop state at a line start.
nonisolated enum LexLevel: Equatable, Sendable {
    /// Nothing carried into the line: code, JSON, markup between tags, Markdown outside a fence, YAML outside a
    /// block scalar.
    case none
    /// YAML inside a `key: |` block scalar whose key line was indented this far.
    case blockScalar(indent: Int)
    /// CSS: braces open and whether a `property:` value is being read.
    case styleSheet(depth: Int, inValue: Bool)
    /// Markdown inside a fence body; the fenced language's tokenizer is the next level.
    case fence(character: UInt16, length: Int, language: CodeLanguage?)
    /// HTML inside a `<script>` (JavaScript) or `<style>` (CSS) body; that tokenizer is the next level.
    case embedded(script: Bool)
}

/// The levels of the tokenizers running at a line start, outermost first (Markdown › a fenced HTML › its script).
/// Three at most: deeper nesting is never tokenized (`depth` limits in the tokenizers), and a tokenizer that would be
/// a fourth level records no checkpoints (its lines are re-tokenized with the construct around them).
nonisolated struct LexState: Equatable, Sendable {
    static let capacity = 3
    private var first = LexLevel.none, second = LexLevel.none, third = LexLevel.none
    private(set) var count = 0

    init() {}

    /// The outermost tokenizer's level (`.none` for an empty state).
    var level: LexLevel { first }

    /// The levels inside the outermost one, or nil when it nests nothing.
    var nested: LexState? {
        guard count > 1 else { return nil }
        var rest = LexState()
        rest.first = second
        rest.second = third
        rest.count = count - 1
        return rest
    }

    /// This state with `level` inside its innermost level, or nil when that would exceed `capacity`.
    func appending(_ level: LexLevel) -> LexState? {
        var state = self
        switch count {
        case 0: state.first = level
        case 1: state.second = level
        case 2: state.third = level
        default: return nil
        }
        state.count += 1
        return state
    }

    /// This state without its innermost level.
    func droppingLast() -> LexState {
        var state = self
        switch count {
        case 1: state.first = .none
        case 2: state.second = .none
        case 3: state.third = .none
        default: return self
        }
        state.count -= 1
        return state
    }
}

/// A line start the tokenizers passed with nothing open: every token before it ends at or before `position`, every
/// later one starts at or after it, and `state` is all they carry into the line.
nonisolated struct LexCheckpoint: Equatable, Sendable {
    var position: Int
    var state: LexState
    /// How far past `position` the decisions before it looked: 0 for the line-local ones (the first unit of the line,
    /// for a CR without LF), more after JSON's `"key"  :` test, CSS's look for a `{` or a `</style>` that starts the
    /// line (`TokenSink.read`). An edit at or before `position + reach` may have changed the state here.
    var reach: Int
}

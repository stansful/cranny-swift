// CrannyNotes/Editor/TypingEffect.swift — the typing effect's bookkeeping (DESIGN.md §7.5): newly typed characters
// appear in the accent and settle to their own colour over 300 ms. Pure state (ranges, ages, colours) so it is
// unit-tested; `TypingEffectRenderer` draws it with TextKit 2 rendering attributes, never touching the text
// storage or the undo stack.
import CrannyCore
import Foundation

nonisolated struct TypingEffect: Equatable {
    static let duration: TimeInterval = 0.3
    /// "touching only the last ≤ 32 ranges"
    static let maximumRuns = 32

    struct Run: Equatable {
        var range: NSRange
        var start: TimeInterval
    }

    private(set) var runs: [Run] = []
    var isIdle: Bool { runs.isEmpty }

    /// Characters were typed at `time`. Returns runs pushed out by the 32-run limit (the renderer clears them).
    @discardableResult mutating func typed(_ range: NSRange, at time: TimeInterval) -> [NSRange] {
        guard range.length > 0 else { return [] }
        if let last = runs.last, last.start == time, NSMaxRange(last.range) == range.location {
            runs[runs.count - 1].range.length += range.length                    // one event, several characters
        } else {
            runs.append(Run(range: range, start: time))
        }
        guard runs.count > Self.maximumRuns else { return [] }
        let dropped = runs.prefix(runs.count - Self.maximumRuns).map(\.range)
        runs.removeFirst(runs.count - Self.maximumRuns)
        return dropped
    }

    /// The text changed (as `NSTextStorage` reports it: `edited` in new coordinates, `delta` = change in length).
    /// Runs after the edit move; characters that were replaced leave their runs.
    mutating func textChanged(edited: NSRange, delta: Int) {
        let start = edited.location
        let oldEnd = edited.location + edited.length - delta
        let newEnd = NSMaxRange(edited)
        runs = runs.compactMap { run in
            let a = run.range.location, b = NSMaxRange(run.range)
            let mappedStart = a < start ? a : (a >= oldEnd ? a + delta : newEnd)
            let mappedEnd = b <= start ? b : (b >= oldEnd ? b + delta : start)
            let end = a < start && b > oldEnd ? b + delta : mappedEnd             // straddles the edit
            guard end > mappedStart else { return nil }
            return Run(range: NSRange(location: mappedStart, length: end - mappedStart), start: run.start)
        }
    }

    /// Splits the runs into those still animating at `time` (with their eased progress 0…1) and finished ones,
    /// which are removed.
    mutating func advance(to time: TimeInterval) -> (active: [(range: NSRange, progress: Double)], finished: [NSRange]) {
        var active: [(NSRange, Double)] = []
        var finished: [NSRange] = []
        for run in runs {
            let p = Self.progress(elapsed: time - run.start)
            if p >= 1 { finished.append(run.range) } else { active.append((run.range, p)) }
        }
        runs.removeAll { Self.progress(elapsed: time - $0.start) >= 1 }
        return (active, finished)
    }

    mutating func removeAll() -> [NSRange] {
        defer { runs = [] }
        return runs.map(\.range)
    }

    /// Ease-out cubic over `duration`: quick to leave the accent, gentle to settle.
    static func progress(elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / duration, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// The colour at `progress` between the accent and the character's own colour (sRGB, with alpha).
    static func blend(from: (rgb: RGB, alpha: Double), to: (rgb: RGB, alpha: Double), progress: Double)
        -> (rgb: RGB, alpha: Double) {
        let p = min(max(progress, 0), 1)
        var delta = to.rgb - from.rgb
        delta.scale(by: p)
        return (from.rgb + delta, from.alpha + (to.alpha - from.alpha) * p)
    }
}

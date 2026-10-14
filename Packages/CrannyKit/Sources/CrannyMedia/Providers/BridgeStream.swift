// CrannyMedia/Providers/BridgeStream.swift — the pure part of a bridge connection's stdout handling, kept on its
// queue and unit-tested: splitting stdout into NDJSON lines (`LineBuffer`).
import Foundation

/// Splits the helper's stdout into lines. A line longer than `maxLineBytes` (an artwork the helper could not
/// shrink) is dropped up to its newline and the stream goes on: the helper stays up. Only a stream that keeps
/// going for `maxDroppedBytes` without any newline counts as corrupt.
nonisolated struct LineBuffer {
    enum Event: Equatable {
        case line(Data)
        /// One oversized line was skipped (its length in bytes).
        case droppedLine(bytes: Int)
        /// No newline for `maxDroppedBytes`: a corrupt or runaway stream.
        case runaway
    }

    let maxLineBytes: Int
    let maxDroppedBytes: Int
    private var pending = Data()
    private var dropping = false
    private var dropped = 0

    init(maxLineBytes: Int, maxDroppedBytes: Int) {
        self.maxLineBytes = maxLineBytes
        self.maxDroppedBytes = max(maxDroppedBytes, maxLineBytes)
    }

    /// Bytes held for an unfinished line.
    var pendingCount: Int { pending.count }

    /// Feeds one chunk; returns the complete lines (without the newline) and what was dropped, in order.
    mutating func append(_ chunk: Data) -> [Event] {
        var events: [Event] = []
        var rest = chunk[...]
        while !rest.isEmpty {
            let newline = rest.firstIndex(of: 0x0A)
            if dropping {
                guard let newline else {
                    dropped += rest.count
                    rest = rest[rest.endIndex...]
                    if dropped > maxDroppedBytes { events.append(.runaway); dropping = false; dropped = 0 }
                    continue
                }
                events.append(.droppedLine(bytes: dropped + (newline - rest.startIndex)))
                dropping = false
                dropped = 0
                rest = rest[rest.index(after: newline)...]
                continue
            }
            guard let newline else {
                pending.append(contentsOf: rest)
                rest = rest[rest.endIndex...]
                if pending.count > maxLineBytes {
                    dropping = true
                    dropped = pending.count
                    pending = Data()
                    if dropped > maxDroppedBytes { events.append(.runaway); dropping = false; dropped = 0 }
                }
                continue
            }
            pending.append(contentsOf: rest[rest.startIndex..<newline])
            events.append(.line(pending))
            pending = Data()
            rest = rest[rest.index(after: newline)...]
        }
        return events
    }
}

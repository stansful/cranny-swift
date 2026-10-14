// CrannyMedia/Providers/BridgeStream.swift — the two pure parts of a bridge connection, kept on its queue and
// unit-tested: splitting stdout into NDJSON lines (`LineBuffer`) and matching answers to commands (`CommandAcks`).
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

/// Matches the bridge's answers to the commands Cranny wrote. The helper handles stdin lines in order and answers
/// every `cmd`/`seek`/`shuffle`/`repeat` line with exactly one `ack` or `error` (CrannyMediaBridge.m `handleLine`),
/// so the answers come back in the order the commands went out. A command whose answer is late keeps its place as
/// a placeholder: the late answer then lands on it instead of on the next command.
nonisolated struct CommandAcks<Waiter> {
    private var entries: [(id: UUID, waiter: Waiter?)] = []

    /// Commands written and not answered yet, placeholders included.
    var count: Int { entries.count }

    /// A command was written; `waiter` gets its answer.
    mutating func append(_ id: UUID, _ waiter: Waiter) {
        entries.append((id, waiter))
    }

    /// The command's time ran out: its waiter is handed back (to be told "no answer") and the entry stays,
    /// so the late answer is matched to it. nil when it was answered already.
    mutating func expire(_ id: UUID) -> Waiter? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let waiter = entries[index].waiter
        entries[index].waiter = nil
        return waiter
    }

    /// The helper answered the oldest command: its waiter, or nil when that command had already expired
    /// (or when no command was outstanding).
    mutating func answerOldest() -> Waiter? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst().waiter
    }

    /// The helper is gone: every waiter still waiting, oldest first.
    mutating func removeAll() -> [Waiter] {
        defer { entries.removeAll() }
        return entries.compactMap(\.waiter)
    }
}

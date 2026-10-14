import Foundation
import Testing
@testable import CrannyTimer

@Suite struct TimerStateFileTests {
    let snapshot = TimerSnapshot(state: TimerState(phase: .paused(remaining: 42), total: 300), lastDuration: 300)

    @Test func roundTrip() throws {
        let file = TimerStateFile(url: temporaryFile())
        #expect(file.load() == nil)                                             // nothing saved yet
        #expect(try file.write(snapshot, sequence: 1))
        #expect(file.load() == snapshot)
    }

    @Test func olderWritesNeverReplaceNewerOnes() throws {
        let file = TimerStateFile(url: temporaryFile())
        let newer = TimerSnapshot(state: TimerState(), lastDuration: 60)
        #expect(try file.write(newer, sequence: 5))
        #expect(try !file.write(snapshot, sequence: 4))
        #expect(file.load() == newer)
    }

    @Test func backgroundWritesKeepTheirOrder() async throws {
        let file = TimerStateFile(url: temporaryFile())
        await withTaskGroup(of: Void.self) { group in
            for n in 1...20 {
                let s = TimerSnapshot(state: TimerState(), lastDuration: n)
                group.addTask { await file.writeInBackground(s, sequence: n) }
            }
        }
        #expect(file.load()?.lastDuration == 20)
    }

    @Test func aCorruptFileIsMovedAsideAndIgnored() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let file = TimerStateFile(url: url)
        #expect(file.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(aside.contains { $0.hasPrefix("state.json.corrupt-") })
    }

    @Test func aFileFromANewerVersionIsIgnoredButKept() throws {
        let url = temporaryFile()
        var future = snapshot
        future.version = TimerSnapshot.currentVersion + 1
        try TimerStateFile(url: url).write(future, sequence: 1)
        #expect(TimerStateFile(url: url).load() == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

// Opt-in (ARCHITECTURE.md §9.6): the real helper under /usr/bin/perl answers every command line exactly once, so
// `BridgeConnection.command` gets the right answer. Only invalid command ids and modes are sent: the helper rejects
// them itself, so no player is ever touched. It reads (never changes) the Now Playing state while it runs.
//   CRANNY_INTEGRATION=1 CRANNY_MEDIA_BRIDGE=<path to libCrannyMediaBridge.dylib> swift test --filter BridgeIntegration
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Bridge integration", .enabled(if: ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"
                                      && ProcessInfo.processInfo.environment["CRANNY_MEDIA_BRIDGE"] != nil))
struct BridgeIntegrationTests {
    @Test func everyCommandLineGetsItsOwnAnswer() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CRANNY_MEDIA_BRIDGE"])
        let connection = BridgeConnection(host: .perl, dylib: URL(fileURLWithPath: path), onMessage: { _ in }, onEnd: { _ in })
        connection.start()
        defer { connection.terminateNow() }
        #expect(await connection.ping() != nil)
        // Sent back to back: each `error` lands on its own command, in order.
        async let first = connection.command("cmd 99")          // "bad command id"
        async let second = connection.command("shuffle 9")      // "bad mode"
        async let third = connection.command("repeat 0")        // "bad mode"
        #expect(await [first, second, third] == [false, false, false])
        #expect(await connection.ping() != nil)                 // the helper is still up
    }
}

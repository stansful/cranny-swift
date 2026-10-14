// Bridge NDJSON fixtures → NowPlaying (ARCHITECTURE.md §10.2 acceptance): full state, missing title, +inf duration
// dropped, lenient MediaRemote values (out-of-range numbers too), artwork keyed by item, protocol messages,
// malformed lines; the connection's line splitting.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

private func line(_ json: String) -> Data { Data(json.utf8) }
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Bridge messages") struct BridgeMessageTests {
    @Test func fullStateMapsEveryField() throws {
        let json = #"{"t":"state","playing":true,"pid":812,"bundleIdentifier":"com.spotify.client","displayName":"Spotify","title":"Midnight Window","artist":"The Example Band","album":"Night Signals","duration":215.5,"elapsed":84.25,"timestamp":1799999990,"rate":1,"itemID":"spotify:track:42","artworkID":"art-1","shuffle":3,"repeat":2,"isMusicApp":1}"#
        guard case .state(let state)? = BridgeMessage.parse(line(json)) else { Issue.record("not a state"); return }
        let np = try #require(state.nowPlaying(receivedAt: now))
        #expect(np.bundleID == "com.spotify.client")
        #expect(np.appName == "Spotify")
        #expect(np.title == "Midnight Window")
        #expect(np.artist == "The Example Band")
        #expect(np.album == "Night Signals")
        #expect(np.duration == 215.5)
        #expect(np.elapsed == 84.25)
        #expect(np.timestamp == Date(timeIntervalSince1970: 1_799_999_990))
        #expect(np.rate == 1)
        #expect(np.isPlaying)
        #expect(np.itemID == "spotify:track:42")
        #expect(np.trackKey == "spotify:track:42")
        #expect(np.artworkID == "art-1")
        #expect(np.shuffle == .tracks)
        #expect(np.repeatMode == .one)
        #expect(np.isMusicApp)
    }

    @Test("Sessions without a title count as nothing playing", arguments: [
        #"{"t":"state","playing":true,"pid":812,"bundleIdentifier":"org.telegram"}"#,
        #"{"t":"state","playing":true,"pid":812,"title":""}"#,
        #"{"t":"state","playing":true,"pid":812,"title":"   "}"#,
    ])
    func missingTitle(_ json: String) {
        guard case .state(let state)? = BridgeMessage.parse(line(json)) else { Issue.record("not a state"); return }
        #expect(state.nowPlaying(receivedAt: now) == nil)
    }

    @Test func noElectedPlayerIsNothingPlaying() {
        // What a blocked bridge reports (R2 §5.4): pid 0, no title.
        guard case .state(let state)? = BridgeMessage.parse(line(#"{"t":"state","playing":false,"pid":0}"#)) else {
            Issue.record("not a state"); return
        }
        #expect(state.nowPlaying(receivedAt: now) == nil)
    }

    @Test("Live streams: +inf (dropped by the bridge), zero or negative durations become nil", arguments: [
        #"{"t":"state","playing":true,"pid":9,"title":"Radio"}"#,
        #"{"t":"state","playing":true,"pid":9,"title":"Radio","duration":0}"#,
        #"{"t":"state","playing":true,"pid":9,"title":"Radio","duration":-1}"#,
        #"{"t":"state","playing":true,"pid":9,"title":"Radio","duration":"inf"}"#,
    ])
    func liveStreamDuration(_ json: String) throws {
        guard case .state(let state)? = BridgeMessage.parse(line(json)) else { Issue.record("not a state"); return }
        let np = try #require(state.nowPlaying(receivedAt: now))
        #expect(np.duration == nil)
        #expect(np.position(at: now.addingTimeInterval(30)) == 30)      // keeps counting without a cap
    }

    @Test func missingTimestampAndRateUseSafeDefaults() throws {
        guard case .state(let state)? = BridgeMessage.parse(line(#"{"t":"state","playing":true,"pid":3,"title":"A","elapsed":5}"#)) else {
            Issue.record("not a state"); return
        }
        let np = try #require(state.nowPlaying(receivedAt: now))
        #expect(np.timestamp == now)
        #expect(np.rate == 1)
        #expect(np.itemID == nil)
        #expect(np.trackKey == "|A||")
    }

    @Test func lenientValues() throws {
        // MediaRemote numbers arrive as ints, doubles or strings; booleans as 0/1.
        let json = #"{"t":"state","playing":1,"pid":"77","title":"T","elapsed":"12.5","itemID":12345,"isMusicApp":true}"#
        guard case .state(let state)? = BridgeMessage.parse(line(json)) else { Issue.record("not a state"); return }
        let np = try #require(state.nowPlaying(receivedAt: now))
        #expect(np.isPlaying)
        #expect(np.elapsed == 12.5)
        #expect(np.itemID == "12345")
    }

    @Test func outOfRangeNumbersAreDroppedNotFatal() throws {
        // Any finite NSNumber reaches the JSON (`plain()` in the bridge); `Int(1e20)` would trap.
        let json = #"{"t":"state","playing":true,"pid":812,"title":"T","shuffle":1e20,"repeat":-1e300,"elapsed":5,"isMusicApp":1e20}"#
        guard case .state(let state)? = BridgeMessage.parse(line(json)) else { Issue.record("not a state"); return }
        let np = try #require(state.nowPlaying(receivedAt: now))
        #expect(np.shuffle == nil)
        #expect(np.repeatMode == nil)
        #expect(np.elapsed == 5)
        #expect(state.shuffle == nil && state.repeat == nil)
        guard case .state(let hugePID)? = BridgeMessage.parse(line(#"{"t":"state","playing":true,"pid":1e20,"title":"T"}"#)) else {
            Issue.record("not a state"); return
        }
        #expect(hugePID.pid == 0)                                          // no usable pid: nothing playing
        #expect(hugePID.nowPlaying(receivedAt: now) == nil)
        #expect(BridgeMessage.parse(line(#"{"t":"hello","pid":-1e40}"#)) == .hello(pid: 0))
        guard case .state(let fractional)? = BridgeMessage.parse(line(#"{"t":"state","playing":true,"pid":7.9,"title":"T"}"#)) else {
            Issue.record("not a state"); return
        }
        #expect(fractional.pid == 7)
    }

    @Test func protocolMessages() {
        #expect(BridgeMessage.parse(line(#"{"t":"hello","v":1,"pid":4242}"#)) == .hello(pid: 4242))
        #expect(BridgeMessage.parse(line(#"{"t":"pong"}"#)) == .pong)
        #expect(BridgeMessage.parse(line(#"{"t":"ack","cmd":2,"ok":true}"#)) == .ack(ok: true))
        #expect(BridgeMessage.parse(line(#"{"t":"ack","ok":false,"why":"pid mismatch"}"#)) == .ack(ok: false))
        #expect(BridgeMessage.parse(line(#"{"t":"error","msg":"bad command id"}"#)) == .error("bad command id"))
    }

    @Test func malformedAndUnknownLinesAreIgnored() {
        #expect(BridgeMessage.parse(line("not json")) == nil)
        #expect(BridgeMessage.parse(line(#"{"no":"type"}"#)) == nil)
        #expect(BridgeMessage.parse(line(#"{"t":"future-thing","x":1}"#)) == nil)
        #expect(BridgeMessage.parse(line(#"{"t":"artwork","itemID":"a","data":"%%%"}"#)) == nil)
    }

    @Test func artworkIsKeyedByItemOrByTheLastState() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let b64 = png.base64EncodedString()
        #expect(BridgeMessage.parse(line(#"{"t":"artwork","itemID":"item-7","mime":"image/png","data":"\#(b64)"}"#))
                == .artwork(itemID: "item-7", data: png))
        #expect(BridgeMessage.parse(line(#"{"t":"artwork","itemID":"","mime":"","data":"\#(b64)"}"#))
                == .artwork(itemID: nil, data: png))

        // Without an item id, the provider files artwork under the last state's track key.
        let provider = MediaRemoteBridgeProvider(host: .perl, dylib: URL(fileURLWithPath: "/nonexistent.dylib"))
        guard case .state(let state)? = BridgeMessage.parse(line(#"{"t":"state","playing":true,"pid":5,"bundleIdentifier":"com.google.Chrome","title":"Video","artist":"Channel"}"#)) else {
            Issue.record("not a state"); return
        }
        let events = provider.events(for: .state(state), at: now)
        let key = try #require(state.nowPlaying(receivedAt: now)?.trackKey)
        #expect(events == [.nowPlaying(state.nowPlaying(receivedAt: now))])
        #expect(provider.events(for: .artwork(itemID: nil, data: png), at: now) == [.artwork(trackKey: key, data: png)])
        #expect(provider.events(for: .artwork(itemID: "other", data: png), at: now) == [.artwork(trackKey: "other", data: png)])
        #expect(provider.events(for: .pong, at: now).isEmpty)
    }

    @Test("Commands use MediaRemote's ids", arguments: [
        (MediaCommand.play, "cmd 0"), (.pause, "cmd 1"), (.togglePlayPause, "cmd 2"), (.nextTrack, "cmd 4"),
        (.previousTrack, "cmd 5"), (.skipBackward15, "cmd 12"), (.skipForward15, "cmd 13"),
        (.seek(to: 30), "seek 30.000"), (.seek(to: -4), "seek 0.000"), (.seek(to: .nan), "seek 0.000"),
        (.setShuffle(.tracks), "shuffle 3"), (.setRepeat(.all), "repeat 3"),
    ])
    func commandLines(_ command: MediaCommand, _ expected: String) {
        #expect(MediaRemoteBridgeProvider.line(for: command) == expected)
    }
}

@Suite("Bridge stream") struct BridgeStreamTests {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func linesAreSplitAcrossChunks() {
        var buffer = LineBuffer(maxLineBytes: 16, maxDroppedBytes: 64)
        #expect(buffer.append(data("ab")).isEmpty)
        #expect(buffer.append(data("c\nde\n\nf")) == [.line(data("abc")), .line(data("de")), .line(Data())])
        #expect(buffer.pendingCount == 1)
        #expect(buffer.append(data("\n")) == [.line(data("f"))])
    }

    @Test func anOversizedLineIsDroppedAndTheStreamGoesOn() {
        // An artwork the helper could not shrink must not take the helper down (it would re-send it on restart).
        var buffer = LineBuffer(maxLineBytes: 8, maxDroppedBytes: 64)
        #expect(buffer.append(data("ok\n0123456789")) == [.line(data("ok"))])
        #expect(buffer.pendingCount == 0)                                  // dropping, not buffering
        #expect(buffer.append(data("abcdef")).isEmpty)
        #expect(buffer.append(data("gh\n{\"t\":\"pong\"}\n")) == [.droppedLine(bytes: 18), .line(data(#"{"t":"pong"}"#))])
    }

    @Test func noNewlineForTooLongIsARunawayStream() {
        var buffer = LineBuffer(maxLineBytes: 8, maxDroppedBytes: 32)
        #expect(buffer.append(Data(repeating: 0x41, count: 20)).isEmpty)
        #expect(buffer.append(Data(repeating: 0x41, count: 20)) == [.runaway])
        var once = LineBuffer(maxLineBytes: 8, maxDroppedBytes: 32)
        #expect(once.append(Data(repeating: 0x41, count: 40)) == [.runaway])
    }
}

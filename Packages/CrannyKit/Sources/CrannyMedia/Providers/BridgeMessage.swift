// CrannyMedia/Providers/BridgeMessage.swift — one NDJSON line from CrannyMediaBridge, decoded leniently
// (ARCHITECTURE.md §6.3 protocol). Pure: unit-tested with fixtures, no process involved.
import CrannyCore
import Foundation

/// A decoded line of the bridge's stdout.
nonisolated enum BridgeMessage: Equatable, Sendable {
    case hello(pid: Int32)
    case state(BridgeState)
    case artwork(itemID: String?, data: Data)
    case pong
    case ack(ok: Bool)
    case error(String)

    /// nil for malformed lines and unknown message types (forward compatibility).
    static func parse(_ line: Data) -> BridgeMessage? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else { return nil }
        switch envelope.t {
        case "hello":
            return .hello(pid: Int32(clamping: envelope.pid ?? 0))
        case "state":
            return (try? JSONDecoder().decode(BridgeState.self, from: line)).map(BridgeMessage.state)
        case "artwork":
            guard let base64 = envelope.data, let data = Data(base64Encoded: base64), !data.isEmpty else { return nil }
            return .artwork(itemID: envelope.itemID.flatMap { $0.isEmpty ? nil : $0 }, data: data)
        case "pong":
            return .pong
        case "ack":
            return .ack(ok: envelope.ok ?? false)
        case "error":
            return .error(envelope.msg ?? "")
        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        var t: String
        var pid: Int?
        var itemID: String?
        var data: String?
        var ok: Bool?
        var msg: String?

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            t = try c.decode(String.self, forKey: .t)
            pid = c.lenientInt(.pid)
            itemID = c.lenientString(.itemID)
            data = c.lenientString(.data)
            ok = c.lenientBool(.ok)
            msg = c.lenientString(.msg)
        }
        enum CodingKeys: String, CodingKey { case t, pid, itemID, data, ok, msg }
    }
}

/// The `state` snapshot exactly as the bridge sends it (keys of CrannyMediaBridge.m `snapshot()`).
nonisolated struct BridgeState: Decodable, Equatable, Sendable {
    var playing: Bool
    var pid: Int
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var displayName: String?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var timestamp: Double?
    var rate: Double?
    var itemID: String?
    var artworkID: String?
    var shuffle: Int?
    var `repeat`: Int?
    var isMusicApp: Bool?

    init(playing: Bool, pid: Int, bundleIdentifier: String? = nil, title: String? = nil) {
        self.playing = playing; self.pid = pid; self.bundleIdentifier = bundleIdentifier; self.title = title
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playing = c.lenientBool(.playing) ?? false
        pid = c.lenientInt(.pid) ?? 0
        bundleIdentifier = c.lenientString(.bundleIdentifier)
        parentApplicationBundleIdentifier = c.lenientString(.parentApplicationBundleIdentifier)
        displayName = c.lenientString(.displayName)
        title = c.lenientString(.title)
        artist = c.lenientString(.artist)
        album = c.lenientString(.album)
        duration = c.lenientDouble(.duration)
        elapsed = c.lenientDouble(.elapsed)
        timestamp = c.lenientDouble(.timestamp)
        rate = c.lenientDouble(.rate)
        itemID = c.lenientString(.itemID)
        artworkID = c.lenientString(.artworkID)
        shuffle = c.lenientInt(.shuffle)
        `repeat` = c.lenientInt(.repeat)
        isMusicApp = c.lenientBool(.isMusicApp)
    }

    enum CodingKeys: String, CodingKey {
        case playing, pid, bundleIdentifier, parentApplicationBundleIdentifier, displayName, title, artist, album
        case duration, elapsed, timestamp, rate, itemID, artworkID, shuffle, `repeat`, isMusicApp
    }

    /// The Core model, or nil = nothing playing: no elected app (`pid` 0, also what a blocked bridge
    /// reports) or a session without a title (Telegram voice notes, untagged audio; R2 §3).
    func nowPlaying(receivedAt now: Date) -> NowPlaying? {
        guard pid > 0, let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let validDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }   // live streams report +inf
        var np = NowPlaying(bundleID: bundleIdentifier.nonEmpty, title: title,
                            artist: artist.nonEmpty, album: album.nonEmpty,
                            duration: validDuration,
                            elapsed: elapsed.flatMap { $0.isFinite ? max($0, 0) : nil } ?? 0,
                            timestamp: timestamp.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? now,
                            rate: rate.flatMap { $0.isFinite ? $0 : nil } ?? (playing ? 1 : 0),
                            isPlaying: playing,
                            itemID: itemID.nonEmpty)
        np.parentBundleID = parentApplicationBundleIdentifier.nonEmpty
        np.appName = displayName.nonEmpty
        np.artworkID = artworkID.nonEmpty
        np.shuffle = shuffle.flatMap(ShuffleMode.init(rawValue:))
        np.repeatMode = `repeat`.flatMap(RepeatMode.init(rawValue:))
        np.isMusicApp = isMusicApp ?? false
        return np
    }
}

// MARK: - Lenient decoding (MediaRemote values are NSNumbers/NSStrings of varying kinds)

private nonisolated extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
    func lenientBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }
}

private nonisolated extension Optional where Wrapped == String {
    /// nil for nil, empty and whitespace-only strings.
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

# R2: Now Playing and media control on macOS 14 to 27, for Cranny

Date: 2026-10-14. Machine: macOS 27.0.1 (build 26A434), Apple Silicon, Xcode 27.0, Swift 6.4, MacOSX27.sdk.
PoC root: `scratchpad/poc/media/` (the full path is `<research-scratchpad>/poc/media/`).

Legend:
- **VERIFIED**: compiled or ran on this machine, or read directly in the SDK.
- **VERIFIED-doc**: read in a primary source (Apple documentation, a project README or source) but not exercised here.
- **UNVERIFIED**: community knowledge or inference. Check it before relying on it.

---

## 0. TL;DR (decisions)

1. **MediaRemote is the primary source. It must be reached through an Apple-signed interpreter.** On macOS 27.0.1, an unentitled process that calls `MRMediaRemoteGetNowPlayingInfo` directly gets `nil`, `0` and `false`. `mediaremoted` logs `Operation not permitted` for it. The same call made from `/usr/bin/perl` returns full metadata, artwork and the playing state, and it can send commands and seek. (VERIFIED)
2. **Write our own small Objective-C bridge (Option 2). Do not vendor `mediaremote-adapter`.** The bridge is about 230 lines and MIT-licensed. It runs as one long-lived helper: JSON events go out on stdout and commands come in on stdin, so command latency is about 12 ms instead of a new perl spawn (about 0.3 s) per command. It ships as a universal dylib of about 120 KB in `Contents/Frameworks`. The loader program is passed with `perl -e`, so no script file is bundled. Credit the technique to ungive/mediaremote-adapter (BSD-3) in About › Acknowledgements as a courtesy. No code is copied, so no license obligation applies.
3. **Host fallback chain:** `/usr/bin/perl` → `/usr/bin/ruby` (Fiddle loads the same dylib unchanged; VERIFIED) → AppleScript provider for Music and Spotify → none. `osascript` cannot host our code (VERIFIED: it only maps platform binaries), but it can read metadata through ASObjC `MRNowPlayingRequest`, polling only and without artwork (VERIFIED).
4. **Distribution:** sign the dylib with the app (CodeSignOnCopy), use a Developer ID and notarize. A quarantined ad-hoc dylib loaded by perl triggers a Gatekeeper prompt and blocks the load (VERIFIED). The app needs no `disable-library-validation` entitlement because perl, not Cranny, loads the dylib (VERIFIED). Cranny must stay non-sandboxed.
5. **Artwork color:** decode a thumbnail, downscale to 24×24, then run k-means in OKLab. A 600 px JPEG takes about 0.27 ms in total (VERIFIED). Do not use `CIAreaAverage`: it is slower at 0.4 to 2 ms and returns muddy averages.
6. **Visualizer:** use a synthetic, playback-driven spectrum by default, rendered with Core Animation (0.06 to 0.34 % of a core in the app process). Offer an opt-in "live" mode that uses a Core Audio global tap excluding Cranny, on macOS 14.2 and later. It needs `NSAudioCaptureUsageDescription` and shows a one-time permission prompt. The FFT costs about 1.5 µs per frame (VERIFIED), so rendering dominates. Avoid SwiftUI `TimelineView` + `Canvas` for the always-on closed-notch bars: it costs 4.6 to 4.8 % of a core (VERIFIED).

---

## 1. Experiments run on this machine

| # | Test | Result | Status |
|---|---|---|---|
| a | Swift CLI calls `dlopen` on MediaRemote and then `MRMediaRemoteGetNowPlayingInfo`, `…IsPlaying`, `…PID` and `…Client` (`poc/media/a-direct/mr_direct.swift`) | `dlopen` and every `dlsym` succeed. All callbacks fire in 3 to 6 ms with `nil`, `false`, `0` and `nil`. A browser tab was playing at that moment (b proves it). | VERIFIED |
| a-log | `log show` for `mediaremoted` during (a) and (b) (`poc/media/logs/mediaremoted_ab.log`) | `Adding client … bundleIdentifier = mr_direct … entitlements=0`, followed by `handlePlaybackQueueRequest … returned with error … kMRMediaRemoteFrameworkErrorDomain Code=3 "Operation not permitted"` | VERIFIED |
| b | ObjC dylib (`clang -dynamiclib`, linker ad-hoc signed) loaded by `/usr/bin/perl` through DynaLoader (`poc/media/b-perl/`) | Returns pid, `playing=1`, `com.google.Chrome`, 13 metadata keys and artwork. The log shows `bundleIdentifier = com.apple.perl … entitlements=264241664`, and the request returns data. | VERIFIED |
| b2 | Bridge v3 (long-lived stdin/stdout protocol) with a fake player that publishes through the public `MPNowPlayingInfoCenter` (`poc/media/v3-bridge/`, `poc/media/publisher/`) | hello after 0.23 to 0.40 s. The publisher's state arrives 87 to 174 ms after its launch and its artwork 62 to 140 ms later. Pause, play, seek(30) and next reach the publisher's `MPRemoteCommandCenter` (its log confirms). Command ack takes about 12 ms and the resulting state about 60 to 75 ms. When the publisher quits, the election moves back to Chrome. RSS is about 23 MB and CPU is 0.02 to 0.03 s over 13 s. The helper exits within 25 ms of stdin EOF and within 1 s after the host is SIGKILLed. | VERIFIED |
| c | `osascript` + ASObjC `MRNowPlayingRequest.localNowPlayingItem()` (`poc/media/c-osascript/np.applescript`) | Works on macOS 27: title, playing state, bundle and keys. The artwork is missing (`artworkAvailable=true`, but there is no data), and the call is poll-only. Logged as `com.apple.osascript … entitlements=264241664`. | VERIFIED |
| d | `/usr/bin/ruby` (com.apple.ruby, Ruby 2.6.10) loading the same dylib through `Fiddle` | Works: hello, state and artwork. Logged as `com.apple.ruby … entitlements=264241664`. | VERIFIED |
| e | JXA (`osascript -l JavaScript`) loading our bundle as a fallback host | arm64 fails with `incompatible architecture (have 'arm64', need 'arm64e')`. arm64e fails with `mapping process is a platform binary, but mapped file is not`, and the process is SIGKILLed. **osascript cannot host third-party code.** | VERIFIED |
| f | Signing matrix for the dylib loaded by perl (`poc/media/sign-tests/`) | Unsigned: `dlopen` fails with "missing code signature". Ad-hoc: loads. Ad-hoc + `com.apple.quarantine`: syspolicyd logs `Prompt shown … waiting for response` (type=WeakSignature), CoreServicesUIAgent presents a code-evaluation dialog, and perl **hangs** until the user answers. | VERIFIED |
| g | Hardened-runtime app (ad-hoc, `--options runtime`) launched through LaunchServices, with the dylib in `Contents/Frameworks`, spawning `/usr/bin/perl` (`poc/media/hr-app/`) | Works with no extra entitlements. | VERIFIED |
| h | Full `MediaService` + providers package in Swift 6 mode (`poc/media/v3-service/`) | Clean build with 0 warnings. It also builds cleanly under CrannyKit-style settings (`defaultIsolation(MainActor)`, `NonisolatedNonsendingByDefault`, `ExistentialAny` …, see `poc/media/v3-service-mainactor/`). The end-to-end demo passes: snapshot, track change, artwork and palette, optimistic toggle, play, seek, next, restart 0.5 s after SIGKILL, and failover to ruby after 3 failures in 60 s. | VERIFIED |
| i | Core Audio process list (`poc/media/v3-viz/procs.swift`, no permission) | The process producing audio is `com.google.Chrome.helper`, not the `com.google.Chrome` PID that MediaRemote reports. | VERIFIED |
| j | SwiftPM ObjC target built without `-fobjc-arc` flags, guarded by `#if !__has_feature(objc_arc) #error` | Builds, so **SwiftPM enables ARC for ObjC targets by default**. `unsafeFlags` is not needed. | VERIFIED |

Privacy note: the user's real media titles were redacted in every saved log.

Side effect to report: test (f) showed one Gatekeeper dialog ("quarantined.dylib" / libCrannyMediaBridge) on the user's screen at 00:45:21. It was closed at 00:47:58, and syspolicyd logged `response=Trash`. That came either from the user or from the test process being killed. The quarantined test file has been deleted. Other Gatekeeper prompts seen in the log at that time came from other processes (another agent's build products) and were not caused by this research.

---

## 2. Why direct MediaRemote stopped working, and why perl works

- Since macOS 15.4, `mediaremoted` gives clients an entitlement mask. Third-party processes get `entitlements=0`, and their now-playing requests fail with `Operation not permitted` while the C API quietly hands `nil` to the callbacks. (VERIFIED on 27.0.1, see 1a-log.)
- Apple platform binaries are admitted with a non-zero mask (`264241664` here). This was observed for `com.apple.perl`, `com.apple.ruby` and `com.apple.osascript` (VERIFIED). The upstream README explains this with bundle IDs that start with `com.apple.` (VERIFIED-doc). Whether the check uses the signing identifier, the platform-binary bit or both is UNVERIFIED and does not matter to us. **We must never spoof a `com.apple.*` identity.**
- `/usr/bin/perl` and `/usr/bin/ruby` have `CodeDirectory flags=0x0`: no hardened runtime and no library validation (VERIFIED with `codesign -dvvv`). That is why they `dlopen` our ad-hoc or Developer ID signed dylib. Their binaries are arm64e, yet they accept our plain arm64 slice (VERIFIED). osascript also has `flags=0x0`, but as a platform binary it refuses non-platform code (VERIFIED, test e).
- Perl 5.34.1 and Ruby 2.6.10 still ship in macOS 27.0.1 (VERIFIED). Apple has warned since Catalina that scripting runtimes may disappear (UNVERIFIED wording, widely reported). That is the main long-term risk, and ruby is only a partial hedge.

---

## 3. ungive/mediaremote-adapter: technique, license and API (read, not built)

Sources: GitHub README, `bin/mediaremote-adapter.pl`, `src/**` and `CMakeLists.txt` at commit 2026-10-10 (VERIFIED-doc). The repo has 285 stars, the license is **BSD-3-Clause** "Copyright (c) 2025 Jonas van den Berg and contributors", and the README badge says it was last tested on macOS 27.0 (26A5425a) on 2026-09-04.

- **Shape:** `MediaRemoteAdapter.framework`, built with CMake, ad-hoc signed and universal x86_64+arm64. It is *bundled but not linked*. Next to it sit `mediaremote-adapter.pl` and an optional `MediaRemoteAdapterTestClient`. Invocation: `/usr/bin/perl mediaremote-adapter.pl /abs/MediaRemoteAdapter.framework [/abs/TestClient] COMMAND [args]`. The script calls `DynaLoader::dl_load_file`, `dl_find_symbol("adapter_<cmd>_env")` and then `dl_install_xsub`. Parameters travel in `MEDIAREMOTEADAPTER_PARAM_*` and `MEDIAREMOTEADAPTER_OPTION_*` environment variables.
- **Commands:**
  - `get`: one JSON dictionary or `null`. Keys include `bundleIdentifier`, `parentApplicationBundleIdentifier`, `playing`, `title`, `artist`, `album`, `duration`, `elapsedTime`, `timestamp`, `artworkMimeType`, `artworkData` (base64), `playbackRate`, `shuffleMode`, `repeatMode`, `contentItemIdentifier`, `isMusicApp`, `mediaType` and about 20 more. Options: `--now`, `--micros`, `--no-artwork`, `--allow-missing-title`, `-h`.
  - `stream`: lines of `{"type":"data","diff":bool,"payload":{…}}`, diffed by default. Options: `--no-diff`, `--debounce=N`, `--micros`, `--no-artwork`, `--allow-missing-title`, `--experimental-peculiar-debounce:com.tidal.desktop=N`.
  - `send ID`, with IDs 0 to 13 = play, pause, toggle, stop, next, previous, toggleShuffle, toggleRepeat, start/end forward seek, start/end backward seek, −15 s, +15 s.
  - `seek MICROS`, `shuffle 1..3`, `repeat 1..3`, `speed N`.
  - `test`: exit code 0 means functional. It launches the test client to fake a now-playing session when nothing is playing.
- **Private functions used** (the same set our bridge uses, VERIFIED present via `dlsym` on 27.0.1): `MRMediaRemoteGetNowPlayingInfo`, `…GetNowPlayingApplicationIsPlaying`, `…GetNowPlayingApplicationPID`, `…GetNowPlayingClient`, `…RegisterForNowPlayingNotifications`, `…SendCommand`, `…SetElapsedTime` (seconds, double), `…SetShuffleMode`, `…SetRepeatMode`, `…SetPlaybackSpeed`. Notifications: `kMRMediaRemoteNowPlayingInfoDidChangeNotification`, `…ApplicationIsPlayingDidChangeNotification`, `…ApplicationDidChangeNotification`, delivered through `NSNotificationCenter` on the main run loop.
- **Known quirks from upstream issues** (VERIFIED-doc), and how our bridge handles each:
  - `+inf` duration on live streams crashes `NSJSONSerialization` (#8, #28). We drop non-finite numbers.
  - An empty first payload (#23). Handled by the service.
  - Artwork briefly disappears on seek. We never clear artwork for the same track key.
  - TIDAL sends partial metadata (peculiar debounce). We use a 50 ms trailing debounce, and the service can add a 300 ms "title changed, artist not yet" hold.
  - Sessions without a title, such as Telegram or untagged audio (#39). We treat them as nothing playing. A later option could show the app name.
  - Only the elected app is visible; reading a specific app is still open upstream (#41/#42). This is a MediaRemote limitation.
- **Swift fork:** ejbills/mediaremote-adapter packages the same code as a SwiftPM `.dynamic` library. The app links the framework, and perl loads `Bundle(for:).executablePath`. GitHub detects no LICENSE file in the fork, so do not depend on it (VERIFIED-doc via the GitHub API).

---

## 4. Integration decision for Cranny

### Option 1: vendor the adapter (BSD-3)
Advantages: maintained, and tested by its author on each macOS beta.

Disadvantages:
- Needs CMake or a re-created Xcode target.
- Every `send`/`seek` spawns a new perl process. Perl plus framework load takes about 0.23 to 0.40 s here, so play/pause feels sluggish.
- The stream is diff-based, so the client has to merge diffs.
- BSD-3 notice obligations apply to both source and binary.
- Its env-var and CLI interface is a moving API ("may experience breaking changes", per the README).

### Option 2 (recommended): our own minimal bridge
`CrannyMediaBridge.m`, about 230 lines and original code. It is in the appendix and at `poc/media/v3-bridge/`.
- **One long-lived helper per app instance.** Out: `hello`, full-snapshot `state` (de-duplicated), `artwork` (only when itemID, artworkID or length changes), `ack`, `error`, `pong`. In: `cmd 0..13 [guardPID]`, `seek <s> [guardPID]`, `shuffle|repeat 1..3`, `refresh`, `ping`, `quit`.
- **Lifetime is safe by construction.** The helper exits on stdin EOF, on SIGPIPE, and when it is re-parented to launchd (5 s check). There are no orphaned perl processes (VERIFIED).
- **Event-driven.** It relies on MR notifications with a 50 ms debounce and never polls. At idle it uses about 0 CPU and about 23 MB RSS (VERIFIED).
- **The loader is inline:** `perl -e '<10-line DynaLoader program>' /abs/path/libCrannyMediaBridge.dylib`, and the same idea works for ruby/Fiddle. No `.pl` resource is needed (VERIFIED in the v3-service demo).
- The environment is minimal and explicit (`PATH`, `LANG`), so the user's `PERL5LIB`, `RUBYOPT` or `DYLD_*` cannot leak in.
- Keep watching upstream's issues and releases as an early-warning system, because they test each beta.

### Build integration (CrannyKit + thin Xcode app)
- `CrannyKit/Sources/CrannyMediaBridge/` holds the ObjC sources and an `include/CrannyMediaBridge.h` that declares `cranny_bridge_main`. Product: `.library(name: "CrannyMediaBridge", type: .dynamic, targets: ["CrannyMediaBridge"])`. **ARC is on by default** (VERIFIED, test j). Export only `cranny_bridge_main`: use `-fvisibility=hidden` plus `__attribute__((visibility("default")))` in the Xcode target, while SwiftPM exports it anyway.
- In the app, the build PoC in `poc/build` currently uses a separate Xcode native dylib target compiled from that folder, plus a "Embed Media Bridge" Copy Files phase into Frameworks with **CodeSignOnCopy**. That produces `Contents/Frameworks/libCrannyMediaBridge.dylib`, signed with the app's identity (`adhoc,runtime` in Debug). This is fine. An alternative is to link the SwiftPM dynamic product so that Xcode embeds `CrannyMediaBridge.framework`; then the runtime path is `…/Frameworks/CrannyMediaBridge.framework/CrannyMediaBridge`. Swift code never imports the module.
- Runtime lookup: `Bundle.main.privateFrameworksURL/libCrannyMediaBridge.dylib`, with a fallback next to the executable for SwiftPM tools and tests (see `MediaRemoteBridgeProvider.defaultDylibURL`).
- Architecture: build it universal (arm64 + x86_64). Perl and ruby run natively, and an Intel Mac needs x86_64.

### Code signing, hardened runtime and library validation
| Concern | Finding | Status |
|---|---|---|
| Dylib must be signed | On arm64, an unsigned dylib fails `dlopen` with "missing code signature". The linker's ad-hoc signature is enough for local builds. | VERIFIED |
| Library validation | It applies to the *loading* process. perl/ruby have none (`flags=0x0`), so any valid signature works: ad-hoc, a different team, or Developer ID. | VERIFIED |
| Cranny's hardened runtime | It does not affect the helper, because the dylib is loaded by perl in a separate process. **No** `com.apple.security.cs.disable-library-validation` is needed. | VERIFIED (test g) |
| Quarantine | A quarantined dylib that is not notarized causes a Gatekeeper prompt on load, and perl blocks. **Releases: Developer ID + hardened runtime + notarize + staple the app** so that nested code is covered by the ticket. | Prompt VERIFIED. Notarized behavior UNVERIFIED (no Developer ID cert here). |
| Ad-hoc / community builds | If a user downloads an un-notarized build and allows the app with "Open Anyway", the embedded dylib may still be quarantined and the perl load may prompt again. Mitigation: before first use, the app can call `removexattr(dylibPath, "com.apple.quarantine", 0)` on its own embedded copy (allowed for non-sandboxed apps), or the README can document `xattr -dr com.apple.quarantine Cranny.app`. Add a full download-to-launch QA pass. | UNVERIFIED (the non-quarantined copy loads silently, VERIFIED) |
| App Sandbox | Do not sandbox Cranny. A child process would inherit the sandbox, and MediaRemote, Apple Events, Accessibility and so on would break. | UNVERIFIED (not tested; Cranny is not sandboxed by design) |
| Activity Monitor | The helper appears as "perl", a child of Cranny. Document this in the FAQ ("Cranny media helper"). | VERIFIED (process name) |

---

## 5. Fallback providers

### 5.1 `/usr/bin/ruby` host (same dylib)
`ruby -e 'require "fiddle"; h = Fiddle.dlopen(ARGV[0]); Fiddle::Function.new(h["cranny_bridge_main"], [], Fiddle::TYPE_VOID).call' /abs/lib.dylib` works (VERIFIED). The service switches to it after 3 perl failures within 60 s (VERIFIED in the demo).

### 5.2 AppleScript / Apple Events for Music and Spotify (permission-gated)
- **Metadata without any permission:** distributed notifications.
  - `com.apple.Music.playerInfo` (the string is present in the Music binary, VERIFIED; `com.apple.iTunes.playerInfo` is also present). Expected `userInfo` keys: `Name`, `Artist`, `Album`, `Total Time` (ms), `Player State` (`Playing`/`Paused`/`Stopped`), `PersistentID`. These keys are UNVERIFIED because Music was not playing.
  - Spotify: `com.spotify.client.PlaybackStateChanged`, with `Name`, `Artist`, `Album`, `Duration` (ms), `Playback Position` (s), `Player State`, `Track ID`. UNVERIFIED: Spotify is not installed and no primary documentation exists. Verify it with a `DistributedNotificationCenter` listener.
- **Commands, position and artwork need Apple Events:**
  - Requirements: `NSAppleEventsUsageDescription` in Info.plist (VERIFIED-doc: "required if your app uses APIs that send Apple events") and, under hardened runtime, the entitlement `com.apple.security.automation.apple-events` (VERIFIED-doc). A TCC "control Music/Spotify" prompt appears for each target app.
  - Music's sdef (VERIFIED with `sdef`): `player state` (`kPSP`/`kPSp`/`kPSS`/…), `player position` (real, read/write), `current track` → `name`, `artist`, `album`, `duration`, `persistent ID`, `artworks` → `raw data`/`data`, and `playpause`, `next track`, `previous track`, `shuffle enabled`, `song repeat`, `sound volume`.
  - Spotify: `player state`, `player position`, `current track` → `artwork url`, `spotify url`, `duration` (ms), plus `playpause` and `next track`. UNVERIFIED (community).
  - Always check `NSRunningApplication.runningApplications(withBundleIdentifier:)` first, because `tell application` would launch the player. Wrap scripts in `with timeout of 2 seconds`. Treat `-1743` (`errAEEventNotPermitted`) as "denied" and show it in Settings instead of retrying.
- **Do not poll.** React to notifications. Query `player position` once on each event or when the Nook opens, and interpolate between queries.
- Run NSAppleScript on the main actor with short timeouts. Its thread safety is undocumented in the header (UNVERIFIED), so keep it main-only.

### 5.3 What does not work
- `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` are *publish/receive for your own app only*. Never use them in Cranny: publishing makes Cranny the elected now-playing app (VERIFIED with the publisher). This is useful only for tests.
- osascript as a code host: see test e.
- ASObjC `MRNowPlayingRequest` (test c) is a diagnostics-only fallback. It is poll-only, has no artwork, and costs about 100 ms per `osascript` spawn.

### 5.4 Detecting that the bridge is silently blocked (future macOS)
If Apple closes the hole, the bridge will still say hello but report `pid=0` (no title), exactly like test a. Heuristic built on public, permission-free APIs: if any Core Audio process has `kAudioProcessPropertyIsRunningOutput == 1` for more than 10 s (`kAudioHardwarePropertyProcessObjectList`, VERIFIED working without permission) while the bridge reports nothing playing, mark the provider "degraded". Then offer the AppleScript provider, show a diagnostic in Settings › Media, and record it in the diagnostics export. Settings can also offer a "Test media detection" button that does what upstream's `test` does: launch a tiny bundled helper that publishes a fake `MPNowPlayingInfoCenter` item for 2 s (as our `PoCPublisher` does) and check that the bridge sees it.

---

## 6. MediaService design

Verified implementation: `poc/media/v3-service/Sources/CrannyMedia/*.swift` (full listings in the appendix). It compiles with 0 warnings in Swift 6 mode and under the CrannyKit MainActor-default settings when types are marked `nonisolated`. It runs end-to-end.

```swift
nonisolated public struct NowPlaying: Equatable, Sendable {      // anchored position, interpolated locally
    public var bundleID, parentBundleID, appName: String?
    public var title: String; public var artist, album: String?
    public var duration: TimeInterval?          // nil = live stream
    public var elapsed: TimeInterval; public var timestamp: Date; public var rate: Double
    public var isPlaying: Bool; public var itemID, artworkID: String?
    public var shuffle: ShuffleMode?; public var repeatMode: RepeatMode?; public var isMusicApp: Bool
    public func position(at now: Date = Date()) -> TimeInterval   // elapsed + (now - timestamp) * rate, clamped
    public var trackKey: String                                   // itemID ?? bundle|title|artist|album
}
nonisolated public enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, skipForward15, skipBackward15
    case seek(to: TimeInterval), setShuffle(ShuffleMode), setRepeat(RepeatMode)
}
nonisolated public enum ProviderEvent: Sendable {
    case nowPlaying(NowPlaying?), artwork(trackKey: String, data: Data), unavailable(reason: String)
}
nonisolated public protocol MediaProvider: AnyObject, Sendable {
    var name: String { get }
    var supportsArtwork: Bool { get }
    func start() -> AsyncStream<ProviderEvent>   // finishes after .unavailable or stop()
    @discardableResult func send(_ command: MediaCommand) async -> Bool
    func stop()
}

@MainActor @Observable public final class MediaService {
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: CGImage?
    public private(set) var palette: ArtworkPalette?       // accent/secondary/dominant/isDark (Sendable RGB floats)
    public private(set) var providerName: String?
    public private(set) var trackChangeCount: Int          // UI: .onChange(of:) → peek the notch
    public private(set) var lastError: String?
    public var ignoredBundleIDs: Set<String>               // Settings › Media › "Ignore apps"
    public init(providers: [@MainActor () -> (any MediaProvider)?])
    public func start(); public func stop()
    @discardableResult public func send(_ c: MediaCommand) async -> Bool  // optimistic for toggle/play/pause/seek
}

// Composition root (app shell):
let media = MediaService(providers: [
    { MediaRemoteBridgeProvider(host: .perl) },            // nil if /usr/bin/perl or the dylib is missing
    { MediaRemoteBridgeProvider(host: .ruby) },
    { AppleScriptProvider(useAppleEvents: settings.allowAppleEventsForMedia) },
])
```

Behavior (all VERIFIED in the demo unless noted):
- **Restart and failover:** on `.unavailable`, restart the same provider after 0.5 s, then 2 s, then 8 s. After 3 failures within 60 s, move to the next provider. Measured: restart 0.52 s after SIGKILL, and immediate failover to ruby on the third kill.
- **Handshake watchdog:** with no `hello` within 4 s, the helper is terminated and reported unavailable.
- **Interpolated progress:** the progress bar uses `position(at:)` with `TimelineView(.periodic(from: .now, by: 1))` only while the Nook is open. MediaRemote is never polled.
- **Track change, used for the peek:** `trackKey` changes increment `trackChangeCount`. For the UI, add a debounce of about 300 ms and require `isPlaying`, and skip the first snapshot after launch (UNVERIFIED UX tuning).
- **Artwork:** decoded off the main thread (`Task.detached(priority: .utility)`) with an ImageIO thumbnail (max 512 px), plus the palette. Kept in an LRU of 16 by `trackKey`. Late artwork for the current track is applied, and artwork for other tracks is cached.
- **Commands:** play/pause/toggle/seek update `nowPlaying` optimistically, and the provider's next state corrects it within about 60 to 75 ms.
- **Ignore list and "music apps only":** filtered before publishing. `isMusicApp` and `mediaType` come from MR, and browsers can be excluded by bundle ID.
- **Concurrency:** `BridgeConnection` confines its process, pipes and buffer to a private serial queue. Events reach the `@MainActor` service through `AsyncStream` (`.bufferingNewest(32)`). Models are `nonisolated` + `Sendable`, so the code compiles both with and without `defaultIsolation(MainActor)`.

Settings surface (Media pane): source app badge and provider status (perl, ruby, AppleScript or none, plus the last error). Toggles: "Allow Apple Events for Music/Spotify (fallback)", "Ignore apps…", "Show browser media", "Peek on song change", "Visualizer: Synthetic / Live (system audio)", "Test media detection".

---

## 7. Artwork and color extraction

Code: `poc/media/v3-color/palette.swift` (benchmark) and `v3-service/Sources/CrannyMedia/ArtworkPalette.swift` (production shape, Sendable).

Algorithm:
1. Decode with `CGImageSourceCreateThumbnailAtIndex` at max 64 px for the palette (and 512 px for display).
2. Draw into a 24×24 sRGB RGBA8 `CGContext`.
3. Convert the 576 pixels to OKLab (Ottosson's published matrices).
4. Run k-means with k = 5 for 8 rounds, seeded deterministically at lightness quantiles.
5. **accent** = argmax over clusters of (chroma + 0.02) × √population. Ignore clusters under 3 % of pixels and down-weight near-black and near-white.
6. **secondary** = the runner-up. **dominant** = the largest cluster.
7. "Glow-safe" clamp in OKLab: L in [0.68, 0.86] and C in [0.10, 0.20]. Hue is kept, and greyscale art stays neutral.

Benchmark (VERIFIED, `poc/media/v3-color/bench.txt`):

| Input | Full make(from: Data) | k-means alone | CIAreaAverage (full) | CIAreaAverage (64 px) | avg vs accent |
|---|---|---|---|---|---|
| synthetic 600 px JPEG (grey + red/blue blocks) | **0.27 ms** | 36 µs | 1.44 ms | 0.48 ms | avg/CI `#403136` (mud) vs accent `#FB566B` |
| 356 px HEIC wallpaper thumbs | 6.6 to 7.7 ms (HEIC decode) | 38 to 51 µs | 1.4 to 2.0 ms | 0.39 to 0.71 ms | e.g. avg `#400C20` vs accent `#D77789` |

MediaRemote artwork is usually JPEG or PNG (Chrome sent `image/jpeg`, VERIFIED), so expect about 0.3 ms per track change. `CIAreaAverage` gives the same muddy mean, costs more because of the GPU round trip, and needs a shared `CIContext`. Use it only if you specifically want the mean color.

---

## 8. Audio visualizer

### Options
| Option | Permission | API (VERIFIED in the SDK) | Cost | Verdict |
|---|---|---|---|---|
| **Synthetic, playback-driven** | none | n/a | CA keyframes: 0.06 to 0.22 % of a core (app). CA layers driven by a 30 Hz timer: 0.34 %. SwiftUI `TimelineView`+`Canvas` at 30/60 fps: **4.6 to 4.8 %** (VERIFIED, `v3-viz/vizcost.txt`, app process only; WindowServer was too noisy to measure at about 50 % baseline) | **Default** |
| **Core Audio process tap** (macOS 14.2+) | "System audio recording" TCC prompt on the first `AudioDeviceStart`. `NSAudioCaptureUsageDescription` is required (VERIFIED-doc, Apple sample "Capturing system audio with Core Audio taps"). There is no API to query the status, and a denied tap delivers silence (UNVERIFIED, community and Apple forums). | `AudioHardwareCreateProcessTap(CATapDescription*, AudioObjectID*)` and `AudioHardwareDestroyProcessTap` are `API_AVAILABLE(macos(14.2))`. `CATapDescription(stereoGlobalTapButExcludeProcesses:)`, `.isPrivate`, `.muteBehavior = .unmuted`, `.uuid`. On macOS 26: `.bundleIDs` and `.isProcessRestoreEnabled`. Also `kAudioHardwarePropertyTranslatePIDToProcessObject`, `kAudioAggregateDeviceTapListKey`, `kAudioAggregateDeviceTapAutoStartKey`, `kAudioSubTapUIDKey`, `kAudioSubTapDriftCompensationKey`, `AudioHardwareCreateAggregateDevice`, `AudioDeviceCreateIOProcIDWithBlock`, `kAudioDevicePermissionsError`. macOS 15+ adds the Swift classes `AudioHardwareSystem`, `AudioHardwareTap` and `AudioHardwareProcess`. | Analysis: IO-thread push 0.3 to 0.4 µs per 512 frames, FFT 1024 + 24 log bands 1.4 to 1.9 µs at 60 Hz, about 0.015 % of a core (VERIFIED, `v3-viz/spectrum-bench.txt`). Rendering is the same as the synthetic option. The HAL IO overhead of the private aggregate device was not measured (UNVERIFIED, expected small). | **Opt-in "Live visualizer"** |
| ScreenCaptureKit audio | Screen Recording permission (a broader, scarier prompt) | `SCStreamConfiguration.capturesAudio`, `excludesCurrentProcessAudio`, `SCStreamOutputTypeAudio` (macOS 13+) | heavier, because it involves a video pipeline | Do not use |

### Notes for the live mode
- **Tap globally while excluding Cranny, not by the MediaRemote PID.** Browsers play audio from helper processes (VERIFIED: Chrome audio came from `com.google.Chrome.helper` while MR reported the main Chrome PID). Safari uses a WebKit GPU process (UNVERIFIED). A per-app tap on macOS 26 could use `bundleIDs` with prefix matching, but the global tap is simpler and robust.
- Keep the IO block allocation-free and lock-free in practice. Mix down to mono into a ring with `OSAllocatedUnfairLock.withLockIfAvailableUnchecked`: a try-lock that drops a buffer on contention and never blocks the HAL thread. Run the FFT at display rate on the UI side. This compiles in Swift 6 mode (VERIFIED). The tap itself was compiled but **not run**, to avoid prompting the user (`v3-viz/spectrum.swift`, `./spectrum tap`).
- Start the tap only while something is playing and the notch is visible. Stop it after 10 s paused, in Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`, VERIFIED in the SDK), and when the screen is locked or asleep.
- Do not use the `INFOPLIST_KEY_` build setting for `NSAudioCaptureUsageDescription`. It reportedly gets dropped (UNVERIFIED community report). Put the key in the hand-written Info.plist (Cranny already uses one).

### Synthetic spectrum design (default)
- Inputs: `isPlaying`, `rate`, `trackKey` (seeds per-bar phases so each song looks different), and optionally a tempo hint. MR has no BPM, so use a gentle 100 to 120 BPM pulse.
- Per bar: an envelope of summed incommensurate sines × a "beat" pulse, clamped to [0.12, 1]. On pause, ease to a low resting height over about 400 ms. On resume, ramp up.
- Colors: gradient from `palette.accent` to `palette.secondary`. Respect a "colorless" setting and Reduce Motion (static bars).
- Rendering: closed and peek notch use `CALayer` bars, with either a `CAKeyframeAnimation` (cheapest, animated by the render server) or 30 Hz data-driven transforms inside `CATransaction.setDisableActions(true)`. The open Nook can use SwiftUI `Canvas` at 30 fps *only while open*.

---

## 9. Risks and open questions

1. **Apple closes the perl path** (High impact, Medium likelihood). The ruby host and the AppleScript fallback reduce the damage, and the blocked-state heuristic (5.4) detects it. Watch upstream; its author tests every beta.
2. **Perl and ruby removed from the base system** (High, Low to Medium). Fallback: AppleScript for Music/Spotify, plus ASObjC `MRNowPlayingRequest` metadata for diagnostics.
3. **Gatekeeper and quarantine for non-notarized builds** (Medium). Releases need Developer ID + notarization. Test the download flow, and use the `removexattr` mitigation for ad-hoc builds (UNVERIFIED).
4. **Private API drift:** keys, notification names or the `MRClient` selectors could change. Every `dlsym` is checked, `respondsToSelector:` guards the client accessors, the bridge exits with codes 10 or 11 if symbols are missing, and the service fails over.
5. **The Spotify notification name and the Music `userInfo` keys are UNVERIFIED.** Verify them on a machine with Spotify and Music playing.
6. **Only one now-playing app** is visible (the MR election). Multi-session UI is not possible through MR.
7. **Live visualizer permission UX:** permission state cannot be queried. Detect silence or `kAudioDevicePermissionsError` (UNVERIFIED approach) and show guidance.

---

## 10. PoC index (all under `scratchpad/poc/media/`)

- `a-direct/mr_direct.swift`: test a (direct MediaRemote, blocked).
- `b-perl/CrannyMRBridge.m`, `b-perl/cranny-mr.pl`: test b (minimal dylib + DynaLoader script, `get`/`stream`/`send`/`seek`).
- `v3-bridge/CrannyMediaBridge.m`, `cranny-media.pl`, `host.swift`, `run2.log`, `hang.swift`: the recommended bridge, its protocol test and the SIGKILL-orphan test.
- `publisher/publisher.swift` (`PoCPublisher.app`): a fake now-playing app built on the public MediaPlayer API. Test commands are guarded to its PID, so the user's player is never touched.
- `sign-tests/`: signing matrix (unsigned, ad-hoc; the quarantined copy was removed).
- `hr-app/`: hardened-runtime host app test.
- `jxa-loader/`: osascript-as-host negative test.
- `c-osascript/np.applescript`, `np_art.applescript`: ASObjC `MRNowPlayingRequest`.
- `v3-service/`: SwiftPM package (`CrannyMediaBridge` dynamic + `CrannyMedia` + `mediademo`), `demo-run1.log`. `v3-service-mainactor/` holds the same sources under CrannyKit settings.
- `v3-color/palette.swift`, `bench.txt`: palette vs CIAreaAverage.
- `v3-viz/spectrum.swift` (FFT pipeline + `SystemAudioTap`, compile-verified), `spectrum-bench.txt`, `vizcost.swift`, `vizcost.txt`, `procs.swift`.
- `logs/mediaremoted_ab.log`: the denial vs admission evidence.

Reproduce (each command separately; prefix every one with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer;`):
```
swiftc -O -o a-direct/mr_direct a-direct/mr_direct.swift && a-direct/mr_direct
clang -dynamiclib -fobjc-arc -fvisibility=hidden -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -framework Foundation -framework AppKit -o v3-bridge/libCrannyMediaBridge.dylib v3-bridge/CrannyMediaBridge.m
(echo ping; sleep 1; echo quit) | /usr/bin/perl v3-bridge/cranny-media.pl "$PWD/v3-bridge/libCrannyMediaBridge.dylib"
cd v3-service && swift build --scratch-path .build && .build/debug/mediademo "$PWD/../publisher/PoCPublisher.app"
/usr/bin/log show --last 2m --info --style compact --predicate 'process == "mediaremoted" AND eventMessage CONTAINS "Adding client"'
```

Sources consulted: github.com/ungive/mediaremote-adapter (README, source, issues #1 to #44, commits to 2026-10-10); github.com/ejbills/mediaremote-adapter (Package.swift, run.pl); Apple documentation "Capturing system audio with Core Audio taps", "Apple Events Entitlement", "NSAppleEventsUsageDescription"; MacOSX27.sdk headers (CoreAudio `AudioHardware.h`, `AudioHardwareTapping.h`, `CATapDescription.h`, the CoreAudio and os Swift interfaces, ScreenCaptureKit `SCStream.h`, Foundation `NSProcessInfo.h`); `sdef /System/Applications/Music.app`; community notes on tap permissions (insidegui/AudioCap, Apple Developer Forums thread 756783, dev.to "2000 buffers of nothing").

---

## Appendix: verified source listings (exact copies of the PoC files)

All of these files compile with 0 warnings: the Swift files under Swift 6 language mode, and also under CrannyKit-style `defaultIsolation(MainActor)` with upcoming features, and the ObjC file under `-Wall -Wextra`. These were exercised end-to-end on macOS 27.0.1: the bridge, `BridgeConnection`, `MediaRemoteBridgeProvider`, `MediaService` and `ArtworkPalette`. Two pieces are **compile-verified only**: `AppleScriptProvider`, because running it would trigger Automation prompts and Music/Spotify were not playing, and `SystemAudioTap` inside `spectrum.swift`, because running it would trigger the system-audio-recording prompt. The spectrum *analysis* part of `spectrum.swift` was benchmarked.

### `v3-bridge/CrannyMediaBridge.m`

```objc
// CrannyMediaBridge v3 — research PoC of the bridge proposed for Cranny.
// Original code (MIT, Cranny). Technique credit: ungive/mediaremote-adapter
// (BSD-3) documented that /usr/bin/perl (identity com.apple.perl*) is admitted
// by mediaremoted and can load a custom library via DynaLoader.
//
// Process model: ONE long-lived /usr/bin/perl child per Cranny instance.
//   stdout  newline-delimited JSON events:
//           {"t":"hello","v":1,"pid":N}
//           {"t":"state", ...}            (full snapshot, de-duplicated)
//           {"t":"artwork","itemID":..,"mime":..,"data":base64}  (only on change)
//           {"t":"ack"|"error"|"pong", ...}
//   stdin   one command per line:
//           cmd <0-13> [expectPID] | seek <seconds> [expectPID]
//           shuffle <1-3> | repeat <1-3> | refresh | ping | quit
//   lifetime: exits on stdin EOF, SIGPIPE, or when re-parented to launchd.
//
// Build (arm64 + x86_64, ad-hoc signed by the linker on arm64):
//   clang -dynamiclib -fobjc-arc -fvisibility=hidden -arch arm64 -arch x86_64 \
//     -mmacosx-version-min=14.0 -framework Foundation -framework AppKit \
//     -o libCrannyMediaBridge.dylib CrannyMediaBridge.m
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <signal.h>
#include <unistd.h>

#if !__has_feature(objc_arc)
#error "CrannyMediaBridge must be compiled with -fobjc-arc"
#endif

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(uint32_t, NSDictionary *);
typedef void (*SetDoubleFn)(double);
typedef void (*SetIntFn)(int);

static struct {
    GetInfoFn info; GetBoolFn playing; GetPIDFn pid; GetClientFn client;
    RegisterFn reg; SendFn send; SetDoubleFn seek; SetIntFn shuffle; SetIntFn repeat;
} MR;

static dispatch_queue_t gQ;          // all MediaRemote calls + state on one serial queue
static dispatch_source_t gDebounce;  // trailing debounce for notification bursts
static NSString *gLastState;         // de-dup identical consecutive snapshots
static NSString *gLastArtKey;        // artwork is re-sent only when this changes

static void emit(NSDictionary *obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return;
    // One write per line keeps lines atomic for the reader.
    NSMutableData *line = [d mutableCopy];
    [line appendBytes:"\n" length:1];
    fwrite(line.bytes, 1, line.length, stdout);
    fflush(stdout);
}

// JSON-safe scalar: strings, finite numbers, dates (as epoch seconds).
// Live streams report Duration = +inf, which NSJSONSerialization rejects.
static id plain(id v) {
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) {
        double x = [(NSNumber *)v doubleValue];
        return isfinite(x) ? v : nil;
    }
    if ([v isKindOfClass:NSDate.class]) return @([(NSDate *)v timeIntervalSince1970]);
    return nil;
}

static NSString *K(NSString *suffix) { return [@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix]; }

static void snapshot(void) {
    MR.pid(gQ, ^(int pid) {
      MR.playing(gQ, ^(Boolean isPlaying) {
        MR.client(gQ, ^(id client) {
          MR.info(gQ, ^(NSDictionary *info) {
            NSMutableDictionary *s = [@{ @"t": @"state", @"playing": isPlaying ? @YES : @NO, @"pid": @(pid) } mutableCopy];
            if (client) {
                for (NSString *sel in @[ @"bundleIdentifier", @"parentApplicationBundleIdentifier", @"displayName" ]) {
                    if ([client respondsToSelector:NSSelectorFromString(sel)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        id v = [client performSelector:NSSelectorFromString(sel)];
#pragma clang diagnostic pop
                        if ([v isKindOfClass:NSString.class] && [v length]) s[sel] = v;
                    }
                }
            }
            if (!s[@"bundleIdentifier"] && pid > 0) {
                NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                if (app.bundleIdentifier) s[@"bundleIdentifier"] = app.bundleIdentifier;
            }
            NSDictionary *map = @{ @"title": @"Title", @"artist": @"Artist", @"album": @"Album",
                                   @"duration": @"Duration", @"elapsed": @"ElapsedTime",
                                   @"timestamp": @"Timestamp", @"rate": @"PlaybackRate",
                                   @"itemID": @"ContentItemIdentifier", @"artworkID": @"ArtworkIdentifier",
                                   @"shuffle": @"ShuffleMode", @"repeat": @"RepeatMode",
                                   @"mediaType": @"MediaType", @"isMusicApp": @"IsMusicApp",
                                   @"prohibitsSkip": @"ProhibitsSkip", @"isAd": @"IsAdvertisement" };
            for (NSString *outKey in map) {
                id v = plain(info[K(map[outKey])]);
                if (v) s[outKey] = v;
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:s options:NSJSONWritingSortedKeys error:nil];
            NSString *str = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
            if (str && ![str isEqualToString:gLastState]) { gLastState = str; emit(s); }

            NSData *art = info[K(@"ArtworkData")];
            if ([art isKindOfClass:NSData.class] && art.length > 0) {
                NSString *artKey = [NSString stringWithFormat:@"%@|%@|%lu", s[@"itemID"], s[@"artworkID"], (unsigned long)art.length];
                if (![artKey isEqualToString:gLastArtKey]) {
                    gLastArtKey = artKey;
                    emit(@{ @"t": @"artwork", @"itemID": s[@"itemID"] ?: @"",
                            @"mime": plain(info[K(@"ArtworkMIMEType")]) ?: @"",
                            @"data": [art base64EncodedStringWithOptions:0] });
                }
            }
          });
        });
      });
    });
}

static void scheduleSnapshot(void) {
    dispatch_source_set_timer(gDebounce, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                              DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
}

// Runs `action` only if the elected now-playing PID matches `expect` (0 = always).
static void guarded(int expect, void (^action)(void)) {
    if (!expect) { action(); return; }
    MR.pid(gQ, ^(int pid) {
        if (pid != expect) { emit(@{ @"t": @"ack", @"ok": @NO, @"why": @"pid mismatch", @"nowPlayingPID": @(pid) }); return; }
        action();
    });
}

static void handleLine(NSString *line) {
    NSArray<NSString *> *p = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *verb = p.firstObject;
    int arg2 = p.count >= 3 ? p[2].intValue : 0;
    if ([verb isEqualToString:@"quit"]) exit(0);
    if ([verb isEqualToString:@"ping"]) { emit(@{ @"t": @"pong" }); return; }
    if ([verb isEqualToString:@"refresh"]) { gLastState = nil; gLastArtKey = nil; snapshot(); return; }
    if ([verb isEqualToString:@"cmd"] && p.count >= 2) {
        int c = p[1].intValue;
        if (c < 0 || c > 13) { emit(@{ @"t": @"error", @"msg": @"bad command id" }); return; }
        guarded(arg2, ^{ emit(@{ @"t": @"ack", @"cmd": @(c), @"ok": MR.send((uint32_t)c, nil) ? @YES : @NO }); });
        return;
    }
    if ([verb isEqualToString:@"seek"] && p.count >= 2 && MR.seek) {
        double sec = p[1].doubleValue;
        if (!(sec >= 0) || !isfinite(sec)) { emit(@{ @"t": @"error", @"msg": @"bad position" }); return; }
        guarded(arg2, ^{ MR.seek(sec); emit(@{ @"t": @"ack", @"seek": @(sec), @"ok": @YES }); });
        return;
    }
    if (([verb isEqualToString:@"shuffle"] || [verb isEqualToString:@"repeat"]) && p.count >= 2) {
        int m = p[1].intValue;
        SetIntFn fn = [verb isEqualToString:@"shuffle"] ? MR.shuffle : MR.repeat;
        if (!fn || m < 1 || m > 3) { emit(@{ @"t": @"error", @"msg": @"bad mode" }); return; }
        guarded(arg2, ^{ fn(m); emit(@{ @"t": @"ack", verb: @(m), @"ok": @YES }); });
        return;
    }
    emit(@{ @"t": @"error", @"msg": [@"unknown command: " stringByAppendingString:line] });
}

__attribute__((visibility("default")))
void cranny_bridge_main(void) {
    signal(SIGPIPE, SIG_DFL);  // host gone while writing -> terminate quietly
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen MediaRemote failed\n"); exit(10); }
    MR.info = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    MR.playing = (GetBoolFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MR.pid = (GetPIDFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
    MR.client = (GetClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingClient");
    MR.reg = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MR.send = (SendFn)dlsym(h, "MRMediaRemoteSendCommand");
    MR.seek = (SetDoubleFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    MR.shuffle = (SetIntFn)dlsym(h, "MRMediaRemoteSetShuffleMode");
    MR.repeat = (SetIntFn)dlsym(h, "MRMediaRemoteSetRepeatMode");
    if (!MR.info || !MR.playing || !MR.pid || !MR.client || !MR.reg || !MR.send) {
        fprintf(stderr, "MediaRemote symbols missing\n"); exit(11);
    }
    gQ = dispatch_queue_create("cranny.media.bridge", DISPATCH_QUEUE_SERIAL);
    gDebounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQ);
    dispatch_source_set_event_handler(gDebounce, ^{ snapshot(); });
    dispatch_source_set_timer(gDebounce, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(gDebounce);

    for (NSString *name in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification" ]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(__unused NSNotification *n) { scheduleSnapshot(); }];
    }
    MR.reg(gQ);

    // stdin command channel; EOF means the host closed the pipe or died.
    NSMutableData *buf = [NSMutableData data];
    dispatch_source_t in = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, gQ);
    dispatch_source_set_event_handler(in, ^{
        char tmp[4096];
        ssize_t n = read(STDIN_FILENO, tmp, sizeof tmp);
        if (n <= 0) exit(0);
        [buf appendBytes:tmp length:(NSUInteger)n];
        if (buf.length > 65536) exit(12);  // runaway input guard
        for (;;) {
            NSRange r = [buf rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buf.length)];
            if (r.location == NSNotFound) break;
            NSString *line = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, r.location)] encoding:NSUTF8StringEncoding];
            [buf replaceBytesInRange:NSMakeRange(0, r.location + 1) withBytes:NULL length:0];
            line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (line.length) handleLine(line);
        }
    });
    dispatch_resume(in);

    // Belt and braces: if the host is SIGKILLed and stdin somehow stays open
    // (e.g. a leaked descriptor), notice re-parenting to launchd.
    dispatch_source_t orphan = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQ);
    dispatch_source_set_timer(orphan, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(orphan, ^{ if (getppid() == 1) exit(0); });
    dispatch_resume(orphan);

    emit(@{ @"t": @"hello", @"v": @1, @"pid": @(getpid()) });
    dispatch_async(gQ, ^{ snapshot(); });
    CFRunLoopRun();  // notifications are delivered via the main run loop
}
```

### `v3-service/Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaServicePoC",
    platforms: [.macOS(.v14)],
    products: [
        // Built as a dylib (SwiftPM) / embedded into Contents/Frameworks by the app; loaded only by perl/ruby.
        .library(name: "CrannyMediaBridge", type: .dynamic, targets: ["CrannyMediaBridge"]),
    ],
    targets: [
        .target(
            name: "CrannyMediaBridge",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]
        ),
        .target(name: "CrannyMedia"),
        .executableTarget(name: "mediademo", dependencies: ["CrannyMedia"]),
    ]
)
```

### `v3-service/Sources/CrannyMedia/Model.swift`

```swift
import Foundation

/// Snapshot of what is playing. Positions are anchored (elapsed @ timestamp) and
/// interpolated locally — never poll the provider to move a progress bar.
nonisolated public struct NowPlaying: Equatable, Sendable {
    public var bundleID: String?          // player app, e.g. com.spotify.client
    public var parentBundleID: String?    // hosting app for web/helper players, when reported
    public var appName: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?    // nil for live streams (MediaRemote reports +inf)
    public var elapsed: TimeInterval      // valid at `timestamp`
    public var timestamp: Date
    public var rate: Double
    public var isPlaying: Bool
    public var itemID: String?
    public var artworkID: String?
    public var shuffle: ShuffleMode?
    public var repeatMode: RepeatMode?
    public var isMusicApp: Bool

    public init(bundleID: String?, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsed: TimeInterval = 0, timestamp: Date = Date(),
                rate: Double = 1, isPlaying: Bool, itemID: String? = nil) {
        self.bundleID = bundleID; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.elapsed = elapsed; self.timestamp = timestamp
        self.rate = rate; self.isPlaying = isPlaying; self.itemID = itemID; self.isMusicApp = false
    }

    public func position(at now: Date = Date()) -> TimeInterval {
        let speed = rate > 0 ? rate : 1
        let p = isPlaying ? elapsed + now.timeIntervalSince(timestamp) * speed : elapsed
        return max(0, duration.map { min(p, $0) } ?? p)
    }

    /// Identity used for "track changed" (peek) and the artwork/palette cache.
    public var trackKey: String { itemID ?? [bundleID ?? "", title, artist ?? "", album ?? ""].joined(separator: "|") }
}

nonisolated public enum ShuffleMode: Int, Sendable { case off = 1, albums = 2, tracks = 3 }
nonisolated public enum RepeatMode: Int, Sendable { case off = 1, one = 2, all = 3 }

nonisolated public enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, skipForward15, skipBackward15
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

nonisolated public enum ProviderEvent: Sendable {
    case nowPlaying(NowPlaying?)
    case artwork(trackKey: String, data: Data)
    /// The provider stopped working (helper died, not entitled, app quit...). The service decides
    /// whether to restart it with backoff or fall back to the next provider.
    case unavailable(reason: String)
}

/// One source of now-playing data + transport control.
nonisolated public protocol MediaProvider: AnyObject, Sendable {
    var name: String { get }
    var supportsArtwork: Bool { get }
    /// Starts the provider. The stream finishes after `.unavailable` or `stop()`.
    func start() -> AsyncStream<ProviderEvent>
    @discardableResult func send(_ command: MediaCommand) async -> Bool
    func stop()
}
```

### `v3-service/Sources/CrannyMedia/BridgeConnection.swift`

```swift
import Foundation
import os

/// One running bridge helper: an Apple-signed interpreter (perl, fallback ruby) that loads
/// libCrannyMediaBridge.dylib and speaks newline-delimited JSON on stdout / text commands on stdin.
/// All mutable state is confined to `queue`.
nonisolated final class BridgeConnection: @unchecked Sendable {
    enum Host: String, Sendable, CaseIterable {
        case perl = "/usr/bin/perl"
        case ruby = "/usr/bin/ruby"

        // Loader programs are passed with -e, so no script file has to be bundled or located.
        func arguments(dylib: String) -> [String] {
            switch self {
            case .perl:
                return ["-e", #"use strict; use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error() . "\n"; my $s = DynaLoader::dl_find_symbol($h, "cranny_bridge_main") or die "entry missing\n"; DynaLoader::dl_install_xsub("main::bridge", $s); bridge();"#, dylib]
            case .ruby:
                return ["-e", #"require "fiddle"; h = Fiddle.dlopen(ARGV[0]); Fiddle::Function.new(h["cranny_bridge_main"], [], Fiddle::TYPE_VOID).call"#, dylib]
            }
        }
        var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: rawValue) }
    }

    private let log = Logger(subsystem: "dev.cranny", category: "media.bridge")
    private let queue = DispatchQueue(label: "dev.cranny.media.bridge", qos: .utility)
    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private var buffer = Data()
    private var closedByUs = false
    private var gotHello = false
    private let onMessage: @Sendable ([String: Any]) -> Void
    private let onEnd: @Sendable (String) -> Void
    private(set) var pid: Int32 = 0

    init(host: Host, dylib: URL,
         onMessage: @escaping @Sendable ([String: Any]) -> Void,
         onEnd: @escaping @Sendable (String) -> Void) {
        self.onMessage = onMessage
        self.onEnd = onEnd
        process.executableURL = URL(fileURLWithPath: host.rawValue)
        process.arguments = host.arguments(dylib: dylib.path)
        // Minimal, explicit environment: nothing from the user's shell (PERL5LIB, RUBYOPT, DYLD_*).
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.qualityOfService = .utility
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    func start() throws {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self else { return }
            self.queue.async { self.consume(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [log] h in
            let d = h.availableData
            if !d.isEmpty { log.error("bridge stderr: \(String(decoding: d, as: UTF8.self), privacy: .public)") }
        }
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            guard let self else { return }
            self.queue.async { self.ended("helper exited with status \(status)") }
        }
        try process.run()
        pid = process.processIdentifier
        // Handshake watchdog: perl + dylib + MediaRemote normally say hello in ~0.4 s.
        queue.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.gotHello, !self.closedByUs else { return }
            self.process.terminate()
        }
    }

    func send(_ line: String) {
        queue.async { [self] in
            guard !closedByUs, process.isRunning else { return }
            try? stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    /// Closing stdin makes the helper exit by itself (it treats EOF as "host is gone").
    func close() {
        queue.async { [self] in
            guard !closedByUs else { return }
            closedByUs = true
            try? stdin.fileHandleForWriting.close()
            queue.asyncAfter(deadline: .now() + 1) { [process] in if process.isRunning { process.terminate() } }
        }
    }

    private func consume(_ chunk: Data) {
        if chunk.isEmpty { return }
        buffer.append(chunk)
        if buffer.count > 8 << 20 { process.terminate(); return }   // corrupt stream guard
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if obj["t"] as? String == "hello" { gotHello = true }
            onMessage(obj)
        }
    }

    private func ended(_ reason: String) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if !closedByUs { onEnd(gotHello ? reason : "no handshake (\(reason))") }
    }
}
```

### `v3-service/Sources/CrannyMedia/MediaRemoteBridgeProvider.swift`

```swift
import Foundation
import os

/// Primary provider: system-wide now playing via MediaRemote, reached through an Apple-signed
/// interpreter (mediaremoted refuses unentitled clients since macOS 15.4).
nonisolated public final class MediaRemoteBridgeProvider: MediaProvider, @unchecked Sendable {
    public enum Host: String, Sendable { case perl, ruby }

    public let name: String
    public let supportsArtwork = true
    /// Test hook: when set, commands are executed only if this PID is the elected now-playing app.
    public var commandGuardPID: Int32? {
        get { lock.withLock { guardPID } }
        set { lock.withLock { guardPID = newValue } }
    }
    public var helperPID: Int32 { lock.withLock { connection?.pid ?? 0 } }

    private let host: BridgeConnection.Host
    private let dylib: URL
    private let lock = NSLock()
    private var connection: BridgeConnection?
    private var guardPID: Int32?
    private var lastTrackKey: String?

    /// Returns nil when the interpreter or the bridge library is missing, so the service
    /// moves on to the next provider immediately.
    public init?(host: Host = .perl, dylib: URL = MediaRemoteBridgeProvider.defaultDylibURL) {
        self.host = host == .perl ? .perl : .ruby
        self.dylib = dylib
        self.name = "MediaRemote via \(host.rawValue)"
        guard self.host.isAvailable, FileManager.default.fileExists(atPath: dylib.path) else { return nil }
    }

    /// App: Contents/Frameworks/libCrannyMediaBridge.dylib. SwiftPM tools: next to the executable.
    public static var defaultDylibURL: URL {
        let name = "libCrannyMediaBridge.dylib"
        if let fw = Bundle.main.privateFrameworksURL?.appendingPathComponent(name),
           FileManager.default.fileExists(atPath: fw.path) { return fw }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent(name)
    }

    public func start() -> AsyncStream<ProviderEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self, bufferingPolicy: .bufferingNewest(32))
        let conn = BridgeConnection(host: host, dylib: dylib,
            onMessage: { [weak self] obj in
                guard let self else { return }
                for e in self.events(from: obj) { continuation.yield(e) }
            },
            onEnd: { reason in
                continuation.yield(.unavailable(reason: reason))
                continuation.finish()
            })
        lock.withLock { connection = conn }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        do { try conn.start() } catch {
            continuation.yield(.unavailable(reason: "cannot spawn \(host.rawValue): \(error)"))
            continuation.finish()
        }
        return stream
    }

    public func send(_ command: MediaCommand) async -> Bool {
        let line: String
        switch command {
        case .play: line = "cmd 0"
        case .pause: line = "cmd 1"
        case .togglePlayPause: line = "cmd 2"
        case .nextTrack: line = "cmd 4"
        case .previousTrack: line = "cmd 5"
        case .skipBackward15: line = "cmd 12"
        case .skipForward15: line = "cmd 13"
        case .seek(let t): line = String(format: "seek %.3f", max(0, t))
        case .setShuffle(let m): line = "shuffle \(m.rawValue)"
        case .setRepeat(let m): line = "repeat \(m.rawValue)"
        }
        let (conn, g) = lock.withLock { (connection, guardPID) }
        guard let conn else { return false }
        conn.send(g.map { "\(line) \($0)" } ?? line)
        return true
    }

    public func stop() {
        let conn = lock.withLock { () -> BridgeConnection? in defer { connection = nil }; return connection }
        conn?.close()
    }

    // MARK: JSON -> events
    private func events(from o: [String: Any]) -> [ProviderEvent] {
        switch o["t"] as? String {
        case "state":
            guard let title = o["title"] as? String, !title.isEmpty, (o["pid"] as? Int ?? 0) > 0 else {
                lock.withLock { lastTrackKey = nil }
                return [.nowPlaying(nil)]
            }
            var np = NowPlaying(bundleID: o["bundleIdentifier"] as? String, title: title,
                                artist: (o["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                album: (o["album"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                duration: (o["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil },
                                elapsed: o["elapsed"] as? Double ?? 0,
                                timestamp: (o["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
                                rate: o["rate"] as? Double ?? 0,
                                isPlaying: o["playing"] as? Bool ?? false,
                                itemID: (o["itemID"] as? String).flatMap { $0.isEmpty ? nil : $0 })
            np.parentBundleID = o["parentApplicationBundleIdentifier"] as? String
            np.appName = o["displayName"] as? String
            np.artworkID = o["artworkID"] as? String
            np.shuffle = (o["shuffle"] as? Int).flatMap(ShuffleMode.init(rawValue:))
            np.repeatMode = (o["repeat"] as? Int).flatMap(RepeatMode.init(rawValue:))
            np.isMusicApp = o["isMusicApp"] as? Bool ?? false
            lock.withLock { lastTrackKey = np.trackKey }
            return [.nowPlaying(np)]
        case "artwork":
            guard let b64 = o["data"] as? String, let data = Data(base64Encoded: b64) else { return [] }
            let item = o["itemID"] as? String ?? ""
            let key: String? = item.isEmpty ? lock.withLock { lastTrackKey } : item
            guard let key else { return [] }
            return [.artwork(trackKey: key, data: data)]
        default:
            return []   // hello / ack / pong / error: diagnostics only
        }
    }
}
```

### `v3-service/Sources/CrannyMedia/MediaService.swift`

```swift
import CoreGraphics
import Foundation
import Observation
import os

/// App-facing media facade. UI binds to it; it owns provider selection, restart/backoff,
/// failover, artwork decoding/palette and "track changed" signalling for the notch peek.
@MainActor @Observable
public final class MediaService {
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: CGImage?
    public private(set) var palette: ArtworkPalette?
    public private(set) var providerName: String?
    /// Increments on every new track (UI: `.onChange(of: media.trackChangeCount) { peek() }`).
    public private(set) var trackChangeCount = 0
    public private(set) var lastError: String?
    /// Settings: players to ignore (e.g. a browser) - applied before anything reaches the UI.
    public var ignoredBundleIDs: Set<String> = []

    public typealias ProviderFactory = @MainActor () -> (any MediaProvider)?
    @ObservationIgnored private let factories: [ProviderFactory]
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var provider: (any MediaProvider)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var failures: [Date] = []
    @ObservationIgnored private var lastTrackKey: String?
    @ObservationIgnored private var artCache: [String: (CGImage, ArtworkPalette?)] = [:]
    @ObservationIgnored private var artOrder: [String] = []
    @ObservationIgnored private let log = Logger(subsystem: "dev.cranny", category: "media")

    /// Providers in priority order, e.g. [perl bridge, ruby bridge, AppleScript].
    public init(providers: [ProviderFactory]) { factories = providers }

    public var activeProvider: (any MediaProvider)? { provider }

    public func start() { activate(0) }

    public func stop() {
        pump?.cancel(); pump = nil
        provider?.stop(); provider = nil
        providerName = nil
    }

    /// Optimistic update for instant UI feedback; the provider's next state event is authoritative.
    @discardableResult
    public func send(_ command: MediaCommand) async -> Bool {
        if var np = nowPlaying {
            let now = Date()
            switch command {
            case .togglePlayPause, .play, .pause:
                np.elapsed = np.position(at: now); np.timestamp = now
                np.isPlaying = command == .play ? true : command == .pause ? false : !np.isPlaying
                nowPlaying = np
            case .seek(let t):
                np.elapsed = t; np.timestamp = now; nowPlaying = np
            default: break
            }
        }
        return await provider?.send(command) ?? false
    }

    // MARK: - Provider lifecycle
    private func activate(_ i: Int) {
        pump?.cancel()
        guard i < factories.count else {
            providerName = nil; apply(nil)
            lastError = "No media provider available"
            return
        }
        index = i
        guard let p = factories[i]() else { activate(i + 1); return }   // not installed / not applicable
        provider = p
        providerName = p.name
        let stream = p.start()
        pump = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: ProviderEvent) {
        switch event {
        case .nowPlaying(let np): apply(np)
        case .artwork(let key, let data): Task { await self.loadArtwork(key: key, data: data) }
        case .unavailable(let reason): providerFailed(reason)
        }
    }

    private func providerFailed(_ reason: String) {
        log.error("provider \(self.providerName ?? "?", privacy: .public) unavailable: \(reason, privacy: .public)")
        lastError = reason
        provider?.stop(); provider = nil
        let now = Date()
        failures = failures.filter { now.timeIntervalSince($0) < 60 } + [now]
        if failures.count >= 3 {               // flapping: give up on this provider, use the next one
            failures = []
            activate(index + 1)
            return
        }
        let delay: Duration = [.milliseconds(500), .seconds(2), .seconds(8)][failures.count - 1]
        let i = index
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.provider == nil, self.index == i else { return }
            self.activate(i)
        }
    }

    // MARK: - State
    private func apply(_ incoming: NowPlaying?) {
        let np = incoming.flatMap { ignoredBundleIDs.contains($0.bundleID ?? "") ? nil : $0 }
        if np?.trackKey != lastTrackKey {
            lastTrackKey = np?.trackKey
            if np != nil { trackChangeCount += 1 }
            let cached = np.flatMap { artCache[$0.trackKey] }
            artwork = cached?.0
            palette = cached?.1
        }
        if nowPlaying != np { nowPlaying = np }
    }

    private func loadArtwork(key: String, data: Data) async {
        if let hit = artCache[key] { if key == lastTrackKey { artwork = hit.0; palette = hit.1 }; return }
        let decoded = await Task.detached(priority: .utility) { ArtworkPalette.decode(data) }.value
        guard let decoded else { return }
        artCache[key] = (decoded.image, decoded.palette)
        artOrder.append(key)
        if artOrder.count > 16 { artCache[artOrder.removeFirst()] = nil }
        if key == lastTrackKey { artwork = decoded.image; palette = decoded.palette }
    }
}
```

### `v3-service/Sources/CrannyMedia/AppleScriptProvider.swift`

```swift
import AppKit
import Foundation

/// Fallback provider for Music.app and Spotify when the MediaRemote bridge is unavailable.
/// - Metadata/state: distributed notifications (no permission needed).
/// - Commands, position, artwork: Apple Events (Automation permission; needs
///   NSAppleEventsUsageDescription + com.apple.security.automation.apple-events under hardened runtime).
/// Never launches a player: every Apple Event is gated on the app already running.
nonisolated public final class AppleScriptProvider: MediaProvider, @unchecked Sendable {
    public struct Player: Sendable {
        let bundleID: String
        let notification: String
        let durationKey: String     // milliseconds in both apps' userInfo (UNVERIFIED for Spotify)
        let artworkScript: String
        public static let music = Player(bundleID: "com.apple.Music", notification: "com.apple.Music.playerInfo",
                                         durationKey: "Total Time",
                                         artworkScript: "get raw data of artwork 1 of current track")
        public static let spotify = Player(bundleID: "com.spotify.client", notification: "com.spotify.client.PlaybackStateChanged",
                                           durationKey: "Duration",
                                           artworkScript: "get artwork url of current track")
    }

    public let name = "AppleScript (Music, Spotify)"
    public let supportsArtwork = true
    private let players: [Player]
    private let useAppleEvents: Bool
    private var observers: [any NSObjectProtocol] = []
    private var current: Player?
    private var continuation: AsyncStream<ProviderEvent>.Continuation?

    /// `useAppleEvents == false` keeps it permission-free (metadata only, no artwork/position/commands).
    public init(players: [Player] = [.music, .spotify], useAppleEvents: Bool) {
        self.players = players
        self.useAppleEvents = useAppleEvents
    }

    public func start() -> AsyncStream<ProviderEvent> {
        let (stream, cont) = AsyncStream.makeStream(of: ProviderEvent.self, bufferingPolicy: .bufferingNewest(16))
        continuation = cont
        let center = DistributedNotificationCenter.default()
        for player in players {
            observers.append(center.addObserver(forName: Notification.Name(player.notification), object: nil, queue: .main) { [weak self] note in
                let info = Snapshot(note.userInfo ?? [:], durationKey: player.durationKey)
                MainActor.assumeIsolated { self?.handle(player, info) }
            })
        }
        return stream
    }

    /// Sendable copy of the notification payload (userInfo itself is not Sendable).
    struct Snapshot: Sendable {
        var state: String, title: String?, artist: String?, album: String?, durationMs: Double?, position: Double?, id: String?
        init(_ u: [AnyHashable: Any], durationKey: String) {
            state = u["Player State"] as? String ?? "Stopped"; title = u["Name"] as? String
            artist = u["Artist"] as? String; album = u["Album"] as? String
            durationMs = u[durationKey] as? Double; position = u["Playback Position"] as? Double
            id = (u["PersistentID"] ?? u["Track ID"]).map { "\($0)" }
        }
    }

    @MainActor private func handle(_ player: Player, _ info: Snapshot) {
        let state = info.state
        guard state != "Stopped", let title = info.title else {
            if current?.bundleID == player.bundleID { current = nil; continuation?.yield(.nowPlaying(nil)) }
            return
        }
        current = player
        var np = NowPlaying(bundleID: player.bundleID, title: title,
                            artist: info.artist, album: info.album,
                            duration: info.durationMs.map { $0 / 1000 },
                            elapsed: info.position ?? 0,
                            isPlaying: state == "Playing",
                            itemID: info.id)
        np.isMusicApp = true
        if useAppleEvents, let pos = run("player position", in: player)?.doubleValue {
            np.elapsed = pos; np.timestamp = Date()
        }
        continuation?.yield(.nowPlaying(np))
        if useAppleEvents, let art = run(player.artworkScript, in: player) {
            if !art.data.isEmpty, art.descriptorType != typeUnicodeText, art.descriptorType != typeUTF8Text {
                continuation?.yield(.artwork(trackKey: np.trackKey, data: art.data))   // Music: raw image bytes
            } else if let s = art.stringValue, let url = URL(string: s), url.scheme == "https" {
                let key = np.trackKey, cont = continuation                               // Spotify: artwork URL
                Task.detached { if let (d, _) = try? await URLSession.shared.data(from: url) { cont?.yield(.artwork(trackKey: key, data: d)) } }
            }
        }
    }

    public func send(_ command: MediaCommand) async -> Bool {
        guard useAppleEvents else { return false }
        return await MainActor.run {
            guard let p = current else { return false }
            let verb: String
            switch command {
            case .play: verb = "play"
            case .pause: verb = "pause"
            case .togglePlayPause: verb = "playpause"
            case .nextTrack: verb = "next track"
            case .previousTrack: verb = "previous track"
            case .skipForward15: verb = "set player position to (player position + 15)"
            case .skipBackward15: verb = "set player position to (player position - 15)"
            case .seek(let t): verb = "set player position to \(t)"
            case .setShuffle(let m): verb = p.bundleID == Player.music.bundleID ? "set shuffle enabled to \(m != .off)" : "set shuffling to \(m != .off)"
            case .setRepeat(let m): verb = p.bundleID == Player.music.bundleID ? "set song repeat to \(m == .one ? "one" : m == .all ? "all" : "off")" : "set repeating to \(m != .off)"
            }
            return run(verb, in: p) != nil
        }
    }

    public func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers = []
        continuation?.finish()
    }

    /// NSAppleScript on the main thread with a short Apple Event timeout; never launches the target.
    @MainActor private func run(_ body: String, in player: Player) -> NSAppleEventDescriptor? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else { return nil }
        let source = "with timeout of 2 seconds\ntell application id \"\(player.bundleID)\" to \(body)\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        // errAEEventNotPermitted (-1743) = user denied Automation; surface in Settings, do not retry in a loop.
        return error == nil ? result : nil
    }
}
```

### `v3-service/Sources/CrannyMedia/ArtworkPalette.swift`

```swift
import CoreGraphics
import Foundation
import ImageIO

/// sRGB color as plain floats so palettes are Sendable and cheap to compare/cache.
nonisolated public struct RGB: Equatable, Sendable {
    public var r, g, b: Float
    public var cgColor: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }
}

/// Colors for the glow / visualizer / mesh background. ~0.3 ms total for a 600 px JPEG (decode dominates).
nonisolated public struct ArtworkPalette: Equatable, Sendable {
    public var average: RGB     // what CIAreaAverage would give (often muddy) - kept for reference only
    public var dominant: RGB    // largest perceptual cluster
    public var accent: RGB      // most colorful populous cluster, lightness/chroma clamped to glow on black
    public var secondary: RGB   // second accent for gradients
    public var isDark: Bool

    /// Decodes a small thumbnail straight from the artwork bytes and extracts the palette.
    public static func decode(_ data: Data, maxPixel: Int = 512) -> (image: CGImage, palette: ArtworkPalette?)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return (image, make(from: image))
    }

    public static func make(from image: CGImage, side: Int = 24, k: Int = 5) -> ArtworkPalette? {
        let n = side * side
        var px = [UInt8](repeating: 0, count: n * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        var pts = [Lab](); pts.reserveCapacity(n)
        var sr: Float = 0, sg: Float = 0, sb: Float = 0
        for i in 0..<n {
            let r = Float(px[i * 4]) / 255, g = Float(px[i * 4 + 1]) / 255, b = Float(px[i * 4 + 2]) / 255
            sr += r; sg += g; sb += b
            pts.append(Lab(r: r, g: g, b: b))
        }
        let avg = Lab(r: sr / Float(n), g: sg / Float(n), b: sb / Float(n))
        let byL = pts.sorted { $0.L < $1.L }
        var centers = (0..<k).map { byL[min(n - 1, (2 * $0 + 1) * n / (2 * k))] }   // deterministic seeds
        var counts = [Int](repeating: 0, count: k)
        for _ in 0..<8 {
            var acc = [Lab](repeating: Lab(L: 0, a: 0, b: 0), count: k)
            counts = [Int](repeating: 0, count: k)
            for p in pts {
                var best = 0, bestD = Float.greatestFiniteMagnitude
                for c in 0..<k { let d = p.distance2(centers[c]); if d < bestD { bestD = d; best = c } }
                counts[best] += 1; acc[best].L += p.L; acc[best].a += p.a; acc[best].b += p.b
            }
            for c in 0..<k where counts[c] > 0 { let f = Float(counts[c]); centers[c] = Lab(L: acc[c].L / f, a: acc[c].a / f, b: acc[c].b / f) }
        }
        let byCount = (0..<k).sorted { counts[$0] > counts[$1] }
        func score(_ c: Int) -> Float {
            guard counts[c] * 100 >= 3 * n else { return 0 }                         // ignore specks
            let lightOK: Float = (centers[c].L < 0.2 || centers[c].L > 0.97) ? 0.15 : 1  // de-prioritise black/white
            return (0.02 + centers[c].chroma) * Float(counts[c]).squareRoot() * lightOK
        }
        let ranked = (0..<k).sorted { score($0) > score($1) }
        let second = score(ranked[1]) > 0 ? ranked[1] : byCount[0]
        return ArtworkPalette(average: avg.rgb, dominant: centers[byCount[0]].rgb,
                              accent: centers[ranked[0]].glowSafe(minL: 0.68).rgb,
                              secondary: centers[second].glowSafe(minL: 0.55).rgb, isDark: avg.L < 0.5)
    }
}

/// OKLab (Björn Ottosson's published formulas); perceptual space for clustering and clamping.
nonisolated struct Lab {
    var L, a, b: Float
    init(L: Float, a: Float, b: Float) { self.L = L; self.a = a; self.b = b }
    init(r: Float, g: Float, b: Float) {
        func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let l = cbrtf(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        let m = cbrtf(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        let s = cbrtf(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }
    var chroma: Float { (a * a + b * b).squareRoot() }
    func distance2(_ o: Lab) -> Float { let x = L - o.L, y = a - o.a, z = b - o.b; return x * x + y * y + z * z }
    /// Keep hue; clamp lightness/chroma so the color reads as a glow on pure black.
    /// Greyscale art stays neutral instead of being tinted.
    func glowSafe(minL: Float) -> Lab {
        let tL = min(max(L, minL), 0.86)
        guard chroma > 0.015 else { return Lab(L: tL, a: 0, b: 0) }
        let tC = min(max(chroma, 0.10), 0.20)
        return Lab(L: tL, a: a / chroma * tC, b: b / chroma * tC)
    }
    var rgb: RGB {
        let l = powf(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = powf(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = powf(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        func enc(_ c: Float) -> Float { let x = max(0, min(1, c)); return x <= 0.0031308 ? 12.92 * x : 1.055 * powf(x, 1 / 2.4) - 0.055 }
        return RGB(r: enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   g: enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   b: enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}
```

### `v3-viz/spectrum.swift`

```swift
// Real-spectrum pipeline for Cranny's optional "live visualizer" (original code, MIT).
//   ./spectrum bench   -> CPU cost of the analysis on synthetic audio (safe, no permissions)
//   ./spectrum tap     -> starts a REAL system-audio tap (triggers the system audio
//                         recording permission prompt; NOT run during research)
import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import os

// MARK: - Analysis (FFT -> log bands). Runs at display rate on a utility queue, not on the IO thread.
final class SpectrumAnalyzer {
    let n: Int, bands: Int
    private let setup: vDSP_DFT_Setup
    private var window: [Float], frame: [Float], re: [Float], im: [Float], outRe: [Float], outIm: [Float], mags: [Float]
    private let edges: [Int]            // FFT bin index boundaries of each band
    private(set) var levels: [Float]    // 0...1 per band, smoothed

    init(n: Int = 1024, bands: Int = 24, sampleRate: Double = 48_000, minHz: Double = 40, maxHz: Double = 16_000) {
        self.n = n; self.bands = bands
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        frame = .init(repeating: 0, count: n)
        re = .init(repeating: 0, count: n / 2); im = re; outRe = re; outIm = re; mags = re
        levels = .init(repeating: 0, count: bands)
        let binHz = sampleRate / Double(n)
        edges = (0...bands).map { i in
            let hz = minHz * pow(maxHz / minHz, Double(i) / Double(bands))   // log-spaced
            return max(1, min(n / 2 - 1, Int(hz / binHz)))
        }
    }
    deinit { vDSP_DFT_DestroySetup(setup) }

    /// `samples` = most recent `n` mono samples. Allocation-free.
    func analyze(_ samples: UnsafePointer<Float>, attack: Float = 0.6, release: Float = 0.12) {
        frame.withUnsafeMutableBufferPointer { f in
            vDSP_vmul(samples, 1, window, 1, f.baseAddress!, 1, vDSP_Length(n))
            // zrop wants the real signal split into even (re) / odd (im) samples.
            re.withUnsafeMutableBufferPointer { r in im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                    vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                }
            } }
        }
        vDSP_DFT_Execute(setup, re, im, &outRe, &outIm)
        outRe.withUnsafeMutableBufferPointer { r in outIm.withUnsafeMutableBufferPointer { i in
            var z = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
            vDSP_zvmags(&z, 1, &mags, 1, vDSP_Length(n / 2))
        } }
        for b in 0..<bands {
            let lo = edges[b], hi = max(edges[b] + 1, edges[b + 1])
            var peak: Float = 0
            mags.withUnsafeBufferPointer { vDSP_maxv($0.baseAddress! + lo, 1, &peak, vDSP_Length(hi - lo)) }
            // power -> dB, map [-60 dB, 0 dB] to [0, 1] (reference: full-scale sine through the window)
            let db = 10 * log10f(peak / Float(n * n / 16) + 1e-12)
            let target = max(0, min(1, (db + 60) / 60))
            let k = target > levels[b] ? attack : release
            levels[b] += (target - levels[b]) * k
        }
    }
}

// MARK: - Mono ring buffer written by the real-time IO proc (never blocks: try-lock, drop on contention)
final class SampleRing: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var buf: UnsafeMutablePointer<Float>
    private let cap: Int
    private var write = 0
    init(capacity: Int = 4096) { cap = capacity; buf = .allocate(capacity: capacity); buf.initialize(repeating: 0, count: capacity) }
    deinit { buf.deallocate() }
    /// Called on the HAL IO thread with interleaved stereo Float32.
    func pushStereo(_ p: UnsafePointer<Float>, frames: Int) {
        _ = lock.withLockIfAvailableUnchecked {
            for i in 0..<frames { buf[(write + i) % cap] = 0.5 * (p[2 * i] + p[2 * i + 1]) }
            write = (write + frames) % cap
        }
    }
    /// Copies the latest `count` samples (oldest first) into `out`.
    func latest(_ count: Int, into out: UnsafeMutablePointer<Float>) {
        lock.withLockUnchecked {
            let start = (write - count + cap) % cap
            for i in 0..<count { out[i] = buf[(start + i) % cap] }
        }
    }
}

// MARK: - System audio tap (macOS 14.2+, needs NSAudioCaptureUsageDescription; prompts once)
@available(macOS 14.2, *)
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    let ring = SampleRing()

    struct Failure: Error { let step: String; let status: OSStatus }

    /// Taps everything that is playing except Cranny itself (robust for browsers, whose audio
    /// comes from helper/GPU processes rather than the PID MediaRemote reports).
    func start() throws {
        let own = try Self.processObject(for: getpid())
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        desc.uuid = UUID()
        desc.name = "Cranny visualizer"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { throw Failure(step: "create tap", status: status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cranny Visualizer",
            kAudioAggregateDeviceUIDKey: "dev.cranny.visualizer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw Failure(step: "create aggregate", status: status) }

        let ring = self.ring
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inData, _, _, _ in
            // Tap format is Float32 interleaved stereo for a stereo mixdown tap.
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard let b = abl.first, let p = b.mData else { return }
            ring.pushStereo(p.assumingMemoryBound(to: Float.self), frames: Int(b.mDataByteSize) / (2 * MemoryLayout<Float>.size))
        }
        guard status == noErr else { stop(); throw Failure(step: "create IO proc", status: status) }
        status = AudioDeviceStart(aggregateID, ioProc)     // permission prompt appears here the first time
        guard status == noErr else { stop(); throw Failure(step: "start", status: status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProc { AudioDeviceStop(aggregateID, ioProc); AudioDeviceDestroyIOProcID(aggregateID, ioProc) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        ioProc = nil; aggregateID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown)
    }

    static func processObject(for pid: pid_t) throws -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = pid, obj = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
        guard st == noErr else { throw Failure(step: "pid->process", status: st) }
        return obj == kAudioObjectUnknown ? nil : obj
    }
}

// MARK: - Entry
let mode = CommandLine.arguments.dropFirst().first ?? "bench"
if mode == "bench" {
    // 10 s of 48 kHz stereo: 220 Hz + 3.1 kHz tones + noise, pushed in 512-frame IO-sized chunks,
    // analysed at 60 Hz exactly like the app would.
    let sr = 48_000, chunk = 512, seconds = 10
    var stereo = [Float](repeating: 0, count: chunk * 2)
    let ring = SampleRing(), an = SpectrumAnalyzer()
    var latest = [Float](repeating: 0, count: an.n)
    var t = 0
    var analyses = 0, pushes = 0
    var nextAnalysisAt = 0
    while t < sr * seconds {
        for i in 0..<chunk {
            let x = Float(t + i) / Float(sr)
            let s = 0.5 * sinf(2 * .pi * 220 * x) + 0.2 * sinf(2 * .pi * 3100 * x) + 0.05 * Float.random(in: -1...1)
            stereo[2 * i] = s; stereo[2 * i + 1] = s
        }
        stereo.withUnsafeBufferPointer { ring.pushStereo($0.baseAddress!, frames: chunk) }
        pushes += 1
        t += chunk
        if t >= nextAnalysisAt {                       // 60 Hz analysis cadence
            latest.withUnsafeMutableBufferPointer { ring.latest(an.n, into: $0.baseAddress!) }
            latest.withUnsafeBufferPointer { an.analyze($0.baseAddress!) }
            analyses += 1
            nextAnalysisAt += sr / 60
        }
    }
    // Time only push + analyse (exclude the synthetic signal generation) with a second pass.
    let ring2 = SampleRing(), an2 = SpectrumAnalyzer()
    var pushNs: UInt64 = 0, anNs: UInt64 = 0
    for k in 0..<(sr * seconds / chunk) {
        let a = DispatchTime.now().uptimeNanoseconds
        stereo.withUnsafeBufferPointer { ring2.pushStereo($0.baseAddress!, frames: chunk) }
        let b = DispatchTime.now().uptimeNanoseconds
        pushNs += b - a
        if k * chunk * 60 / sr != (k + 1) * chunk * 60 / sr {
            let c = DispatchTime.now().uptimeNanoseconds
            latest.withUnsafeMutableBufferPointer { ring2.latest(an2.n, into: $0.baseAddress!) }
            latest.withUnsafeBufferPointer { an2.analyze($0.baseAddress!) }
            anNs += DispatchTime.now().uptimeNanoseconds - c
        }
    }
    let total = Double(pushNs + anNs) / 1e9
    print(String(format: "pushes=%d (IO callbacks), analyses=%d over %d s of audio", pushes, analyses, seconds))
    print(String(format: "IO-thread work: %.2f µs per 512-frame callback", Double(pushNs) / Double(pushes) / 1000))
    print(String(format: "analysis: %.2f µs per FFT+bands (1024 pt, 24 bands)", Double(anNs) / Double(analyses) / 1000))
    print(String(format: "=> %.3f %% of one core for push+analysis at 60 Hz", total / Double(seconds) * 100))
    let peakBand = an.levels.indices.max { an.levels[$0] < an.levels[$1] }!
    print("levels:", an.levels.map { String(format: "%.2f", $0) }.joined(separator: " "), "peak band", peakBand)
} else if mode == "tap" {
    if #available(macOS 14.2, *) {
        let tap = SystemAudioTap()
        do { try tap.start(); print("tap running; ctrl-c to stop"); dispatchMain() } catch { print("tap failed: \(error)") }
    }
}
```

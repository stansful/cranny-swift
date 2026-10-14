# Contributing to Cranny

Thank you for helping. Cranny is MIT-licensed, clean-room and dependency-free. This page is the short
version of the rules; [ARCHITECTURE.md](ARCHITECTURE.md) (§9 rules, §10 process) and [DESIGN.md](DESIGN.md)
are normative.

## Ground rules

- **Clean room.** Never copy code, assets, names or UI text from other notch apps. No GPL code. The
  word "Nook" is an internal code name only and never appears in UI text (the panel is "Cranny", the
  widget page is "Home", the pane is "Layout & Widgets").
- **Zero dependencies.** No Swift packages, vendored code, fonts, sounds, videos, GIFs or Lottie.
- **One module, one folder.** Each work package edits only its own `Sources/<Target>/…` and
  `Tests/<Target>Tests/…` (plus named files in `CrannyAppShell`). Shared files — `Package.swift`,
  `Sources/CrannyCore/**`, `App/**`, `Cranny.xcodeproj/**`, `scripts/**`, `.github/**`, `docs/**`,
  `THIRD_PARTY_NOTICES.md`, `CompositionRoot.swift`, `AppDelegate.swift`, `CrannyScenes.swift` — belong
  to the foundation owner (WP0, later WP-Final). `NotchScene.swift` and `ThemeResolver.swift` belong to
  WP12; `App/ShellContributions.swift` to WP16. Need a change there? Open a *change request*.
- **Core change requests are additive only:** a new type, a new case with a default, a new protocol
  requirement with a default implementation, a new well-known ID. No renames, removals or signature
  changes. Adding a public CrannyCore type? Run `make probe` (see below) and commit the result.
- **Branches:** one per work package (`wp/07-timer`), PRs into `main`, rebase daily. `main` is always
  green: CI runs `check-modules` + tests + `strings-check` + the name probe + a universal build + the
  smoke test + packaging.

## Toolchain

- Xcode 26+ (27 recommended; `make strings`/`strings-check` need Xcode 27's SwiftPM), Swift 6.2+.
- If `xcode-select` points at the Command Line Tools, start every manual command (including the Metal
  Toolchain install below) with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the
  scripts do it themselves. If your shell profile prints errors, run important commands one by one and
  check each exit status instead of chaining them with `&&`.
- **Metal Toolchain** component: CrannyEffects compiles `Sources/CrannyEffects/Shaders/*.metal` into
  `default.metallib`. Install once with `xcodebuild -downloadComponent MetalToolchain` (check:
  `xcodebuild -showComponent MetalToolchain` says `Status: installed`). The scripts stop with that
  command when it is missing, prefixed with the `DEVELOPER_DIR` they use. Shaders live only in
  CrannyEffects, are SwiftUI stitchable functions reached through `ShaderEffects.library`, are listed in
  `ShaderEffects.requiredFunctions` with a render test, end with `cranny::light(…, cap)` and keep a SwiftUI
  fallback (ARCHITECTURE.md D13, DESIGN.md §5.6).

## Everyday commands

```sh
make check                                   # every CrannyKit target builds alone, zero warnings (JOBS=4 to parallelize)
scripts/check-modules.sh CrannyTimer         # just your module (logs in build/logs/)
make test                                    # swift test (all test targets)
cd Packages/CrannyKit && swift test --scratch-path .build-test --filter CrannyTimerTests
make strings && make strings-check           # sync String Catalogs, then verify (add Russian first)
make probe-check                             # SDK name-collision probe is current
make build && make smoke                     # universal Release app + launch smoke test (--diagnostics)
make run                                     # Debug build + launch through LaunchServices
make dist                                    # zip + dmg + sha256 in dist/
```

Ad-hoc signed rebuilds lose privacy grants (Accessibility, Camera, Calendars…). To keep them, create a
self-signed "Cranny Dev" code-signing certificate (Keychain Access ▸ Certificate Assistant) and run
`DEV_SIGN_IDENTITY="Cranny Dev" make run`. Reset grants with `tccutil reset All app.cranny.Cranny`.

## Visual QA hooks (Debug builds only)

Debug builds accept launch arguments that force a state on the primary panel without any input, so
you can screenshot every presentation from a script. They are compiled out of Release builds
(`#if DEBUG`, `Sources/CrannyAppShell/App/QAHooks.swift`).

| Argument | Effect |
|---|---|
| `--qa-state closed\|compact\|peek\|open` | Forces that state on the primary display and holds it regardless of the pointer. `compact` and `peek` show a sample activity ("Hi"). |
| `--qa-page <page id>` | With `open`: shows that page — `nook` (Home), a module page such as `tray` once its module registers it, or a user page `page.<uuid>`. A page that does not exist opens the last page instead, as it does for users. |
| `--qa-exit-after <seconds>` | Quits after that many seconds. |
| `--qa-settings <pane id>` | Also opens Settings at that pane (`general`, `appearance`, `about`, …). |
| `-CrannyDisableShaders YES` | Forces every effect onto its SwiftUI fallback (also in Release builds: QA and energy A/B runs). |

```sh
scripts/run.sh -- --qa-state open --qa-page nook --qa-exit-after 8
```

Screenshot the panel by window id: it is the app's only window at layer 26 (find it with
`CGWindowListCopyWindowInfo`), then `screencapture -x -o -l <id> open.png`. That works even while the
screen is covered; `--diagnostics` lists which display hosts the panel (`panelScreens`).

## Engineering rules (summary of ARCHITECTURE.md §9)

**Concurrency.** UI and façades are `@MainActor` (the default isolation of every target except
CrannyCore). Persisted or cross-thread models are `nonisolated struct …: Codable, Sendable`. Leave the
main actor explicitly with `@concurrent` functions or actors; with `NonisolatedNonsendingByDefault` a
plain `nonisolated async` function still runs on the caller's actor. Dedicated threads only where an OS
API demands one (event tap, Core Audio, camera, the bridge pipe), documented at the top of the file.
`MainActor.assumeIsolated` only in callbacks documented to run on main. No Combine, no semaphores on
main; `Task.sleep` to deadlines, never repeating timers.

**Performance and energy (release gate).** Closed with nothing playing = zero work: no timers, no
`TimelineView`, no polling. Timers only while visible; effects ≤ 30 fps on AC, ≤ 20 on battery, a
static halo in Low Power Mode, paused when hidden, locked or behind full screen; Reduce Motion freezes a
resting frame. Anything redrawn more often than about twice a second takes its time from `EffectClock`
(CrannyCore), never `TimelineView(.animation(minimumInterval:))` or `.periodic`, which keep SwiftUI redrawing
at the display's refresh rate (ARCHITECTURE.md §9.2). Hardware (camera, audio tap) only while visible.
No I/O on the main actor.

**Errors and logging.** User-visible errors are localized one-liners in a `<Module>Error`; widgets show
`WidgetStateView(.error, …)` with a retry. Expected absences are not errors. Log with
`Log.logger(<category>)`, user data with `privacy: .private`. No `print`, `fatalError`, `try!`, `as!` or
force unwraps in production code; `precondition` only for programmer errors at registration.

**Style.** Swift API Design Guidelines; small files, one primary type per file; doc comments on every
`public` declaration; explicit imports (`Foundation` for `String(localized:)`, `os` for `Logger`,
`Observation` for `@Observable`). Views use tokens only (`@Environment(\.cranny)`, `crannyFont`, `Space`,
`Radius`, `theme.animation(…)`), never literal colours, sizes or animations; SF Symbols from DESIGN.md
§14.1 only. Every view file ends with `#Preview`s. Never give a public type a name an Apple framework
exports (`make probe` keeps a compile-time check of every public CrannyCore name).

**Strings.** One String Catalog per target (`Sources/<Target>/Resources/Localizable.xcstrings`). Always
pass the module bundle (`Text("…", bundle: .module, comment: "…")`, `String(localized:bundle:comment:)`);
never bare `LocalizedStringKey` initializers inside the package. Keys are the English text in sentence
case, every key has a comment `"<Surface>: <purpose>"` (one comment per key), Russian follows the
glossary in ARCHITECTURE.md §8.7 with state `translated`. Formatting through `FormatStyle` only.

**Accessibility.** Every control has a localized label, every widget is a VoiceOver container, every
live activity is one element with label, value and named actions. Nothing is hover-only. Honour Reduce
Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color through the theme.

**Testing.** Swift Testing in `Tests/<Target>Tests`. Test pure logic exhaustively; test modules alone
with `CrannyServices.preview()` and the public doubles (`PreviewNotchControl.calls`, `emit`). Tests that
need hardware or prompts are opt-in (`CRANNY_INTEGRATION=1`) and never run in CI. After touching the panel
(`Overlay/`), run `CRANNY_INTEGRATION=1 swift test --scratch-path .build-test --filter panelOnScreen`: it
shows a panel for a few seconds and re-checks R1's facts (layer 26, per-pixel pass-through, no activation)
through window-server queries, without posting input.

**Definition of done.** `scripts/check-modules.sh <YourTarget>` with zero warnings; your tests pass;
`make strings-check` with Russian for every new key; `make build && make smoke`; previews, accessibility
labels and Reduce Motion behaviour for every view; energy rules respected; settings keys documented in
your `<Module>Settings` enum; permissions declared; the package's acceptance criteria demonstrated in the
PR (a screen recording for UI).

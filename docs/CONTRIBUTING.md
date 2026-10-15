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
- **Branches:** one per work package or review fix (`wp/07-timer`, `fix/crannytray`), PRs into `main`, rebase
  daily. `main` is always green: CI runs the copy rules + `check-modules` + tests + `strings-check` + the name
  probe + a universal build + the smoke test + packaging.

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
make strings                                 # add new English keys to the String Catalogs
make l10n-pending                            # mark them pending in every language you did not translate (docs/TRANSLATING.md)
make strings-check                           # catalogs in sync + copy rules + every shipped language valid (CI)
make copy-check                              # just the copy rules (scripts/lint-copy.py, no build)
make l10n-check                              # shipped languages complete and valid (scripts/l10n/validate.py, no build)
make probe-check                             # SDK name-collision probe is current
make build && make smoke                     # universal Release app + launch smoke test (--diagnostics)
make run                                     # Debug build + launch through LaunchServices
make dist                                    # zip + dmg + sha256 in dist/
```

**Building in the Xcode app rewrites String Catalogs.** After an IDE build, Xcode's catalog editor sorts keys
its own way (case-insensitively) and may mark keys it did not see in that build as stale, while
`xcstringstool` (used by `make strings` and CI) sorts by code point. If `git status` shows catalogs you did not
mean to change, run `make strings` (or `git checkout -- '*.xcstrings'` when you added no strings) before
committing; `make strings-check` fails on IDE-sorted catalogs.

Ad-hoc signed rebuilds lose privacy grants (Accessibility, Camera, Calendars…). To keep them, create a
self-signed "Cranny Dev" code-signing certificate (Keychain Access ▸ Certificate Assistant) and run
`DEV_SIGN_IDENTITY="Cranny Dev" make run`. Reset grants with `tccutil reset All app.cranny.Cranny`.

## Visual QA hooks (Debug builds only)

Debug builds accept launch arguments that force a state without any input, so you can capture every
presentation from a script. No hook posts input or asks for a permission, and they are
compiled out of Release builds (`#if DEBUG`) except the two effect switches marked "also Release". Arguments
that start with `--qa-` are read from the command line (parsed by CrannyCore's `LaunchArguments`); `-Cranny…`
switches are `UserDefaults` arguments (`-Key value`). Each owner documents its hooks at the top of the file named in
its heading. Run the app for QA with an isolated home (`CFFIXED_USER_HOME=<temp dir>`), so a run keeps its files
(timer state, tray files, notes) out of your real `~/Library`, **and** with its own settings suite,
`--qa-defaults-suite <name>`, on every QA launch.

**The isolated home does not isolate settings; the suite does.** On macOS 27 Cranny's preferences still go to your
real `~/Library/Preferences/app.cranny.Cranny.plist` under `CFFIXED_USER_HOME`, also with
`__CFPREFERENCES_AVOID_DAEMON=1` (ARCHITECTURE.md §10.20 #29). `--qa-defaults-suite <name>` (Debug builds,
`CrannyAppShell/App/QAHooks+Defaults.swift`) makes every writer in the app use `UserDefaults(suiteName: <name>)`
instead: the settings store (so `--qa-demo`, `--qa-pause`, onboarding and Settings write there) and the Settings
window's last pane; the window's frame is not autosaved in such a run (AppKit would write it to the real domain).
Use a name of its own, such as `app.cranny.Cranny.qa`: the app's own domain or a global one is refused, and the run
then keeps its settings in memory. The suite outlives the run (`~/Library/Preferences/<name>.plist`), so a
`--qa-pause` run and a later `--qa-pause resume` run see the same pause; `defaults delete <name>` starts the next
session from the defaults (it leaves an empty `<name>.plist`, which you may delete). Seed the settings a run needs through the `UserDefaults` argument domain, which is part
of the suite's search list and never written to disk: the key is `-cranny.<module>.<name>` and the value is the
setting's JSON as plist data (`-cranny.general.demoMode '<74727565>'` is `true`). `defaults read app.cranny.Cranny`
is the same before and after a QA session (AppKit's own state, such as the menu bar item's position after a ⌘-drag,
is not Cranny's to redirect).

**Your real folders stay protected under an isolated home.** `CFFIXED_USER_HOME` also moves what
`homeDirectoryForCurrentUser` returns, so CrannyCore's `ProtectedLocations` checks the places of both homes: the
isolated one and your account's own, looked up in the user database. A QA run therefore never reads a file in your
real Desktop, Documents or Downloads on its own initiative (no Files & Folders prompt), for example a wallpaper
there for the Settings miniature or an app left in Downloads (ARCHITECTURE.md §3.13).

```sh
QA=(--qa-defaults-suite app.cranny.Cranny.qa)            # an array: bash and zsh pass it as two arguments
scripts/run.sh -- "${QA[@]}" --qa-state open --qa-page nook --qa-exit-after 8
scripts/run.sh -- "${QA[@]}" --qa-state open --qa-page nook --qa-calendar sample --qa-snapshot /tmp/open.png --qa-exit-after 6
scripts/run.sh -- "${QA[@]}" --qa-pause oneHour --qa-state closed --qa-snapshot /tmp/pause.png --qa-exit-after 5
defaults delete app.cranny.Cranny.qa                      # the next session starts from the defaults
```

**Right to left.** `-AppleLanguages "(ar)"` (or `"(he)"`) alone shows Arabic text in a left-to-right layout: AppKit
mirrors the app only with `-AppleTextDirection YES` as well. Pass both to QA Arabic and Hebrew, and `-AppleLocale ar_SA`
to see Arabic-Indic digits. Rules and tests: ARCHITECTURE.md §8.7 rule 10.

```sh
scripts/run.sh -- "${QA[@]}" -AppleLanguages "(ar)" -AppleTextDirection YES --qa-state open --qa-page nook \
  --qa-media playing --qa-calendar sample --qa-snapshot /tmp/open-ar.png --qa-exit-after 6
```

### Capturing

- **Window by id** (`screencapture -x -o -l <id> open.png`; the panel is the app's only window at layer 26, find
  it with `CGWindowListCopyWindowInfo`) works while other windows cover the panel, but **needs an awake
  display**: while the display sleeps or the session is locked, `screencapture` fails ("could not create image
  from window").
- **In-process snapshots** work while the display sleeps and need no Screen Recording access. Use them as the
  fallback: `--qa-snapshot <file.png>` (the primary panel's canvas), `--qa-snapshot <dir>` (every window: menus,
  Settings, Welcome), `--qa-capture <dir>`, `-CrannyQASnapshot <file.png>` (Settings) and
  `--qa-timer-snapshot <prefix>`. Known artifacts: the media visualizer draws a placeholder and window materials
  come out blank. A locked session also pauses the effects, so the light shows its resting frame.
- `Cranny --diagnostics <file.json>` (also Release) writes a report and quits before any window exists, without
  writing a preference: resource bundles, the media bridge, menus, shader status and renderer, and which displays
  host a panel (`panelScreens`). `make smoke` runs it, with `--qa-defaults-suite app.cranny.Cranny.smoke` (a Debug
  build then reads that suite instead of your settings; a Release build ignores the switch).

### Shell (`CrannyAppShell/App/QAHooks.swift`, `MenuBar/MenuBarQA.swift`)

| Argument | Effect |
|---|---|
| `--qa-state closed\|compact\|peek\|open` | Forces that state on the primary display and holds it regardless of the pointer. `compact` and `peek` show a sample activity ("Hi"). |
| `--qa-state calibrate` | The Appearance ▸ Notch fit outline and loupe. |
| `--qa-state keyboard` | Opens as the hot key does (takes key focus) and logs focus facts. |
| `--qa-page <page id>` | With `open`: shows that page — `nook` (Home), a module page such as `tray`, or a user page `page.<uuid>`. A page that does not exist opens the last page instead, as it does for users. |
| `--qa-close-after <seconds>` | Closes the panel that many seconds after launch and holds it closed, as `--qa-state closed` does: with `--qa-state open`, measures what an open panel leaves behind (`footprint <pid>`). |
| `--qa-reopen-after <seconds>` | With `--qa-close-after`: opens the `--qa-page` page again that many seconds after each close and closes it after the `--qa-close-after` interval, so the panel cycles until the run ends (memory that grows per open). |
| `--qa-exit-after <seconds>` | Quits after that many seconds. |
| `--qa-settings <pane id>[#<row>]` | Also opens Settings at that pane (`general`, `appearance`, `keyboard`, `nook`, `activities`, `hud`, `gestures`, `media`, `calendar`, `shortcuts`, `tray`, `permissions`, `about`); `general#hoverDelay` also scrolls to and highlights a row. |
| `--qa-capture <dir>` [`--qa-capture-after <s>`] | Writes a PNG of each visible window (the panel, Settings) after that many seconds (default 3). |
| `--qa-snapshot <file.png>` | 3 s after launch, renders the primary panel's canvas offscreen (final state, on mid-grey) to that PNG (CrannyNotchUI). |
| `--qa-snapshot <dir>` [`--qa-snapshot-at 1,3.5`] | Renders every window of the app (menus, Settings, the status item) into `<dir>` at those seconds; with `--qa-welcome` or `--qa-tutorial`, the welcome windows after 3 s. A path ending in `.png` is the canvas snapshot above. |
| `--qa-menu main\|pause\|showOn` | Opens the menu bar item's menu, or one of its submenus, after 1.5 s. A menu cannot be rendered by code, so its rows (title, ✓, disabled) are written to `qa-trace.txt` in the `--qa-snapshot` folder. |
| `--qa-defaults-suite <name>` | Keeps every setting the run writes in that suite instead of the app's preferences (see above). Use it on every QA launch. |
| `--qa-demo on\|off` | Turns Demo mode on or off after 1 s (it writes the setting: run it with `--qa-defaults-suite`). |
| `--qa-update-check` | Runs "Check for Updates…" as the menu does. |
| `--qa-open-cranny <seconds>` | Runs the menu's "Open Cranny" after that many seconds. |
| `--qa-pause oneHour\|untilTomorrow\|untilResumed\|resume` | After 1.5 s, runs that Pause Live Activities choice as the menu does, so its confirmation shows (`resume`: a silent one-hour pause, then Resume). With `--qa-state closed --qa-snapshot <file.png>` the snapshot shows the wing and the peek row; with `--qa-state open`, the confirmation in the open header. It writes `activities.pausedUntil`: run it with `--qa-defaults-suite`, and end a pause with a `resume` run in the same suite (or `defaults delete` it). |
| `--qa-show-tutorial` | Runs the menu's "Show Tutorial" after 1 s, so `--qa-menu main` shows Skip Tutorial. |
| `--qa-welcome hello\|openIt\|gestures\|preset\|permissions\|done` | Shows the Welcome window at that step; records nothing. |
| `--qa-tutorial <n>` | Starts the interactive tutorial at step n (1-based); records nothing. |

### Open panel (`CrannyNotchUI/Keyboard/NotchUIQAHooks.swift`)

| Argument | Effect |
|---|---|
| `--qa-mode palette\|edit\|focus\|catch` | With `--qa-state open`: switches the open panel to that mode once. |
| `--qa-hints` | Shows the hold-⌘ key caps as if ⌘ were held. |

### Settings window (`CrannySettingsUI/SettingsQAOptions.swift`, `CrannyAppShell/Windows/SettingsWindowController.swift`)

| Argument | Effect |
|---|---|
| `-CrannyQAStageState closed\|activity\|peek\|open\|hud` | The preview stage starts in this state on every pane. |
| `-CrannyQAKeepStageLive YES` | Keeps the live stage while the window is occluded or the screen locked (otherwise the stage is removed by design). |
| `-CrannyQASimulate songChange\|timer\|meeting\|volume\|dropFile` | Plays that Simulate chip once when the stage appears. |
| `-CrannyQASearch "<text>"` | The sidebar search field starts with this text. |
| `-CrannyQAAppearance light\|dark` | Pins the window's appearance. |
| `-CrannyQASnapshot <file.png>` [`-CrannyQASnapshotDelay <s>`] | Renders the window's own view hierarchy to a PNG after that many seconds (default 3). |
| `-CrannyQAViewReport <file.txt>` | At the same moment, writes the window's table views with their row counts and drag types. |

### Modules

Combine them with the shell's `--qa-state` (`open`, or none for the closed band) and `--qa-page`. Each replaces
the live service with samples, so nothing reaches a real player, camera, calendar or file.

| Argument | Effect |
|---|---|
| `--qa-media playing\|paused\|none` | Media: the sample track, playing or paused, or nothing playing (`CrannyMedia/Debug/MediaQA.swift`). |
| `--qa-calendar sample\|inProgress\|empty\|notDetermined\|denied\|error` | Calendar: fixtures instead of EventKit (`CrannyCalendar/Debug/CalendarQA.swift`). |
| `-CrannyQAQuickApps editing,states` | Quick Apps: edit mode; running, finished and failed shortcut tiles (`CrannyQuickApps/Support/QuickAppsQA.swift`). |
| `--qa-mirror off\|running\|toolbar\|starting\|denied\|restricted\|nocamera\|lidclosed\|failed` | Mirror: sample camera parts, no camera or prompt (`CrannyMirror/Preview/MirrorQA.swift`). |
| `--qa-notes select:<n>,rename,saveFailed,focus,delete,capture,typing` | Notes: states that otherwise need clicks or typing, comma-separated (`CrannyNotes/NotesQAHooks.swift`). |
| `-CrannyQATodosFile <path>`, `-CrannyQATodosEditing <n>\|new`, `-CrannyQATodosComplete <n>` [`-CrannyQATodosCompleteAfter <s>`] | To-dos: a throw-away list, a row being edited, a row checked off (`CrannyTodos/QA/TodosQA.swift`). |
| `--qa-timer idle\|running:<left>[/<total>]\|paused:<left>[/<total>]\|done[:<total>]\|setup:<s>` | Timer: a throw-away timer in that state (`CrannyTimer/TimerQA.swift`). |
| `--qa-timer-snapshot <prefix>` [`--qa-timer-snapshot-after <s>`] | Timer: writes every visible panel as `<prefix>-<n>.png` after that many seconds (default 3). |
| `--qa-tray-samples`, `--qa-tray-select <n>`, `--qa-tray-states`, `--qa-tray-catch <uti,…>`, `--qa-tray-quicklook`, `--qa-tray-copied`, `--qa-tray-settings-bottom` | Tray: throw-away sample files, a selection, running/failed/fresh states, the drag catch view, Quick Look, Copy paths' confirmation after 2 s (the "Copied" flash; nothing is copied), Settings ▸ Tray scrolled down (`CrannyTray/Debug/TrayQA.swift`). |
| `--qa-hud volume\|muted\|brightness\|keyboard[:<0…1>]`, `--qa-hud-fine`, `--qa-hud-device` | HUD: shows it for an hour, with fine-step ticks or a device glyph (`CrannyHUD/QA/HUDQAHook.swift`). |
| `--qa-system charging\|charged\|plugged\|unplugged\|warning\|critical\|airpods\|trackpad\|headphones` | System activities: that activity with sample data, held until quit (`CrannySystemActivities/SystemQAScenario.swift`). |

### Effects (`CrannyEffects/ShaderEffects.swift`, `EffectEnvironment.swift`)

| Argument | Effect |
|---|---|
| `-CrannyDisableShaders YES` | Every effect on its SwiftUI fallback (also Release: QA and energy A/B runs). |
| `-CrannyDisableEffectLayer YES` | The ambient light through SwiftUI shaders instead of its Metal layer (also Release: energy A/B runs). |
| `-CrannyQAEffectsAlwaysOn YES` | Keeps the light running at full quality while the screen is locked, the panel occluded or Low Power Mode on, to measure its CPU cost on a locked machine. |
| `-CrannyQAEffectsOnBattery YES` | With the above: the battery frame rate (20 fps). |

### Opt-in tests

These suites are skipped unless their variable is set, and never run in CI:

```sh
cd Packages/CrannyKit
CRANNY_INTEGRATION=1 swift test --scratch-path .build-test --filter panelOnScreen
CRANNY_SNAPSHOT_DIR=/tmp/cranny-snapshots swift test --scratch-path .build-test --filter CrannyNotchUITests.SnapshotGallery
```

**`CRANNY_INTEGRATION=1`** (tests that show a window, need hardware or the media helper):

| Suite | What it does |
|---|---|
| `CrannyAppShellTests` `panelOnScreenMatchesR1`, `aLayoutChangeDuringAPeekIsAppliedAfterIt`, `aDropOnOnePanelEndsTheDragOnTheOthers` (`PanelSelfTests.swift`) | Shows real panels for a few seconds and checks R1's facts (layer 26, per-pixel pass-through, no activation) through window-server queries, without posting input; also that a layout change during a peek is applied after it and that a drop on one panel ends the drag on the others. Run them after touching `Overlay/`. |
| `keyboardFocusIsTakenAndHandedBack` (same file) | Also needs an **unlocked** session: the panel takes key focus from the hot key and hands it back on Esc. |
| `aPanelRemovedWhileOpenClosesFirst` (`LifecycleTests.swift`) | A pinned open panel whose display goes away closes through its machine first. |
| `smallControlsTakeClicksAroundTheirVisual` (`CrannyCoreTests/DesignSystemTests.swift`) | Clicks a chip just outside its capsule and a 24-pt icon button just outside its well in an offscreen window (in-process events only). |
| Effects GPU time and resize cost (`ShaderRenderTests`, `AmbientMetalViewTests`) | Measured on every run; the limits (≤ 1.5 ms per frame, median resize < 2 ms) are asserted only here, because they depend on the GPU. |
| `BridgeIntegrationTests`, `BridgeLifetimeIntegrationTests` (CrannyMedia), with `CRANNY_MEDIA_BRIDGE=<path to libCrannyMediaBridge.dylib>` | The real helper under `/usr/bin/perl`: one answer per command (only invalid commands are sent, no player is touched), and the helper exits within 2 s of its host or of stdin closing. |
| `HUDKeyIntegrationTests`, with `CRANNY_HUD_KEYS=1` | **Changes the output volume by one step for about a second and posts synthetic key events**; the test runner needs Accessibility. Only on your own machine, on purpose. |

**Snapshot suites** (PNG files for review; nothing is asserted against them). One variable turns every one of them
on: **`CRANNY_SNAPSHOT_DIR=<dir>`**. Each test target writes into its own folder, `<dir>/<Folder>/` (Core's
`SnapshotOutput`), so one run of several suites never mixes files; pick the suites with `--filter`.
**`CRANNY_SNAPSHOT_LANGUAGE=ru`** asks the two suites that can render Russian, System activities and Tray, for it
(English otherwise). Set it only for a run of one of them; the Tray suite must run alone (see its row).

| Folder | Suite (`--filter`) | Notes |
|---|---|---|
| `NotchUI` | `CrannyNotchUITests.SnapshotGallery` | Every presentation × display × variant, plus the palette, editor, catch state and hints. |
| `Calendar` | `CalendarSnapshots` | Widget sizes, activities, Settings rows (including the Russian Join layouts). |
| `QuickApps` | `LauncherSnapshot` | The launcher in its states (real app icons, read-only). |
| `SystemActivities` | `CrannySystemActivitiesTests.SnapshotRenderTests` | Every sample in the band and the peek, the option rows; follows the language variable. |
| `Tray` | `CrannyTrayTests.SnapshotTests` | Follows the language variable, which switches the whole test process: run the Russian set alone, with exactly this filter. Never set `CRANNY_SNAPSHOT_LANGUAGE=ru` for a run that includes other Tray tests (`--filter CrannyTrayTests`, the whole package): they read the strings in English first, so the snapshot test fails and writes nothing. |
| `Todos` | `TodosSnapshotTests` | The widget's states. |
| `Notes` | `CrannyNotesTests.SnapshotGallery` | Cards with the real editor (Debug builds). |
| `Media` | `CrannyMediaTests.SnapshotRenderTests` | The widget and the Now Playing presentations. |
| `Timer`, `HUD`, `Mirror`, `Onboarding` | `TimerSnapshotTests`, `HUDRenderTests`, `MirrorResourceTests`, `RenderedSurfacesTests` | Render checks that always run; with the variable set they also write their PNGs (Onboarding: the Welcome steps and the longest tutorial bubble in every language). |

Package test processes resolve English for `String(localized:)`; the suites that render Russian say so above.

**Benchmarks:** `CRANNY_NOTES_BENCH=<file>` runs the Notes keystroke benchmark (release configuration; see the file).

`CRANNY_MEDIA_BRIDGE=<dylib>` also tells a Debug build of the app which media bridge to load (Release ignores it).

## Manual checks (each release)

Some things only a person at a Mac can check: real input, a hardware notch, permission prompts. The hardware
checklist is ARCHITECTURE.md §11.2 (item 2 covers menus from the panel; items 11–13 cover permissions, the Tray's
selection focus, the Pause Live Activities confirmation and the flash labels on a real band), and what is still
unverified is listed in ARCHITECTURE.md §10.20. Also check:

- **Live visualizer permission.** The app ships no microphone entitlement (`device.audio-input`) and no
  `NSMicrophoneUsageDescription`: the Core Audio process tap is "System Audio Recording", which needs only
  `NSAudioCaptureUsageDescription`. Confirm it on a Release build: run
  `tccutil reset AudioCapture app.cranny.Cranny`, play music, then choose Live in Settings ▸ Media. macOS should
  ask once for System Audio Recording and never for the microphone, and after you allow it the bars should follow
  the music. If they stay flat, put `com.apple.security.device.audio-input` and `NSMicrophoneUsageDescription`
  back and add the entitlement to the allow-list in `scripts/smoke.sh`.

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
never bare `LocalizedStringKey` initializers inside the package. Keys are the English text, written to
the copy rules below; every key has a comment `"<Surface>: <purpose>"` (one comment per key; a key used in
two places shares one). **New or changed English text: translate it or mark it pending, for every shipped
language** (all 35, `scripts/l10n/languages.json`). Translate the languages you know through `scripts/l10n`
(`export.py <lang> --missing-only` → `validate.py` → `import.py`; Russian follows the glossary in ARCHITECTURE.md
§8.7), then run `make l10n-pending`, which gives every language still without the key the English text in state
`needs_review`. `make strings-check` (and CI) accepts pending keys and lists them; it fails on a key a shipped
language has no entry for. The release workflow fails while any key is pending, so maintainers translate them before
a release. You never need to know 34 languages to send a pull request: docs/TRANSLATING.md ▸ New strings.
Formatting through `FormatStyle` only. A name, file name or key combination put into a sentence is
`crannyIsolated`, and layout code follows the right-to-left rules of ARCHITECTURE.md §8.7 rule 10 (leading/trailing,
media and rings left to right, physical input converted). Every count gets plural variations in the catalog (English one/other,
Russian one/few/many/other), also when English writes both forms alike; `make l10n-check` fails a count without
them. Never choose words with `count == 1` for a number that is shown.
**Translations** (every UI language macOS ships) come in through `scripts/l10n`: `export.py <lang>` writes one
JSON file for translators, `validate.py` checks it, `import.py` writes it back, `pending.py` marks what is not
translated yet, and `apple-terms.py <lang>` lists Apple's own names for Apple's apps and settings in that language.
[docs/TRANSLATING.md](TRANSLATING.md) is the guide for translators (rules, terminology sheets in
`docs/l10n/terms/`, adding a language); `scripts/l10n/README.md` documents the file format and every check.
Catalogs are JSON, so parallel branches conflict line by line; `.gitattributes` routes them to a
per-key merge driver. Enable it once per clone:

```zsh
git config merge.xcstrings.name "String Catalog union merge"
git config merge.xcstrings.driver "python3 scripts/merge-xcstrings.py %O %A %B"
```

**Copy.** These rules apply to every key and Info.plist string (the docs keep their own spelling):

- **American English**, because macOS's `en` is: color, gray, customize, behavior, license, organization,
  favorite, acknowledgment, canceled. The system's own setting names are American too ("Differentiate
  without color").
- **Sentence case** is the default: everything on the notch (buttons, chips, tooltips, its context and ⋯
  menus, ⌘K commands, live activities, confirmations inside a card), the Welcome window and the tutorial, and
  everywhere labels, switches, picker options, section headers, footnotes and VoiceOver text.
- **Title case** (macOS HIG) only in standard AppKit chrome: the menu bar item's menu, and the menu items and
  push buttons of the Settings window, its sheets, popovers and alerts. So one action can be written twice:
  "Keep Cranny Open" in the menu bar and "Keep Cranny open" on the notch; "Try Again" in a Settings sheet
  and "Try again" in a widget; "Check for Updates" (a Settings button) and "Check for updates" (a Welcome
  switch). When one key is both a menu item and a VoiceOver action, the menu decides.
- **Names keep their capitals** in either case: Cranny, Home, Tray, Quick Apps, Live Activities, Layout &
  Widgets, Settings (Cranny's window), and Apple's Quick Look, Finder, Shortcuts, System Settings, Login
  Items, Low Power Mode.
- **Typography:** ’ for apostrophes and “ ” for quotes in English (never `'` or `"`), « » in Russian; `…` as
  one character, on a command that asks for more before it acts.
- **Flash labels** (`NotchControl.flash`, the word in the compact wings) are one short word that must fit the wing
  **by measured width**, never by a character count, in every language (DESIGN.md §9.1, ruling E4). Let the
  glyph carry the meaning ("Copied" / «Готово» beside `doc.on.doc`). List every new flash call, as written, in
  `FlashLabelCatalog` (`CrannyAppShellTests`): `FlashLabelFitTests` renders each listed label at every notch unit
  from 0.8 to 1.25 and fails if one does not fit, and `everyFlashCallIsListed` fails on a call that is not listed.
  At run time a word that fits no wing leaves the glyph alone (a safety net, not a design choice). VoiceOver does
  not read the glyph, so when the word alone says too little, tell VoiceOver another way (the Tray's Copy paths
  posts "Path copied" as a feedback announcement).
- **System Settings by pane name, not by path:** "allow Cranny under Login Items in System Settings". Paths and
  pane names change between macOS versions (macOS 15 renamed General ▸ Login Items to "Login Items &
  Extensions"). Cranny's own panes may use paths: "Settings ▸ Keyboard".

`make strings-check` also runs `scripts/lint-copy.py`, which checks spelling, punctuation, System Settings
paths and the competitor denylist (ARCHITECTURE.md D20) in every catalog; case needs a reviewer.

**Accessibility.** Every control has a localized label, every widget is a VoiceOver container, every
live activity is one element with label, value and named actions. Nothing is hover-only. Honour Reduce
Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color through the theme.

**Testing.** Swift Testing in `Tests/<Target>Tests`. Test pure logic exhaustively; test modules alone
with `CrannyServices.preview()` and the public doubles (`PreviewNotchControl.calls`, `emit`). Tests that
need hardware or prompts are opt-in (`CRANNY_INTEGRATION=1`) and never run in CI. After touching the panel
(`Overlay/`), run `CRANNY_INTEGRATION=1 swift test --scratch-path .build-test --filter panelOnScreen`: it
shows a panel for a few seconds and re-checks R1's facts (layer 26, per-pixel pass-through, no activation)
through window-server queries, without posting input. The other opt-in suites are listed under Opt-in tests.
Never bound main-actor scheduling with a short real-time wait: parallel suites can keep the main actor busy for 2–3 s
while a suite starts. Wait for a signal instead, or use a generous bound (CrannyMedia's `eventually` defaults to 30 s
and returns as soon as its condition holds).

**Settings in tests and previews.** `CrannyServices.preview()` keeps its settings in memory; anything else that
needs a `UserDefaults` takes `InMemoryDefaults()` (CrannyCore). Never create a `UserDefaults(suiteName:)` in a test,
preview or sample: each suite becomes a plist in `~/Library/Preferences` as soon as one value is written, and
`removePersistentDomain(forName:)` still leaves an empty file (a Core test fails on new uses). Earlier builds left
thousands of such files behind; remove them once (works in zsh and bash):

```sh
find ~/Library/Preferences -maxdepth 1 -type f \( -name 'cranny.preview.*.plist' -o -name 'cranny.test.*.plist' \
  -o -name 'cranny.hud.tests.*.plist' -o -name 'cranny.tray.tests.*.plist' -o -name 'cranny.timer.sample.*.plist' \
  -o -name 'CrannyEffectsTests.*.plist' \) -delete
```

**Changing a default.** A setting equal to its default is never stored, so a new default silently changes every
existing user who kept the old one. Add a step to `CrannyCore/Settings/SettingsUpgrades.swift` that writes the old
value for installs from an earlier revision and bump `currentRevision` (ARCHITECTURE.md §3.11; revision 1 kept Type
to capture on Notes for existing users when the fresh-install default became Off).

**Definition of done.** `scripts/check-modules.sh <YourTarget>` with zero warnings; your tests pass;
`make strings-check` (every new key translated or pending in every shipped language, copy rules); `make build && make smoke`; previews, accessibility
labels and Reduce Motion behaviour for every view; energy rules respected; settings keys documented in
your `<Module>Settings` enum; permissions declared; the package's acceptance criteria demonstrated in the
PR (a screen recording for UI).

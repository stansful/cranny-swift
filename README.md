# Cranny

**A calm, keyboard-friendly home for the notch on your Mac.** Cranny turns the camera housing into a
small panel that grows out of the hardware: what's playing, your next meeting, a running timer, files
you're moving, volume and brightness — glanceable when closed, a full set of widgets when you open it.
Free and open source (MIT), no account, no analytics.

> **Status: early development (v0.1.0, the foundation).** This build has the notch panel itself —
> the closed cutout (or a small handle on displays without a notch), hover-to-open, the open panel with
> its grid, the menu bar item and the Settings window skeleton. The features below arrive one by one;
> see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §10 for the plan.

## Features (v1 plan)

- **Live activities in the notch** — now playing (with an honest visualizer), timers, meetings with a
  Join button, charging and low battery, AirPods and other Bluetooth accessories. Two at once: the
  second becomes a small satellite beside the notch.
- **Widgets** when you open it — Media, Calendar, Quick Apps & Shortcuts, Mirror (camera preview), Notes
  (with code mode), To-dos, Timer, AirDrop and a Files shelf, in pages you arrange yourself.
- **Tray** — drop files on the notch to keep them, AirDrop them, or run them through pipelines
  (compress, convert, resize, zip…).
- **One HUD, not two** — optional replacement for the system volume and brightness overlay.
- **Keyboard first** — ⌃⌥N opens Cranny from anywhere, ⌘K finds any action, hold ⌘ to see every shortcut.
- **Made for every Mac** — hardware-exact on notched MacBooks, a floating island on external displays,
  per-display settings, an optional ambient light layer drawn with Metal.
- **Respectful** — Reduce Motion, Increase Contrast, VoiceOver and keyboard-only use throughout;
  zero work while closed; English and Russian.

## Install

Requires **macOS 14 Sonoma or later** (Apple silicon or Intel).

1. Download `Cranny-<version>.dmg` (or `.zip`) from the GitHub Releases page.
2. Drag **Cranny** to **Applications** and open it. It lives in the menu bar; there is no Dock icon.

**"Cranny can't be opened" / "unidentified developer".** Builds that are not notarized by Apple are
blocked by Gatekeeper the first time. Either open **System Settings ▸ Privacy & Security** and click
**Open Anyway** next to the message about Cranny, or remove the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Cranny.app
```

## Build from source

You need **Xcode 26 or later** (Xcode 27 recommended; the string-catalog tooling needs 27) with its
**Metal Toolchain** component — Cranny's light effects are Metal shaders compiled at build time:

```sh
xcodebuild -downloadComponent MetalToolchain     # once; check: xcodebuild -showComponent MetalToolchain
```

Then:

```sh
git clone <this repository> Cranny && cd Cranny
make build      # universal Release build → build/Cranny.app (ad-hoc signed, no Apple account needed)
make run        # Debug build + launch
make test       # unit tests (Swift Testing)
make check      # every CrannyKit module builds on its own, with zero warnings
make help       # everything else (strings, smoke test, dist, …)
```

If `xcode-select -p` points at the Command Line Tools, the scripts find Xcode in `/Applications`
themselves. For manual `swift`, `xcodebuild` or `xcrun` commands, select it per command:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Every rebuild of an ad-hoc signed app looks like a new app to macOS privacy controls, so granted
permissions reset; see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for a stable development identity.

## Permissions FAQ

Cranny asks for a permission only when you turn on the feature that needs it, and works without all
of them. You can review everything in **Settings ▸ Permissions**.

| Permission | Asked when | Used for |
|---|---|---|
| Accessibility | You enable "Replace the system HUD" | Intercepting the volume and brightness keys so only Cranny's HUD shows |
| Calendars | You click "Show your events" in the Calendar widget | Showing upcoming events and meeting links (read-only) |
| Camera | You first click the Mirror widget | The camera preview; video is never recorded |
| Automation (Music, Spotify) | You enable the Apple Events fallback for media | Controlling those apps when the system media source is unavailable |
| System Audio Recording | You choose the "Live" visualizer | Animating the visualizer from audio levels; audio is never recorded or stored |
| Bluetooth | You enable "Show all Bluetooth devices" | Listing every connected device with its battery |

Global shortcuts, gestures and hovering need no permission.

**Why is there a process called "perl" in Activity Monitor?** That is Cranny's media helper. Since
macOS 15.4 only Apple's own system tools may read what is playing, so Cranny loads its small,
open-source bridge (`Contents/Frameworks/libCrannyMediaBridge.dylib`, source in
`Packages/CrannyKit/Sources/CrannyMediaBridge`) into the system's own `/usr/bin/perl`. The helper only
reads and controls Now Playing, talks to Cranny over a pipe, uses almost no CPU and exits when Cranny
quits. It is never installed anywhere and needs no permission.

## Privacy

- Everything stays on your Mac. Notes, to-dos and tray files live in
  `~/Library/Application Support/app.cranny.Cranny/`; settings in the app's preferences.
- No analytics, no crash reporting, no accounts, no ads.
- The only network request is the optional daily update check against this project's GitHub Releases
  page (no identifiers, no cookies). Turn it off in Settings ▸ General.

## Contributing

Bug reports and pull requests are welcome. Start with [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
(workflow, rules, how to build one module, visual QA), then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
(code structure and contracts) and [docs/DESIGN.md](docs/DESIGN.md) (every pixel, colour and animation).

## Credits

Cranny is original work by the Cranny contributors, MIT-licensed, with zero third-party code. Technique
acknowledgements are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). SF Symbols and system
frameworks are Apple's.

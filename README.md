# Cranny

**A calm, keyboard-friendly home for the notch on your Mac.** Cranny turns the camera housing into a
small panel that grows out of the hardware: what's playing, your next meeting, a running timer, files
you're moving, the volume — glanceable when closed, a full set of widgets when you open it.
Free and open source (MIT), no account, no analytics.

> **Status: 0.1.0, the first complete build.** Every feature below is implemented, reviewed and covered by about
> 1,760 unit tests, and `make dist` produces a universal app. So far it has run only on macOS 27 on an external
> display, and nobody has used it with real input yet — see [Known limitations](#known-limitations).

## Features

- **Live activities in the notch** — now playing (with an honest visualizer), timers, upcoming and running meetings
  with a Join button, charging and low battery, AirPods and other Bluetooth accessories. Two at once: the second
  becomes a small satellite beside the notch. Hover for a peek, swipe up to dismiss, pause them all from the menu bar.
- **Widgets** when you open it — Media, Calendar, Quick Apps & Shortcuts, Mirror (camera preview), Notes (with code
  mode), To-dos, Timer, AirDrop and a Files shelf, in up to four pages you arrange yourself (⌘E).
- **Tray** — drop files on the notch to keep them, AirDrop them, or run them through pipelines (compress, convert,
  resize, zip, remove background, copy text…), including chains you build yourself, with Undo.
- **One HUD, not two** — an optional replacement for the system volume overlay. Brightness and keyboard-backlight
  support is included but off by default until it has been tested on a MacBook.
- **Keyboard first** — ⌃⌥N opens Cranny from anywhere, ⌘K finds any action, hold ⌘ to see every shortcut, start typing
  to capture a note or to-do.
- **For notched MacBooks and external displays** — a shape built to match the notch, a floating island on displays
  without one, per-display settings, an optional ambient light layer drawn with Metal.
- **Settings you can see** — a live preview of the real notch views, search, per-row reset, and a Welcome window with a
  one-minute tutorial.
- **Respectful** — Reduce Motion, Reduce Transparency, Increase Contrast, keyboard-only use and VoiceOver labels and
  actions throughout; zero work while closed; English and Russian.

## Install

Requires **macOS 14 Sonoma or later** (Apple silicon or Intel; so far it has only run on macOS 27 on Apple silicon,
see [Known limitations](#known-limitations)).

1. Download `Cranny-<version>.dmg` (or `.zip`) from the GitHub Releases page (no release is published yet; until
   then, build from source below).
2. Drag **Cranny** to **Applications** and open it. It lives in the menu bar; there is no Dock icon.

**"Cranny can't be opened" / "unidentified developer".** Builds that are not notarized by Apple are
blocked by Gatekeeper the first time. Either open **System Settings ▸ Privacy & Security** and click
**Open Anyway** next to the message about Cranny, or remove the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Cranny.app
```

## Build from source

You need **Xcode 26 or later** (Xcode 27 recommended; the string-catalog tooling needs 27) with its
**Metal Toolchain** component — Cranny's light effects are Metal shaders compiled at build time.

If `xcode-select -p` points at the Command Line Tools rather than Xcode, select Xcode for the commands
you type yourself (the `make` targets find Xcode in `/Applications` on their own):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Install the Metal Toolchain once (the build stops with this command if it is missing):

```sh
xcodebuild -downloadComponent MetalToolchain     # check: xcodebuild -showComponent MetalToolchain
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

Every rebuild of an ad-hoc signed app looks like a new app to macOS privacy controls, so granted
permissions reset; see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for a stable development identity.

## Permissions FAQ

Cranny asks for a permission only when you turn on the feature that needs it, and works without all
of them. You can review everything in **Settings ▸ Permissions**.

| Permission | Asked when | Used for |
|---|---|---|
| Accessibility | You enable "Replace the system HUD", or allow it in the Welcome window | Intercepting the volume (and, if you turn them on, brightness) keys so only Cranny's HUD shows |
| Calendars | You click "Show your events" in the Calendar widget, or allow it in the Welcome window | Showing upcoming events and meeting links (read-only) |
| Camera | You first click the Mirror widget | The camera preview; video is never recorded |
| Automation (Music, Spotify; only the ones installed) | You enable the Apple Events fallback for media | Reading and controlling those apps when the system media source is unavailable |
| System Audio Recording | You choose the "Live" visualizer | Animating the visualizer from audio levels; audio is never recorded or stored |
| Bluetooth | You enable "Show all Bluetooth devices" | Listing every connected device with its battery |
| Files and Folders | Possibly, when the Tray is set to link to originals instead of copying them, or saves a pipeline result next to a file in Desktop, Documents or Downloads (by default it keeps copies) | Reading the originals and writing results there |

Global shortcuts, gestures and hovering need no permission. The Welcome window only offers the permissions your chosen
layout needs (Automation and Bluetooth only once you turn on the switch that uses them). Cranny never asks for the
microphone.

**Why is there a process called "perl" in Activity Monitor?** That is Cranny's media helper. Since
macOS 15.4 only Apple's own system tools may read what is playing, so Cranny loads its small,
open-source bridge (`Contents/Frameworks/libCrannyMediaBridge.dylib`, source in
`Packages/CrannyKit/Sources/CrannyMediaBridge`) into the system's own `/usr/bin/perl`. The helper only
reads and controls Now Playing, talks to Cranny over a pipe, uses almost no CPU, needs no permission
and exits when Cranny quits. Nothing is installed system-wide. On builds that are not notarized, macOS
quarantines the downloaded app and perl would refuse the bridge, so Cranny copies it to
`~/Library/Application Support/app.cranny.Cranny/media/` and loads that copy; deleting that folder
removes it.

## Known limitations

Cranny 0.1.0 was built and tested on one Mac (macOS 27, Apple silicon, lid closed, external display, screen locked
for most of the automated QA). So far:

- **No hardware-notch testing.** The closed shape, Notch fit and full-screen detection have never been checked
  against a real notch on a 13″, 14″ or 16″ MacBook.
- **macOS 14 and 15 are untested**, and so are **Intel Macs** (the universal binary's x86_64 half has never run) and
  Macs with two GPUs.
- **No real input yet:** hover, clicks, the ⌃⌥N hot key, keyboard focus, two-finger swipes, haptics and drags from
  other apps are covered by unit tests only.
- **No real permission grants yet:** Accessibility (HUD keys), Calendars, Camera, System Audio Recording (Live
  visualizer), Automation and Bluetooth paths, and Launch at login, have not been exercised with a granted
  permission. Brightness and keyboard-backlight HUDs stay off by default for this reason.
- **No real player control** was tried, and **VoiceOver** has not been run through the app.
- **Energy** was measured only on a Debug build (about 2–5 % CPU with the light running, depending on the display
  setup); the Instruments check on a 120-Hz MacBook is still to do.
- Builds are **ad-hoc signed and not notarized**; the **update check is off** until releases are published.

The checklists for these runs are [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §11.2 and
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) ("Manual checks"); open issues are in ARCHITECTURE.md §10.20.

## Privacy

- Everything stays on your Mac. Notes, to-dos and tray files live in
  `~/Library/Application Support/app.cranny.Cranny/`; settings in the app's preferences.
- No analytics, no crash reporting, no accounts, no ads.
- The only network request is the optional daily update check against this project's GitHub Releases
  page (no identifiers, no cookies). Turn it off in Settings ▸ General.

## Contributing

Bug reports and pull requests are welcome. Start with [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
(workflow, rules, how to build one module, visual QA), then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
(code structure and contracts) and [docs/DESIGN.md](docs/DESIGN.md) (every pixel, color and animation).

## Credits

Cranny is original work by the Cranny contributors, MIT-licensed, with zero third-party code. Technique
acknowledgements are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). SF Symbols and system
frameworks are Apple's.

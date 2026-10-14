# R1: Overlay window architecture for Cranny's notch

Research date: 2026-10-14. Target: Cranny (MIT, clean room). Deployment target: macOS 14. Tested on macOS 27.0.1 with Xcode 27.0 and Swift 6.4.
PoC: `scratchpad/poc/notch-window/`. The full file list is in section 12.

Status tags used below:
- **[VERIFIED-run]**: built with Swift 6 language mode and run on this machine. The result is in a log under `poc/notch-window/out/`.
- **[VERIFIED-SDK]**: checked in the MacOSX27 SDK headers or `.swiftinterface`, or it compiled.
- **[UNVERIFIED]**: comes from documentation or third-party reports, or was reasoned out but not reproduced here.

> **Limitation:** this Mac is a MacBook Pro (Mac16,5) running in clamshell mode. Its built-in notched display was offline, and the only screen was a 2560×1440@2x, 240 Hz external OLED.
> Everything about a hardware notch (exact `safeAreaInsets`/`auxiliaryTop*Area` values, how the notch looks) is therefore SDK-verified only. The external-display, virtual-notch, window, input and animation behaviour was verified at runtime.
> Section 10 gives a 2-minute checklist to run on a notched display.

---

## 0. Recommended architecture

1. **One overlay `NSPanel` per display, keyed by display UUID.**
   - Configure it as `NotchPanel` in section 3.1: `[.borderless, .nonactivatingPanel]` passed **at init**, level `statusBar + 1` (= 26), behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, clear and non-opaque, no window shadow.
   - Also set `hidesOnDeactivate = false`, `canBecomeKey` → true, `becomesKeyOnlyIfNeeded = true`, `animationBehavior = .none`.
   - The app runs as an agent (`LSUIElement` / `.accessory`).
2. **Fixed-size transparent canvas window.**
   - Size it once to the largest open size plus shadow padding, glued to the top edge and centred on the notch.
   - It never resizes during a morph. It is resized only when geometry or settings change (do that while closed).
   - All closed → peek → open morphing is a SwiftUI `Shape` animated with a spring. Measured: **222–238 fps on a 240 Hz display**, window frame constant.
3. **Click-through relies on the window server's per-pixel pass-through.**
   - Alpha-0 pixels pass clicks, moves and drags through. The SwiftUI `.shadow` passes through. Any drawn pixel captures, even alpha 0.001.
   - **Never write `ignoresMouseEvents = false`.** Explicitly setting it to false switches the whole window rectangle to capture mode, transparent pixels included. A root-view `hitTest` override keeps SwiftUI from reacting outside the shape.
4. **Hover is geometric, driven by global + local `NSEvent` mouse monitors.**
   - Mouse monitors need no Accessibility permission for mouse events.
   - Use a hot zone that extends above `frame.maxY` (the cursor's y can equal `maxY`) plus an open delay of about 120 ms and a close delay of about 250 ms.
   - Do not auto-close while pinned, while the panel is key (the user is typing) or during a drag.
5. **Text input without activating the app.** The panel becomes key only when a text view is clicked (`becomesKeyOnlyIfNeeded`). Typing works while the other app stays frontmost.
   - On close, give key focus back with `orderOut` + `orderFrontRegardless`. The other app's window becomes key again with no activation call.
   - Install a hidden Edit main menu so Cmd-A/C/V/X/Z work.
6. **Files Tray drag-in.**
   - A global `.leftMouseDragged` monitor checks `NSPasteboard(name: .drag)` (`changeCount` + file types) and auto-opens when a file drag nears the notch.
   - The opened shape receives the drop through an **AppKit `NSDraggingDestination`** on the panel's root view.
   - **Drag-out goes through AppKit `NSDraggingSource` with `NSURL` writers.** SwiftUI `.onDrag` hands a **temporary copy** to the receiving app (verified).
7. **Gestures.** Two-finger swipes come in as `scrollWheel` events in `NSPanel.sendEvent` (they arrive even when the panel is not key). A phase-aware recognizer fires once per touch sequence, ignores momentum and normalises natural scrolling. Haptics use `NSHapticFeedbackManager` with `.now`.
8. **Hide over full-screen apps.** Combine two public signals: the menu-bar window (layer 24) is missing from the display, and a layer-0 window of another app covers the whole display. `visibleFrame` does **not** change in full screen.

---

## 1. How it was tested

| Item | Value |
|---|---|
| OS / toolchain | macOS 27.0.1, Xcode 27.0 (27A266a), Swift 6.4, `-swift-version 6 -target arm64-apple-macos14.0` |
| Machine | Mac16,5 (M4 Max) in clamshell mode; one external MPG322UX OLED: 2560×1440 pt, 5120×2880 px, 240 Hz, backing scale 2 |
| System settings seen | Stage Manager **on** (`com.apple.WindowManager GloballyEnabled = 1`), natural scrolling on, menu bar not auto-hidden, Russian keyboard layout active |
| Build | `poc/notch-window/build.sh`: swiftc → hand-made `.app` bundle (`LSUIElement`), ad-hoc signed, plus a regular `Helper` app used as "the other app" |

**Test modes**
- `--selftest` (32/32 PASS): in-process checks plus window-server queries (`NSWindow.windowNumber(at:)`, `CGWindowListCopyWindowInfo`). It posts no system-wide input.
- `--hitprobe`: pass-through probing against real windows of other apps.
- `--keyfocus-test`: activation and key status of panel variants.
- `--fullscreen-test`: 8 level/behaviour variants while the Helper enters native full screen. Includes pixel proof (`out/fullscreen-top.png`).
- `--interaction-test`: **synthetic HID events** (`CGEvent.post(tap: .cghidEventTap)`) through the real window server.
  - Covered: hover, click-through, click-to-open, typing, focus return, scroll gestures, drag-in from the other app, drag-out to the other app, activation pitfalls.
  - Safety: it waits for user idle, tags every synthetic event with `eventSourceUserData`, aborts on untagged (real) input and types through Unicode strings.

**Caveats about the interaction runs**
- Run 1 overlapped with real user activity. Steps 1–3 were invalid there; steps 4–9 passed.
- Run 2 aborted itself correctly when it detected the user typing.
- Run 3 (steps 3 and 10, user idle) is clean.
- **Side effect in run 3:** the Helper could not bring itself to the front because Google Chrome was frontmost (see the cooperative-activation gotcha in section 8). As a result, about 6 synthetic clicks landed on a Chrome window under the test area, at points near (952, 922) and (992, 1227) in AppKit coordinates.

---

## 2. Notch geometry

### 2.1 APIs [VERIFIED-SDK]

| API | Availability | Notes |
|---|---|---|
| `NSScreen.safeAreaInsets` | macOS 12 | `.top > 0` only on displays with a camera housing. Measured: 0 on the external display [VERIFIED-run]. |
| `NSScreen.auxiliaryTopLeftArea`, `.auxiliaryTopRightArea` | macOS 12 | The Swift overlay returns **`NSRect?`**; it was `nil` on the external display [VERIFIED-run]. Header: "at the top of the screen, outside the rectangle defined by safeAreaInsets, but also unobscured". Notch = the gap between the two. |
| `NSScreen.cgDirectDisplayID` | **macOS 26** (Swift: `CGDirectDisplayID?`) | Fall back to `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]` on 14/15 [VERIFIED-run, id 5]. |
| `CGDisplayIsBuiltin(id)` | — | Returned 0 for the external display [VERIFIED-run]. |
| `CGDisplayCreateUUIDFromDisplayID` | — | Stable per-display key across reconnects and reboots (display IDs are not) [VERIFIED-run]. |
| `NSScreen.maximumFramesPerSecond`, `min/maximumRefreshInterval`, `displayLink(target:selector:)` | 12 / 12 / 14 | Measured 240 fps, interval 0.00417 [VERIFIED-run]. |
| `NSScreen.TouchCapabilities` / `touchCapabilities` | **macOS 27** (new) | Not relevant now. Worth noting that touch-capable Mac screens are on the horizon [VERIFIED-SDK]. |

Apple's documentation notes these values change with the current UI settings, so never cache them; recompute on screen-parameter changes [UNVERIFIED wording, cited by search results].

### 2.2 Geometry function (PoC `Geometry.swift`) [VERIFIED-run on the external display; notch branch VERIFIED-SDK only]

```swift
static func geometry(of screen: NSScreen, virtual spec: VirtualNotchSpec = .init()) -> DisplayGeometry {
    let id = displayID(of: screen)                     // cgDirectDisplayID on 26+, NSScreenNumber before
    let frame = screen.frame
    let safeTop = screen.safeAreaInsets.top
    let auxL = screen.auxiliaryTopLeftArea, auxR = screen.auxiliaryTopRightArea
    var notch: CGRect
    var hasNotch = false
    if safeTop > 0, let l = auxL, let r = auxR, l.width > 0, r.width > 0,
       frame.width - l.width - r.width > 0 {
        // Use only the WIDTHS: correct whichever coordinate space the aux rects use.
        let minX = frame.minX + l.width, maxX = frame.maxX - r.width
        notch = CGRect(x: minX, y: frame.maxY - safeTop, width: maxX - minX, height: safeTop)
        hasNotch = true
    } else {   // virtual notch / "handle" for displays without one
        let h = spec.height ?? menuBarHeight(of: screen)
        notch = CGRect(x: frame.midX - spec.width / 2, y: frame.maxY - h, width: spec.width, height: h)
    }
    notch = screen.backingAlignedRect(notch, options: .alignAllEdgesNearest)   // no half-pixel edges
    ...
}
```

The coordinate space of the `auxiliaryTop*Area` rects (screen-local or global) is not documented in the header [UNVERIFIED]. Using only the widths makes the code independent of that. The rest of the code assumes the notch is horizontally centred, which holds for all notched MacBook models [UNVERIFIED but universally reported].

### 2.3 Menu bar height (needed for the virtual notch) [VERIFIED-run on macOS 27]

| Source | Value on this external display |
|---|---|
| `frame.maxY - visibleFrame.maxY` | **30 pt** |
| Window Server menu-bar window (layer 24) bounds height | **30 pt** |
| `NSStatusBar.system.thickness` | **22**: stale, do not use |
| `NSApp.mainMenu?.menuBarHeight` (agent app) | nil, and `NSMenu().menuBarHeight` = 0: unusable |
| `safeAreaInsets.top` | 0 (no notch) |

- The menu bar is **30 pt** on macOS 27 on this 1440-pt-tall display. A user measured 31 px on macOS 26 versus 25 on 15, and an Apple forum post reports `safeAreaInsets.top` = 34 on a 14″ M2 Pro [UNVERIFIED].
- **Never hard-code 24.** Order of preference: (1) `safeAreaInsets.top` on notched displays; (2) `frame.maxY - visibleFrame.maxY` when greater than 0; (3) the height of the Window Server layer-24 window on that display, which works even when the menu bar auto-hides (`visibleFrame` then includes the top strip); (4) a fallback of 30.

### 2.4 Virtual notch for displays without one

- Default PoC size: 185 × menu-bar-height pt, centred.
- Make width and height user-tunable ("notch width fine-tune"). The "handle" pill uses the same footprint; a transparent handle is simply an alpha-0 fill plus geometric hover detection (section 4.2).

### 2.5 Coordinates and HiDPI [VERIFIED-run]

- AppKit global coordinates have a bottom-left origin on the primary screen. CG (`CGWindowList`, `CGEvent`) uses a top-left origin: `cgY = primaryScreenHeight - appKitMaxY`. The window-server bounds of our panel matched exactly: `cg=(932,0,696,238)`.
- **Top-edge gotcha:** with the cursor on the very top row, `NSEvent.mouseLocation.y == screen.frame.maxY` (1440.0). `CGRect.contains` excludes `maxY`, so `notchRect.contains(mouse)` was **false** there. Always expand hover rects upward (the PoC uses `insetBy(dx:-4, dy:-4)`).
- `backingAlignedRect(_:options: .alignAllEdgesNearest)` keeps shape edges on device pixels. At 2× a 0.5-pt origin is a whole pixel. Scaled "More Space" modes still report `backingScaleFactor` 2 on Apple panels, so the notch's size in points changes with the chosen resolution and must always be read from the APIs [UNVERIFIED for built-in panels].

### 2.6 Reacting to display changes [VERIFIED-SDK; listeners compiled and installed, events not triggered live]

- `NSApplication.didChangeScreenParametersNotification`: resolution, arrangement, connect/disconnect. It fires several times per change, so coalesce (PoC: 250 ms debounce).
- `CGDisplayRegisterReconfigurationCallback`: per-display flags (add/remove/mode/mirror). Ignore `.beginConfigurationFlag`.
- `NSWorkspace.screensDidWakeNotification` / `didWakeNotification` / `activeSpaceDidChangeNotification`: re-validate frames and z-order.
- **Rebuild algorithm:** for each `NSScreen` key by UUID → update the existing controller (`setFrame` only if geometry changed) or create one. Close controllers whose screen disappeared.
- **Clamshell:** a closed lid removes the built-in screen from `NSScreen.screens` entirely. Observed here: only the external display is listed, and `CGGetOnlineDisplayList` returns 1 display [VERIFIED-run].
- **Display selection setting** ("notch display only / main / all / follow mouse"): pick from `NSScreen.screens`. `NSScreen.main` means the screen with the key window, not the mouse screen; for "follow mouse" use `NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }`.

---

## 3. The window

### 3.1 Panel configuration (PoC `NotchPanel.swift`) [VERIFIED-run]

```swift
extension NSWindow.Level {
    static let notchOverlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) // 26
}

final class NotchPanel: NSPanel {
    var scrollInterceptor: ((NSEvent) -> Bool)?

    init(frame: CGRect) {
        // .nonactivatingPanel MUST be in the init style mask (see 3.5).
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true            // setter resets level to .floating(3) -> set level AFTER
        level = .notchOverlay
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // SwiftUI draws the shadow
        hidesOnDeactivate = false         // default is TRUE for most panels
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true     // buttons don't take key, text views do
        isExcludedFromWindowsMenu = true
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }    // borderless panels refuse key by default
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
    override func sendEvent(_ e: NSEvent) {
        if e.type == .scrollWheel, let f = scrollInterceptor, f(e) { return }
        super.sendEvent(e)
    }
}
```

Verified facts behind this configuration (`out/selftest.log`):

**Activation and key status**
- Ordering the panel front (`orderFrontRegardless`) does not activate the app and does not change the frontmost app.
- A borderless `NSPanel` has `canBecomeKey == false` by default, so the override is required.

**Panel defaults and setter order**
- Setting `isFloatingPanel = true` after `level = 26` resets the level to **3**.
- `hidesOnDeactivate` defaults (fresh panels): `true` for borderless, titled and titled+utility; `false` when `.nonactivatingPanel` is in the init mask. Set it to false explicitly anyway, because the app does become active while Settings or onboarding windows are open.

**Placement**
- A borderless panel can sit flush in the menu-bar strip; AppKit did not push it down.
- Window-server layer = 26 and bounds equal the requested frame.

**Hosting**
- `NSHostingView.acceptsFirstMouse` defaults to **false**. Without an override, the first click on an inactive agent app's panel is swallowed; the PoC subclass returns true.

### 3.2 Window level

Window levels and layers measured on macOS 27 [VERIFIED-run]:

| Level | Value | Who lives there (macOS 27, `CGWindowList`) |
|---|---|---|
| `.floating` | 3 | ordinary floating panels |
| Stage Manager | 17 | WindowManager |
| Dock | 20 | Dock |
| Notification Center | 21 | banners |
| `.mainMenu` | 24 | Window Server menu bar, MenuBarAgent, Siri |
| `.statusBar` | 25 | status-item windows |
| **Cranny: `.statusBar + 1`** | **26** | — |
| `.popUpMenu` | 101 | menus, including status-item menus |
| `CGWindowLevelForKey(.overlayWindow)` | 102 | — |
| (observed) | 103 | Chrome/Claude popovers |
| `.helpWindow` (tooltips) | 200 | — |
| `.draggingWindow` (drag images) | 500 | — |
| `.screenSaver` | 1000 | — |
| `.assistiveTechHigh` | 1500 | — |
| (observed) | 3000 | AccessibilityVisualsAgent |
| `CGShieldingWindowLevel()` | 2147483628 | TextInputSwitcher HUD |
| `.cursorWindow` | 2147483630 | — |

**Recommendation: 26 (`statusBar + 1`).**
- It is above the menu bar and status items, so the open Nook covers them and the closed shape sits over the menu-bar strip.
- It is below pop-up menus, so status-item menus and context menus opened over the Nook still show.
- It is below tooltips, drag images (a dragged file stays visible above the Nook) and the screen saver.
- It is below the input-source HUD and accessibility overlays.

Rejected alternatives:
- **`.floating` (3) or anything below 24.** In the full-screen pixel test, the level-3 variant was **shifted down by 30 pt out of the menu-bar strip** (`out/fullscreen-top.png`, 4th square) [VERIFIED-run]. It would also sit under the Dock, Notification Center and the menu bar.
- **`.mainMenu` (24).** It ties with the menu-bar window, so z-order between the two is undefined.
- **`.mainMenu + 3` (27), as some notch apps use.** It works (variant F visible everywhere); 26 versus 27 makes no practical difference.
- **`.screenSaver` (1000).** An Apple DTS answer on the Developer Forums (thread 826308, macOS 26) recommends it for "above full-screen apps" and claims 3 and 25 sit below full-screen content. **This was not reproduced:** for an accessory app every tested level (3, 26, 27, 1000) was drawn above another app's full-screen window [VERIFIED-run, pixel proof]. Level 1000 would also cover pop-up menus, tooltips and drag images, so it is wrong for an interactive notch.
- **`CGShieldingWindowLevel()`.** Meant for captured displays; it would sit above the input-source switcher and most system UI.

### 3.3 collectionBehavior, full screen, Spaces, Stage Manager

Full-screen test (`out/fullscreen.log` + `out/fullscreen-top.png`), [VERIFIED-run]:
- The Helper app entered native full screen at 2560×1440 on a new Space; `activeSpaceDidChange` fired.
- All 8 variants were on screen **and drawn above** the full-screen window. That includes variant B (no `.fullScreenAuxiliary`), H (`.canJoinAllSpaces` only), G (a panel without `.nonactivatingPanel`) and D (`.floating`, displaced 30 pt down).
- **What matters for an agent app is `.canJoinAllSpaces`**, not the level or `.fullScreenAuxiliary`.

Recommended set: `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` [VERIFIED-SDK semantics].
- `.canJoinAllSpaces`: present on every Space, including full-screen Spaces.
- `.stationary`: "unaffected by exposé", so the panel stays put during Mission Control. Header documents it; not triggered live [UNVERIFIED].
- `.ignoresCycle`: excluded from Cmd-` window cycling.
- `.fullScreenAuxiliary`: documented as "can be shown with the fullscreen window". It was not needed here but is cheap insurance for other configurations, such as a regular-policy app [UNVERIFIED].
- `.canJoinAllApplications` (macOS 13+) is documented for "floating windows and system overlays". It made no visible difference (variant C), so it is optional.
- At most one of managed/transient/stationary may be set, and one of fullScreenPrimary/Auxiliary/None (header).

**Stage Manager** was enabled during every test. The overlay was never moved, grouped or hidden, and its window-server bounds always matched [VERIFIED-run]. The Helper (a regular app) was managed by Stage Manager as usual.

### 3.4 Hiding over full-screen apps

There is no public API to ask whether another app is in full screen (Apple DTS, forum thread 792917). Measured signals while the Helper was in full screen [VERIFIED-run]:

| Signal | Normal desktop | Other app full screen |
|---|---|---|
| `screen.visibleFrame` | (0,0,2560,1410) | **(0,0,2560,1410), unchanged: useless** |
| Window Server layer-24 menu-bar window on this display (`CGWindowList` on-screen) | present | **absent** |
| Layer-0 window of another app whose bounds equal `CGDisplayBounds(display)` | none | **Helper** |
| Extra full-screen title-bar window | — | layer 0, bounds (0, −32, 2560, 32), parked above the screen |

```swift
// Heuristic (PoC FullscreenTest.swift). Run on activeSpaceDidChange + didActivateApplication + a slow timer.
func menuBarOnScreen(display: CGDirectDisplayID) -> Bool {
    let db = CGDisplayBounds(display)
    return windows().contains {
        ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow))
        && ($0[kCGWindowOwnerName as String] as? String) == "Window Server"
        && bounds($0).minY == db.minY && abs(bounds($0).width - db.width) < 1
    }
}
func fullDisplayWindowOwner(display: CGDirectDisplayID) -> String? {
    let db = CGDisplayBounds(display)
    for w in windows() where (w[kCGWindowLayer as String] as? Int) == 0 {
        // skip own pid, Dock, Finder (desktop) ...
        if bounds(w) == db { return w[kCGWindowOwnerName as String] as? String }
    }
    return nil
}
// isFullscreenSpace = !menuBarOnScreen && fullDisplayWindowOwner != nil   (debounce ~300 ms)
```

Caveats [UNVERIFIED]:
- On notched displays, apps that do not extend under the camera housing get a full-screen frame of `height - safeAreaInsets.top`; compare with that tolerance.
- When "Automatically hide and show the menu bar" is set to Always, the menu-bar window is also missing on normal Spaces, so the full-display-window check is what decides.
- `CGWindowListCopyWindowInfo` bounds and owner names need **no** Screen Recording permission. Only `kCGWindowName` does.
- To hide, animate the SwiftUI content to alpha 0, which automatically restores click-through, or call `orderOut`. Do **not** toggle `ignoresMouseEvents` (section 4.1).

### 3.5 Activation, key focus and text input

Measured [VERIFIED-run]: `keyfocus.log`, `selftest.log`, `interaction-run1.log` steps 4–6, `interaction-run3-steps3-10.log` step 10.

**Click-to-open and key status**
- A single click on the closed notch is delivered on the first click and opens it. The frontmost app does not change and the panel does **not** become key, thanks to `becomesKeyOnlyIfNeeded` plus `acceptsFirstMouse`.
- Clicking the SwiftUI `TextField` in the open panel **makes the panel key**. The other app stays frontmost and keeps the menu bar; its window resigns key, but the app stays active.

**Typing**
- System keyboard events reach the TextField. Run 1 typed the "o" and "k" key codes on a Russian layout and the field received "щл", so the keys arrived.
- **`NSApp.isActive` reports `true` while a non-activating panel is key**, even though `NSWorkspace.frontmostApplication` is still the other app. It returns to false after `orderOut`. Use `frontmostApplication` (or your own state), never `NSApp.isActive`, to decide "we are frontmost".

**Shortcuts need a hidden Edit menu**
- In an agent app, **Cmd-A/C/V/X/Z do nothing without a main menu**: key equivalents are resolved through `NSApp.mainMenu`. Verified in-process: no menu → selection stayed `{2,0}`; with a never-shown Edit menu → `{0,2}`.

```swift
static func makeEditMenu() -> NSMenu {   // assign once: NSApp.mainMenu = makeEditMenu()
    let main = NSMenu(), editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit; main.addItem(editItem); return main
}
```

**Returning focus on close**
- Collapsing the shape does **not** give up key status: the panel stays key and keystrokes would go to an invisible field.
- `orderOut(nil); orderFrontRegardless()` makes the panel non-key. The window server then returns key to the other app's previously focused window: the Helper logged `KEY_BECAME`. The next keystroke went to the Helper. No `activate`/`yieldActivation` call was needed.
- Ordering out and back in is invisible because it happens in the same runloop turn.

```swift
func relinquishKeyIfNeeded(_ panel: NSPanel) {
    guard panel.isKeyWindow else { return }
    panel.orderOut(nil)
    panel.orderFrontRegardless()
}
```

**Activation pitfalls (run 3, user idle, clean watchdog)** [VERIFIED-run, with the caveat below]

| Window clicked (level 26) | Our app activated by the click? |
|---|---|
| `NSPanel([.borderless, .nonactivatingPanel])` (mask at init) | **No.** The click was delivered and the panel became key (`becomesKeyOnlyIfNeeded = false` in this probe). |
| `NSPanel([.borderless])` then `styleMask.insert(.nonactivatingPanel)` | **Yes.** The late mask does not prevent activation. |
| `NSPanel([.borderless])` | Yes |
| `NSWindow([.titled])` | Yes |

Caveat: in run 1, which overlapped real user input, the late-mask and plain-panel variants did *not* activate. Treat "pass the mask at init" as a hard rule either way.

If the app ever does get activated (Settings, onboarding), go back to the previous app with `NSApp.yieldActivation(to: previousApp)` + `previousApp.activate(from: .current, options: [])` (macOS 14 cooperative activation, [VERIFIED-SDK]). Record `frontmostApplication` before activating. This restore path was not exercised end-to-end [UNVERIFIED].

---

## 4. Mouse

### 4.1 Click-through: per-pixel pass-through, and the tri-state `ignoresMouseEvents` [VERIFIED-run]

Measured with `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` (documented as "the window that would be hit by a mouse-down") and with real posted HID events (`selftest.log`, `hitprobe.log`, interaction runs).

| Probe (panel in its *default* mouse state) | Hit |
|---|---|
| Empty canvas (nothing drawn) | window below |
| SwiftUI rect filled `black.opacity(0.0)` | window below |
| filled `opacity(0.001)` | **overlay** |
| filled `opacity(0.01)`, `1.0`, the closed black shape | overlay |
| Inside the open shape's bounding box but outside its r=30 rounded corner | window below: per-pixel, not per-layer-bounds |
| Shoulder area next to the open shape's top | the **menu bar** (Window Server layer 24) |
| 2–20 pt below the open shape, inside its SwiftUI `.shadow` | window below: shadows do not capture |

Real events:
- In run 1, the Helper's tracking area, located entirely under our transparent canvas, fired `STRIP_ENTERED`/`EXITED`, so **mouse moves pass through**.
- In run 3, a real click on a transparent canvas point reached Chrome and our app received 0 mouse-downs.
- During a file drag, hovering transparent canvas pixels did **not** trigger our `draggingEntered`, so **drags pass through too**.

**`ignoresMouseEvents` behaves as a tri-state:**
- **default:** the getter returns `false`, but pass-through is per pixel.
- **`= true`:** everything passes through, opaque pixels included.
- **`= false` set explicitly:** the **whole window rectangle captures**: the empty canvas corner and the shadow then hit the overlay. Going `true → false` also leaves it capturing everything. There is no public API to return to the default state.

Recommendations:
- **Never assign `ignoresMouseEvents`** on the canvas panel. Pass-through follows whatever SwiftUI draws, including the morph mid-animation, at zero cost.
- If you need a larger invisible hit zone, for example a bigger drop or swipe zone while a drag is in progress, temporarily draw an `opacity(0.001)` fill. Remove it afterwards, because it blocks menu-bar clicks underneath.
- Keep a root-view `hitTest` override (below) so SwiftUI gestures outside the shape never fire; it does not affect window-server routing.

```swift
final class NotchRootView: NSView {
    var interactiveRect: () -> CGRect = { .zero }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

The alternative "toggle `ignoresMouseEvents` from a global mouse monitor" is rejected:
- Because of the tri-state, it must always write explicit values.
- It lags by one event when the pointer enters.
- It cannot be pixel-exact during the morph.
- Window-server pass-through already does the job.

### 4.2 Hover detection

Run 2 measurements [VERIFIED-run]:
- 17 posted moves toward the notch produced 16 events in the **global** monitor (our app was in the background), 0 in the local monitor, and **1 `mouseEntered`** from an `NSTrackingArea(.mouseEnteredAndExited, .activeAlways)` on the closed shape.
- The hover-open fired after 120 ms with `openReason == .hover`.
- Hover involves no click, so nothing can activate the app. The run-2 check "frontmost unchanged" failed only because the Helper never became frontmost in that run (see gotcha 17); it is not a hover problem.
- Global monitors miss events sent to our own windows, so install a local monitor as well. Mouse monitors need no permission; key-event global monitors need Accessibility (NSEvent.h).

**Recommendation: geometric hover from global + local monitors** (`.mouseMoved`, `*.MouseDragged`, `.leftMouseUp`), using `NSEvent.mouseLocation`.
- Hot zone: closed → notch rect + 4 pt (including above `maxY`); open → open shape + 8 pt.
- Open delay about 120 ms (settable), close delay about 250 ms.
- Do not close while `pinned`, while `panel.isKeyWindow` or while a file drag is in progress.
- Tracking areas only fire where our window receives events (opaque pixels). They are fine as a cheap secondary signal but cannot implement hysteresis zones beyond the pixels or the "handle" on a transparent virtual notch.
- Cost: monitor callbacks run on every mouse move system-wide; keep the handler O(displays) with no allocation.

The PoC handler (`Coordinator.swift`) [VERIFIED-run]:

```swift
private func pointerEvent(at p: NSPoint, kind: PointerMonitor.Kind) {
    if kind == .drag {
        let cc = dragPasteboard.changeCount
        if cc != lastDragChangeCount {          // a new drag session started somewhere
            lastDragChangeCount = cc
            let types = dragPasteboard.types ?? []
            fileDragInProgress = types.contains(.fileURL) || types.contains { $0.rawValue.contains("promise") }
        }
    } else if kind == .up { fileDragInProgress = false }

    for (key, c) in controllers {
        if kind == .drag {
            if fileDragInProgress, c.model.phase != .open, c.dragProximityScreenRect().contains(p) {
                c.model.open(.drag)               // auto-open the tray
            }
            continue
        }
        if c.hoverScreenRect().contains(p) {
            pendingClose[key]?.cancel(); pendingClose[key] = nil
            if c.model.phase == .closed, hoverToOpen { scheduleHover(key, c) }     // 120 ms
        } else {
            pendingHover[key]?.cancel(); pendingHover[key] = nil
            if c.model.phase == .open, !c.model.pinned, !c.panel.isKeyWindow, !fileDragInProgress {
                scheduleClose(key, c)                                              // 250 ms
            }
        }
    }
}
```

### 4.3 Large fixed canvas vs resizing the window per state

| | Fixed canvas (recommended) | Resize window on every state/frame |
|---|---|---|
| Morph smoothness | SwiftUI drives shape and content in one transaction: **222–238 fps** measured on 240 Hz, window frame constant [VERIFIED-run] | Window frame (window server) and content (CA commit) are separate updates; with a top-anchored window, every grow also moves `origin.y`. Expect 1-frame tearing/jitter at the edges [UNVERIFIED-reasoned] |
| Spring physics / interruption | SwiftUI springs retarget with velocity preserved when hover flips mid-animation [UNVERIFIED: documented SwiftUI spring behaviour, not measured] | Would need a hand-rolled AppKit animation that mirrors SwiftUI's spring |
| CPU | Tiny | `setFrame(display:)` + layout cost **0.13 ms avg, 1.5 ms max** per step [VERIFIED-run]: affordable, so CPU is **not** the argument |
| Click-through | Per-pixel pass-through makes the unused area free [VERIFIED-run] | Window is mostly opaque content anyway |
| Downsides | The transparent window covers part of the menu bar. Mitigated: clicks, moves and drags pass through. Also: keep the canvas only as large as the max open size + shadow, and resize it (while closed) when the user changes widget layout | — |

Optional hybrid, when memory or the menu-bar overlap must be minimal: a closed-size window that is grown to the canvas size *before* starting the open animation and shrunk *after* the close animation completes. This keeps frame changes out of the animation. Not needed given the measurements.

---

## 5. Drag & drop (Files Tray)

### 5.1 Drag-in while closed (auto-open) [VERIFIED-run, interaction-run1 step 8]

Scenario: the Helper app started an AppKit drag of a file (`NSDraggingItem(pasteboardWriter: url as NSURL)`), and the cursor was dragged to a point **beside** the closed notch, over transparent pixels only.

Results:
- Our **global** monitor received **30 `leftMouseDragged` events** from the other app's drag session.
- `NSPasteboard(name: .drag).changeCount` changed and `types` contained `public.file-url` → `fileDragInProgress = true` → the shape auto-opened (`dragDetections = 1`, `draggingEntered` not yet called).
- Moving onto the opened tray → `draggingEntered` on our root `NSView` → `performDragOperation` read the URL, and the tray received `from-other-app.txt`. The source reported `DRAG_END op=1` (copy).

Notes:
- **Privacy:** reading the *drag* pasteboard is not subject to the macOS 15.4+ paste alert. The SDK header says only the General pasteboard asks; "All other pasteboards default to always allow access" [VERIFIED-SDK]. A clipboard-history widget reading `.general` *will* trigger that alert.
- `changeCount` increases for every drag (text, images, tabs), so always check `types`. File promises (Photos, Mail attachments, Safari images) put `com.apple.NSFilePromiseItemMetaData` / `com.apple.pasteboard.promised-file-*` types on the pasteboard, which the PoC registers via `NSFilePromiseReceiver.readableDraggedTypes` [VERIFIED-run list]. Receiving promises (`receivePromisedFiles(atDestination:options:operationQueue:reader:)`) was not exercised [UNVERIFIED].

### 5.2 Drop target: AppKit vs SwiftUI

| | AppKit `NSDraggingDestination` on the panel's root view (recommended) | SwiftUI `onDrop` / `dropDestination` |
|---|---|---|
| Auto-open hook (`draggingEntered`) | yes, synchronous | `isTargeted` binding only |
| Multiple files, operations, file promises | full control (`NSFilePromiseReceiver`) | `onDrop(of:)` gives `[NSItemProvider]`; loading file promises is awkward [UNVERIFIED] |
| Registered types | exactly what you register | `onDrop(of: [.fileURL])` registered **`public.data`, `public.item`** on the hosting tree [VERIFIED-run] |
| macOS 14 availability | yes | `onDrop` 11+; `dropDestination(for:action:isTargeted:)` 13+ is **deprecated** in the 27 SDK in favour of `dropDestination(for:isEnabled:action:)` with `DropSession` (**macOS 26+**); `onDropSessionUpdated`/`dropConfiguration` 26+ [VERIFIED-SDK] |

Keep the tray *UI* in SwiftUI and drive its "targeted" highlight from the AppKit destination (`model.dropTargeted`).

### 5.3 Drag-out to Finder or other apps [VERIFIED-run, interaction-run1 step 9]

- SwiftUI `.onDrag { NSItemProvider(object: url as NSURL) }` from a non-activating, non-key panel works: the first mouse-down is accepted and the drag starts.
- **However**, the receiving app got `~/Library/Caches/com.apple.SwiftUI.Drag-<UUID>/from-other-app.txt`: a temporary copy made by SwiftUI, not the original path. Offered types included `public.file-url`, `NSFilenamesPboardType` and `public.url`.

For a Files Tray, a copy is wrong: no move semantics, a slow copy for big files, and confusing paths. **Use AppKit for drag-out:**
- Wrap each tray item in an `NSViewRepresentable` whose `NSView` starts `beginDraggingSession(with: [NSDraggingItem(pasteboardWriter: url as NSURL)], event:, source:)` in `mouseDragged`, exactly like the Helper's `SourceView` (`poc/notch-window/helper/main.swift`).
- The `NSURL` pasteboard writer offers `public.file-url` of the original file [VERIFIED-run: writer types]. The Helper's AppKit drag into our tray worked end-to-end.
- Implement `draggingSession(_:sourceOperationMaskFor:)` (`.copy` / `.move` / `.generic`), and `draggingSession(_:endedAt:operation:)` to remove an item after `.move` or when "remove after drop" is enabled.
- For generated files (converted or compressed images, zips), use `NSFilePromiseProvider` so the file is written only when dropped [UNVERIFIED in PoC].
- macOS 26 adds SwiftUI `draggable(containerItemID:)`/`dragContainer`/`onDragSessionUpdated` [VERIFIED-SDK]. They are not usable at a deployment target of 14, and whether they also copy is untested.

---

## 6. Trackpad gestures over a non-key panel

Scroll events are delivered to the window under the cursor, even when it is not key and the app is inactive. Run 1 step 7 posted phase-carrying HID scroll events over the closed notch while the Helper was frontmost and our panel was not key: one horizontal swipe gave exactly **one** gesture, and a vertical swipe gave `.down` and opened the shape [VERIFIED-run].

Recognizer (`SwipeRecognizer.swift`, pure struct, unit-testable) [VERIFIED-run with synthetic events]:

```swift
mutating func handle(_ i: Input) -> SwipeGesture? {
    if !i.momentumPhase.isEmpty { return nil }            // fingers already lifted: ignore momentum
    if i.phase.isEmpty || !i.precise { return nil }       // classic mouse wheel: not a swipe
    if i.phase.contains(.began) || i.phase.contains(.mayBegin) { accX = 0; accY = 0; firedThisSequence = false }
    if i.phase.contains(.ended) || i.phase.contains(.cancelled) { accX = 0; accY = 0; firedThisSequence = false; return nil }
    guard i.phase.contains(.changed) || i.phase.contains(.began) else { return nil }
    let sign: CGFloat = i.invertedFromDevice ? 1 : -1     // normalise to physical finger motion
    accX += i.dx * sign; accY += i.dy * sign
    guard !firedThisSequence, i.timestamp - lastFire >= cooldown else { return nil }   // cooldown 0.15 s
    // threshold 36 pt of finger travel, dominant axis >= 1.6x the other
    ...
}
```

How it behaves:
- The recognizer runs in `NotchPanel.sendEvent` and only consumes scrolls while closed or peeking. In the open state, scrolls pass to the widgets.
- Thresholds: 36 pt of accumulated `scrollingDeltaX/Y` (precise deltas), an axis-dominance ratio of 1.6, and one gesture per touch sequence (`began`…`ended`).
- Momentum is ignored and a 0.15 s cooldown applies. The cooldown is measured with event timestamps; back-to-back synthetic sequences need it.
- Diagonal drags and phase-less mouse-wheel events never fire [VERIFIED-run].
- Natural scrolling: `isDirectionInvertedFromDevice == true` means deltas already follow the fingers. The "invert track swipe" setting just flips left/right.
- Synthetic `CGEvent` scrolls map `scrollWheelEventScrollPhase` → `NSEvent.phase` correctly, so the recognizer is testable without hardware.

Haptics: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` [VERIFIED-SDK, compiled and called].
- The header says the system suppresses feedback when the user is not touching a Force Touch trackpad. Fire it exactly when the swipe is recognised (finger still down).
- Expose a setting to disable it. Physical effect not verifiable here (clamshell, no trackpad confirmed) [UNVERIFIED].
- Patterns available: `.generic`, `.alignment`, `.levelChange`.

---

## 7. SwiftUI hosting and the morph

### 7.1 Hosting setup [VERIFIED-run]

```swift
host = NotchHostingView(rootView: NotchCanvasView(model: model))  // subclass: acceptsFirstMouse -> true
host.sizingOptions = []        // macOS 13+: SwiftUI never resizes/constrains the window
host.safeAreaRegions = []      // macOS 13.3+: no menu-bar / camera-housing safe-area insets inside the canvas
host.frame = root.bounds; host.autoresizingMask = [.width, .height]
root.addSubview(host)          // root = NotchRootView (hitTest + drag destination + tracking)
panel.contentView = root
```

- `host.safeAreaInsets` measured 0 on the external display. On a notched display the canvas overlaps the camera-housing safe area, so `safeAreaRegions = []` is what prevents a 32–38 pt layout jump there [UNVERIFIED on notch hardware].
- Use `contentView` + `NSHostingView`, not `NSHostingController` as `contentViewController`. The controller's default sizing can drive the window size [UNVERIFIED-reasoned; `sizingOptions` makes both safe].
- State: an `@Observable @MainActor` model per display. AppKit side effects (updating the tracking area on phase change) use `withObservationTracking` re-armed in `onChange`, with no Combine [VERIFIED-run].

### 7.2 Morph

- `NotchShape: Shape` has the flat top glued to the screen edge, concave "shoulders" (top radius), straight sides and convex bottom corners (bottom radius). Radii animate through `animatableData`; size animates through `.frame`.
- The shape is drawn once for the fill and once for the clip: 216 `path(in:)` calls over 108 frames. Keep `path(in:)` allocation-light.
- Apply one `.animation(.spring(response: 0.38, dampingFraction: 0.82), value: phase)` at the root. Content swaps with `.transition(.opacity.combined(with: .scale(0.96, anchor: .top)))` and is clipped by the same shape, so it never spills out.
- Measured closed→open: **108 distinct frames in 449 ms ≈ 238 fps** on a 240 Hz display (an earlier run: 222 fps). The window frame stayed (932,1202,696,238) throughout [VERIFIED-run]. `NSWindow.displayLink(target:selector:)` (macOS 14) delivered 248–253 callbacks/s.
- On a ProMotion built-in panel (120 Hz, adaptive) the rate should follow the panel [UNVERIFIED].

Avoiding layout jumps:
- Lay content out at its *final* size inside a fixed-size frame and reveal it with clip and opacity, rather than letting text reflow while the frame grows.
- Use `matchedGeometryEffect` for elements that travel between peek and open (album art).
- Avoid `GeometryReader`-driven layout during the morph.
- Pin the shape's top to the canvas top (`.frame(..., alignment: .top)`).

Snapshots of the four shape states: `poc/notch-window/out/shape-{closed,peek,mid,open}.png`. Live capture: `out/open-canvas.png`.

---

## 8. Gotchas

1. **`isFloatingPanel = true` resets `level` to 3.** Set the level afterwards [VERIFIED-run].
2. **`ignoresMouseEvents` is tri-state.** An explicit `false` turns the whole window into a click catcher [VERIFIED-run].
3. **Any drawn pixel catches clicks** (alpha 0.001 included); alpha 0 and SwiftUI `.shadow` do not [VERIFIED-run].
4. **Pass `.nonactivatingPanel` at init.** Inserting it later did not stop click activation in the clean run [VERIFIED-run, see the caveat in 3.5].
5. **Borderless panels can't become key** without overriding `canBecomeKey` [VERIFIED-run].
6. **`NSHostingView.acceptsFirstMouse` is false by default.** The first click on an inactive agent app is lost unless overridden [VERIFIED-run].
7. **`NSApp.isActive == true` while our non-activating panel is key**, although the other app is still frontmost [VERIFIED-run].
8. **Agent apps need a main menu** (hidden Edit menu) for Cmd-A/C/V/X/Z in text fields [VERIFIED-run].
9. **Collapsing the Nook leaves the panel key.** Call `orderOut` + `orderFrontRegardless` to hand keyboard focus back [VERIFIED-run].
10. **`NSEvent.mouseLocation.y == frame.maxY` at the top edge.** Extend hover rects above the screen [VERIFIED-run].
11. **`NSStatusBar.system.thickness` = 22 but the menu bar is 30 pt on macOS 27.** Never hard-code 22 or 24 [VERIFIED-run].
12. **`visibleFrame` does not change in another app's full-screen Space**, so it can't be used to detect full screen [VERIFIED-run].
13. **Windows below level 24 get pushed out of the menu-bar strip** (seen in a full-screen Space) [VERIFIED-run].
14. **SwiftUI `.onDrag` with file URLs delivers a temporary copy** under `~/Library/Caches/com.apple.SwiftUI.Drag-*` [VERIFIED-run].
15. **`onDrop(of:[.fileURL])` registers `public.data`/`public.item`** on the hosting view. It is broad; prefer the AppKit destination [VERIFIED-run].
16. **The drag pasteboard `changeCount` bumps for every drag**, so filter by types [VERIFIED-run].
17. **Cooperative activation (macOS 14+):** an app launched by a background agent could not bring itself to the front while Chrome was frontmost; the Helper's `NSApp.activate()` was ignored [VERIFIED-run, observed]. Only call `NSApp.activate()` directly in response to a user click (e.g. "Open Settings…"), and expect it may still be refused [UNVERIFIED].
18. **`CGEventSource(.hidSystemState)` keeps posted modifier flags.** Use `.privateState` and set `flags` explicitly in UI tests [VERIFIED-run].
19. **Global monitors never see events delivered to our own app.** Pair them with local monitors [VERIFIED-run].
20. **`NSPanel.hidesOnDeactivate` defaults to true** (except non-activating panels): the Nook would vanish after the Settings window deactivates the app [VERIFIED-run].
21. **`sharingType = .none` is not a reliable way to hide from screen recording** on macOS 15+ (ScreenCaptureKit reports). Keep the default `.readOnly` so "demo mode" recordings work [UNVERIFIED].

---

## 9. Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Resize the window every animation frame | Frame/content desync (top-anchored window moves origin), no shared spring with SwiftUI; CPU fine (0.13 ms) but quality worse |
| Toggle `ignoresMouseEvents` from a mouse monitor | Tri-state pitfall, one-event lag, not pixel-exact; pass-through already works |
| `NSTrackingArea` as the only hover source | Fires only over opaque pixels of our window; no hysteresis zone; fine as a secondary signal |
| Level `.screenSaver` / `CGShieldingWindowLevel` | Covers menus, tooltips, drag images and system HUDs; not needed for full-screen Spaces |
| Level `.floating` / `< 24` | Under the menu bar, Dock and Notification Center; displaced out of the menu-bar strip |
| Activating `NSWindow` | Clicking it activated the app in the clean run 3 (step 10); for windows in general, an Apple DTS answer reports that ordering a regular `NSWindow` front can kick another app out of its full-screen Space [UNVERIFIED here] |
| SwiftUI `.onDrag` for tray drag-out | Temporary copy instead of the original file |
| SwiftUI `dropDestination` as tray drop target | Old variant deprecated; new one is macOS 26+; less control (promises, `draggingEntered`) |
| Private CGS/SkyLight space APIs (some notch apps use them to force visibility) | Not needed (public behaviour suffices), fragile, App Store-hostile |
| Metal shaders for the shape | Metal toolchain unavailable offline; SwiftUI Shape already renders at display rate |

---

## 10. Open risks and how to verify on a notched MacBook

**Unverified items**
1. Notch geometry on real hardware: `safeAreaInsets.top`, the widths of `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, the coordinate space of those rects, behaviour with scaled resolutions, and whether the computed notch rect covers the physical camera housing pixel-perfectly.
2. Full-screen detection on a notched display, where apps that do not use the camera-housing area get a frame shorter by `safeAreaInsets.top`.
3. Haptic feedback reaching a Force Touch trackpad from a background agent app.
4. Mission Control / Exposé behaviour with `.stationary`.
5. Real display connect/disconnect and lid open/close: listeners compiled, no events fired during testing.
6. ProMotion (120 Hz adaptive) frame rate of the morph on the built-in panel.
7. File-promise drops (Photos/Mail/Safari images) and `NSFilePromiseProvider` drag-out.
8. Run 1 vs run 3 disagreed on click activation for late-mask and plain panels; run 3 is clean, but re-check on a calm machine.
9. Restoring the previously active app after Cranny was really activated (Settings flow): `yieldActivation` + `activate(from:)`.

**Checklist on a notched Mac (lid open):**

```zsh
cd scratchpad/poc/notch-window && ./build.sh
probe/probe                                   # prints safeAreaInsets / aux areas / notch rect per screen
build/NotchPoC.app/Contents/MacOS/NotchPoC --selftest out      # 32 checks
build/NotchPoC.app/Contents/MacOS/NotchPoC --demo 30           # hover the notch, type in the field, drag a file in
build/NotchPoC.app/Contents/MacOS/NotchPoC --fullscreen-test build/Helper out/fs.png   # needs 20 s idle
```

`--interaction-test` moves the real cursor and types. Run it only on an idle machine; it waits for 8–20 s of idle time and aborts on real input. It also needs the parent process to have post-event access.

---

## 11. Suggested module boundaries for CrannyKit

- `CrannyCore/Display`: `DisplayGeometry`, `DisplayInspector` (geometry, menu-bar height, UUIDs), `DisplayMonitor` (notifications + reconfiguration callback, debounced).
- `CrannyShell/Overlay`: `NotchPanel`, `NotchRootView` (hitTest, drag destination), `NotchPanelController` (one per display), `OverlayCoordinator` (rebuild, pointer monitor, hover/close policy, drag detection, full-screen hider, focus hand-back).
- `CrannyShell/Gestures`: `SwipeRecognizer` (pure, unit-tested), haptics wrapper honouring settings.
- `CrannyUI/NotchShape`: `NotchShape`, `NotchCanvasView` (state → spec mapping, transitions).
- `CrannyTray`: AppKit drag source/destination views wrapped for SwiftUI.

---

## 12. PoC index (`scratchpad/poc/notch-window/`)

**Build and run**
- `build.sh`: builds `build/NotchPoC.app` (agent app) and `build/Helper` with the Xcode 27 toolchain.
- `run-gated.sh`: idle-gated full-screen run.

**App sources (`app/Sources/`)**
- `Geometry.swift`: display and notch geometry, canvas frame, coordinate conversion.
- `NotchPanel.swift`: panel, root view (hitTest / tracking / drop), hosting view, per-display controller.
- `Coordinator.swift`: monitors, hover/close policy, drag detection, display reconfiguration.
- `NotchModel.swift`, `NotchShape.swift`: state and morphing SwiftUI view, including TextField and tray.
- `SwipeRecognizer.swift`: gesture state machine.
- Tests: `SelfTest.swift` (32 checks), `HitProbe.swift`, `KeyFocusTest.swift`, `FullscreenTest.swift`, `InteractionTest.swift`.

**Helper and probes**
- `helper/main.swift`: the "other app" (full-screen mode; interact mode with click strip, AppKit drag source, drop target, key/activation logging).
- `probe/`: display/levels/permission/idle probes.

**Outputs (`out/`)**
- Logs: `selftest.log`, `hitprobe.log`, `keyfocus.log`, `fullscreen.log`, `interaction-run1.log`, `interaction-run2-aborted.log`, `interaction-run3-steps3-10.log`.
- Images: `fullscreen-top.png`, `open-canvas.png`, `shape-*.png`.

All PoC code is original and written for this research. NotchDrop sources in `poc/notch-window/refs/` were skimmed for ideas only (its drag detection also uses a `leftMouseDragged` monitor). No code was copied, and nothing from NotchNook or boring.notch was used.

---

## Sources

- SDK: `MacOSX27.sdk` AppKit headers `NSScreen.h`, `NSWindow.h`, `NSPanel.h`, `NSApplication.h`, `NSRunningApplication.h`, `NSHapticFeedback.h`, `NSPasteboard.h`, `NSEvent.h`; `AppKit.swiftmodule`, `SwiftUI.swiftmodule`, `SwiftUICore.swiftmodule` interfaces.
- Apple Developer Forums, "Overlay window above all windows, even when moving spaces" (DTS answer recommending accessory policy + non-activating panel + `.screenSaver`, tested on macOS 26): https://origin-devforums.apple.com/forums/thread/826308
- Apple Developer Forums, "Fullscreen Detection" (DTS: no API for other apps' full-screen state; `CGWindowList` approximation; pitfalls with notch and auto-hide): https://developer.apple.com/forums/thread/792917
- Apple Developer Forums, "Fullscreen detection using Core Graphics": https://developer.apple.com/forums/thread/779272
- Apple Developer Forums, "Get MacOS menubar size in Swift" (`safeAreaInsets.top` = 34 reported on a 14″ M2 Pro; `NSStatusBar` thickness 24 on an external display): https://developer.apple.com/forums/thread/779268
- Apple Developer Forums, "ScreenCaptureKit sample initially omits application with NSWindowSharingNone": https://developer.apple.com/forums/thread/808016
- Apple docs, `NSHapticFeedbackPerformer.perform(_:performanceTime:)`: https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)
- AppleInsider on the 2021 notch APIs: https://appleinsider.com/articles/21/10/19/apps-can-use-full-screen-area-around-new-macbook-pros-camera-notch
- MacRumors forum (Tahoe menu bar 31 px vs Sequoia 25 px, user measurement): https://forums.macrumors.com/tags/menubar/

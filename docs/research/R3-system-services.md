# R3 — System integrations for Cranny (verified research)

Date: 2026-10-14 · Host: MacBook Pro Mac16,5 (M4 Max), macOS 27.0.1 (`sw_vers` build 26A434), Xcode 27.0, Swift 6.4, MacOSX27.sdk.
Host state that limited some tests: **lid closed (clamshell) with one external non-Apple display**, so built-in display brightness, the
keyboard backlight and the built-in camera could not be exercised. AirPods were the default audio output, and a Magic Trackpad was connected.

Legend: **VERIFIED** means it was compiled against MacOSX27.sdk with `-swift-version 6 -target arm64-apple-macos14.0` and/or ran on this machine,
or it was checked in SDK headers. **UNVERIFIED** means it comes from docs, knowledge or third-party reports and was not exercised here.
Device names and identifiers in outputs are redacted.

PoC root: `scratchpad/poc/system/` (full path `<research-scratchpad>/poc/system/`).
Build helper: `poc/system/build.sh <dir> <out> <files…>`. It exports `DEVELOPER_DIR` and compiles in Swift 6 mode at deployment target 14.0.
**Consolidated reference code** compiles cleanly with zero warnings and is the recommended starting point for CrannyKit:
`poc/system/reference/{MediaKeys,SystemVolume,Brightness,Power,Environment}.swift` (+ `main.swift` smoke test, `e2e/` end-to-end key test).

---

## 0. Executive summary

| # | Integration | Verdict | Public? | Permission |
|---|---|---|---|---|
| 1 | Volume HUD replacement | **Works on macOS 27.0.1.** If a session-level CGEventTap consumes `NX_SYSDEFINED`/subtype 8 volume keys, the system action **and the system OSD are suppressed** (VERIFIED end-to-end). We then apply the change with CoreAudio. | Event tap + CoreAudio are public | Accessibility |
| 1 | Brightness HUD | Key interception is the same mechanism. Setting brightness needs **private DisplayServices** (there is no public API on Apple Silicon: no `IODisplayConnect`). Not exercised on a built-in panel here. | Private | Accessibility |
| 1 | Keyboard backlight | Private `CoreBrightness.KeyboardBrightnessClient`. Read is VERIFIED; write is untested. Modern Apple Silicon keyboards have no backlight keys, so this is low priority. | Private | – |
| 2 | Battery/charging | IOKit `IOPS*` + `ProcessInfo.isLowPowerModeEnabled`. Fully public; VERIFIED. | Public | none |
| 3 | Bluetooth accessories | **Recommended no-permission path:** CoreAudio device list for headphone connect, IOKit HID matching for Magic devices with `BatteryPercent`, and private `IOPSCopyPowerSourcesByType(4)` for AirPods L/R/case. All VERIFIED with no TCC prompt. IOBluetooth is optional: it needs a Bluetooth TCC prompt and its battery selectors are private. | Mixed | none (IOBluetooth path: Bluetooth) |
| 4 | Calendar | EventKit `requestFullAccessToEvents` (14+), `EKEventStoreChanged`, and a meeting-link detector (12/12 tests pass). VERIFIED compile and SDK. | Public | Calendars |
| 5 | Camera mirror | AVCaptureSession + preview layer in NSViewRepresentable. Device enumeration works **without** permission. `isSuspended` = true with the lid closed. VERIFIED compile and enumeration. | Public | Camera |
| 6 | Shortcuts/apps | `/usr/bin/shortcuts list/run --input-path/--output-path` (VERIFIED flags) and `NSWorkspace.openApplication`/`icon(forFile:)`. | Public | none |
| 7 | AirDrop/share | `NSSharingService(.sendViaAirDrop).perform` **auto-activates the app** and works from a non-activating panel, but its window is **centered on the source window** (it ends up partly off-screen for a top-edge panel). `NSSharingServicePicker` **shows nothing unless the app is activated first**. VERIFIED. | Public | none |
| 8 | Tray pipelines | `ditto` zip/unzip, Apple Archive, ImageIO JPEG/HEIC/**AVIF encode** (macOS 27), WebP/JPEG-XL decode-only, QLThumbnailGenerator, and bookmarks. VERIFIED. | Public | none (watch out for TCC folder prompts) |
| 9 | Launch at login | `SMAppService.mainApp`. The API was verified, but `register()` was **not executed** because it changes the user's login items. The status of an unregistered ad-hoc app is `.notFound`. **Ad-hoc DR = cdhash, so every rebuild resets TCC grants** (VERIFIED). | Public | user approval |
| 10 | Fullscreen/lock/sharing | Fullscreen heuristic via CGWindowList was VERIFIED against a real fullscreen transition. `activeSpaceDidChange` fires (needs `NSApp.run`). The lock signal is undocumented. **There is no public API for screen-sharing detection.** | Mixed | none |

**Top recommendations**
1. Build the HUD as **two tiers**:
   - *Passive* (no permission): the CoreAudio listener shows Cranny's HUD **in addition to** the system OSD.
   - *Replace* (Accessibility): a dedicated-thread CGEventTap consumes the keys, applies them through CoreAudio/DisplayServices, and suppresses the OSD.
   - Pass keys through whenever we cannot apply them ourselves, for example HDMI audio without settable volume, external non-Apple displays, or Option-only presses that open Settings.
2. **Sign with a stable identity** (Developer ID, or at minimum one fixed self-signed certificate reused for every release). With ad-hoc signing the designated requirement is `cdhash H"…"`, so Accessibility, Camera and Calendar grants silently stop matching after every update.
3. Bluetooth accessories: use the **permission-free** sources by default and isolate all private symbols behind a `CrannyPrivate` target with `dlsym` and graceful fallback.
4. AirDrop: present from a **temporary, transparent, normal-level anchor window placed below the notch**, or from the expanded Nook if it is at least 400×300. Call `NSApp.activate()` before presenting the picker. Afterwards, re-activate the previously frontmost app.
5. File tray: **copy files into Application Support by default.** Keeping references to files in Desktop/Documents/Downloads can cause TCC folder prompts after relaunch (UNVERIFIED), and the originals may be deleted.

---

## 1. Volume / brightness HUD replacement

### 1.1 Key event format (VERIFIED in SDK headers)
- `IOKit/hidsystem/IOLLEvent.h`: `NX_SYSDEFINED = 14`, `NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8`.
- `IOKit/hidsystem/ev_keymap.h`: `NX_KEYTYPE_SOUND_UP 0`, `SOUND_DOWN 1`, `BRIGHTNESS_UP 2`, `BRIGHTNESS_DOWN 3`, `MUTE 7`,
  `PLAY 16`, `NEXT 17`, `PREVIOUS 18`, `FAST 19`, `REWIND 20`, `ILLUMINATION_UP 21`, `ILLUMINATION_DOWN 22`, `ILLUMINATION_TOGGLE 23`.
  These import into Swift through `import IOKit.hidsystem` (VERIFIED: `NX_KEYTYPE_SOUND_DOWN`, `NX_SYSDEFINED` and `NX_SUBTYPE_AUX_CONTROL_BUTTONS` are used directly in the reference code).
- `CGEventType` has **no named case** for system-defined events. Use `CGEventType(rawValue: 14)` or compare `type.rawValue == UInt32(NX_SYSDEFINED)`.
  The AppKit equivalent is `NSEvent.EventType.systemDefined` (= 14).
- Decode `NSEvent(cgEvent:)`: `data1` bits 31–16 hold the key code. `(data1 & 0xFF00) >> 8` is `0x0A` for down and `0x0B` for up. `data1 & 1` is the repeat flag.
  Modifiers come from `modifierFlags`.

### 1.2 Interception + OSD suppression on macOS 27 (VERIFIED, the central result)
Test `poc/system/osdtest/` posted synthetic volume-key events at `.cghidEventTap` and ran an active tap at `.cgSessionEventTap`/`.headInsertEventTap`:

```
V0 = 0.4375
phase A (tap consumes):      seen = 2  V1 = 0.4375 UNCHANGED -> suppressed   new windows: []
phase B (tap passes through): seen = 2  V2 = 0.375  changed                  new windows: ["MenuBarAgent … layer=101 352x149 @top-right"]
```
- On macOS 27 the volume OSD is a **352×149 window at layer 101 owned by `/System/Library/CoreServices/MenuBarAgent.app`**, in the top-right corner. `OSDUIHelper` is no longer running.
- When the event is consumed, neither the volume change nor that window happens. When it passes through, both happen. This is the control showing that synthetic events reach the system handler.
- End-to-end with the reference interceptor (`reference/e2e/`): the tap runs on its own thread, consumes the key and calls `SystemVolume.apply`. Result: the volume moved one step down and back, and **0 OSD windows** appeared. **Changing volume through CoreAudio does not trigger the system OSD.**
- Independent confirmation (UNVERIFIED by us): the MIT-licensed volumeHUD 3.0 README describes exactly this on macOS 26. It intercepts the keys and applies the change itself, needs Accessibility, and stops intercepting when the level did not actually change ([volumeHUD](https://github.com/dannystewart/volumeHUD)).
- Caveat: synthetic events take the same session-tap path as hardware events. Real hardware keys, especially **brightness keys on the built-in Apple Silicon keyboard**, were *not* pressed. Use the manual tool `poc/system/eventtap/keylog` (`./keylog 20`, or `./keylog 20 --consume-brightness`) on a MacBook with the lid open to confirm. Brightness codes are expected to arrive as `NX_KEYTYPE_BRIGHTNESS_*` (volumeHUD intercepts them on built-in displays). Some keyboards send brightness as `keyDown` keycodes 144/145; the tool logs those too.
- Public alternative to suppress the OSD: **none**. There is no API or default that hides the system HUD (`OSDUIHelper`/`MenuBarAgent` are SIP-protected system agents).

### 1.3 Permissions for taps (partly VERIFIED)
- Tap creation succeeded for `systemDefined`, `scrollWheel` and `mouseMoved` (both `.defaultTap` and `.listenOnly`) while the responsible app had Accessibility.
  A `keyDown` **listen-only** tap was refused while `CGPreflightListenEventAccess()` was false. Keyboard listening is gated by **Input Monitoring**, but Cranny does not need keyDown.
  Later in the session Input Monitoring became true for the host app. This matrix should be re-checked from a fresh signed `.app`.
- That an active `systemDefined` tap **requires Accessibility** is UNVERIFIED locally: the host was already trusted, and we avoided triggering prompts. volumeHUD states it is required. Plan for it: `AXIsProcessTrusted()` → onboarding → `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])`.
  In Swift 6, `kAXTrustedCheckOptionPrompt` is a mutable global and triggers a concurrency error, so use the literal string (VERIFIED compile).
- `CGPreflightListenEventAccess/CGRequestListenEventAccess/CGPreflightPostEventAccess/CGRequestPostEventAccess` exist (macOS 10.15+, VERIFIED header).
- There is no Info.plist key for Accessibility or Input Monitoring. The system prompt text is fixed.
- Accessibility changes do not notify the app. Poll `AXIsProcessTrusted()` every 1–2 s while onboarding is visible, or on `NSApplication.didBecomeActiveNotification`.

### 1.4 Reference interceptor (VERIFIED compile and run: `reference/MediaKeys.swift`)
Key design points:
- **Dedicated `Thread` with its own CFRunLoop.** The callback stays responsive when the main thread is busy with SwiftUI layout. macOS disables taps that respond slowly (`tapDisabledByTimeout`), and the callback re-enables them.
- The handler returns `true` to consume. Consume **both** down and up for the keys we handle.
- **Pass through** (return `false`):
  - the output device has no settable volume (`SystemVolume.canControl == false`, typical for HDMI/DisplayPort sinks), so macOS shows its "not adjustable" OSD;
  - there is no controllable display for brightness (external non-Apple display, lid closed);
  - Option-only presses, so macOS opens Sound/Displays settings natively;
  - the feature is disabled, or the HUD is hidden in fullscreen if the user prefers the system HUD there.
- If our tap dies (crash), keys automatically revert to system handling. If the tap thread stalls, macOS disables the tap and keys also flow to the system.

```swift
let tap = MediaKeyInterceptor { ev in               // runs on the tap thread — keep it fast
    switch ev.key {
    case .soundUp, .soundDown, .mute:
        guard ev.isDown else { return true }          // swallow key-up too
        guard !ev.option, let r = SystemVolume.apply(ev.key, fine: ev.fine) else { return false } // pass through
        Task { @MainActor in hud.showVolume(r.volume, muted: r.muted) }
        return true
    case .brightnessUp, .brightnessDown:
        guard ev.isDown else { return true }
        guard !ev.option, let b = DisplayBrightness.shared?.step(up: ev.key == .brightnessUp, fine: ev.fine) else { return false }
        Task { @MainActor in hud.showBrightness(b) }
        return true
    default: return false
    }
}
tap.start()   // false => no Accessibility
```
Note: in production, guard brightness key-ups with the same pass-through decision as the key-down, so up and down are consumed symmetrically.

### 1.5 Volume via CoreAudio (VERIFIED: `reference/SystemVolume.swift`, `volume/`, `vollisten/`)
- **`kAudioHardwareServiceDeviceProperty_VirtualMainVolume` is declared in AudioToolbox** (`AudioHardwareService.h`), not CoreAudio. You need `import AudioToolbox`; the first compile failed without it. `…VirtualMasterVolume` is deprecated.
- Scope `kAudioDevicePropertyScopeOutput`, element `kAudioObjectPropertyElementMain`. Mute: `kAudioDevicePropertyMute` (UInt32).
  Default device: `kAudioHardwarePropertyDefaultOutputDevice` on `kAudioObjectSystemObject`.
- With AirPods (Bluetooth) as output on this host: volume settable = true, read 0.4375 (7/16). One system key step = **0.0625 = 1/16**, VERIFIED in phase B.
- Steps: normal 1/16, **Option+Shift = 1/64** (quarter step, Apple convention). Snap to the grid. Volume-up while muted → unmute.
- **Passive listener** `AudioObjectAddPropertyListenerBlock` (VERIFIED):
  - It fires on changes from other clients; the test used `osascript set volume`.
  - It fired **4 callbacks per change**, so coalesce over about 15 ms.
  - Re-attach when `kAudioHardwarePropertyDefaultOutputDevice` changes.
  - In passive mode the system OSD *also* shows. Passive mode also cannot show a HUD at 0 %/100 % because the value doesn't change.
- Feedback sound: the user default `com.apple.sound.beep.feedback` exists (`defaults read -g` → 1 here). When we consume the key, macOS does **not** play its feedback, so replicate it. Play the OS's own file at runtime: `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff` exists on 27.0.1 (VERIFIED). Shift+volume inverts the setting (Apple convention, UNVERIFIED).
- Showing the HUD for "device changed" (AirPods connect) is a nice extra: hook the default-device listener.

### 1.6 Brightness (partly VERIFIED: `reference/Brightness.swift`, `brightness/`, `kbd/`)
- There is **no public path on Apple Silicon.** `ioreg -c IODisplayConnect` returns 0 entries (VERIFIED), so `IODisplaySetFloatParameter(kIODisplayBrightnessKey)` has no service to talk to. `CGDisplayIOServicePort` is deprecated (10.9).
- Private `DisplayServices.framework` (dlopen/dlsym). VERIFIED present: `DisplayServicesGetBrightness`, `SetBrightness`, `CanChangeBrightness`, `SetBrightnessSmooth`, `RegisterForBrightnessChangeNotifications`, `UnregisterForBrightnessChangeNotifications`, `HasAmbientLightCompensation`, `AmbientLightCompensationEnabled`. CoreDisplay also exports `CoreDisplay_Display_{Get,Set}UserBrightness`.
  - On the external non-Apple display: `CanChangeBrightness` = false and `Get` rc = 1000. That is correct, so pass the key through.
  - **Built-in panel get/set not exercised (lid closed).** It is widely used (MonitorControl's "Apple native" path, volumeHUD), but status here is UNVERIFIED.
  - The signature of `RegisterForBrightnessChangeNotifications` is UNVERIFIED. For passive brightness changes, poll `Get` at about 2 Hz only while a brightness HUD is visible, or skip passive brightness entirely.
  - **Hardened runtime OK:** an ad-hoc binary signed with `--options runtime` dlopens DisplayServices, CoreBrightness and IOKit-private symbols without `disable-library-validation` (VERIFIED: `bright_hr`, `accps_hr`).
- Target display: the built-in display when online and awake (`CGDisplayIsBuiltin`, `CGDisplayIsAsleep`). Apple external displays (Studio/Pro Display) are reportedly controllable by DisplayServices too (UNVERIFIED). Everything else → pass through. DDC/CI for third-party monitors is out of scope.
- Keyboard backlight: `KeyboardBrightnessClient` (CoreBrightness, private ObjC).
  - VERIFIED: `copyKeyboardBacklightIDs` → one built-in ID, `brightnessForKeyboard:` → 0.0 (lid closed), `isKeyboardBuiltIn:` → true, `isAutoBrightnessEnabledForKeyboard:` → true.
  - Write (`setBrightness:forKeyboard:`) is untested.
  - Apple Silicon MacBooks have no illumination keys; F5/F6 are Dictation/Focus (UNVERIFIED knowledge). Keep `ILLUMINATION_*` handling as a low-priority bonus for older or external keyboards.

---

## 2. Battery / charging (VERIFIED: `reference/Power.swift`, `battery/`, `accps/`)
- `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription`, `IOPSGetProvidingPowerSourceType` (`kIOPSACPowerValue`), `IOPSCopyExternalPowerAdapterDetails` (`kIOPSPowerAdapterWattsKey`), `IOPSGetTimeRemainingEstimate` (-1 unknown, -2 unlimited/AC), `IOPSNotificationCreateRunLoopSource` (C callback without captures; route through a static or context pointer). Notify keys: `kIOPSNotifyPowerSource`, `kIOPSNotifyLowBattery`, `kIOPSNotifyAnyPowerSource`.
- Live output on this host:
  - `percent 80, isCharging false, isPluggedIn true, adapter 140 W, time remaining -2`.
  - **"AC attached; not charging"** is a real state, caused here by a charge limiter (AlDente) and possible on macOS's own charge limit / optimized charging. The UI needs a third state, "Plugged in, not charging", besides charging/discharging.
  - The description dict contains an undocumented `"LPM Active"` key, and `ProcessInfo.isLowPowerModeEnabled` plus `.NSProcessInfoPowerStateDidChange` is the public signal (VERIFIED compile).
- Keys used: `kIOPSCurrentCapacityKey/MaxCapacityKey` (Max = 100 → already a %), `kIOPSIsChargingKey`, `kIOPSIsChargedKey`, `kIOPSTimeToEmptyKey`, `kIOPSTimeToFullChargeKey` (0/-1 while calculating → show "Calculating…"), `kIOPSBatteryHealthKey`.
- Live activity triggers: AC plug-in/unplug (transition of `isPluggedIn`), charged, below 20 % / 10 % (or `kIOPSNotifyLowBattery`), and Low Power Mode toggled.
- Desktop Macs have no `InternalBattery` source (`hasBattery = false`), so hide the battery activity there.

## 3. Bluetooth devices (VERIFIED where noted: `accessories/`, `accps/`, `bluetooth/`)
**What is realistically achievable:**

| Need | Recommended source | Public? | TCC | Status |
|---|---|---|---|---|
| "Headphones connected" event | CoreAudio `kAudioHardwarePropertyDevices` + default-output listener; transport `kAudioDeviceTransportTypeBluetooth` (`'blue'`) / `…BluetoothLE` (`'blea'`) | public | none | VERIFIED (2 BT audio devices listed) |
| AirPods L/R/Case/Combined battery + name + category + productID | `IOPSCopyPowerSourcesByType(4)` (exported by IOKit, absent from SDK headers). Same data as `pmset -g accps` and the Batteries widget | **private** | none | VERIFIED: entries `Accessory Category=Headset` `Part Identifier=Combined` with `Combined Parts` [Left, Right], plus `Audio Battery Case` `Part Identifier=Case`, `Vendor ID=76`, `Product ID`, `Group Identifier`, `Low Warn Level`, `Is Charging` |
| Magic Keyboard/Mouse/Trackpad battery + connect/disconnect | IOKit `IOServiceAddMatchingNotification` on `AppleDeviceManagementHIDEventService` (`kIOFirstMatchNotification`/`kIOTerminatedNotification`), properties `BatteryPercent`, `Product`, `ProductID`, `Transport` | public API, undocumented property | none | VERIFIED (trackpad 64 %, `Transport=Bluetooth`) |
| Any BT device connect/disconnect, name, class-of-device | `IOBluetoothDevice.register(forConnectNotifications:selector:)`, `device.register(forDisconnectNotification:selector:)`, `name`, `deviceClassMajor/Minor`, `isConnected()`, `pairedDevices()` | public (SDK headers) | **Bluetooth** (`NSBluetoothAlwaysUsageDescription`) | compile VERIFIED; runtime not run (see below) |
| Third-party headset battery | `IOBluetoothDevice` `batteryPercentSingle/Left/Right/Case/Combined` | **private**: `instancesRespond(to:)` = true at runtime, **absent from SDK headers** (VERIFIED) | Bluetooth | unverified |

- IOBluetooth runtime was deliberately not exercised. TCC attributes the access to the *responsible* app, which here is the host Claude app. Third-party reports say processes without `NSBluetoothAlwaysUsageDescription` are killed with a TCC SIGABRT rather than prompted ([OBS report](https://obsproject.com/forum/threads/crash-when-launching-filesystem-security-settings-problem.150604), [Qt report](https://bugreports-test.qt.io/browse/QTCREATORBUG-26710)) — UNVERIFIED here.
- **Recommendation:** ship the permission-free trio (CoreAudio + IOKit HID + IOPS accessories) as the default "Bluetooth" live activity:
  - Refresh the accessory list on IOPS notifications, on CoreAudio device-list changes and HID add/remove, and every 60 s while an accessory activity is visible. Whether IOPS notifications fire for accessory % changes is UNVERIFIED.
  - Offer IOBluetooth as an opt-in "Show all Bluetooth devices" with its own permission step.
- Icons: map the Apple product ID (vendor 76) to SF Symbols, and fall back to category (`Headset` → `headphones`, `Trackpad`, `Keyboard`, `Mouse`). Symbols present on macOS 27 (VERIFIED with `NSImage(systemSymbolName:)`): `airpods`, `airpods.gen3`, `airpods.gen4`, `airpods.pro`, `airpods.max`/`airpodsmax`, `airpods.chargingcase(.wireless)`, `airpodspro.chargingcase.wireless`, `beats.headphones`, `beats.earphones`, `beats.powerbeatspro`, `beats.studiobuds`, `headphones`, `earbuds`, `magicmouse`, `keyboard`, `computermouse`, `gamecontroller`, `hifispeaker`, `battery.*`. **Missing:** `trackpad`, `airdrop` (use `dot.radiowaves.left.and.right` for AirDrop). Some symbols may be missing on macOS 14, so always handle `nil` (UNVERIFIED for 14).
- Don't hard-code a productID→model table as "truth"; keep it data-driven and fall back to the generic symbol.

## 4. Calendar (VERIFIED: `calendar/main.swift`, `calendar/detector2.swift`)
- `EKEventStore.requestFullAccessToEvents()` (async, macOS 14.0) and `requestWriteOnlyAccessToEvents` (14.0). `requestAccessToEntityType` is deprecated in 14. VERIFIED in header.
- `EKAuthorizationStatus` raw values: `notDetermined 0, restricted 1, denied 2, fullAccess 3, writeOnly 4`. `.authorized` is a deprecated alias of `fullAccess`. On this host the CLI status was 0.
- Info.plist: `NSCalendarsFullAccessUsageDescription`. With deployment target 14, the legacy `NSCalendarsUsageDescription` is not needed (Apple [TN3152](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)).
  **Hardened-runtime entitlement `com.apple.security.personal-information.calendars` is required.** VERIFIED: it is listed under Hardened Runtime resource access in Apple's doc JSON. Without it, access is denied without a prompt (UNVERIFIED behaviour).
- Observe `NotificationCenter` `.EKEventStoreChanged` (object: store). Also re-plan on `NSWorkspace.didWakeNotification`, `.NSSystemTimeZoneDidChange`, `.NSCalendarDayChanged`. Keep **one long-lived `EKEventStore`**.
- Fetch: `predicateForEvents(withStart:end:calendars:)` with start = startOfDay − daysBehind and end = startOfDay + daysAhead + 1. The max span is 4 years. Sort with `compareStartDate`. Filter:
  - `status == .canceled`;
  - the current user declined (`attendees?.first { $0.isCurrentUser }?.participantStatus == .declined`, VERIFIED API);
  - optionally all-day events and birthdays (`calendar.type == .birthday`);
  - calendars the user disabled in Settings (store `calendarIdentifier`s).
- Colors: `EKCalendar.color` (NSColor, macOS 10.8) and `cgColor` (10.15). VERIFIED header.
- **Meeting link detector** v2 (`detector2.swift`): 12/12 self-tests pass (VERIFIED).
  - Covers Zoom (`zoom.us`, `zoomgov.com`, `zoommtg://`), Google Meet (`xxx-xxxx-xxx` and `/lookup/`), Teams (`/l/meetup-join`, **new `/meet/<id>?p=`**, `teams.live.com`, gov/dod, `msteams:`), Webex (`/j.php`, `/meet/`, `/join`), FaceTime, Slack huddle, Whereby, GoTo, Jitsi and Chime.
  - It unwraps **Outlook SafeLinks** and Google `url?q=` redirects, and decodes `&amp;`.
  - Search order is `event.url` → `location` → `notes`, and the earliest match in a field wins (dial-in numbers come later).
- Opening: `NSWorkspace.shared.open(url)`. Optionally prefer native clients when installed. VERIFIED on this host: `urlForApplication(toOpen: "zoommtg://…")` → zoom.us.app; `msteams:` → nil (not installed). Convert Zoom `https://…/j/<id>?pwd=<p>` to `zoommtg://zoom.us/join?confno=<id>&pwd=<p>` only when a handler exists. `https://facetime.apple.com/join` resolves to the default browser here.
- Live-activity plan:
  - Schedule a single `Timer` to the next "start − N min" boundary; don't poll.
  - While the meeting runs, tick once per minute for elapsed time.
  - Recompute on store change, wake, and timezone/day change.
- Denied access → deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`. The scheme resolves to System Settings (VERIFIED); the anchor behaviour on 27 is UNVERIFIED.

## 5. Camera mirror (VERIFIED compile/enumeration: `camera/main.swift`)
- `AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)`.
  - `.external` and `.continuityCamera` are macOS 14.0 (VERIFIED header); `.deskViewCamera` is macOS 13.0.
  - `.continuityCamera` is reported only with **`NSCameraUseContinuityCameraDeviceType = YES`** in Info.plist (header comment). Otherwise iPhones show up as other types.
  - **Filter out Desk View** for a mirror. It was listed here next to the built-in camera.
- Enumeration ran **without** any camera permission and without a prompt (status stayed `notDetermined`, VERIFIED). Only starting a session or creating an input prompts.
- Device selection: KVO `AVCaptureDevice.systemPreferredCamera` (macOS 13; Apple says to observe it). Set `userPreferredCamera` when the user picks one. Hot-plug: `AVCaptureDevice.wasConnectedNotification` / `wasDisconnectedNotification`.
- **`isSuspended` = true with the lid closed** (VERIFIED). Show a "Camera unavailable (lid closed)" state and KVO it.
- Session: `AVCaptureSession` confined to a private serial queue (`startRunning`/`stopRunning` block), preset `.high` (or `.medium` for energy). `AVCaptureVideoPreviewLayer` sits in a layer-hosting `NSView` behind an `NSViewRepresentable`. Mirror with `connection.automaticallyAdjustsVideoMirroring = false; isVideoMirrored = true` when `isVideoMirroringSupported`; otherwise flip the layer.
- **Run only while visible.** Start in `onAppear` *and* only while the Nook is open and the Mirror widget is on screen. Stop on close, `NSWorkspace.screensDidSleep`, session resign-active, and on lock. Expect the green camera indicator, plus system video effects (Center Stage/Portrait/Reactions) applied via Control Center.
- Info.plist: `NSCameraUsageDescription`. Hardened runtime: **`com.apple.security.device.camera`** (VERIFIED in Apple's hardened-runtime entitlement list). Without it the camera is denied under hardened runtime (UNVERIFIED behaviour).
- Errors: `AVCaptureSession.runtimeErrorNotification`, plus interruption when another app takes exclusive use.

## 6. Shortcuts.app & quick apps (VERIFIED: `apps-share/main.swift`)
- CLI help on macOS 27 (VERIFIED):
  - `shortcuts list [--folder-name <name|id|none>] [--folders] [--show-identifiers]`
  - `shortcuts run <name-or-identifier> [--input-path <p> …] [--output-path <p>] [--output-type <UTI>]`
  - `shortcuts view <name>` opens the editor.
- `list --show-identifiers` prints `Name (UUID)`. The parser handled 7 shortcuts here. **Run by UUID** so it survives renames, and keep the name for display. `list` took about 0.02 s.
- Run via `Process` off the main actor. Read stdout before `waitUntilExit` to avoid pipe deadlock. Support cancellation with `terminate()`.
  The CLI needs no Apple Events permission. Actions inside a shortcut prompt on behalf of Shortcuts, not Cranny (UNVERIFIED).
  Alternative: `shortcuts://run-shortcut?name=…` opens the Shortcuts UI (`shortcuts://` → Shortcuts.app, VERIFIED).
- There is no API for a shortcut's glyph or colour. Use a generic SF Symbol (or the Shortcuts app icon) plus a user-chosen tint.
- Apps:
  - Launch: `NSWorkspace.shared.openApplication(at:configuration:)` with `OpenConfiguration.activates = true`, `addsToRecentItems = false`.
  - Open files with an app: `open(_:withApplicationAt:configuration:)`.
  - Icons: `NSWorkspace.shared.icon(forFile:)`, size set via `img.size`.
  - Find apps: `urlForApplication(withBundleIdentifier:)`.
  - Pick apps: `NSOpenPanel` with `allowedContentTypes = [.application]`, or drag from Finder/Dock.
  - Reveal: `activateFileViewerSelecting`.
  - All of the above VERIFIED compile at 14.0.

## 7. AirDrop & sharing (VERIFIED runtime: `airdrop/main.swift`)
Probe: an accessory-policy app with a borderless `.nonactivatingPanel` at `.statusBar` level near the top of the screen, another app frontmost.

| Call | Without `NSApp.activate()` | With `NSApp.activate()` |
|---|---|---|
| `NSSharingService(named: .sendViaAirDrop)!.perform(withItems: [fileURL])` | UI appears. **The app activates itself** (frontmost becomes Cranny). In-process windows `SHKRemoteWindow` (key) + `SHKDimAndShadowWindow` + `SHKBlurWindow`, 360×260, **at the source window's level (25)** and **centered on the source window**: y = −50, partly off-screen | same |
| `NSSharingServicePicker(items:).show(relativeTo:of:preferredEdge:)` | **Nothing appears**; `show` returns immediately and the app stays inactive | `_NSPopoverWindow` 266×266 at layer 101 below the anchor; key |

- `canPerform(withItems:)` returned true for a file URL. `willShareItems` fired. The delegate's `sourceWindowForShareItems` / `sourceFrameOnScreenForShareItem` control placement.
- **Recommendations**
  - For the AirDrop drop zone, return a source window that is large enough and fully on screen: the expanded Nook panel (≥ 400×300), or a temporary transparent anchor window centered below the notch. Then call `perform`.
  - For the picker, call `NSApp.activate()` first.
  - Capture `NSWorkspace.shared.frontmostApplication` before sharing and re-activate it in `didShareItems`/`didFailToShareItems` (or the picker's `didChoose`) so focus isn't stolen permanently.
  - The share window inherits our high window level. That is good above other apps, but our own notch panel must not cover it.

## 8. File tray pipelines (VERIFIED: `tray/main.swift`, `tray/bookmark.swift`, `tray2/main.swift`, `apicheck/`)
- **ImageIO write support on macOS 27** (`CGImageDestinationCopyTypeIdentifiers`, VERIFIED):
  - JPEG ✓, PNG ✓, HEIC ✓, **AVIF ✓** (encode + round-trip decode OK), TIFF ✓, GIF ✓.
  - **WebP ✗** (decode only; `CGImageDestinationCreateWithURL` → nil, error "feature not supported"), **JPEG-XL ✗** (decode only).
  - Gate formats by querying the list at runtime (older OS versions differ).
  - Sizes for a 1600² synthetic image:

    | Format | q 0.9 | q 0.6 | q 0.3 |
    |---|---|---|---|
    | JPEG | 549 KB | 322 KB | 159 KB |
    | HEIC | 385 KB | 272 KB | 192 KB |
    | AVIF | 267 KB | 189 KB | 140 KB |

    PNG (lossless) was 651 KB.
  - Use `kCGImageDestinationLossyCompressionQuality`.
  - Resize with `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` + `…WithTransform` (applies EXIF orientation).
  - `CGImageDestinationAddImageFromSource` keeps metadata; offer "strip metadata" by re-adding a plain `CGImage`.
- **Zip:** `/usr/bin/ditto -c -k --sequesterRsrc --keepParent <src> <dst.zip>` (Finder-compatible). For multiple items, stage them into a temp folder named like the archive. **Unzip:** `ditto -x -k <zip> <dir>`. VERIFIED round-trip.
  Apple Archive (`AppleArchive`, `.aar`/LZFSE) also works (VERIFIED) but is not zip-compatible, so use it only for internal storage.
- **Thumbnails:** `QLThumbnailGenerator.shared.generateBestRepresentation(for:)` with `iconMode = true` → VERIFIED 64×64. Fall back to `NSWorkspace.icon(forFile:)`.
- **Extra pipelines (VERIFIED compile at 14.0, no dependencies):**
  - Vision `VNGenerateForegroundInstanceMaskRequest` → "Remove background" (macOS 14.0);
  - `VNRecognizeTextRequest` → "Copy text (OCR)";
  - PDFKit `PDFPage(image:)` → "Images → PDF" and PDF merge;
  - `AVAssetExportSession` → "Compress video": `export(to:as:)` is macOS 15+, with fallback `export()`;
  - Copy path (NSPasteboard);
  - Reveal in Finder;
  - Open with…
- **Persistence:**
  - Non-sandboxed plain bookmarks survive move/rename on the same volume (VERIFIED: resolved after the move, `isStale = true` so re-save, cached name from `resourceValues(forKeys:fromBookmarkData:)`). They fail after delete (error 4).
  - **Default to copying** dropped files into `~/Library/Application Support/<bundle-id>/Tray/<uuid>/name`, with a JSON/SwiftData index (UUID, original bookmark, date, size). Offer "Link to original" as an option.
  - Reasons for copying:
    - the originals may be temporary (screenshots, file promises from Photos/Mail/Safari via `NSFilePromiseReceiver`, which is compile-VERIFIED);
    - **TCC folder protection:** re-reading Desktop/Documents/Downloads files after relaunch can prompt (UNVERIFIED for drag-originated access). Add `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription` and `NSNetworkVolumesUsageDescription` strings anyway.
  - Enforce a size cap and an "auto-clear after N days" setting.

## 9. Launch at login (`loginitem/`)
- `SMAppService.mainApp` (`mainAppService`, macOS 13). `register()`/`unregister()` (throwing; async unregister available), `status` ∈ `.notRegistered, .enabled, .requiresApproval, .notFound`, `SMAppService.openSystemSettingsLoginItems()`, `SMAppServiceErrorDomain` (15.0). VERIFIED header and compile.
- The header documents error `kSMErrorInvalidSignature` for an "improperly code signed" bundle, and `kSMErrorLaunchDeniedByUser` / `kSMErrorAlreadyRegistered`.
- Observed: an **ad-hoc + hardened-runtime signed `Probe.app` in /private/tmp reports `.notFound` before any registration** (VERIFIED). Treat `.notFound` as "off". Read `status` every time Settings opens or the app becomes active; never cache a Bool.
- **`register()` was not executed.** It modifies the user's login items and posts a "Background item added" notification. Whether it works for an ad-hoc signed app outside /Applications is **UNVERIFIED**; third-party reports are mixed.
  Test plan (needs user consent):
  1. Build `Cranny.app` with stable signing; copy it to `/Applications`; launch once.
  2. Settings toggle → `try SMAppService.mainApp.register()` → expect `.enabled` (or `.requiresApproval` → `openSystemSettingsLoginItems()`).
  3. Log out and log in.
  4. Repeat with the app in `~/Downloads` (quarantined/translocated) to see the failure mode.
- Fallback if registration fails: a user-level LaunchAgent plist in `~/Library/LaunchAgents` with `open -b <bundle-id>`. It works with any signature, but appears as a separate "background item" (UNVERIFIED on 27).
- **Signing finding (VERIFIED):**
  - `codesign -d -r-` on the ad-hoc app shows `designated => cdhash H"…"`. TCC (Accessibility, Camera, Calendars, Input Monitoring) keys grants to the designated requirement, so **every rebuild/update of an ad-hoc build invalidates the grants**. The old toggle stays visibly "on" but no longer matches.
  - Use a Developer ID or one long-lived self-signed code-signing certificate. With a certificate, the DR becomes `identifier … and certificate leaf = H"…"`, which survives updates.
  - Also prompt users to move the app to /Applications. App Translocation randomises the path of quarantined apps run from Downloads, which breaks login items and relative paths.

## 10. Fullscreen, screen sharing/recording, lock, app changes (`fullscreen/`, `environment/`, `session/`, `reference/Environment.swift`)
- **Fullscreen (VERIFIED with a real native-fullscreen transition):**
  - The heuristic "the frontmost app owns a layer-0 on-screen window whose CG bounds equal the screen frame" flipped true→false exactly with the fullscreen space. It needs **no Screen Recording permission**: owner PID, layer and bounds are always available, and only `kCGWindowName` is gated.
  - `NSApp.currentSystemPresentationOptions` **does not reflect other apps** (always 0, VERIFIED), so don't use it.
  - Checking the menu-bar window is unreliable: it reappears when the user hovers the top edge in fullscreen.
  - Borderless "fullscreen" (games, some video players) also matches the bounds heuristic, which is desirable.
- **Triggers (VERIFIED):** `NSWorkspace.activeSpaceDidChangeNotification` fired on entering and leaving the fullscreen space, and `didActivateApplicationNotification` fired on app switches. **Both only arrive while a real `NSApp.run()` event loop runs.** A bare `RunLoop.main.run` without `finishLaunching` got no space notifications. Re-evaluate about 0.6 s after the notification, once the space animation settles. Per-screen: evaluate each `NSScreen`, because the fullscreen app may be on another display.
- **Lock:** distributed notifications `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`, plus `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` (key absent when unlocked; VERIFIED absent). Both are undocumented but long-standing; runtime lock was not tested (UNVERIFIED). Public complements: `NSWorkspace.screensDidSleep/DidWake`, `willSleep/didWake`, `sessionDidResignActive/BecomeActive` (fast user switching). Public session keys present: `kCGSessionOnConsoleKey`, `kCGSessionLoginDoneKey`, etc.
- **Screen sharing/recording:**
  - **There is no public API** (Apple DTS forum answers; [MacPaw research](https://macpaw.tech/research/is-mac-screen-captured)).
  - Private `CGSIsScreenWatcherPresent()` exists in CoreGraphics and returns false at idle (VERIFIED symbol and idle value). Its value *during* capture is UNVERIFIED; we did not record the user's screen.
  - Heuristics: bundle IDs of running conferencing/recorder apps, ScreenCaptureKit indicators. All fragile, so make "Hide while screen sharing" a best-effort, off-by-default option.
  - `NSWindow.sharingType = .none` excludes a window from legacy captures, but is reportedly ignored by ScreenCaptureKit-based recorders on macOS 15+ (UNVERIFIED). Don't promise privacy. "Demo mode" (always visible) needs nothing special.
- **Active app changes:** `NSWorkspace.didActivateApplicationNotification` (userInfo `NSWorkspace.applicationUserInfoKey` → `NSRunningApplication`) VERIFIED; `frontmostApplication` is KVO-observable.

---

## 11. Permission matrix

| Feature | API | TCC service (System Settings) | Info.plist key | Hardened-runtime entitlement | Prompt trigger | Without permission |
|---|---|---|---|---|---|---|
| HUD replace (volume/brightness keys) | CGEventTap `.defaultTap` on NX_SYSDEFINED | **Accessibility** | — (no key exists) | — | `AXIsProcessTrustedWithOptions(prompt)` | Passive HUD via CoreAudio listener (system OSD also shows) |
| Gestures over notch (other module) | scroll/gesture taps or NSEvent monitors | scroll/gesture taps were created with Accessibility granted and Input Monitoring *not* granted, so Input Monitoring is not needed. Behaviour without Accessibility is UNVERIFIED | — | — | — | local-only monitors inside our panel |
| Volume read/write/observe | CoreAudio/AudioToolbox | none | — | — | — | — |
| Brightness set | DisplayServices (private) | none | — | — (no library-validation exception needed, VERIFIED) | — | pass key through |
| Battery | IOKit.ps | none | — | — | — | — |
| Accessory batteries (AirPods/Magic) | IOPS private / IOKit HID / CoreAudio | none (VERIFIED) | — | — | — | — |
| Bluetooth device list (optional) | IOBluetooth | **Bluetooth** | `NSBluetoothAlwaysUsageDescription` | — (`com.apple.security.device.bluetooth` is sandbox-only) | first IOBluetooth use | use the permission-free sources |
| Calendar | EventKit | **Calendars** | `NSCalendarsFullAccessUsageDescription` | `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` | widget shows "Connect Calendar" |
| Reminders (if to-dos sync) | EventKit | Reminders | `NSRemindersFullAccessUsageDescription` | (same calendars entitlement, UNVERIFIED) | `requestFullAccessToReminders()` | local to-dos |
| Camera mirror | AVFoundation | **Camera** | `NSCameraUsageDescription` (+ `NSCameraUseContinuityCameraDeviceType` = YES) | `com.apple.security.device.camera` | first `AVCaptureDeviceInput`/`requestAccess(for: .video)` | placeholder state |
| Media control via AppleScript (media module) | NSAppleScript / Apple Events | **Automation** (per target app) | `NSAppleEventsUsageDescription` | `com.apple.security.automation.apple-events` | first event sent to Music/Spotify | MediaRemote-free fallback |
| Shortcuts | `/usr/bin/shortcuts` | none for Cranny | — | — | — | — |
| AirDrop/share | NSSharingService | none | — | — | — | — |
| Tray file access | FileManager on user files | **Files & Folders** (Desktop/Documents/Downloads/removable/network) | `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription` | — | reading protected paths without user intent | copy files into App Support on drop |
| Launch at login | SMAppService | Login Items (user toggle) | — | — | `register()` → notification | — |
| Fullscreen detection | CGWindowList bounds/owner | none (window **names** need Screen Recording; we don't use them) | — | — | — | — |

Other Info.plist: `LSUIElement = YES`, `LSMinimumSystemVersion = 14.0`, `NSSupportsAutomaticTermination = NO` (an agent with live UI; UNVERIFIED necessity), `CFBundleDevelopmentRegion = en`, and localizations en and ru. All usage strings need Russian translations in `InfoPlist.xcstrings`.

Entitlements file (non-sandboxed, hardened runtime):
```xml
<dict>
  <key>com.apple.security.device.camera</key><true/>
  <key>com.apple.security.personal-information.calendars</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>   <!-- only if media uses Apple Events -->
</dict>
```
The entitlement keys are VERIFIED against Apple's Hardened Runtime documentation JSON. That page lists `device.audio-input`, `device.camera`, `personal-information.{addressbook,calendars,location,photos-library}` and `automation.apple-events`.
Do **not** add `cs.disable-library-validation`; it is not needed for dlopen of system private frameworks (VERIFIED).

Settings deep links (the scheme resolves to System Settings, VERIFIED; anchors UNVERIFIED on 27):
`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, `…?Privacy_Camera`, `…?Privacy_Calendars`, `…?Privacy_Bluetooth`, `…?Privacy_ListenEvent`, `…?Privacy_Automation`, `x-apple.systempreferences:com.apple.Sound-Settings.extension`.

Onboarding UX:
- Ask for each permission **in context**: Accessibility when the user enables "Replace system HUD", Calendar when the Calendar widget is first shown, Camera when Mirror is opened.
- Never ask at first launch all at once.
- For Accessibility, show a two-step card ("Open Settings" → toggle Cranny) and poll `AXIsProcessTrusted()` so the card completes itself.
- Explain the ad-hoc reset problem in release notes if stable signing isn't available.

---

## 12. Risks & open questions
1. **Private APIs.** DisplayServices, CoreBrightness `KeyboardBrightnessClient`, `IOPSCopyPowerSourcesByType`, `CGSIsScreenWatcherPresent`, the `CGSSessionScreenIsLocked` key and IOBluetooth `batteryPercent*` could change in any OS update.
   Mitigation: an isolated `CrannyPrivate` target with `dlsym`/`responds(to:)` guards, no linking, a feature probe at launch, and graceful UI degradation.
2. **Brightness keys on real Apple Silicon hardware** were not pressed. Run `poc/system/eventtap/keylog` with the lid open before committing to the brightness HUD.
3. **TCC and signing.** Ad-hoc builds lose grants on every update (VERIFIED DR = cdhash). Without notarization, macOS 15+ requires System Settings → Privacy & Security → "Open Anyway" for the first launch (UNVERIFIED on 27). There is also App Translocation.
4. **`SMAppService` with ad-hoc signing** is unverified. Keep the LaunchAgent fallback.
5. **Event-tap robustness.**
   - Taps get disabled on timeout, so re-enable them.
   - Secure Event Input (password fields) blocks keyboard taps. Whether NX_SYSDEFINED media keys are also blocked is UNVERIFIED; if so, the system HUD simply appears, which is benign.
   - Multiple HUD apps (MonitorControl, volumeHUD, SoundSource) compete: whichever tap is at the head wins. Detect known bundle IDs and warn.
6. **Passive volume mode** double-shows the HUD (ours + system's) and can't show at limits. Present it as "Show alongside system HUD".
7. **Per-app/HDMI audio:** if the default output has no settable VirtualMainVolume, we must pass through (VERIFIED logic, untested on HDMI hardware). Multi-output/aggregate devices behave the same.
8. **AirDrop UI placement** is centered on the source window and inherits its level (VERIFIED). A poor anchor puts the sheet off-screen. Sharing also activates Cranny and steals focus.
9. **IOBluetooth TCC crash** if the usage string is missing, which also matters for dev builds run from Xcode/terminal, where the parent app is responsible (third-party reports).
10. **Screen-share detection** has no public API. Keep it best-effort and off by default.
11. **Tray TCC prompts** for referenced files in protected folders (UNVERIFIED). Copying on drop avoids it.
12. **AVIF encode / WebP decode support varies by OS.** Always query `CGImageDestinationCopyTypeIdentifiers()` at runtime.

## 13. Suggested CrannyKit layout for these services
- `CrannySystem` (public APIs only):
  - `MediaKeys` (interceptor), `Audio` (SystemVolume, VolumeObserver), `Power` (PowerSources, PowerObserver)
  - `Accessories` (CoreAudio + HID parts), `Calendar` (EventKit service + MeetingLinkDetector), `Camera` (MirrorCamera + preview)
  - `Shortcuts` (CLI wrapper), `Apps`, `Sharing` (AirDrop sender with anchor window), `Tray` (ImageIO, ditto, thumbnails, storage)
  - `LoginItem`, `Environment` (fullscreen/lock/space observer).
- `CrannyPrivate` (each symbol behind a capability check): `DisplayBrightness`, `KeyboardBacklight`, `IOPSAccessories`, `ScreenWatcher`.
- All services expose `@Observable @MainActor` façade models. Heavy work runs on their own queues or threads (tap thread, CoreAudio listener queue, camera session queue, `Process` for CLIs).

## 14. Files produced (all under `scratchpad/poc/system/`)
- `reference/` — consolidated, warning-free Swift 6 reference code + `main.swift` smoke test (`ref`) + `e2e/` (key consume + CoreAudio apply, no OSD).
- `osdtest/` — OSD suppression proof (consume vs pass-through, MenuBarAgent window detection).
- `eventtap/keylog.swift` — **manual** hardware key logger (pass-through; `--consume-brightness`).
- `vollisten/` — CoreAudio listener proof. `volume/`, `brightness/`, `kbd/`, `battery/`, `accps/` (IOPS accessories), `accessories/` (permission-free watcher).
- `calendar/detector2.swift` — meeting-link detector v2 with 12 tests. `camera/`, `apps-share/`, `airdrop/` (AirDrop/picker presentation probe).
- `tray/`, `tray2/` (format support and sizes), `loginitem/` (Probe.app), `fullscreen/` (observer + fullscreen test app), `environment/`, `session/`, `schemes/`, `symbols/`, `tapmatrix/`, `apicheck/` (compile-only availability checks at 14.0).

Sources:
- [volumeHUD README (MIT)](https://github.com/dannystewart/volumeHUD) — interception approach on macOS 26, Accessibility requirement
- [Apple TN3152 calendar access levels](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels)
- [Apple Hardened Runtime docs (JSON)](https://developer.apple.com/documentation/security/hardened-runtime)
- [MacPaw: Detecting screen capture](https://macpaw.tech/research/is-mac-screen-captured)
- [Apple forum: detect screen sharing](https://developer.apple.com/forums/thread/667549)
- [Apple forum: SMAppService](https://developer.apple.com/forums/thread/777520)
- [Hammerspoon private AirPods battery category](https://cdn05042023.gitlink.org.cn/dnrops/hammerspoon/src/branch/track-lua-threads/extensions/battery/libbattery.m)
- [MonitorControl README](https://github.com/MonitorControl/MonitorControl/blob/main/README.md)

# Cranny Design System: Direction B, "Expressive Ambient" (codename *Afterglow*)

> **Status:** proposal, verified as a PoC. Every Swift API named here was checked against the
> macOS 27 SDK (Xcode 27.0, Swift 6.4). The full token and component code (Appendix A) **compiles
> cleanly, with no warnings, as a SwiftPM library** (`platforms: [.macOS(.v14)]`, tools 6.2, Swift 6
> language mode). It uses the same upcoming features as the real `CrannyKit`
> (`NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility`,
> `ExistentialAny`). It was also rendered to reference PNGs with `ImageRenderer`. PoC location:
> `scratchpad/poc/design-ambient/pkg` (library target `CrannyDesign` plus executable
> `AmbientRender`). Renders are in `scratchpad/poc/design-ambient/out/*.png`.
>
> The direction in one sentence: **the island is a black crevice that light leaks out of.** At rest
> you cannot tell it apart from the hardware notch. When something happens, the colour of what is
> happening spills out of it as light. The colour comes from album art, the meeting's calendar,
> the ember of a timer, or the green of a charger. That light behaves like light, not like
> decoration.

---

## 0. Research: what exists and what people complain about

**What the category looks like.** NotchNook, Alcove, boring.notch, Atoll, Notchy and Droppy all
follow the same model. A black shape grows out of the notch. In the "closed" or "compact" state,
small content flanks the camera, such as album art plus a waveform, or a timer. On hover or click
it expands into a panel of widgets (media, calendar, shortcuts, mirror, tray). NotchNook is
generally seen as the most visually refined and has the best file tray. Alcove is the one praised
for animation: MacStories called its UI animations "buttery smooth", close to Apple's Dynamic
Island. boring.notch is free and open source, but its animations are generally described as less refined.

**Concrete complaints and how this proposal answers each one.** Sources are listed at the end of
this section.

| # | Complaint (source) | Cranny response (section) |
|---|---|---|
| 1 | On an external monitor NotchNook still draws a notch shape, which the reviewer found visually jarring; a floating island was suggested (MacStories) | Default no-notch style is a **menu-bar pill** that opens as a **floating panel with convex corners**; the virtual notch is opt-in (§3.4) |
| 2 | The Now Playing overlay stays above full-screen apps and video (MacStories; boring.notch #663, #239, #1278, #814, #522) | **Full-screen courtesy:** the closed island and compact activities hide in full-screen spaces; only HUD and "meeting in ≤1 min" break through; hovering needs a 0.4 s dwell there (§4.6) |
| 3 | Battery and CPU drain (MacRumors thread; competitor claims) | **Energy budget:** `TimelineView` is *paused* whenever nothing is visible; 30 fps when compact or on battery; Low Power Mode degrades to a static halo (§5.4) |
| 4 | The closing animation jiggles and does not fit the real notch (boring.notch #316, #535) | One animatable vector drives the whole outline; **close is critically damped (bounce 0)**; the closed outline is **1 pt inside** the hardware notch, so calibration error can never show (§3, §4) |
| 5 | The wobble is too aggressive, and people ask for a switch (boring.notch #303) | **Motion style: Calm / Standard / Playful** scales bounce 0 / 1 / 1.35 (§4.1) |
| 6 | A blinking idle emoji is distracting for an ADHD user (boring.notch #294) | **Nothing loops in the closed or compact state** except the audio spectrum while audio actually plays, and that can be set to static. Ambient loops live only in the panel the user opened (§1, P2) |
| 7 | The island covers menu-bar text (boring.notch #121) | Wings are **sized from content** (48 / 72 / 104 pt) and symmetric; **menu-bar courtesy** retracts them while the pointer works the menus (§6.3) |
| 8 | Moving the mouse to a display *above* opens the notch (boring.notch #427); a hidden notch triggers when reaching for browser tabs (Notchy #47) | **Hover intent:** dwell, pass-through velocity, mouse-button and full-screen checks (`HoverIntent`, §4.6) |
| 9 | Album art is hidden under the camera on some setups (boring.notch #448) | `CompactSlots` keeps a **content-free camera housing** plus 6 pt clearance; geometry is re-measured per screen on `didChangeScreenParameters` (§3.3) |
| 10 | Artwork flicker (boring.notch #143); HUD flicker (#1110); hover flicker (#381) | Palette and art transitions are keyed by **track identity**, not artwork object identity; HUD level changes animate only the bar (§4.2) |
| 11 | Focus stealing; Settings opens behind windows (boring.notch #175, #478) | The panel is non-activating and becomes key **only** for keyboard use or text entry; Settings activates the app and orders front (§7) |
| 12 | Unlocalized strings (boring.notch #1073) | All UI text lives in a String Catalog (en, ru); token-level text styles; no string literals in views without `LocalizedStringKey` (§9) |
| 13 | NotchNook Calendar showed no events; Mirror worked only with the built-in camera (MacStories) | Designed **empty and permission states** for every widget; a **camera picker** in Mirror (§6.2) |
| 14 | Users want a media progress bar *around* the notch (boring.notch #1350) | Optional **progress rim**: playback progress traced as light along the island's lower edge (§5.3) |
| 15 | Sneak peek on secondary monitors is unwanted (boring.notch #1415) | Per-display toggles: live activities, peeks and HUD can each be enabled or disabled per display (§7.1) |

**Apple's own Dynamic Island guidance, adopted as rules** (HIG, Live Activities): use **concentric
margins**, where inner radius = outer radius − margin; keep a **black opaque** background with a
**key line** on dark surroundings; never draw content all the way to the edge; custom animations
last **≤ 2 s**; during a layout change, **preserve existing elements and move them** rather than
removing and re-adding them.

Sources: MacStories, "NotchNook and MediaMate"
(https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/);
Club MacStories, "Alcove: an excellent notch utility with beautiful animations"
(https://club.macstories.net/posts/alcove-an-excellent-notch-utility-with-beautiful-animations);
MacRumors forum thread "Notchnook" (https://forums.macrumors.com/threads/notchnook.2463695/);
Notchy's comparison blog, which is competitor-written
(https://notchy.dev/blog/notchnook-vs-boring-notch-vs-alcove/); boring.notch issues #121, #130,
#143, #175, #294, #303, #316, #381, #427, #448, #478, #535, #663, #1073, #1110, #1350, #1415
(https://github.com/TheBoredTeam/boring.notch/issues; **titles and descriptions only**, the code
is GPL and was not read); Notchy feedback #47
(https://github.com/vishvavariya/notchy-feedback/issues/47); Apple HIG, Live Activities
(https://developer.apple.com/design/human-interface-guidelines/live-activities). No competitor
assets, code or UI text are used anywhere in this document.

---

## 1. Principles (and what each one improves over NotchNook)

1. **Light is information, never decoration.** Every colour on the island comes from something
   real: the album art, the calendar of the event, timer ember, charging green, or the semantic
   battery state. There is no random gradient. *Improves on:* NotchNook's colour is mostly the
   waveform. Here the whole island speaks one colour language, which makes it more meaningful and
   less noisy.
2. **Invisible at rest, calm in the corner of the eye.** The closed state is pixel-identical to
   the hardware notch. The compact state has no idle motion, apart from the spectrum while audio
   plays, and that can be set to static. Ambient effects animate only inside the open Nook, which
   the user opened on purpose. *Improves on:* attention-grabbing idle animations, and overlays on
   top of full-screen video.
3. **One continuous object.** The island is a single shape with one animatable outline vector.
   Elements are *carried* between states with matched geometry: album art flies from the 20 pt
   wing to the 34 pt peek to the 104 pt card. Nothing pops or wobbles. It grows with a little joy
   and lands back in the notch exactly, with zero overshoot. *Improves on:* jiggle on close,
   shape mismatch, and content that teleports between states.
4. **Intent over accident.** It opens when you mean it: hover dwell, pass-through detection,
   mouse-button and full-screen checks, a close grace period, and menu-bar courtesy. *Improves
   on:* accidental opens when moving to another display or reaching for tabs.
5. **Legible first.** Every text token is contrast-audited against the worst-case glow beneath it
   (§2.1). Accents extracted from art are guarded to ≥ 4.5:1, or ≥ 7:1 with Increase Contrast. Glows
   are light and never sit behind text without a scrim or a dense card.
6. **Expressiveness is a dial, and the system wins.** Ambience (Off, Subtle, Vivid), Motion (Calm,
   Standard, Playful) and Accent source (Content, System, Brand, White) are user dials. Reduce
   Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color always override
   them.
7. **Energy-honest.** Effects pause when unseen, degrade in Low Power Mode and on battery, and the
   visualizer never pretends to be beat-accurate unless it has real audio levels.

---
## 2. Tokens (Swift; module `CrannyDesign`)

**Module placement.** Put this in a library target, `CrannyDesign`, inside `CrannyKit`. Give it
`defaultIsolation(nil)`, the same "nonisolated" settings as `CrannyCore`. Feature modules depend on
it and read **one** environment value, `\.cranny`.

> **Verified gotcha:** in a target with `.defaultIsolation(MainActor.self)`, which is what feature
> modules use, a `Shape` or `VectorArithmetic` struct becomes main-actor-isolated. The compiler then
> rejects its `Shape` and `Animatable` conformances ("conformance … crosses into main
> actor-isolated code"). Either keep shapes and token values in `CrannyDesign`, which is
> nonisolated by default, or declare them `nonisolated struct Foo: Shape` in feature modules. The
> PoC's `CheckMark` shape in a MainActor-default target compiles that way.

### 2.1 Colour

**The island is always dark.** It must read as part of the bezel, so it never follows light mode.
Settings, onboarding and the menu use **system** colours and follow the user's appearance.

| Token | Standard | Vivid ambience | Increase Contrast | Reduce Transparency |
|---|---|---|---|---|
| `notch` | `#000000` | = | = | = |
| `card` (smoked glass) | white 0.13 @ 74 % | white 0.13 @ 80 % | white 0.12 opaque | white 0.11 opaque |
| `cardHover` / `cardPressed` | 0.17 @ 78 % / 0.21 @ 80 % | @ 84 % / @ 86 % | 0.18 / 0.24 opaque | 0.15 / 0.19 |
| `well` (inset fields, tracks) | white 7 % | = | white 0.16 opaque | white 0.15 |
| `hairline` (key line, card rim) | white 9 % | = | white 34 % | white 0.20 |
| `strokeStrong` (selection, drop target) | white 22 % | = | white 70 % | white 0.36 |
| `divider` | white 8 % | = | white 28 % | white 0.17 |
| `scrim` (text directly on light) | black 45 % | = | black 75 % | black |
| `textPrimary` | white 96 % | = | white 100 % | white 0.96 |
| `textSecondary` | white 68 % | **white 72 %** | white 86 % | white 0.70 |
| `textTertiary` | white 52 % | **white 60 %** | white 74 % | white 0.55 |
| `textDisabled` (never informational) | white 30 % | = | white 45 % | white 0.32 |

Cards are **smoked**, meaning dark and translucent, and not white-alpha. Over a bright aurora a
white-alpha card washes out, while a smoked card dims the light under it.

**Contrast audit.** The values below are computed in the PoC (`AmbientRender`, sRGB "over"
compositing). "Worst glow" assumes the brightest possible aurora pixel, pure white light, directly
under the card.

| Text on… | primary | secondary | tertiary |
|---|---|---|---|
| card over black (Standard) | 16.3 | 8.6 | 5.6 |
| card over worst glow, Subtle ambience | — | 6.6 | **4.54** |
| card over worst glow, Vivid with *standard* tokens | 7.9 | 4.9 | 3.6 ✗ |
| card over worst glow, Vivid with **vivid** tokens | — | 6.0 | **4.74** ✓ |
| high-contrast card | 16.6 | 12.5 | 9.6 |

This is why Vivid automatically swaps in denser cards and lifted secondary and tertiary text.
Semantic colours on a card: success 8.7, warning 12.5, danger 5.2, info 10.3, brand iris 4.8.

**Semantic and brand.** These are the system dark-appearance hues, so they match the menus and
HUDs people already know.

| Token | Hex | Use |
|---|---|---|
| `success` | `#30D158` | charging, Join, completed |
| `warning` | `#FFD60A` | ≤ 20 % battery, timer last 10 s |
| `danger` | `#FF453A` | ≤ 10 % battery, failed pipeline, weekday label |
| `info` | `#64D2FF` | AirDrop target active, links |
| `record` | `#FF375F` | camera live dot (Mirror) |
| Brand "Afterglow" ramp | ember `#FF7A45` · rose `#FF4F8B` · iris `#8B6CFF` · lagoon `#2ED3C6` · night `#0B0A14` | icon, onboarding, fallback ambient palette, timer (ember) |

**Accent strategy.** Accent is resolved **per activity**, not globally:

| Activity | Accent and glow source |
|---|---|
| Media | `AmbientPalette.extract(from: artwork)` gives three glows plus a contrast-guarded accent. Greyscale art yields an honest silver `mono` palette, never invented colour |
| Calendar | the event's calendar colour → `AmbientPalette.calendar(c)` |
| Timer | `.timer` (ember) |
| Battery | `.charging` / `.lowBattery` (semantic) |
| HUD | album `glow1` if media is playing *and* "Colour HUD" is on; otherwise white |
| Fallback | `.afterglow` brand palette |

The user can override this in Settings ▸ Appearance ▸ Accent: **From content** (default),
**System** (`NSColor.controlAccentColor`), **Brand**, or **White** (no colour at all).

Two roles are never mixed:

- `glow1…3` are **light**. They may be any brightness and are used only for aurora, halos,
  underglow and the HUD fill gradient.
- `accent` is for **foreground marks**: progress fills, the live caption, rings and toggles.
  `RGB.legibleOnBlack(ratio:)` lifts brightness and then reduces saturation until the colour reaches
  4.5:1, or 7:1 with Increase Contrast.
- Labels *on* an accent fill use `RGB.onColor`, which picks black or white by contrast.

```swift
// Excerpt (full: Appendix A.1/A.2)
public extension RGB {
    func legibleOnBlack(ratio: Double = 4.5) -> RGB { /* brighten, then desaturate, until ≥ ratio */ }
    var onColor: RGB { contrast(with: .black) >= contrast(with: .white) ? .black : .white }
    var luminous: RGB { /* s ∈ 0.45…0.90, v ∈ 0.75…0.95 — light, never neon-white */ }
}
```

**Palette extraction** runs on a 24×24 thumbnail with deterministic k-means (k = 5, 8 iterations).
Clusters are ranked by population × colourfulness, with near-black and near-white penalised. It
picks three hue-distinct glows and the most chromatic cluster as the accent. **Measured: 0.115 ms
per artwork**, averaged over 100 runs in the PoC. Run it off the main actor and cache it by track
identifier. The PoC's mock artwork gave an accent with **4.71:1** against black. When the album
changes, call `withAnimation(theme.anim.colorShift) { palette = new }`. `AmbientBackdrop` is
`Animatable` over the palette vector, because `RGB` conforms to `VectorArithmetic`, so the light
cross-fades smoothly inside Canvas and MeshGradient. Those views would otherwise snap.

### 2.2 Typography

macOS has **no Dynamic Type for third-party UI**. This was verified in the PoC:
`.dynamicTypeSize(.accessibility3)` renders "Cranny Hello" at exactly the same 78 px width as
`.large`. Cranny therefore resolves every font through its own `TypeScale`, and the user picks a
size in Settings ▸ Appearance ▸ Text size: **Small 0.9 · Default 1.0 · Large 1.15 · Extra Large
1.3**.

| Style | Size @1.0 | Weight / design | Digits | Use |
|---|---|---|---|---|
| `display` | 30 | semibold, **SF Pro Rounded** | tabular | timer face, big numerals |
| `title2` | 20 | semibold rounded | — | calendar day number, tray count |
| `title` | 15 | semibold rounded | — | track title, widget hero |
| `headline` | 13 | semibold SF Pro | — | card titles, event titles |
| `body` | 13 | regular | — | notes, to-dos |
| `callout` | 12 | medium | — | artist, secondary lines |
| `caption` | 11 | medium | **tabular** | times, metadata |
| `micro` | 10 | semibold rounded, **UPPERCASE, +0.6 tracking** | — | section labels, badges |
| `compact` | 12, **capped at 14** | semibold rounded | **tabular** | live-activity wings (fixed band height) |
| `code` | 12 | regular **SF Mono** | — | notes code mode |

Rules:

- Rounded is used for numerals and titles, which gives warmth. SF Pro is used for reading text,
  which gives density.
- Every changing number (timer, HUD value, battery, times) uses `.monospacedDigit()` together
  with `.contentTransition(.numericText(value:))`, so digits roll rather than jitter.
- `Text(...).crannyFont(.micro)` applies font, tracking and uppercasing in one call.
- At Large and Extra Large, the **cell grows** to `64 × min(scale, 1.15)` pt, so widgets keep their
  content instead of truncating. Wings switch to a wider `SlotWidth` when text no longer fits.

### 2.3 Spacing, density, radii, strokes

**Spacing** uses a 4-pt base with 2- and 6-pt half steps: `xxs 2 · xs 4 · s 6 · m 8 · l 12 · xl
16 · xxl 20 · xxxl 24 · huge 32`. **Density** (Settings ▸ Appearance ▸ Padding: Compact 0.75 ·
Regular 1 · Spacious 1.25) scales *inner* paddings only. The cell grid and island geometry never
reflow because of density.

**Radii** are all continuous (`RoundedRectangle(cornerRadius:style: .continuous)`) and all
**concentric**: inner = outer − gap.

```
open panel bottom  30 ─(12 panel padding)→ card 18 ─(8)→ control 10
peek chin          22                       album art (media card) 12, compact art 5
compact wings      min(height/2, 14)        quick-app tile 14, chip 8
```

**Strokes:**

- `Stroke.hairline(displayScale)` is exactly 1 device pixel: 0.5 pt on Retina, 1 pt on most
  external displays.
- `regular` 1 · `focus` 2 · `ring` 5 (widget rings) · `ringCompact` 2.5 · `dropDash [6, 5]`.

### 2.4 Elevation and light

| Token | Value | Notes |
|---|---|---|
| `Elevation.panel` | black 55 %, radius 28, y 14 | open Nook and peek with chin; the host window must extend ≥ 42 pt below |
| `Elevation.chin` | black 40 %, r 16, y 8 | HUD, quick peek |
| `Elevation.glowSoft` / `glowStrong` | 35 % r 24 / 55 % r 40 | halos behind art and rings, in content colour |
| `Elevation.underglow` | `glow1` @ 30 %, r 36, y 10 | coloured light spilling **onto the desktop** below the open island. **Vivid only**; never with Reduce Transparency or Increase Contrast |

Content halos (`Halo`) scale with `theme.ambience.intensity`. At Ambience Off there are none.

### 2.5 Theme plumbing

```swift
public struct CrannyTheme: Sendable, Equatable {
    public var surfaces: SurfaceTokens = .standard
    public var type = TypeScale()
    public var density: Density = .regular
    public var ambience: AmbienceLevel = .subtle      // off · subtle · vivid
    public var motion: MotionStyle = .standard        // calm · standard · playful
    public var accentSource: AccentSource = .content
    public var capsuleButtons = true                  // Appearance ▸ Button shape
    public var dividers = false                       // Nook ▸ Show dividers
    public var hapticsEnabled = true
    // resolved from the system by CrannyThemeRoot — features never read raw a11y flags
    public var reduceMotion = false, reduceTransparency = false
    public var increaseContrast = false, differentiateWithoutColor = false
    public var anim: MotionTokens { MotionTokens(style: motion, reduceMotion: reduceMotion) }
}
public extension EnvironmentValues { @Entry var cranny = CrannyTheme() }   // @Entry verified with Xcode 27 macros

// Root of every notch-hosted view:
hostingView.rootView = NotchRoot().modifier(CrannyThemeRoot(base: settings.theme))
// → merges accessibilityReduceMotion / accessibilityReduceTransparency / colorSchemeContrast /
//   accessibilityDifferentiateWithoutColor, swaps surface sets (vivid → opaque → highContrast),
//   caps ambience at .subtle under Increase Contrast, forces .colorScheme(.dark).
```

---
## 3. Geometry of the island

### 3.1 Hardware facts (measured, never hard-coded)

Measure these per `NSScreen` and re-measure on
`NSApplication.didChangeScreenParametersNotification`:

```swift
let left  = screen.auxiliaryTopLeftArea      // nil on displays without a notch
let right = screen.auxiliaryTopRightArea
let notchWidth    = screen.frame.width - (left?.width ?? 0) - (right?.width ?? 0)   // only if both non-nil
let notchHeight   = screen.safeAreaInsets.top                                       // 0 without a notch
let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY                    // when the menu bar is shown
```

The PoC probe was run on this Mac's active display, an external 2560×1440 OLED. It reported no
auxiliary areas, `safeTop 0`, and a **30 pt menu bar** (`NSStatusBar.thickness` reports 22, so use
`visibleFrame`, not the status-bar thickness). `HardwareNotch.fallback` (185 × 32 pt, the 14"/16"
MacBook Pro at default scaling) is used only if measurement fails on a notched display. The
physical notch is fixed in *pixels*, so its width in points changes with display scaling, which is
another reason to always measure.

### 3.2 The shape

`NotchShape` is a single closed path driven by **one** animatable value, `NotchMetrics`
(`VectorArithmetic`). It holds width, height, bottom radius, a **signed** top corner and a top
offset. Positive `topCorner` draws concave **ears**: the quarter-round flares where the island's
top edge meets the screen edge, so it appears to grow *out of* the bezel. Negative `topCorner`
draws convex corners for a detached pill or panel. The value crosses zero smoothly, so one spring
can morph an attached tab into a floating panel. A `smoothing` term (0.6) lengthens the Bézier
handles and the corner extents for a continuous-corner feel without a superellipse.

The host frame stays **fixed** at the window's maximum size and only `metrics` animates. This
means no layout pass per frame, and the camera housing stays exactly centred.

```swift
// MARK: - Animatable metrics

/// Everything the island outline needs, as ONE animatable vector: a single spring drives width,
/// height, both radii and the attach/detach offset together, so the outline can never wobble
/// out of sync (the "jiggle on close" users report in other notch apps).
public struct NotchMetrics: VectorArithmetic, Sendable {
    public var width: CGFloat         // body width, excluding ears
    public var height: CGFloat        // from the top edge (+ topOffset when detached)
    public var bottomRadius: CGFloat
    /// Signed top corner: > 0 concave "ear" flaring into the screen edge (attached),
    /// < 0 convex corner (detached pill/panel), 0 square. Crossing 0 morphs smoothly.
    public var topCorner: CGFloat
    public var topOffset: CGFloat     // 0 when attached to the top edge

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, topCorner: CGFloat, topOffset: CGFloat = 0) {
        self.width = width; self.height = height; self.bottomRadius = bottomRadius
        self.topCorner = topCorner; self.topOffset = topOffset
    }

    public static var zero: NotchMetrics { .init(width: 0, height: 0, bottomRadius: 0, topCorner: 0) }
    public static func + (a: Self, b: Self) -> Self {
        .init(width: a.width + b.width, height: a.height + b.height, bottomRadius: a.bottomRadius + b.bottomRadius,
              topCorner: a.topCorner + b.topCorner, topOffset: a.topOffset + b.topOffset)
    }
    public static func - (a: Self, b: Self) -> Self {
        .init(width: a.width - b.width, height: a.height - b.height, bottomRadius: a.bottomRadius - b.bottomRadius,
              topCorner: a.topCorner - b.topCorner, topOffset: a.topOffset - b.topOffset)
    }
    public mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        width *= k; height *= k; bottomRadius *= k; topCorner *= k; topOffset *= k
    }
    public var magnitudeSquared: Double {
        Double(width * width + height * height + bottomRadius * bottomRadius + topCorner * topCorner + topOffset * topOffset)
    }
    /// Horizontal footprint including ears (hit-testing, window sizing).
    public var outerWidth: CGFloat { width + 2 * max(topCorner, 0) }
    public var bottom: CGFloat { topOffset + height }
}

// MARK: - Shape

/// The Cranny island, centred horizontally in its rect and top-aligned.
/// Host it in a FIXED frame (the window's max size) and animate only `metrics`:
/// no layout pass per frame, and the camera housing stays exactly centred.
public struct NotchShape: Shape {
    public var metrics: NotchMetrics
    /// 0 = circular corners; 1 = longer, softer curvature onset (continuous-corner feel).
    public var smoothing: CGFloat

    public init(metrics: NotchMetrics, smoothing: CGFloat = 0.6) {
        self.metrics = metrics; self.smoothing = smoothing
    }

    public var animatableData: NotchMetrics {
        get { metrics }
        set { metrics = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let m = metrics
        let w = max(m.width, 0), h = max(m.height, 0)
        guard w > 0.5, h > 0.5 else { return Path() }

        let minX = rect.midX - w / 2, maxX = rect.midX + w / 2
        let top = rect.minY + m.topOffset, bottom = top + h

        let k = 0.5523 + 0.12 * smoothing          // cubic handle ratio (0.5523 = circle)
        let ext = 1 + 0.28 * smoothing              // corner reaches further along each edge
        let ear = min(max(m.topCorner, 0), h * 0.5)                   // concave
        let cvx = min(max(-m.topCorner, 0) * ext, h * 0.5, w * 0.5)   // convex
        let br = min(max(m.bottomRadius, 0) * ext, h - max(ear, cvx), w * 0.5)

        var p = Path()
        p.move(to: CGPoint(x: minX - ear + cvx, y: top))
        p.addLine(to: CGPoint(x: maxX + ear - cvx, y: top))
        // top-right
        if ear > 0 {        // concave quarter, centre (maxX + ear, top + ear)
            p.addCurve(to: CGPoint(x: maxX, y: top + ear),
                       control1: CGPoint(x: maxX + ear - ear * k, y: top),
                       control2: CGPoint(x: maxX, y: top + ear - ear * k))
        } else if cvx > 0 {
            p.addCurve(to: CGPoint(x: maxX, y: top + cvx),
                       control1: CGPoint(x: maxX - cvx + cvx * k, y: top),
                       control2: CGPoint(x: maxX, y: top + cvx - cvx * k))
        }
        // right wall, bottom-right
        p.addLine(to: CGPoint(x: maxX, y: bottom - br))
        p.addCurve(to: CGPoint(x: maxX - br, y: bottom),
                   control1: CGPoint(x: maxX, y: bottom - br + br * k),
                   control2: CGPoint(x: maxX - br + br * k, y: bottom))
        // bottom edge, bottom-left
        p.addLine(to: CGPoint(x: minX + br, y: bottom))
        p.addCurve(to: CGPoint(x: minX, y: bottom - br),
                   control1: CGPoint(x: minX + br - br * k, y: bottom),
                   control2: CGPoint(x: minX, y: bottom - br + br * k))
        // left wall, top-left
        if ear > 0 {
            p.addLine(to: CGPoint(x: minX, y: top + ear))
            p.addCurve(to: CGPoint(x: minX - ear, y: top),
                       control1: CGPoint(x: minX, y: top + ear - ear * k),
                       control2: CGPoint(x: minX - ear + ear * k, y: top))
        } else {
            p.addLine(to: CGPoint(x: minX, y: top + cvx))
            if cvx > 0 {
                p.addCurve(to: CGPoint(x: minX + cvx, y: top),
                           control1: CGPoint(x: minX, y: top + cvx - cvx * k),
                           control2: CGPoint(x: minX + cvx - cvx * k, y: top))
            }
        }
        p.closeSubpath()
        return p
    }
}
```

### 3.3 Sizes per state

All sizes are derived from `band` (the hardware notch height, or the menu-bar height), `W` (the
notch width) and the grid. The numbers below are PoC output for **W = 185, band = 32** (14"/16"
MacBook Pro).

| State | Formula | W × H (pt) | Bottom r | Top corner |
|---|---|---|---|---|
| **Closed** (notched) | `(W − 2) × (band − 1)`, r = round(0.30·band), ears = round(0.14·band) | **183 × 31** | 10 | ears 4 |
| Closed + hover "breath" | +14 w, +3 h, +1 r | 197 × 34 | 11 | ears 4 |
| **Compact**, icon wings | `W + 2·side`, `side = band + 16` (48) | **281 × 32** | min(h/2, 14) = 14 | ears 8 |
| Compact, text wings | side = 2.25·band (72) | 329 × 32 | 14 | ears 8 |
| Compact, wide wings | side = 3.25·band (104) | 393 × 32 | 14 | ears 8 |
| **Peek** (hover expansion / quick peek) | compact + chin 50, min width 360 | **360 × 82** | 22 | ears 10 |
| **HUD** | compact (icon / text) + chin 16 | 329 × 48 | 22 | ears 10 |
| **Open** (10 columns × 2 rows) | grid + 2×12 wide; `band + 6 + 136 + 12` tall | **736 × 186** | 30 | ears 14 |
| Open (12 columns × 3 rows, "tall") | | 880 × 258 | 30 | ears 14 |
| Host window (10 columns) | open outer width + 112, open bottom + 56 | 876 × 242 | | |

Notes:

- **Closed is 1 pt inside the hardware outline** (−2 pt width, −1 pt height). A calibration error
  therefore can never show as a black rim around the real notch. The island is invisible until it
  grows *past* the hardware and seems to emerge from it. The bottom radius and ear values are
  **starting values to calibrate on real hardware**: this machine's notch could not be measured
  because its display is external. Settings ▸ General ▸ Notch fit offers width ±20, height ±4 and
  radius ±4, with a live red fit-check outline while a slider is dragged (render `states.png`,
  row 1).
- **Wings are symmetric.** The camera is centred, so both wings take the wider of the two slot
  widths, and content inside each wing aligns *away* from the camera. `CompactSlots` keeps the
  camera housing content-free, with 6 pt camera clearance and 8 pt outer inset, so content never
  pokes into the corner curve. This is the HIG concentric-margin rule.
- **Width scaling.** Slot widths are multiples of `band`, so they scale with display scaling. The
  open width is clamped to `screenWidth − 96` and is never narrower than `W + 320`.
  `NookGridSpec.columnsThatFit` caps the columns: 1470 pt and 1280 pt screens both allow 12.

### 3.4 Displays without a notch

On an external display a fake notch is jarring (MacStories), so the default is
**`NoNotchStyle.menuBarPill`**:

| State | Geometry (30 pt menu bar) | Look |
|---|---|---|
| Closed "handle" | 44 × 5 pt capsule, 3 pt below the top edge (`topCorner −2.5`) | black; *Transparent handle* option makes it invisible until the pointer is within 60 pt, then fades in over 0.15 s |
| Hover | 72 × 8 capsule | |
| Compact | `(120 + 2·side) × (menuBar − 6)`, e.g. **212 × 24**, fully rounded | a pill *inside* the menu-bar band; never covers window content |
| Open | same grid panel, **detached, convex 30 pt corners**, `topOffset 3` | a floating panel (`no-notch.png`) |

`.virtualNotch` (an attached 72 × 6 tab with ears) is available for people who like the notch look.
`.hiddenHandle` behaves like the pill but has no visible handle. In the open header the empty
"camera zone" becomes a **clock/date label** on no-notch displays (micro style, secondary), so the
centre is never dead space. The signed top corner morphs attached ⇄ detached in one spring
(`morph-pill.png`).

### 3.5 Window, hit-testing and layering (contract for the notch-window module)

- One borderless, non-activating `NSPanel` per enabled display, at its fixed `windowSize(grid:)`,
  top-centred, transparent, above the menu bar, joining all spaces.
- **Hit-testing follows the path, not the window.** On every pointer move, test
  `NotchShape(metrics: current).path(in: bounds).contains(point)`. Add 6 pt slop when closed and
  4 pt when compact. Toggle `ignoresMouseEvents` so everything outside the island clicks through.
- The panel becomes key (`canBecomeKey` returns true only while open) **only** when the user
  types in Notes or To-dos, or opens via the keyboard shortcut. Otherwise it never steals focus.

---

## 4. Motion

### 4.1 Springs and tokens

All values are `Animation.spring(duration:bounce:)` (perceptual duration; macOS 14+) unless noted.
**Bounce is multiplied by the Motion style**: Calm × 0, Standard × 1, Playful × 1.35.

| Token | Value | Used for |
|---|---|---|
| `open` | 0.42 s, bounce 0.14 | closed/peek → open |
| `close` | 0.36 s, **bounce 0, always** | open/peek → closed. Must land exactly on the notch |
| `peekIn` | 0.38 s, 0.18 | compact wings appear |
| `peekOut` | 0.30 s, **0** | wings retract into the camera |
| `chinDrop` | 0.45 s, 0.16 | hover expansion, quick peek, HUD appear |
| `breathe` | 0.26 s, 0.25 | closed hover breath |
| `resize` | 0.40 s, 0.08 | open → open (tabs of different height) |
| `contentIn` | 0.34 s, 0.06 | content materialising |
| `contentOut` | easeIn 0.10 s | content leaves *before* the shape shrinks |
| `crossFade` | `.smooth(duration: 0.28)` | activity content swap |
| `tab` | 0.32 s, 0.10 | tab capsule (`matchedGeometryEffect`) |
| `hover` | 0.20 s, 0.20 | card fill, tile lift, button background |
| `press` | 0.16 s, 0 | button scale 0.92 |
| `level` | 0.18 s, 0 | HUD bar follows key repeat directly |
| `snapBack` | 0.30 s, 0.05 | uncommitted swipe returns |
| `tracking` | `.interactiveSpring(duration: 0.15)` | finger-driven offsets |
| `colorShift` | easeInOut 0.8 s | palette cross-fade on album change |

The governing rule: **geometry may overshoot when it grows, and never when it shrinks back into
the hardware.** No custom transition exceeds 0.8 s. The only exceptions are ambient loops and the
0.9 s ember burst, which keeps everything under the HIG's 2 s ceiling.

### 4.2 Choreography

The time origin is the trigger (hover dwell met, click, or swipe commit).

**Open**

- 0.00 The shape starts `open`. Wing content fades out (`contentOut`), **except the album art,
  which flies** (`matchedGeometryEffect`, shared namespace) from the 20 pt wing to the 104 pt media
  card.
- 0.06 The header (tabs and actions) materialises: opacity 0→1, blur 8→0, scale 0.94→1, anchored
  top.
- 0.06 + 0.025·i Widget cards materialise left to right. The stagger is capped at 4, so the last
  card starts by 0.16 s.
- 0.10 Ambient intensity ramps 0 → target over 0.5 s easeOut, so the light "fills" the island as it
  opens. The backdrop is framed to the island's *current* bounds, so the light rises with the
  bottom edge.
- The motion settles at ≈ 0.5 s.

**Close**

- 0.00 Content leaves (`contentOut`, no stagger) and ambient goes to 0 over 0.2 s.
- 0.04 The shape starts `close` and lands on the hidden closed outline. If an activity is
  running, it lands on *compact* instead, and the wing content re-enters at 0.20 with
  `emerge(from:)`.

**Peek in and out (activity starts or ends)**

- In: the shape `peekIn`. Wing content `emerge`s *from behind the camera* (anchored on the camera
  side, scale 0.6→1, blur 4→0) at +0.08.
- Out: the reverse, with `peekOut`.

**Song change**

- A quick peek (`chinDrop` to 360 × 82). The art swaps with `.blurReplace`, the palette
  cross-fades (`colorShift`) and the tide gets an energy ripple (0→1→0 over 0.6 s).
- It auto-retracts after 2.5 s unless hovered. Configurable: Off / On change / On change and
  resume.

**HUD**

- The first key press opens the HUD chin (`chinDrop`).
- Later presses animate **only** the bar (`level`) and the number (`.numericText`). The shape does
  not move, which removes flicker.
- It dismisses 1.5 s after the last change (`peekOut`).

**Tab switch**

- The capsule slides (`tab`), the content uses `tabSlide(forward:)` (14 pt slide plus 6 pt blur),
  and the panel height changes with `resize` if the tabs differ in height.

**Hover**

- Closed → `breathe`. Cards change fill (`cardHover`) without moving. Tiles lift with scale 1.04.
  Buttons get a hover background. Nothing moves on hover in Calm.

**Reduce Motion**

- `MotionTokens` returns ease-out ≤ 0.22 s **without bounce** for geometry.
- All materialise, emerge and slide transitions become `.opacity`.
- The stagger is 0. Press feedback is an opacity change instead of a scale.
- Matched-geometry flights become cross-fades.
- Ambient effects **freeze on a pleasant frame**: the colour stays and the movement goes.
- Ember bursts become a static glow fade. Typing effects are off and the spectrum is static.

### 4.3 Transitions (excerpt; full code in A.3)

```swift
.transition(.materialize(theme.reduceMotion))                     // content out of the notch
.transition(.emerge(from: .leading, reduceMotion: theme.reduceMotion))  // wing content from the camera
.transition(.tabSlide(forward: newIndex > oldIndex, reduceMotion: theme.reduceMotion))
Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))   // "4:59"
    .monospacedDigit().contentTransition(.numericText(countsDown: true))
```

### 4.4 Gestures and rubber-banding

| Gesture (trackpad scroll phases over the island) | Behaviour |
|---|---|
| Two-finger horizontal swipe on compact or media | Content tracks the finger through `rubberBand(dx, limit: 22)`. **Commit** at 56 pt accumulated or 600 pt/s, which plays haptic `.alignment`, slides the old art out 24 pt in the swipe direction and the next art in from the other side. Otherwise `snapBack`. Invertible in Settings ▸ Gestures |
| Two-finger swipe down on closed or compact | The island **stretches**: height + `rubberBand(dy, limit: 28)`, bottom radius stays. Commit opens the Nook |
| Swipe up on open | Closes |
| Swipe up on compact | **Dismisses that activity** until its next event. Wings retract into the camera with a 6 pt upward drift |
| Axis lock | Horizontal only if \|dx\| > 1.6·\|dy\| |

`rubberBand(x, limit, c = 0.55) = sign(x)·(1 − 1/(|x|·c/limit + 1))·limit`. The resistance grows
continuously and never hard-stops.

### 4.5 Delight moments (all original, all optional)

Delight moments have caps: at most one plays at a time, none play in full-screen spaces, and none
play when "Quiet" is on in the menu bar extra.

| Moment | What happens | Reduce Motion |
|---|---|---|
| **First light** (first open per session) | The aurora fades in from the camera outward over 1.2 s | static fade |
| **Song change** | Palette cross-fade plus a tide ripple | colour only |
| **Timer done** | `EmberBurst` fans out of the notch (0.9 s), the underglow pulses twice in ember, and the chin offers "Stop · +1 min" | static ember glow |
| **File dropped into the tray** | The island "gulps": height −3 pt then a spring back over 0.25 s, plus a small ember burst and haptic `.generic` | no gulp |
| **Charger connected** | Green light sweeps once along the lower rim (progress-rim path) | instant rim |
| **Second activity** | **Satellite split**: a 22 pt black bubble buds off the trailing wing with a liquid neck (Canvas `blur` + `alphaThreshold`, no Metal; `satellite.png`), then detaches 6 pt away. Clicking it swaps primary and secondary | fade in |
| **To-do completed** | The check draws itself (trim 0→1, 0.25 s) and six motes sparkle | instant check |
| **Meeting in 1 min** | The underglow breathes in the event colour on a 2 s period, at most 3 cycles | static tint |

### 4.6 Intent: when to open, when to stay out of the way

`HoverIntent.shouldOpen(...)` in A.3 implements these rules:

- **Dwell.** Instant 0 · Short 0.12 s (default) · Long 0.35 s.
- **Pass-through.** Upward pointer velocity above 900 pt/s means the pointer is travelling to a
  display above, so the island does not open.
- **Mouse button down** (window drags, selections) means no open. A **file drag**, however, opens
  the island immediately as a drop zone.
- **Full-screen spaces** require a 0.4 s dwell, because browser tabs and toolbars live up there.
- **Close grace.** The pointer may leave for 0.35 s without closing.
- **Never close while** pinned, typing in Notes or To-dos, dragging, showing a menu or popover, or
  while Demo mode is on.
- **Inactivity timeout.** An open Nook with no interaction closes after N s (default 0 = never).
  *Hide when idle* fades the compact island after N s with no activity (no-notch displays only),
  and **auto-unhides** on the next event.
- **Menu-bar courtesy.** While the pointer is in the menu-bar band more than 40 pt from the island,
  and while menus are tracking, compact wings retract to closed and return 1.5 s later.
  `NSMenu.didBeginTrackingNotification` covers Cranny's own menus. For other apps, use the pointer
  heuristic.

---
## 5. Ambient light: effects, energy, translucency

### 5.1 Effect catalogue

These are original procedural effects. They are pure functions of
`(time, palette, energy, intensity)`, with no per-particle state and no timers. `TimelineView`
provides time.

| Effect | Engine | Look | Where |
|---|---|---|---|
| **Aurora** (default) | `MeshGradient` 4×4 (macOS 15+). Rows 0–1 are fully transparent, so the header band stays pure notch-black; rows 2–3 carry the glows; interior points drift on incommensurate sines, so there is no visible loop. **Fallback on macOS 14:** `Canvas` with 3 blurred sine curtains, `plusLighter` | curtains of album colour rising from the bottom edge; louder audio lifts them | open Nook |
| **Motes** | `Canvas`, 36 stateless particles (hash-seeded); halo plus core fills, no blur filter | slow rising specks, twinkle, brighter on loud passages | open Nook |
| **Tide** | `Canvas`, 3 tapered sine strokes plus a 3 pt bloom copy | luminous wave lines along the bottom edge; amplitude follows audio | open Nook, quick-peek chin |
| **Halo** | `RadialGradient`, `plusLighter` | a single bloom; **cheapest**; used in Low Power Mode | behind art and rings everywhere; open Nook fallback |
| None | — | — | — |

`Settings ▸ Appearance ▸ Effect` and `Ambience Off · Subtle (0.55) · Vivid (1.0)` control these.
The aurora at Vivid is shown in `effects.png`, row 1, with the coloured *underglow* spilling onto
the desktop below the panel. Tide is in row 2, and Subtle is in `open.png`.

**The backdrop is sized to the island's current bounds, not the window.** The PoC caught a real
bug here. Framed to the window, the aurora's bright bottom rows fell *below* the panel and were
masked away. Framed per metrics (as in A.5 `IslandHost`), the light sits at the real bottom edge
and rises as the island opens.

**Audio energy.** The media module supplies `energy` ∈ 0…1. This is real RMS from a Core Audio
process tap, available on macOS 14.2+ with the System Audio Recording permission, smoothed with a
60 ms attack and 300 ms release. Without that permission, energy is 0 and the visualizer runs in
**Ambient** mode, an honest "breathing" pattern (`SpectrumBars.ambient`) that is labelled as such
in Settings ▸ Media ▸ Visualizer: *Live · Ambient · Static · Off*.

**Progress rim (optional, off by default).** In compact media, playback progress is drawn as a
1.5 pt accent line tracing the island's **lower** outline from the left ear to the right ear. It
is a `trim(from: 0, to: progress)` of a bottom-only variant of `NotchShape`. The same path carries
the one-shot "charger connected" sweep.

### 5.2 Energy budget (contract)

| Island state | Effect timeline | Max fps |
|---|---|---|
| Closed | **none exists** | 0 |
| Compact | spectrum only, and only while audio plays (else static bars) | 30 |
| Peek or quick peek | tide in the chin, for its 2.5 s lifetime | 30 |
| Open, on AC | ambient effect | 60 |
| Open, on battery | ambient effect | 30 |
| Low Power Mode, or `thermalState ≥ .serious` | static **halo** (`EffectBudget.effective`) | 0 |
| Full-screen app frontmost on this display, or window occluded | paused | 0 |
| Reduce Motion | paused at a **resting frame** (colour stays) | 0 |

`EffectBudget.minimumInterval` returns `nil` → `TimelineView(.animation(minimumInterval:paused:))`
is paused, which costs nothing.

**Performance targets**, to be verified with Instruments (SwiftUI, Animation Hitches and Energy
Log) on an M1 Air. This PoC could not measure them, because `ImageRenderer` does not reflect
on-screen GPU cost:

- open plus aurora ≤ 3 % CPU at 60 fps
- compact plus spectrum ≤ 0.7 %
- closed ≈ 0 %
- no hitches during open or close at 120 Hz

### 5.3 Translucent background and Liquid Glass

- **Default: opaque black.** The island must be indistinguishable from the hardware.
- **Translucent background** (Settings ▸ Appearance). The **hardware band stays opaque**, so there
  is never a seam around the camera, and the panel below fades to 58 % black over a glass layer.
  - macOS 26+: `Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)`. The
    `Glass` API was verified: `.regular`, `.clear`, `.tint(_:)`, `.interactive(_:)`,
    `GlassEffectContainer`.
  - macOS 14–15: `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, dark aqua).
  - Reduce Transparency always forces opaque.
- **Liquid Glass is not used on the closed or compact island.** Black is the whole illusion.
  Settings, the menu-bar extra and onboarding get the system's Liquid Glass automatically on
  macOS 26+ by using standard controls.

### 5.4 Deliberate non-goals

- **No Metal shader files.** The Metal toolchain is not installed. SwiftUI `Shader` needs a
  compiled metallib, which rules out runtime `makeLibrary(source:)` for SwiftUI.
- **No video, GIF or Lottie loops.**
- **No per-frame blur over large areas.** Only the macOS 14 aurora fallback blurs, once per
  layer.
- **No light behind text without a guarantee** (see §2.1).

---

## 6. Layouts

### 6.1 The open Nook

```
 ← 12 →┌──────────────────────── 736 (10 cols) ────────────────────────┐← 12 →   ears 14
       │ [▦ Nook | ▤ Tray]     ░░░ camera zone (W+12) ░░░     [📌] [⚙︎] │  header = band (32)
       │                                                               │  6
       │ ┌──── 4 cells (280) ───┐┌── 3 (208) ──┐┌ 2 (136) ┐┌1 (64)┐    │
       │ │ MEDIA                ││ CALENDAR    ││ TIMER   ││ app  │    │  2 rows = 136
       │ │                      ││             ││         ││ app  │    │
       │ └──────────────────────┘└─────────────┘└─────────┘└──────┘    │  12
       ╰───────────────────────────────────────────────────────────────╯  bottom r 30
```

**Header.**

- Left wing: tabs in a well capsule (`NookTabs`): **Nook** (widgets), **Tray** (files), plus
  optional user pages "Nook 2…".
- Right wing: **Pin** (`pin` / `pin.fill`, keeps the Nook open) and **Settings** (`gearshape.fill`).
  A 24 pt `IconButton`, capsule or rounded per settings.
- The camera zone holds no content on notched displays and a clock/date on others.

**Grid.**

- Cell 64 pt (74 at Large text), gutter 8, panel padding 12. 6–12 columns (default 10), 2 rows
  (136 pt) or 3 rows in the "tall" layout (208 pt).
- A widget's width is an integer number of cells: `width(cells: n) = 64n + 8(n−1)`.
- The sum of widths can never exceed the columns. The Settings grid editor shows "N cells left"
  and refuses overflow, so there is no hidden horizontal scroll.
- Additional widgets go on a second page, which becomes a header tab.

**Cards.**

- Smoked `card` fill, `Radius.card` 18 (concentric with panel 30 − padding 12), 1 px hairline,
  12 pt padding × density.
- **Flat style** (*Show dividers* on): no card fills; a 1 px `divider` sits between widgets. This
  is the low-ink alternative.

| Widget | Default × rows | Min / max cells | Notes |
|---|---|---|---|
| Media | 4 × 2 | 3 / 5 | |
| Calendar | 3 × 2 | 2 / 4 | |
| Quick Apps / Shortcuts | 1 per column (2 tiles) | 1 / 4 columns | |
| Mirror | 2 × 2 | 2 / 3 | |
| Notes | 3 × 2 | 2 / 6 | tall layout recommended |
| To-dos | 3 × 2 | 2 / 4 | |
| Timer | 2 × 2 | 2 / 3 | |
| AirDrop target | 1 × 2 | 1 / 2 | |
| Files Tray | own tab, full width | — | |

Reference renders: `open.png` (Nook A: media 4 + calendar 3 + timer 2 + apps 1; Nook B: notes 3 +
to-dos 3 + mirror 2 + shortcuts 1 + AirDrop 1; Tray tab).

### 6.2 Widget anatomy

**Media (4 × 2).**

- **Layout:**
  - Art 104 pt, radius 12, with a `Halo` in `glow1` behind it scaled by ambience. The source-app
    badge (18 pt circle, `music.note` or the app icon) sits on its bottom-right corner.
  - The right column holds the title (`title`, 1 line), artist (`callout`, secondary), and a
    scrubber: a 4 pt `well` track with an `accent` fill.
  - Below the scrubber: elapsed and remaining times (`caption`, tabular, tertiary), then the
    controls: previous (28), **play/pause (32, prominent white)**, next (28), a spacer, and output
    device (24, `airplayaudio`).
- **Interactions:**
  - Hover over the art shows "Open in <app>".
  - Dragging the scrubber grows the track to 6 pt and fires haptic `.levelChange` at 10 % steps.
  - A horizontal swipe changes the track (§4.4).
- **States:**
  - Nothing playing: the last track, dimmed, with "Play"; or an empty state with
    `music.note.list` and "Play something".
  - Unsupported player: title only.
- **VoiceOver:**
  - One element, "Now playing: <title> by <artist>".
  - Named actions: Play/Pause, Next, Previous, "Open in <app>".
  - The scrubber is adjustable via `accessibilityAdjustableAction`.

**Calendar (3 × 2).**

- **Header:** weekday (`micro`, danger red), day (`title2`), and a 5-day strip with today in a
  white circle. The strip spans *days behind/ahead* from settings.
- **Rows are single-line:** colour bar 3 × 14, time (`caption`, tabular, tertiary, 34 pt column),
  title (`headline`).
- **Only the live or next event is two-line:** title, then "Now · 12 min left" or "In 4 min" in
  the event colour (guarded ≥ 4.5:1), plus the **Join** capsule (success fill, `video.fill`,
  black label) when a Zoom, Meet or Teams link is detected.
- **Past events today:** shown at 50 % if enabled.
- **Overflow:** "+3 more" (`caption`), and the list scrolls with a fading top and bottom mask.
- **States:** no permission shows the "Connect Calendar" button and a one-line why; no events shows
  "Nothing else today" plus tomorrow's first event.
- The PoC first overflowed with three two-line rows (render v1). That is why only the live event
  gets two lines.

**Quick Apps and Shortcuts (1 cell per column, 2 tiles).**

- **Tiles:** 64 × 64, radius 14. Apps use their icon at 40 pt. Shortcuts use the shortcut's
  colour as a vertical gradient fill with its glyph at 22 pt and a 9 pt semibold label (1 line).
- **Hover:** the tile lifts (scale 1.04) and a `.help` tooltip appears with the full name.
- Click runs or opens. Drag reorders. A "+" tile appears in edit mode.

**Mirror (2 × 2).**

- The camera preview fills the card (aspect-fill), clipped to radius 18, mirrored by default. A
  6 pt `record` dot top-right is labelled "Camera on" for VoiceOver.
- On hover a capsule of controls appears at the bottom: flip, choose camera (`web.camera`, a menu
  of every `AVCaptureDevice` including external ones).
- **Privacy:** the camera never starts by itself. The first click on "Tap to preview" starts it,
  and it stops when the Nook closes.

**Notes (3 × 2; tall recommended).**

- **Header:** note picker (`note.text` + name + `chevron.down`; the menu offers new, rename,
  delete), a **code-mode toggle** (an accent capsule with `chevron.left.forwardslash.chevron.right`)
  and `plus`.
- **Editor:** a `well` with radius 10, `body` 13 or `code` 12 SF Mono.
- **Syntax tokens:** keyword `#FF7AB2`, type/call `#67E8F9`, string `#FFD479`, number/flag
  `#FFA657`, comment `#8E8E93`, plain `#E5E5EA`. In Markdown, headings use iris, emphasis uses
  secondary italic, and code spans use the `well` background. Language is auto-detected from a
  shebang or fenced block, or chosen in the menu.
- **Typing effect** (Motion ≠ Calm, Reduce Motion off):
  - New glyphs are tinted with the accent for 0.35 s and ease back to the text colour. This uses
    TextKit 2 `NSTextLayoutManager.addRenderingAttribute`, which was verified in the SDK.
  - A soft "comet" glow follows the caret, drawn as an overlay at the insertion-point rect.
  - In read-only previews on macOS 15+, a `TextRenderer` reveals text line by line.

**To-dos (3 × 2).**

- **Header:** `TO-DOS` (`micro`) with "2 left" (`caption`).
- **Rows:** a 16 pt check circle (1.5 pt `strokeStrong`, or a success fill with a drawn black
  check), then the text in `body`.
- **Done:** the text is struck through, turns tertiary, and collapses after 1.2 s if "Hide
  completed" is on.
- An inline "+ Add a to-do" row sits at the bottom. Return adds, Esc cancels, ⌘⌫ deletes.

**Timer (2 × 2).**

- **Ring:** 72 pt with a 5 pt stroke, an ember angular gradient, and a `Halo` behind it (ambience
  scaled). Digits are 19 pt rounded, tabular, rolling via `.numericText(countsDown: true)`.
- **Controls:** pause (prominent ember, black glyph) and cancel.
- **Idle:** preset chips (1 · 5 · 10 · 25 min) plus "Custom". Scrolling on the ring adjusts the
  time ±1 min, with a `.levelChange` haptic per step.
- **Last 10 s:** the digits tint `warning` and pulse once per second (Calm or Reduce Motion: colour
  only).

**AirDrop target (1 × 2).**

- A dashed `strokeStrong` drop zone (`Stroke.dropDash`) with `dot.radiowaves.up.forward` and the
  label "AirDrop". The public `airdrop` SF Symbol name does not exist; this was verified.
- **Drag-over:** the stroke turns `info` and the dash phase animates. A click opens
  `NSSharingService(named: .sendViaAirDrop)`.

**Files Tray (own tab).**

- **Left (6 cells):** `TRAY` header with "5 items · 48 MB". Tiles are 52 pt `QLThumbnailGenerator`
  thumbnails in a `well` with radius 12, with 10 pt names truncated in the middle.
- **Selection:** a white check badge. ⌘-click and shift-click multi-select. Space opens Quick Look.
  Drag out moves or copies. × removes.
- **Middle (3 cells): Actions.** Context-aware *pipelines* for the selection:
  - images: Compress, Convert to JPEG/PNG/HEIC, Resize
  - anything: Zip, Copy path, Reveal in Finder, Share
  - archives: Unzip
  - Each runs in place, with a 2.5 pt ring on the tile and the result replacing or adding an item.
    Failures show a `danger` badge with a tooltip.
- **Right (1 cell):** AirDrop.
- "Keep files between launches" is a toggle. The empty state shows `tray.and.arrow.down.fill` and
  "Drop files on the notch".

**Drag-to-notch "catch" state.**

- When a file drag comes within 40 pt of the island (`HoverIntent` lets file drags through
  instantly), the island opens to a catch panel.
- Drop zones are offered according to what the dragged `UTType`s support: **Tray** · **AirDrop**
  · **Compress** (images) · **Zip**.
- The zone under the pointer scales to 1.04, its dash animates, and haptic `.alignment` plays on
  entry. Dropping on an action runs that pipeline directly ("drop-on-action").

### 6.3 Live activities: compact anatomy

| Activity | Leading wing | Trailing wing | Slot | Peek (hover or event) chin | Click | Priority |
|---|---|---|---|---|---|---|
| **HUD** volume, brightness, keyboard | level glyph (`speaker.wave.1/2/3.fill`, `speaker.slash.fill`, `sun.min/max.fill`, `light.min/max`) | value 0–100 (`compact`, `.numericText`) | icon / text | chin 16: `LevelBar` 6 pt, 16 steps | — | 1 (transient 1.5 s) |
| **Meeting** (≤ N min, default 5, and during) | calendar colour bar 3 × 14 + title (`caption`) | "in 4m", "12m left" or elapsed + **Join** capsule | wide / wide | title, time range, link host, Join · Dismiss | Join opens the link | 2 |
| **Timer** | 16 pt ring (2.5 stroke, ember) | `04:59` in accent, tabular | icon / text | presets, pause, +1 min | open the Timer widget | 3; "done" persists until dismissed |
| **Now Playing** | 20 pt art (radius 5) + glow halo | 5-bar spectrum (3 / 2 / 14 pt) in accent | icon / icon | art 34, title, artist, spectrum, tide | open the Nook | 4; paused: hides after 30 s, **auto-unhides** on resume |
| **Charging / battery** | `battery.100percent.bolt` (success) or a level glyph (warning / danger) | "82 %" | text / text | time to full or empty | — | 5 (transient 3 s; ≤ 10 % persists) |
| **Bluetooth device** | device glyph (`airpodspro`, `airpodsmax`, `headphones`, …) | battery "64 %" + 12 pt ring | text / text | L / R / case batteries | — | 6 (transient 4 s) |

**Arbitration.**

- The highest priority owns the wings. A second *persistent* activity becomes the **satellite**
  (§4.5), with its leading glyph inside a 22 pt bubble. There is at most one satellite.
- Transient activities (HUD, battery, Bluetooth) temporarily replace the wings, cross-fading with
  `crossFade`, then hand them back.
- **Leading and trailing always describe one activity**, the HIG "unified" rule.
- The wing widths animate with `peekIn` when the slot class changes.

**Peek expansion** (hover on a compact activity, after the dwell): `chin(...)` grows to
360 × (band + 50). Wing content stays and moves into the chin layout via matched geometry; nothing
is removed and re-added.

**Dismiss** with a swipe up on the activity. **Interactive:** click targets inside the wings are at
least 24 × 24 pt. When activities are clickable, the wings' hover state shows a `cardHover`
capsule behind the hit area.

### 6.4 HUD replacement anatomy (`states.png`, rows 7–8)

```
┌─ wing ─┐ (camera) ┌─ wing ─┐        329 × 48, bottom r 22
│ 🔊     │          │     62 │        glyph 13 semibold · value: compact, tabular, rolling
│  ━━━━━━━━━━━━━━━━━━━━━──────────  │  LevelBar: 6 pt capsule, well track, 20 pt side insets
└────────────────────────────────────┘
```

- **Fill:**
  - When "Colour HUD" is on and media is playing: a gradient `glow1` → `glow1.legibleOnBlack`,
    album-tinted.
  - Otherwise: white at 92 %. Settings ▸ HUD ▸ "Use colour" toggles this, which is the "disable
    colours" option.
- **Mute:** `speaker.slash.fill` and the bar at 35 %.
- **Differentiate Without Color or Increase Contrast:** 16 step ticks are drawn on the bar.
- **Each step crossing** fires haptic `.levelChange` (trackpad only).
- **VoiceOver:** "Volume, 62 percent" is posted as a low-priority announcement only when the value
  settles.
- **Separate toggles** for volume, brightness and keyboard backlight. Display brightness follows
  the display under the pointer.

---
## 7. Settings, onboarding, menu bar extra

### 7.1 Settings window

- **Structure.** A SwiftUI `Settings` scene, opened with `@Environment(\.openSettings)` (macOS 14,
  verified). It contains a `NavigationSplitView` with a 210 pt sidebar and a `Form` with
  `.formStyle(.grouped)` in the detail. Minimum size is 760 × 560.
- **Appearance.** It follows system light/dark mode, unlike the island. On macOS 26+ standard
  controls give Liquid Glass sidebar and toolbar chrome for free.
- **Activation.** Opening Settings calls `NSApp.activate()` and orders the window front, which
  addresses the "opens behind windows" complaint.
- **Sidebar rows** use System Settings-style 20 pt rounded-square icons with white glyphs
  (`settings.png`):

| Section | Icon (symbol on colour) | Contents |
|---|---|---|
| General | `gearshape` / grey | Launch at login (`SMAppService.mainApp`). **Displays**: a table of displays × {Island, Live activities, Peeks, HUD} toggles. Open on: Hover (dwell Instant / Short / Long) / Click. Close when pointer leaves (+ grace). Inactivity timeout. Hide when idle (no-notch). Full-screen behaviour (Hide / Activities only / Always). **Notch fit** sliders with live red fit-check outline. No-notch style. Open-Nook keyboard shortcut. **Demo mode** (never hides, for recordings). Updates (daily check via GitHub Releases API, "Check now"). **Reset all settings…** (destructive, confirmation sheet) |
| Appearance | `paintbrush.fill` / purple | **Ambience** (Off / Subtle / Vivid), **Effect** (Aurora / Motes / Tide / Halo), **Accent** (From content / System / Brand / White), **Motion** (Calm / Standard / Playful), Text size, Padding, Button shape (Capsule / Rounded), Card style (Cards / Flat with dividers), Translucent background, Underglow, Progress rim |
| Nook & Widgets | `square.grid.2x2.fill` / blue | **Grid editor**, a 1:1 scaled copy of your grid: drag widgets in from a palette, resize width in cells with handles, "N cells left", snapping with haptic `.alignment`. Columns (6–12), Rows (Standard / Tall), Pages. **Keyboard-accessible alternative:** a list with visibility checkboxes and Move Up/Down. Per-widget drill-in (Calendar days, Notes font, …) |
| Live Activities | `dot.radiowaves.up.forward` / pink | A reorderable priority list with toggles (Now Playing, Meeting, Timer, Battery, Bluetooth). Peek on change. Meeting lead minutes. Elapsed vs remaining. Satellite on/off. Activity inactivity timeout |
| Tray | `tray.full.fill` / green | Keep files between launches; action list order; image quality and format; output location; clear on quit |
| Gestures | `hand.draw.fill` / orange | Horizontal swipe changes track (Invert); vertical swipe opens/closes; swipe up dismisses an activity; **Haptics** on/off with a "Feel it" test button |
| Media | `music.note` / red-pink | Preferred sources; **Visualizer**: Live (requests System Audio Recording, with a why-sheet) / Ambient / Static / Off; art in compact |
| Calendar | `calendar` / red | Calendars (checkbox list with colours), days behind/ahead, show today's past events, link detection (Zoom, Meet, Teams, Webex), join in app or browser |
| Shortcuts | `square.2.layers.3d.fill` / indigo | Pick Shortcuts.app shortcuts and Quick Apps; tile labels |
| HUD | `speaker.wave.3.fill` / cyan | Replace volume / brightness / keyboard backlight (needs Accessibility, with a status pill and a deep link to System Settings); use colour; show value |
| About | `info.circle.fill` / grey | Live icon, version, MIT licence, third-party licences, GitHub, "Replay tutorial" |

**Live preview.** This is the signature feature of Settings. Appearance, Nook & Widgets, Live
Activities, Gestures and HUD pin a 170 pt **live preview** at the top of the pane:

- It renders the **real** `IslandHost` and widgets over a miniature of **your own wallpaper**
  (`NSWorkspace.desktopImageURL(for:)`), using the measured notch geometry.
- It updates live as any control changes, and it is interactive: hovering opens it.
- Below it sit "Simulate" chips: *Song change · Timer · Meeting · Volume · Drop file*.

This means users never toggle blind, which is a large UX gain over every app in the category.

**Control style.** Use system controls only:

- `Toggle(.switch)` for on/off.
- Segmented `Picker` for ≤ 4 options, a menu `Picker` otherwise.
- `Slider` with ticks for notch fit, and `Stepper` for minutes.
- Every non-obvious row has a one-line footnote in `.secondary`.
- Permission rows show a status pill (Granted ✓ / Not granted → *Open System Settings*).
- `.searchable` filters settings by keywords from a localized index.

### 7.2 Onboarding and interactive tutorial

The onboarding window is 680 × 520 with a full-size content view and a hidden title bar, on a
`night` background with the **brand aurora** running behind the content. The same
`AmbientBackdrop` with the `.afterglow` palette is used, so onboarding *is* the product.

1. **Welcome.** The app icon, drawn live, light pouring out of the crevice. The headline is
   original copy, e.g. "Your notch, lit from within." Button: **Get started**.
2. **Meet the island.** "Move your pointer to the notch." The step completes when the user
   **actually** hovers the real island, which plays an ember burst from the notch, then "Now
   click it". The coach mark is drawn next to the real notch in a transparent overlay window.
3. **Gestures.** "Two-finger swipe down on the notch" opens it, then "swipe sideways" changes
   track if music is playing. Each completes on real detection. Mouse users see the click
   alternatives and can skip.
4. **Pick a starting Nook.** Three presets, each with a mini live preview:
   - *Listener*: media, calendar, timer, apps.
   - *Maker*: notes, to-dos, timer, tray.
   - *Minimal*: media plus HUD only.
5. **Permissions, just in time.** Only the cards the chosen preset needs: Calendar (EventKit),
   Accessibility (HUD key interception), Automation / Apple Events (control music apps),
   Bluetooth (device battery).
   - Each card states *why*, what Cranny does **not** do, and offers "Allow" or "Later".
   - Camera is **not** requested here. Mirror asks on first use.
   - Nothing blocks progress.
6. **Done.** "Launch at login" (on), and "Open Settings". The tutorial can be replayed from the menu
   bar extra or About.

Progress shows as dots plus a 3 pt progress capsule. Every step can be skipped and works with the
keyboard (Return continues, Esc skips). Under Reduce Motion the aurora is a still frame.

### 7.3 Menu bar extra

Use `MenuBarExtra(... ) { … }.menuBarExtraStyle(.menu)` (verified) with the custom **template
glyph**: an 18 × 14 rounded "screen" outline with a filled notch tab (A.7, `menubar.png`). The
fallback SF Symbol is `rectangle.topthird.inset.filled`.

```
Open Nook                ⌥⌘N  (user-configurable)
Keep Nook Open (Pin)
Quiet  ▸  For 1 hour · Until tomorrow · Off        ← pauses peeks + delight moments
Demo Mode
Displays ▸  ✓ Built-in Retina Display · ✓ MPG322UX OLED
──────────
Settings…                ⌘,
Replay Tutorial
Check for Updates…
About Cranny
──────────
Quit Cranny              ⌘Q
```

"Hide menu bar icon" is available in General. Relaunching the app then opens Settings.

---

## 8. Iconography, haptics, sound, app icon

### 8.1 SF Symbols

All of these were verified to exist with `NSImage(systemSymbolName:)` on macOS 27.
`airdrop` does **not** exist as a public symbol. Keep the names in one `enum Symbols`, and add a
unit test that asserts every name resolves on the minimum OS in CI.

| Area | Symbols |
|---|---|
| Header / app | `square.grid.2x2.fill` (Nook) · `tray.full.fill` (Tray) · `pin` / `pin.fill` · `gearshape.fill` · `eye.slash` (hide) · `lock.fill` / `lock.open.fill` |
| Media | `play.fill` · `pause.fill` · `backward.fill` · `forward.fill` · `shuffle` · `repeat` · `airplayaudio` · `music.note` · `music.note.list` · `waveform` · `hifispeaker.fill` |
| HUD | `speaker.fill` · `speaker.wave.1.fill` · `speaker.wave.2.fill` · `speaker.wave.3.fill` · `speaker.slash.fill` · `sun.min.fill` · `sun.max.fill` · `light.min` · `light.max` |
| Calendar | `calendar` · `calendar.badge.clock` · `video.fill` (Join) · `clock` · `mappin.and.ellipse` |
| Quick apps / shortcuts | `square.2.layers.3d.fill` · `bolt.fill` · `wand.and.stars` · `command` · `app.dashed` · `plus` |
| Mirror | `web.camera` · `camera.fill` · `arrow.left.and.right.righttriangle.left.righttriangle.right` (mirror) · `video.slash` |
| Notes / to-dos | `note.text` · `chevron.left.forwardslash.chevron.right` (code mode) · `chevron.down` · `checklist` · `circle` · `checkmark.circle.fill` · `square.and.pencil` |
| Timer | `timer` · `stopwatch` · `xmark` · `arrow.clockwise` |
| AirDrop / tray / pipelines | `dot.radiowaves.up.forward` (AirDrop) · `tray.and.arrow.down.fill` · `doc.zipper` · `photo` · `arrow.down.right.and.arrow.up.left` (compress) · `doc.on.clipboard` (copy path) · `folder` · `square.and.arrow.up` · `trash` · `film` · `doc.text` |
| Power / devices | `battery.100percent.bolt` · `battery.100percent` · `battery.25percent` · `battery.0percent` · `powerplug.fill` · `airpods` · `airpodspro` · `airpodsmax` · `headphones` · `beats.headphones` |
| Gestures / settings | `hand.draw.fill` · `hand.tap` · `paintbrush.fill` · `info.circle.fill` · `sparkles` · `slider.horizontal.3` · `accessibility` |

Rendering rules:

- Island glyphs are `.semibold`, sized at 0.46 × the button size, hierarchical white.
- Symbols animate only with `symbolEffect` on state change: `.bounce` on Join appearing,
  `.variableColor.iterative` on `waveform` only while buffering. All are disabled under Reduce
  Motion.

### 8.2 Haptics

Haptics use `NSHapticFeedbackManager.defaultPerformer`, which works only on Force Touch trackpads
and does nothing with a mouse. They are off with one switch in Settings ▸ Gestures, and **never on
hover**.

| Event | Pattern |
|---|---|
| Swipe committed (track change, open/close by swipe) | `.alignment` |
| Swipe threshold crossed while still tracking | `.levelChange` |
| Scrubber 10 % steps · timer-ring minute detents | `.levelChange` |
| Drop zone entered · widget snapped in the grid editor | `.alignment` |
| File accepted · to-do completed | `.generic` |

SwiftUI's `.sensoryFeedback(.alignment / .levelChange, trigger:)` (macOS 14) works for in-view
triggers. Gesture code driven by `NSEvent` monitors calls `Haptics.alignment()` and its siblings
directly (A.5).

### 8.3 Sound

Cranny makes **no sound by default** and bundles **no audio**.

- **Timer done** plays a user-chosen *system* alert sound (`NSSound(named:)`, e.g. "Glass") at a
  user-set volume.
- An optional **UI sounds** toggle (off by default) plays system "Pop" on file drop and "Tink" on
  to-do completion.

### 8.4 App icon: "Afterglow" (original)

**Concept.** A night-indigo squircle with a black, notch-shaped **crevice** hanging from its top
edge. Aurora curtains (lagoon → iris → rose → ember) **pour out beneath it**, with a warm core
right under the slit, a thin rim of light tracing the crevice ("light leaking from under a door"),
and one bright mote. It tells the product story (a small opening, light coming out) without
Apple product imagery or any competitor motif. The crevice uses the *same* `NotchShape` as the
app. See `icon-1024.png` and `icon-32.png`; it stays legible at 32 px.

**macOS 26+: Icon Composer layered `.icon`.** The key names below were verified from Icon
Composer's `IconComposerFoundation` strings: `fill`, `linear-gradient`, `groups`, `layers`,
`image-name`, `blend-mode`, `glass`, `specular`, `shadow` {`kind`: neutral}, `translucency`,
`blur-material`, `fill-specializations`, `opacity`, `position` {`scale`, `translation-in-points`},
`supported-platforms` {`squares`: macOS}, and blend value `plus-lighter`. Icon Composer warns
about too many visible groups, so keep it to 3.

```jsonc
{
  "fill": { "linear-gradient": ["extended-srgb:0.118,0.086,0.251,1", "extended-srgb:0.027,0.024,0.051,1"] },
  "groups": [
    { "name": "mote",     "layers": [{ "image-name": "mote.svg",   "name": "mote" }],
      "glass": true, "specular": true },
    { "name": "crevice",  "layers": [{ "image-name": "crevice.svg", "name": "crevice" }],   // NotchShape path, black
      "glass": true, "specular": true, "shadow": { "kind": "neutral", "opacity": 0.5 } },
    { "name": "light",    "layers": [{ "image-name": "light.png", "name": "curtains",       // CG-rendered curtains, no bg
                                       "blend-mode": "plus-lighter" }],
      "glass": false, "blur-material": 0.3 }
  ],
  "supported-platforms": { "squares": ["macOS"] }
}
```

How the layers behave:

- Liquid Glass on the **crevice** gives it a specular rim. On macOS 26 that replaces the
  hand-drawn rim light of the flat version.
- The **light** layer stays non-glass, so the curtains remain soft.
- In the **Tinted** and **Clear** appearances, `fill-specializations` swaps the background to the
  system tint. The light layer drops to 40 % opacity in monochrome, and the crevice and mote carry
  the silhouette.
- `crevice.svg` is exported from `NotchShape(metrics: (0.40, 0.15, 0.06, 0.045) × 824 pt)`.
  `light.png` is rendered by `CrannyIconRenderer` with the crevice hidden.

**Flat fallback (macOS 14–15).** `CrannyIconRenderer.draw(in:side:monochrome:)` (A.7) uses pure
CoreGraphics: a continuous squircle clip on the macOS 824/1024 grid, a body gradient, 5 elliptical
radial-gradient curtains plus a core with `plusLighter`, the crevice path with an ember-shadowed
rim stroke, the mote, and an inner highlight. It has no blur filters, so it renders identically at
every size.

- A build-time script renders 16, 32, 64, 128, 256, 512 and 1024 px (plus @2x) into
  `AppIcon.appiconset`.
- Ship both the `.icon` and the appiconset, then check what `actool` emits for the macOS 14
  deployment target in the first xcodebuild. If Xcode already derives a legacy icns from the
  `.icon`, the appiconset becomes a no-op fallback.

---
## 9. Accessibility

| Setting / need | Behaviour |
|---|---|
| **Reduce Motion** (`accessibilityReduceMotion`) | `MotionTokens`: geometry eases out in ≤ 0.22 s with no bounce; all materialise, slide and emerge transitions become `.opacity`; no stagger; matched-geometry flights become cross-fades; ambient effects **freeze** on a resting frame; spectrum is static; typing effects are off; ember bursts and the satellite neck become fades; `Motion` is forced to Calm. Swipe still works, but content does not track the finger |
| **Reduce Transparency** | `SurfaceTokens.opaque`; translucent background, glass and underglow are off; the scrim becomes solid black |
| **Increase Contrast** (`colorSchemeContrast == .increased`) | `SurfaceTokens.highContrast` (opaque cards, 34 % hairlines, tertiary text 9.6:1); accents guarded at **7:1**; ambience capped at Subtle; no underglow; 1 pt rims; HUD bar shows step ticks |
| **Differentiate Without Color** | Colour is never the only carrier: battery states change glyph (`battery.25percent` etc.) and add a "Low" label; calendar rows keep their time and title; the live event says "Now"; HUD shows ticks and the number; pipeline errors show `!` plus a tooltip; selection uses a check badge, not only a tint |
| **VoiceOver** | The island is an `.accessibilityElement(children: .contain)` labelled "Cranny". Each compact activity is **one** combined element ("Timer, 4 minutes 59 seconds remaining") with named actions (`accessibilityAction(named:)`: Pause, Add a minute, Open). Decorative layers (effects, halos, spectrum, satellite) are `accessibilityHidden`. Events post `AccessibilityNotification.Announcement` (Accessibility framework, macOS 14, verified): timer done and meeting starting are high priority; song change is low; HUD announces only when settled. Images in tiles carry app or shortcut names |
| **Keyboard** | A global shortcut (default ⌥⌘N, rebindable) opens the Nook **and makes it key**. In the Nook: ←/→ move focus between widgets, Tab moves within a widget, Space / Return activate, Esc closes, ⌘1…⌘9 switch tabs, ⌘P pins, ⌘, opens Settings. Media-focused shortcuts: Space play/pause, ⌘←/⌘→ previous/next. Focus uses Cranny's own **2 pt white concentric ring** (`crannyFocusRing`), because system rings are clipped by the island mask and blue on black is weak. Implement with `.focusable()`, `.focusEffectDisabled()` and `.onKeyPress` (all verified) |
| **Text size** | macOS gives third-party apps no Dynamic Type (verified), so Cranny has its own **Text size** (0.9–1.3×) applied through `TypeScale`. Compact text caps at 14 pt and wings widen instead; at Large and above the grid cell grows to 74 pt |
| **Motor** | Open on click (no hover needed); adjustable dwell and close grace; every hover-revealed control is also reachable by keyboard; targets ≥ 24 × 24 pt in wings and ≥ 28 pt in widgets; swipe actions all have click or keyboard equivalents |
| **Time limits** | Peeks, HUD duration and inactivity close are adjustable or can be disabled (WCAG 2.2.1); *Pin* keeps the Nook open indefinitely |
| **Flashing** | No effect exceeds 1 flash per second. The underglow breathes at 0.5 Hz with ≤ 3 cycles and the timer pulse is 1 Hz, well under the WCAG 2.3.1 threshold of 3 per second |
| **Localization** | All strings live in a String Catalog (en + ru). Russian runs ~15–25 % longer, so labels in wings use `.lineLimit(1)` with `minimumScaleFactor(0.9)`, and the *slot class* widens instead of truncating. Numbers and dates use `FormatStyle`, never string concatenation |

---

## 10. Risks and trade-offs of the Expressive Ambient direction

1. **Energy cost** is the category's #1 complaint, and expressive effects make it worse.
   - *Mitigation:* the §5.2 budget is a hard contract. No timeline exists while closed; pause
     whenever unseen or occluded; 30 fps on battery; halo in Low Power Mode.
   - *Residual risk:* Vivid plus Motes at 60 fps on a 120 Hz display can still cost a few % CPU.
     Measure with Instruments before shipping; Subtle stays the default.
2. **Attention capture and taste.** Light plus motion near the top of the screen can be
   distracting, and album palettes can be garish.
   - *Mitigation:* idle motion only inside the user-opened Nook; luminous clamping (s ≤ 0.9,
     v ≤ 0.95); greyscale art is not coloured; Ambience, Motion and Accent dials, including a
     "White" accent.
   - *Residual risk:* some users will want an entirely monochrome app. That is supported, but it is
     not the showcase look.
3. **Legibility over light.** Glows behind cards can undercut contrast.
   - *Mitigation:* smoked cards; vivid token set; contrast audit (tertiary ≥ 4.5:1 even over a
     worst-case glow); `scrim` for any text placed directly on light; accent guards.
   - *Residual risk:* third-party album art and calendar colours are unbounded. Keep the audit as a
     unit test.
4. **Hardware-match accuracy.** The closed-state radii are estimates, because this machine's
   notch could not be measured (external display).
   - *Mitigation:* the 1 pt inset makes errors invisible at rest; the fit sliders and fit-check
     overlay handle the rest.
   - *Residual risk:* morph *start* frames could show a slight mismatch for ~1 frame on some models.
     Calibrate per model (14", 16", 13", 15" Air) on real hardware.
5. **Liquid Glass era.** On macOS 26+, system chrome is translucent glass while Cranny's island is
   opaque black.
   - *Trade-off:* deliberate. The island must merge with the bezel. Glass is used where the system
     uses it (Settings, menus) and for the optional translucent mode.
   - *Risk:* it could look "pre-26" next to Apple's own surfaces. Revisit if Apple ships a glass
     notch treatment.
6. **macOS 14 fidelity.** `MeshGradient` needs macOS 15, and the Canvas fallback is visibly softer.
   `TextRenderer` needs macOS 15. The `.icon` needs macOS 26.
   - *Mitigation:* fallbacks were designed and verified to compile with a deployment target of
     macOS 14.
   - *Residual risk:* macOS 14 users get a slightly simpler aurora.
7. **Menu-bar real estate and system Live Activities.** Wings cover parts of the menu bar, and on
   macOS 26+ the system can show iPhone Live Activities in the menu bar.
   - *Mitigation:* content-sized symmetric wings, menu-bar courtesy, swipe-up dismiss and
     per-display toggles.
   - *Residual risk:* crowded menu bars on 13" screens. Keep the icon slot (48 pt) as the default.
8. **Complexity.** The settings surface is large: dials, per-display toggles, per-activity
   options.
   - *Mitigation:* good defaults, a live preview, search, and section-level resets. Progressive
     disclosure keeps "Advanced" rows collapsed.
9. **Satellite and metaball delight.** The Canvas blur plus threshold costs more than a plain shape
   and only looks right on black.
   - *Mitigation:* it runs only during the 0.38 s split and then becomes two crisp shapes. It is
     disabled under Reduce Motion and Low Power Mode.
10. **No real spectrum without permission.** A true visualizer needs the System Audio Recording
    permission, which users may distrust.
    - *Mitigation:* the honest "Ambient" mode is the default; Live is opt-in with a clear
      why-sheet.

---

## 11. Implementation notes and verification log

**Where things go** (`CrannyKit`):

- `CrannyDesign` (nonisolated default): `RGB`, `Tokens`, `Palette`, `NotchGeometry`, `Motion`,
  `Effects`, `Components`, `Delight`, `AppIcon`, exactly as in Appendix A.
- Feature modules (MainActor default) import it and read `@Environment(\.cranny)` only.
- The notch-window module owns `HardwareNotch` measurement, the fixed-size panel, path
  hit-testing and the `EffectBudget` inputs:
  - visibility and occlusion: `NSWindow.occlusionState`
  - power: `ProcessInfo.isLowPowerModeEnabled`, `thermalState`
  - full-screen detection

**Tests to add:**

- *Contrast:* lock the §2.1 table with `RGB.contrast`.
- *Geometry:*
  - closed is inside the hardware notch;
  - wings are symmetric;
  - open fits the screen minus 96;
  - `columnsThatFit`.
- *SF Symbols:* every name in the `Symbols` enum resolves.
- *Snapshots:* `ImageRenderer` with `.environment(\.crannySnapshot, true)`, which makes Canvas
  render synchronously. The PoC needed this, because async Canvas content does not appear in
  snapshots.
- *Palette:* the same artwork always gives the same palette; greyscale gives `isMonochrome`.

**Verification log (this PoC):**

| Check | Result |
|---|---|
| `swift build --target CrannyDesign` (tools 6.2, Swift 6 mode, macOS 14 platform, `defaultIsolation(nil)`, the 4 upcoming features) | ✅ 0 errors, 0 warnings |
| Same code as a dependency of a `defaultIsolation(MainActor.self)` executable target that also declares a `nonisolated struct … : Shape` | ✅ builds and runs |
| `@Entry`, `@Animatable` (26+), `MeshGradient` (15+), `glassEffect` / `Glass` / `GlassEffectContainer` (26+), `sensoryFeedback`, `.numericText(countsDown:)`, `.blurReplace`, `phaseAnimator`, `symbolEffect`, `TextRenderer` (15+), `onKeyPress`, `focusEffectDisabled`, `openSettings`, `MenuBarExtra`, `AccessibilityNotification.Announcement`, `NSHapticFeedbackManager`, `NSTextLayoutManager.addRenderingAttribute`, `NSSharingService.Name.sendViaAirDrop`, `QLThumbnailGenerator`, `desktopImageURL(for:)`, `GraphicsContext.Filter.alphaThreshold` | ✅ type-checked for `arm64-apple-macos14.0` (with `#available` where marked) or found in SDK interfaces |
| 86 SF Symbol names used in this doc | ✅ all resolve (`airdrop` does not, so it is not used) |
| Palette extraction | 0.115 ms per artwork; accent 4.71:1; greyscale gives mono |
| Contrast audit | see §2.1 (Vivid needed its own token set; found and fixed by the audit) |
| `dynamicTypeSize` on macOS | no effect (78 px vs 78 px), so the own `TypeScale` is justified |
| Renders | `out/states.png`, `open.png`, `no-notch.png`, `effects.png`, `a11y.png`, `morph.png`, `morph-pill.png`, `satellite.png`, `settings.png` (AppKit-backed controls such as `Picker` and `Toggle` do not render in `ImageRenderer`; sidebar and preview only), `icon-1024.png`, `icon-32.png`, `icon-mono.png`, `menubar.png` |
| Bugs found by rendering and fixed | (1) ambient backdrop sized to the window hid the light below the panel; now framed to the island's bounds. (2) Calendar card overflowed 136 pt with two-line rows; rows are now single-line with only the live event two-line. (3) The halo inside a `ZStack` inflated the timer ring; it is now a `.background`. (4) Canvas effects were blank in snapshots; added the `crannySnapshot` environment flag |
| Not verified here | on-screen fps and CPU (needs Instruments on hardware); hardware notch radii (no notched display attached); `.icon` → legacy icns behaviour of `actool` for the macOS 14 target |

---

## Appendix A: complete source of the design-system module (compiled as shown)

These files are copied verbatim from `scratchpad/poc/design-ambient/pkg/Sources/CrannyDesign/`.
The render harness (mock scenes, contrast audit, PNG writer) is in `…/Sources/AmbientRender/`.

### A.1 `RGB.swift`
```swift
import SwiftUI

/// sRGB triple (0...1) used for palette math. Cheap, Sendable, and *animatable*
/// (VectorArithmetic) so album-derived palettes can cross-fade inside Canvas/MeshGradient,
/// which do not interpolate captured colours on their own.
public struct RGB: Hashable, Sendable, VectorArithmetic {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public var color: Color { Color(.sRGB, red: clamp(r), green: clamp(g), blue: clamp(b), opacity: 1) }
    public func color(_ opacity: Double) -> Color {
        Color(.sRGB, red: clamp(r), green: clamp(g), blue: clamp(b), opacity: opacity)
    }
    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    // MARK: VectorArithmetic
    public static var zero: RGB { RGB(0, 0, 0) }
    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func - (a: RGB, b: RGB) -> RGB { RGB(a.r - b.r, a.g - b.g, a.b - b.b) }
    public mutating func scale(by k: Double) { r *= k; g *= k; b *= k }
    public var magnitudeSquared: Double { r * r + g * g + b * b }

    // MARK: Colour science (WCAG 2.x)
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    /// Contrast ratio 1...21.
    public func contrast(with o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    public var chroma: Double { max(r, g, b) - min(r, g, b) }

    public var hsb: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
    public init(h: Double, s: Double, v: Double) {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: self.init(v, t, p)
        case 1: self.init(q, v, p)
        case 2: self.init(p, v, t)
        case 3: self.init(p, q, v)
        case 4: self.init(t, p, v)
        default: self.init(v, p, q)
        }
    }
    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { a + (b - a).scaled(t) }
    public func scaled(_ k: Double) -> RGB { var c = self; c.scale(by: k); return c }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) { self = RGB(hex: hex).color(opacity) }
}
```

### A.2 `Tokens.swift`
```swift
import SwiftUI

// MARK: - Surfaces & text (the island is ALWAYS dark; Settings/onboarding use system colours)

/// Values are chosen so every text token clears WCAG AA (4.5:1) on `card` composited over the
/// black island — verified by `ContrastAudit` in the PoC. Cards are *smoked* (dark, translucent),
/// not white-alpha: over a bright aurora a white-alpha card would wash out, a smoked card dims it.
public struct SurfaceTokens: Sendable, Equatable {
    public var notch: Color          // the island itself — must equal the hardware notch (pure black)
    public var card: Color           // elevated widget card (smoked glass)
    public var cardHover: Color
    public var cardPressed: Color
    public var well: Color           // inset fields: note editor, scrubber/level track, search
    public var hairline: Color       // card outline, lower-edge island rim
    public var strokeStrong: Color   // selected / drop-target outlines
    public var divider: Color        // optional dividers between widgets
    public var scrim: Color          // behind text that sits directly on an ambient effect
    public var textPrimary: Color
    public var textSecondary: Color
    public var textTertiary: Color
    public var textDisabled: Color   // exempt from contrast rules, never used for information

    public static let standard = SurfaceTokens(
        notch: .black,
        card: Color(white: 0.13, opacity: 0.74), cardHover: Color(white: 0.17, opacity: 0.78),
        cardPressed: Color(white: 0.21, opacity: 0.80),
        well: .white.opacity(0.07),
        hairline: .white.opacity(0.09), strokeStrong: .white.opacity(0.22), divider: .white.opacity(0.08),
        scrim: .black.opacity(0.45),
        textPrimary: .white.opacity(0.96), textSecondary: .white.opacity(0.68),
        textTertiary: .white.opacity(0.52), textDisabled: .white.opacity(0.30))

    /// Ambience = Vivid: denser cards and lifted secondary/tertiary text so AA still holds when the
    /// brightest possible aurora pixel sits directly under a card (audited: tertiary ≥ 4.7:1).
    public static let vivid: SurfaceTokens = {
        var s = SurfaceTokens.standard
        s.card = Color(white: 0.13, opacity: 0.80); s.cardHover = Color(white: 0.17, opacity: 0.84)
        s.cardPressed = Color(white: 0.21, opacity: 0.86)
        s.textSecondary = .white.opacity(0.72); s.textTertiary = .white.opacity(0.60)
        return s
    }()

    /// System ▸ Accessibility ▸ Display ▸ Increase contrast.
    public static let highContrast = SurfaceTokens(
        notch: .black,
        card: Color(white: 0.12), cardHover: Color(white: 0.18), cardPressed: Color(white: 0.24),
        well: Color(white: 0.16),
        hairline: .white.opacity(0.34), strokeStrong: .white.opacity(0.70), divider: .white.opacity(0.28),
        scrim: .black.opacity(0.75),
        textPrimary: .white, textSecondary: .white.opacity(0.86),
        textTertiary: .white.opacity(0.74), textDisabled: .white.opacity(0.45))

    /// System ▸ Reduce transparency: identical hierarchy, everything opaque.
    public static let opaque = SurfaceTokens(
        notch: .black,
        card: Color(white: 0.11), cardHover: Color(white: 0.15), cardPressed: Color(white: 0.19),
        well: Color(white: 0.15),
        hairline: Color(white: 0.20), strokeStrong: Color(white: 0.36), divider: Color(white: 0.17),
        scrim: .black,
        textPrimary: Color(white: 0.96), textSecondary: Color(white: 0.70),
        textTertiary: Color(white: 0.55), textDisabled: Color(white: 0.32))
}

/// Fixed semantic + brand colours (dark-appearance values; the island never turns light).
public enum CrannyColor {
    // Semantic (system dark-mode hues, so they match HUDs/menus users already know)
    public static let success = RGB(hex: 0x30D158)
    public static let warning = RGB(hex: 0xFFD60A)
    public static let danger  = RGB(hex: 0xFF453A)
    public static let info    = RGB(hex: 0x64D2FF)
    public static let record  = RGB(hex: 0xFF375F)   // camera/mic live, Mirror recording dot

    // Brand ramp "Afterglow": onboarding, About, icon, and fallback ambient palette.
    public static let ember  = RGB(hex: 0xFF7A45)
    public static let rose   = RGB(hex: 0xFF4F8B)
    public static let iris   = RGB(hex: 0x8B6CFF)
    public static let lagoon = RGB(hex: 0x2ED3C6)
    public static let night  = RGB(hex: 0x0B0A14)
}

// MARK: - Accent strategy

/// Where the accent comes from. Resolved per *activity*, not globally:
/// media → album art, timer → ember, calendar → the event's calendar colour,
/// battery → semantic, HUD → album glow if playing else neutral.
public enum AccentSource: String, CaseIterable, Sendable {
    case content      // default: album art / event colour / semantic per activity
    case system       // NSColor.controlAccentColor (follows System Settings)
    case brand        // Afterglow iris
    case mono         // white only — no colour at all (pairs well with Ambience Off)
}

public extension RGB {
    /// Brighten (then desaturate) until the colour reaches `ratio` against black.
    /// Use for *foreground marks* (text, glyphs, progress fills) on the island.
    func legibleOnBlack(ratio: Double = 4.5) -> RGB {
        var (h, s, v) = hsb
        s = min(s, 0.85); v = max(v, 0.72)
        var out = RGB(h: h, s: s, v: v)
        var guardrail = 0
        while out.contrast(with: .black) < ratio && guardrail < 24 {
            if v < 1 { v = min(1, v + 0.04) } else { s = max(0, s - 0.06) }
            out = RGB(h: h, s: s, v: v); guardrail += 1
        }
        return out
    }
    /// Label colour to put ON a filled accent (prominent button, Join capsule).
    var onColor: RGB { contrast(with: .black) >= contrast(with: .white) ? .black : .white }
    /// Glows read as *light*: saturated, bright, never neon-white.
    var luminous: RGB {
        let (h, s, v) = hsb
        return RGB(h: h, s: min(max(s, 0.45), 0.90), v: min(max(v, 0.75), 0.95))
    }
}

// MARK: - Typography

/// macOS has no Dynamic Type for third-party UI, so Cranny ships its own text-size setting
/// (Settings ▸ Appearance ▸ Text size) and resolves every font through `TypeScale`.
public enum CrannyTextStyle: CaseIterable, Sendable {
    case display    // timer face, big numerals            30 semibold rounded, tabular
    case title2     // calendar day number, tray count     20 semibold rounded
    case title      // track title, widget hero            15 semibold rounded
    case headline   // card titles, event title            13 semibold
    case body       // notes, to-dos                       13 regular
    case callout    // artist, secondary line              12 medium
    case caption    // times, metadata                     11 medium, tabular
    case micro      // UPPERCASE labels, badges            10 semibold rounded, +0.6 tracking
    case compact    // live-activity slots by the notch    12 semibold rounded, tabular (capped 14)
    case code       // notes code mode                     12 regular SF Mono
}

public struct TypeScale: Sendable, Equatable {
    /// 0.9 Small · 1.0 Default · 1.15 Large · 1.3 Extra Large
    public var factor: CGFloat = 1
    public init(factor: CGFloat = 1) { self.factor = factor }

    public func size(_ s: CrannyTextStyle) -> CGFloat {
        let base: CGFloat = switch s {
        case .display: 30
        case .title2: 20
        case .title: 15
        case .headline, .body: 13
        case .callout, .compact, .code: 12
        case .caption: 11
        case .micro: 10
        }
        // Compact slots live inside the fixed menu-bar-height band: cap growth so they never clip.
        return s == .compact ? min(base * factor, 14) : (base * factor).rounded()
    }

    public func font(_ s: CrannyTextStyle) -> Font {
        let sz = size(s)
        return switch s {
        case .display:  .system(size: sz, weight: .semibold, design: .rounded).monospacedDigit()
        case .title2:   .system(size: sz, weight: .semibold, design: .rounded)
        case .title:    .system(size: sz, weight: .semibold, design: .rounded)
        case .headline: .system(size: sz, weight: .semibold)
        case .body:     .system(size: sz, weight: .regular)
        case .callout:  .system(size: sz, weight: .medium)
        case .caption:  .system(size: sz, weight: .medium).monospacedDigit()
        case .micro:    .system(size: sz, weight: .semibold, design: .rounded)
        case .compact:  .system(size: sz, weight: .semibold, design: .rounded).monospacedDigit()
        case .code:     .system(size: sz, weight: .regular, design: .monospaced)
        }
    }
    public func tracking(_ s: CrannyTextStyle) -> CGFloat { s == .micro ? 0.6 : 0 }
}

public extension View {
    /// `Text("Up next").crannyFont(.micro)` — font + tracking + case in one place.
    func crannyFont(_ style: CrannyTextStyle) -> some View { modifier(CrannyFontModifier(style: style)) }
}
struct CrannyFontModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    var style: CrannyTextStyle
    func body(content: Content) -> some View {
        content
            .font(theme.type.font(style))
            .tracking(theme.type.tracking(style))
            .textCase(style == .micro ? .uppercase : nil)
    }
}

// MARK: - Spacing, radii, strokes

public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
    public static let xxxl: CGFloat = 24
    public static let huge: CGFloat = 32
}

/// Settings ▸ Appearance ▸ Padding. Scales inner paddings only; the cell grid and the island
/// geometry stay fixed so a density change never reflows the grid.
public enum Density: CGFloat, CaseIterable, Sendable { case compact = 0.75, regular = 1, spacious = 1.25 }

public enum Radius {
    public static let panel: CGFloat = 30       // open Nook bottom corners
    public static let chin: CGFloat = 22        // peek with an info "chin" (quick peek, HUD)
    public static let compactMax: CGFloat = 14  // compact wings, capped at height/2
    public static let card: CGFloat = 18        // = panel − 12 panel padding (concentric)
    public static let control: CGFloat = 10     // buttons/fields inside cards (= card − 8)
    public static let art: CGFloat = 12         // album art in media card
    public static let artCompact: CGFloat = 5   // album art in a compact wing
    public static let tile: CGFloat = 14        // quick-app / shortcut tiles
    public static let chip: CGFloat = 8

    /// Concentric inner radius: outer radius minus the gap between the two edges.
    public static func concentric(_ outer: CGFloat, inset: CGFloat, floor: CGFloat = 4) -> CGFloat {
        Swift.max(outer - inset, floor)
    }
}

public enum Stroke {
    /// One device pixel. Pass `@Environment(\.displayScale)` (2 on Retina, 1 on most externals).
    public static func hairline(_ scale: CGFloat) -> CGFloat { 1 / Swift.max(scale, 1) }
    public static let regular: CGFloat = 1
    public static let focus: CGFloat = 2          // keyboard focus ring
    public static let ring: CGFloat = 5           // timer/progress rings in widgets
    public static let ringCompact: CGFloat = 2.5  // rings inside compact wings
    public static let dropDash: [CGFloat] = [6, 5]
}

// MARK: - Elevation & light

public struct Glow: Sendable, Equatable {
    public var opacity: Double
    public var radius: CGFloat
    public var y: CGFloat = 0
}

public enum Elevation {
    /// Shadow under the open panel so it separates from bright wallpapers. The host NSWindow must
    /// extend ≥ radius + y below the panel or the shadow is clipped.
    public static let panel = Glow(opacity: 0.55, radius: 28, y: 14)
    public static let chin = Glow(opacity: 0.40, radius: 16, y: 8)
    public static let none = Glow(opacity: 0, radius: 0)
    /// Light emitted by content (album accent behind art, timer ember behind the ring).
    public static let glowSoft = Glow(opacity: 0.35, radius: 24)
    public static let glowStrong = Glow(opacity: 0.55, radius: 40)
    /// Coloured light spilling *outside* the island onto the desktop. Vivid ambience only,
    /// never with Reduce Transparency or Increase Contrast.
    public static let underglow = Glow(opacity: 0.30, radius: 36, y: 10)
}

public extension View {
    func elevation(_ g: Glow, color: Color = .black) -> some View {
        shadow(color: color.opacity(g.opacity), radius: g.radius, x: 0, y: g.y)
    }
}

// MARK: - Theme (one environment value; feature modules read only this)

public enum AmbienceLevel: Int, CaseIterable, Sendable {
    case off, subtle, vivid
    public var intensity: Double { [0, 0.55, 1.0][rawValue] }
}

/// Settings ▸ Appearance ▸ Motion. Scales *bounce* only; durations stay put.
public enum MotionStyle: Int, CaseIterable, Sendable {
    case calm, standard, playful
    public var bounceScale: Double { [0, 1, 1.35][rawValue] }
}

public struct CrannyTheme: Sendable, Equatable {
    public var surfaces: SurfaceTokens = .standard
    public var type = TypeScale()
    public var density: Density = .regular
    public var ambience: AmbienceLevel = .subtle
    public var motion: MotionStyle = .standard
    public var accentSource: AccentSource = .content
    public var capsuleButtons = true          // Settings ▸ Appearance ▸ Button shape
    public var dividers = false               // Settings ▸ Nook ▸ Show dividers
    public var hapticsEnabled = true
    // Resolved from the system by CrannyThemeRoot — never set by features.
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    public var differentiateWithoutColor = false

    public init() {}

    public var buttonShape: AnyShape {
        capsuleButtons ? AnyShape(Capsule())
                       : AnyShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
    /// Minimum accent contrast against black for foreground marks.
    public var accentContrast: Double { increaseContrast ? 7 : 4.5 }
    public var allowsUnderglow: Bool { ambience == .vivid && !reduceTransparency && !increaseContrast }
}

public extension EnvironmentValues {
    @Entry var cranny = CrannyTheme()
}

/// Root modifier for every view hosted in the notch window: merges user settings with the
/// system accessibility flags. Feature modules never read the raw system flags themselves.
public struct CrannyThemeRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor
    public var base: CrannyTheme
    public init(base: CrannyTheme) { self.base = base }

    public func body(content: Content) -> some View {
        var t = base
        t.reduceMotion = reduceMotion || base.reduceMotion
        t.reduceTransparency = reduceTransparency || base.reduceTransparency
        t.increaseContrast = contrast == .increased || base.increaseContrast
        t.differentiateWithoutColor = noColor || base.differentiateWithoutColor
        if t.ambience == .vivid { t.surfaces = .vivid }
        if t.reduceTransparency { t.surfaces = .opaque }
        if t.increaseContrast { t.surfaces = .highContrast; t.ambience = min(t.ambience, .subtle) }
        if t.reduceMotion { t.motion = .calm }   // ambient effects FREEZE (see EffectBudget), not vanish
        return content
            .environment(\.cranny, t)
            .environment(\.colorScheme, .dark)
    }
}

extension AmbienceLevel: Comparable {
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
```

### A.3 `Motion.swift`
```swift
import SwiftUI

/// Motion tokens, resolved from the theme (Motion style + Reduce Motion).
/// Rule: geometry may overshoot when it GROWS (delight); it never overshoots when it SHRINKS
/// back into the hardware notch — it must land exactly, with zero wobble.
public struct MotionTokens: Sendable {
    public let reduceMotion: Bool
    private let k: Double   // bounce scale: calm 0 · standard 1 · playful 1.35

    public init(style: MotionStyle, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        self.k = reduceMotion ? 0 : style.bounceScale
    }

    private func spring(_ d: Double, _ bounce: Double) -> Animation {
        reduceMotion ? .easeOut(duration: min(d, 0.22)) : .spring(duration: d, bounce: bounce * k)
    }

    // Island geometry
    public var open: Animation      { spring(0.42, 0.14) }   // closed/peek → open
    public var close: Animation     { reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.36, bounce: 0) }
    public var peekIn: Animation    { spring(0.38, 0.18) }   // compact wings appear
    public var peekOut: Animation   { reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.30, bounce: 0) }
    public var chinDrop: Animation  { spring(0.45, 0.16) }   // quick peek / hover expansion
    public var breathe: Animation   { spring(0.26, 0.25) }   // closed-state hover
    public var resize: Animation    { spring(0.40, 0.08) }   // open → open (tab with a different height)

    // Content
    public var contentIn: Animation  { reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: 0.34, bounce: 0.06 * k) }
    public var contentOut: Animation { .easeIn(duration: reduceMotion ? 0.12 : 0.10) }
    public var crossFade: Animation  { .smooth(duration: reduceMotion ? 0.2 : 0.28) }
    public var tab: Animation        { spring(0.32, 0.10) }
    public var hover: Animation      { reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.20, bounce: 0.20 * k) }
    public var press: Animation      { .spring(duration: 0.16, bounce: 0) }
    public var level: Animation      { .spring(duration: 0.18, bounce: 0) }      // HUD fill follows key repeat
    public var snapBack: Animation   { spring(0.30, 0.05) }                      // swipe released
    public var tracking: Animation   { .interactiveSpring(duration: 0.15) }      // finger-driven
    public var colorShift: Animation { .easeInOut(duration: reduceMotion ? 0.3 : 0.8) }  // album palette change

    /// Content enters once the shape has covered ~25 % of its travel; exits before it shrinks.
    public var contentLead: Double { reduceMotion ? 0 : 0.06 }
    public var closeLag: Double { reduceMotion ? 0 : 0.04 }

    /// Delay for the n-th staggered child; capped so a full grid never feels slow (≤ 0.1 s).
    public func stagger(_ index: Int, step: Double = 0.025, cap: Int = 4) -> Double {
        reduceMotion ? 0 : Double(min(index, cap)) * step
    }
}

public extension CrannyTheme {
    var anim: MotionTokens { MotionTokens(style: motion, reduceMotion: reduceMotion) }
}

// MARK: - Gestures

/// iOS-style rubber band: resistance grows with distance, asymptotically approaching `limit`.
public func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient c: CGFloat = 0.55) -> CGFloat {
    guard limit > 0 else { return 0 }
    let sign: CGFloat = offset < 0 ? -1 : 1
    let x = abs(offset)
    return sign * (1 - 1 / (x * c / limit + 1)) * limit
}

/// Gesture thresholds (trackpad scroll-wheel phases over the island).
public enum GestureSpec {
    public static let commitDistance: CGFloat = 56     // accumulated scrollingDelta to commit a swipe
    public static let commitVelocity: CGFloat = 600    // or this many pt/s at .ended
    public static let horizontalLimit: CGFloat = 22    // max visual travel of compact content (rubber band)
    public static let verticalLimit: CGFloat = 28      // max stretch of the island when pulled down
    public static let axisLock: CGFloat = 1.6          // |dx| must exceed |dy| × this to be "horizontal"
}

// MARK: - Hover intent (anti-accidental-open)

/// Decides whether a hover should open the island. Fixes the "it opens when I move to the
/// display above / reach for browser tabs" class of complaints.
public struct HoverIntent: Sendable {
    public var dwell: Double = 0.12               // Settings: Instant 0 · Short 0.12 · Long 0.35
    public var passThroughSpeed: CGFloat = 900    // pt/s upward; faster = travelling to a display above
    public var closeGrace: Double = 0.35          // pointer may leave briefly without closing

    public init() {}

    public func shouldOpen(hoverDuration: Double, verticalVelocity vy: CGFloat,
                           mouseButtonDown: Bool, isFileDrag: Bool, fullscreenSpace: Bool) -> Bool {
        if isFileDrag { return true }                       // dragging a file opens the tray drop zone
        if mouseButtonDown { return false }                 // window drags, selections
        if fullscreenSpace && hoverDuration < 0.4 { return false }   // tabs/toolbar live up there
        if vy > passThroughSpeed { return false }           // y-up coordinates: fast upward travel
        return hoverDuration >= dwell
    }
}

// MARK: - Transitions

/// Blur + scale + fade used for content materialising inside the island.
public struct MaterializeModifier: ViewModifier {
    public var progress: Double            // 0 hidden → 1 shown
    public var anchor: UnitPoint = .top
    public var blur: CGFloat = 8
    public var minScale: CGFloat = 0.94
    public func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * blur)
            .scaleEffect(minScale + (1 - minScale) * progress, anchor: anchor)
    }
}

public extension AnyTransition {
    /// Content materialising out of the notch (top-anchored). Reduce Motion → `.opacity`.
    static func materialize(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
            : .modifier(active: MaterializeModifier(progress: 0), identity: MaterializeModifier(progress: 1))
    }
    /// Compact-wing content growing out from behind the camera housing.
    static func emerge(from edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        let a: UnitPoint = edge == .leading ? .trailing : .leading
        return reduceMotion ? .opacity
            : .modifier(active: MaterializeModifier(progress: 0, anchor: a, blur: 4, minScale: 0.6),
                        identity: MaterializeModifier(progress: 1, anchor: a, blur: 4, minScale: 0.6))
    }
    /// Tab switch: short directional slide + blur.
    static func tabSlide(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let dx: CGFloat = forward ? 14 : -14
        return .asymmetric(
            insertion: .offset(x: dx).combined(with: .modifier(active: MaterializeModifier(progress: 0, blur: 6, minScale: 1),
                                                              identity: MaterializeModifier(progress: 1, blur: 6, minScale: 1))),
            removal: .offset(x: -dx).combined(with: .opacity))
    }
}
```

### A.4 `NotchGeometry.swift` (hardware, per-state layout, grid; shape is in §3.2)
```swift
// MARK: - Hardware facts (measured at runtime; re-measure on didChangeScreenParameters)

///   notchWidth    = screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width
///   notchHeight   = screen.safeAreaInsets.top
///   menuBarHeight = screen.frame.maxY − screen.visibleFrame.maxY   (when the menu bar is visible)
public struct HardwareNotch: Sendable, Equatable {
    public var width: CGFloat           // 0 on displays without a notch
    public var height: CGFloat
    public var menuBarHeight: CGFloat
    public var screenWidth: CGFloat
    public var hasNotch: Bool { width > 0 && height > 0 }

    public init(width: CGFloat, height: CGFloat, menuBarHeight: CGFloat, screenWidth: CGFloat) {
        self.width = width; self.height = height; self.menuBarHeight = menuBarHeight; self.screenWidth = screenWidth
    }
    /// Only used if measurement fails on a notched display.
    public static let fallback = HardwareNotch(width: 185, height: 32, menuBarHeight: 32, screenWidth: 1512)
}

/// Settings ▸ General ▸ Notch fit (with a live outline overlay while dragging the sliders).
public struct NotchFit: Sendable, Equatable {
    public var widthAdjust: CGFloat = 0         // −20…+20 pt
    public var heightAdjust: CGFloat = 0        // −4…+4 pt
    public var bottomRadiusAdjust: CGFloat = 0  // −4…+4 pt
    public init() {}
}

/// Displays without a notch.
public enum NoNotchStyle: String, CaseIterable, Sendable {
    case menuBarPill   // DEFAULT: detached capsule inside the menu-bar band; opens as a floating panel
    case virtualNotch  // attached black tab with ears (looks like a notch)
    case hiddenHandle  // like menuBarPill but the closed handle is invisible until approached
}

/// Width of one compact wing, derived from the band height so it scales with display scaling.
public enum SlotWidth: Int, Comparable, Sendable {
    case none, icon, text, wide
    public func points(band h: CGFloat) -> CGFloat {
        switch self {
        case .none: 0
        case .icon: (h + 16).rounded()      // 48 @ 32 pt: art / glyph / ring + insets
        case .text: (h * 2.25).rounded()    // 72: "12:45", "−3m", "84 %"
        case .wide: (h * 3.25).rounded()    // 104: "Join" capsule, short title
        }
    }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Per-state geometry

public struct IslandLayout: Sendable, Equatable {
    public var hw: HardwareNotch
    public var fit = NotchFit()
    public var noNotchStyle: NoNotchStyle = .menuBarPill

    public init(hw: HardwareNotch, fit: NotchFit = NotchFit(), noNotchStyle: NoNotchStyle = .menuBarPill) {
        self.hw = hw; self.fit = fit; self.noNotchStyle = noNotchStyle
    }

    private var detached: Bool { !hw.hasNotch && noNotchStyle != .virtualNotch }
    /// Height of the band the island lives in when not open (the hardware notch or the menu bar).
    public var band: CGFloat { (hw.hasNotch ? hw.height : max(hw.menuBarHeight, 24)) + fit.heightAdjust }
    /// Width of the "camera housing" that must stay content-free (virtual on external displays).
    public var notchW: CGFloat { (hw.hasNotch ? hw.width : 120) + fit.widthAdjust }
    /// Pill inset inside the menu-bar band when detached.
    private var pillInset: CGFloat { detached ? 3 : 0 }

    /// CLOSED. On a notched display the island hugs the hardware notch, inset by 1 pt so a
    /// calibration error can never show as a visible rim: it is invisible until it grows.
    public var closed: NotchMetrics {
        if hw.hasNotch {
            return .init(width: notchW - 2, height: band - 1,
                         bottomRadius: (band * 0.30).rounded() + fit.bottomRadiusAdjust,  // ≈ 10 @ 32 pt
                         topCorner: (band * 0.14).rounded())                               // ≈ 4 pt shoulders
        }
        switch noNotchStyle {
        case .virtualNotch: return .init(width: 72, height: 6, bottomRadius: 3, topCorner: 3)
        case .menuBarPill, .hiddenHandle:
            return .init(width: 44, height: 5, bottomRadius: 2.5, topCorner: -2.5, topOffset: 3)
        }
    }

    /// CLOSED + pointer hovering: a small "breath" that says the island is alive before it opens.
    public var closedHover: NotchMetrics {
        var m = closed
        if hw.hasNotch { m.width += 14; m.height += 3; m.bottomRadius += 1 }
        else { m.width += 28; m.height += 3; m.bottomRadius = m.height / 2; if detached { m.topCorner = -m.height / 2 } }
        return m
    }

    /// COMPACT (live activity). Same height as the band, widened symmetrically by two wings.
    /// Symmetric because the camera housing is centred: both wings take the wider slot.
    public func compact(leading: SlotWidth, trailing: SlotWidth) -> NotchMetrics {
        let h = band - 2 * pillInset
        let side = max(leading, trailing).points(band: band)
        let r = min(h / 2, Radius.compactMax)
        return .init(width: notchW + 2 * side, height: h, bottomRadius: r,
                     topCorner: detached ? -r : 8, topOffset: pillInset)
    }

    /// PEEK (hover on an activity, quick peek on song change, HUD): compact + an info "chin".
    public func chin(leading: SlotWidth, trailing: SlotWidth, chinHeight: CGFloat, minWidth: CGFloat = 360) -> NotchMetrics {
        var m = compact(leading: leading, trailing: trailing)
        m.width = max(m.width, minWidth)
        m.height += chinHeight
        m.bottomRadius = Radius.chin
        m.topCorner = detached ? -Radius.chin : 10
        return m
    }

    /// OPEN ("the Nook"): grid-driven, clamped to the screen with a 48 pt margin.
    public func open(grid: NookGridSpec) -> NotchMetrics {
        let w = min(grid.panelWidth, hw.screenWidth - 2 * 48)
        let h = grid.headerHeight(band: band) + Space.s + grid.bodyHeight + grid.padding
        return .init(width: max(w, notchW + 2 * 160), height: h, bottomRadius: Radius.panel,
                     topCorner: detached ? -Radius.panel : 14, topOffset: pillInset)
    }

    /// Fixed host-window size: the largest state + room for shadow/underglow.
    public func windowSize(grid: NookGridSpec) -> CGSize {
        let o = open(grid: grid)
        return CGSize(width: o.outerWidth + 2 * 56, height: o.bottom + 56)
    }
}

/// Open-Nook cell grid.
public struct NookGridSpec: Sendable, Equatable {
    public var cell: CGFloat = 64        // square cell
    public var gutter: CGFloat = 8
    public var columns: Int = 10         // user: 6…12, auto-clamped by `columnsThatFit`
    public var rows: Int = 2             // 2 = standard (136 pt), 3 = "tall" layout (208 pt)
    public var padding: CGFloat = 12     // = Radius.panel − Radius.card (concentric)

    /// `textScale` = TypeScale.factor: at Large / Extra Large the cell grows (capped at +15 %)
    /// so widgets keep their content instead of truncating.
    public init(columns: Int = 10, rows: Int = 2, textScale: CGFloat = 1) {
        self.columns = columns; self.rows = rows
        self.cell = (64 * min(max(textScale, 1), 1.15)).rounded()
    }

    public func headerHeight(band: CGFloat) -> CGFloat { max(band, 32) }
    public var bodyHeight: CGFloat { CGFloat(rows) * cell + CGFloat(rows - 1) * gutter }
    public var gridWidth: CGFloat { width(cells: columns) }
    public var panelWidth: CGFloat { gridWidth + 2 * padding }
    public func width(cells n: Int) -> CGFloat { CGFloat(n) * cell + CGFloat(max(n - 1, 0)) * gutter }

    public static func columnsThatFit(screenWidth: CGFloat, cell: CGFloat = 64, gutter: CGFloat = 8,
                                      padding: CGFloat = 12, margin: CGFloat = 48, maxColumns: Int = 12) -> Int {
        let avail = screenWidth - 2 * margin - 2 * padding
        return max(6, min(maxColumns, Int((avail + gutter) / (cell + gutter))))
    }
}
```

### A.5 `Components.swift`
```swift
import SwiftUI
import AppKit

// MARK: - Island host

/// Hosts any state's content inside the morphing island. The frame is FIXED (window size);
/// only `metrics` animates. Content is laid out at its final size and revealed by the mask.
public struct IslandHost<Content: View>: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    public var metrics: NotchMetrics
    public var band: CGFloat                 // hardware notch / menu-bar band height
    public var palette: AmbientPalette
    public var effect: AmbientEffect
    public var energy: Double
    public var budget: EffectBudget
    public var elevated: Bool                // panel shadow (peek with chin, open)
    public var translucent: Bool             // Settings ▸ Appearance ▸ Translucent background
    @ViewBuilder public var content: () -> Content

    public init(metrics: NotchMetrics, band: CGFloat, palette: AmbientPalette, effect: AmbientEffect = .aurora,
                energy: Double = 0, budget: EffectBudget, elevated: Bool, translucent: Bool = false,
                @ViewBuilder content: @escaping () -> Content) {
        self.metrics = metrics; self.band = band; self.palette = palette; self.effect = effect
        self.energy = energy; self.budget = budget; self.elevated = elevated; self.translucent = translucent
        self.content = content
    }

    public var body: some View {
        let shape = NotchShape(metrics: metrics)
        ZStack(alignment: .top) {
            if theme.allowsUnderglow && elevated {
                // Coloured light spilling onto the desktop below the island (vivid only).
                shape.fill(palette.glow1.color(Elevation.underglow.opacity))
                    .blur(radius: Elevation.underglow.radius)
                    .offset(y: Elevation.underglow.y)
                    .allowsHitTesting(false)
            }
            surface(shape)
            if theme.ambience != .off && effect != .none {
                // Sized to the island's CURRENT bounds (not the window), so the light rises with
                // the island as it opens and sits at the panel's real bottom edge.
                AmbientBackdrop(effect: effect, palette: palette, energy: energy,
                                intensity: theme.ambience.intensity, budget: budget)
                    .frame(width: max(metrics.width, 1), height: max(metrics.height, 1))
                    .padding(.top, metrics.topOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .mask(shape)
            }
            content().mask(shape)
            // Rim on the lower edge only: the top must stay seamless with the bezel/menu bar.
            shape.stroke(theme.surfaces.hairline,
                         lineWidth: theme.increaseContrast ? Stroke.regular : Stroke.hairline(displayScale))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .white, location: min(0.99, (band + 6) / max(metrics.bottom, 1)))],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .elevation(elevated ? Elevation.panel : Elevation.none)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
    }

    /// Opaque black by default. Translucent mode keeps the hardware band opaque (no seam around the
    /// camera housing) and lets the wallpaper through below it; Liquid Glass on macOS 26+.
    @ViewBuilder private func surface(_ shape: NotchShape) -> some View {
        if translucent && !theme.reduceTransparency {
            let split = min(0.99, band / max(metrics.bottom, 1))
            let fade = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: split),
                                              .init(color: .black.opacity(0.58), location: min(1, split + 0.12))],
                                      startPoint: .top, endPoint: .bottom)
            if #available(macOS 26.0, *) {
                shape.fill(fade).background { Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)), in: shape) }
            } else {
                shape.fill(fade).background { VisualEffectBlur().clipShape(shape) }
            }
        } else {
            shape.fill(theme.surfaces.notch)
        }
    }
}

/// NSVisualEffectView bridge (pre-macOS 26 translucent island).
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Compact wings around the camera housing

public struct CompactSlots<Leading: View, Trailing: View>: View {
    public var notchWidth: CGFloat
    public var side: CGFloat
    public var height: CGFloat
    public var outerInset: CGFloat = 8       // keeps content off the bottom-corner curve
    public var cameraClearance: CGFloat = 6  // never closer than this to the housing
    @ViewBuilder public var leading: () -> Leading
    @ViewBuilder public var trailing: () -> Trailing

    public init(notchWidth: CGFloat, side: CGFloat, height: CGFloat,
                @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.notchWidth = notchWidth; self.side = side; self.height = height
        self.leading = leading; self.trailing = trailing
    }

    public var body: some View {
        let inner = max(side - outerInset - cameraClearance, 0)
        HStack(spacing: 0) {
            leading().frame(width: inner, height: height, alignment: .leading)
                .padding(.leading, outerInset).padding(.trailing, cameraClearance)
            Color.clear.frame(width: notchWidth, height: height)        // camera housing: no content
                .accessibilityHidden(true)
            trailing().frame(width: inner, height: height, alignment: .trailing)
                .padding(.leading, cameraClearance).padding(.trailing, outerInset)
        }
    }
}

// MARK: - HUD level bar (volume / brightness / keyboard backlight)

public struct LevelBar: View {
    @Environment(\.cranny) private var theme
    public var value: Double                 // 0…1
    public var steps = 16                    // macOS hardware steps
    public var tint: RGB?                    // nil = monochrome (Settings ▸ HUD ▸ Colour off)
    public var muted = false
    public var label: String

    public init(value: Double, steps: Int = 16, tint: RGB?, muted: Bool = false, label: String) {
        self.value = value; self.steps = steps; self.tint = tint; self.muted = muted; self.label = label
    }

    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.surfaces.well)
                Capsule().fill(fillStyle)
                    .frame(width: max(6, g.size.width * value))
                    .opacity(muted ? 0.35 : 1)
                if theme.differentiateWithoutColor || theme.increaseContrast {
                    // Step ticks so the level is readable without relying on colour/fill alone.
                    HStack(spacing: 0) {
                        ForEach(1..<steps, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: 6)
        .animation(theme.anim.level, value: value)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(muted ? "Muted" : "\(Int((value * 100).rounded())) percent"))
    }

    private var fillStyle: AnyShapeStyle {
        guard let t = tint else { return AnyShapeStyle(Color.white.opacity(0.92)) }
        return AnyShapeStyle(LinearGradient(colors: [t.color(0.85), t.legibleOnBlack(ratio: theme.accentContrast).color],
                                            startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: - Cards

public struct CardModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isFocused) private var isFocused
    public var isHovered = false
    public var padding: CGFloat = Space.l
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(padding * theme.density.rawValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(isHovered ? theme.surfaces.cardHover : theme.surfaces.card))
            .overlay(shape.strokeBorder(theme.surfaces.hairline,
                                        lineWidth: theme.increaseContrast ? 1 : Stroke.hairline(displayScale)))
            .animation(theme.anim.hover, value: isHovered)
    }
}
public extension View {
    func crannyCard(hovered: Bool = false, padding: CGFloat = Space.l) -> some View {
        modifier(CardModifier(isHovered: hovered, padding: padding))
    }
    /// Own focus ring (system rings are clipped by the island mask): 2 pt, concentric, white.
    func crannyFocusRing(_ focused: Bool, radius: CGFloat = Radius.card) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
            .strokeBorder(Color.white.opacity(focused ? 0.9 : 0), lineWidth: Stroke.focus)
            .padding(-3)
            .allowsHitTesting(false))
    }
}

/// Icon button used across widgets (capsule or rounded per Settings ▸ Appearance ▸ Button shape).
public struct IconButton: View {
    @Environment(\.cranny) private var theme
    public var symbol: String
    public var label: LocalizedStringKey
    public var size: CGFloat = 28
    public var prominent = false
    public var tint: RGB = .white
    public var action: () -> Void = {}
    @State private var hovering = false

    public init(symbol: String, label: LocalizedStringKey, size: CGFloat = 28, prominent: Bool = false,
                tint: RGB = .white, action: @escaping () -> Void = {}) {
        self.symbol = symbol; self.label = label; self.size = size; self.prominent = prominent
        self.tint = tint; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(prominent ? tint.onColor.color : theme.surfaces.textPrimary)
                .frame(width: size, height: size)
                .background(theme.buttonShape.fill(prominent ? tint.color
                                                   : (hovering ? theme.surfaces.cardHover : Color.clear)))
                .contentShape(theme.buttonShape)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(theme.anim.hover) { hovering = h } }
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

public struct PressScaleStyle: ButtonStyle {
    @Environment(\.cranny) private var theme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed && theme.reduceMotion ? 0.7 : 1)
            .animation(theme.anim.press, value: configuration.isPressed)
    }
}

// MARK: - Header tabs (left wing of the open Nook)

public struct NookTab: Identifiable, Hashable {
    public var id: String
    public var title: LocalizedStringKey
    public var symbol: String
    public init(id: String, title: LocalizedStringKey, symbol: String) { self.id = id; self.title = title; self.symbol = symbol }
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct NookTabs: View {
    @Environment(\.cranny) private var theme
    @Namespace private var ns
    public var tabs: [NookTab]
    @Binding public var selection: String

    public init(tabs: [NookTab], selection: Binding<String>) { self.tabs = tabs; self._selection = selection }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { t in
                let sel = selection == t.id
                Button { withAnimation(theme.anim.tab) { selection = t.id } } label: {
                    Label(t.title, systemImage: t.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(theme.type.font(.callout))
                        .foregroundStyle(sel ? theme.surfaces.textPrimary : theme.surfaces.textSecondary)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background {
                            if sel { Capsule().fill(theme.surfaces.cardPressed).matchedGeometryEffect(id: "tab", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.surfaces.well))
    }
}

// MARK: - Haptics (Force Touch trackpad; silently does nothing with a mouse)

@MainActor public enum Haptics {
    public static var enabled = true
    /// Swipe commit, snap to a grid slot, widget reorder drop.
    public static func alignment() { perform(.alignment) }
    /// Crossing a HUD step boundary, timer preset detents, swipe threshold reached.
    public static func level() { perform(.levelChange) }
    /// Generic confirmation (file accepted by the tray).
    public static func tap() { perform(.generic) }
    private static func perform(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }
}
```

### A.6 `Palette.swift` and `Effects.swift`
```swift
import SwiftUI
import CoreGraphics
import AppKit

/// Colours derived from what is playing (or from the active activity).
/// `glow1…3` are LIGHT (aurora, halos, underglow) and may be any brightness.
/// `accent` is for FOREGROUND marks on black and is contrast-guarded (≥ 4.5:1, ≥ 7:1 with
/// Increase Contrast). Never put text on a glow without a scrim.
public struct AmbientPalette: Equatable, Sendable {
    public var glow1: RGB
    public var glow2: RGB
    public var glow3: RGB
    public var accent: RGB
    public var isMonochrome: Bool

    public init(glow1: RGB, glow2: RGB, glow3: RGB, accent: RGB, isMonochrome: Bool = false) {
        self.glow1 = glow1; self.glow2 = glow2; self.glow3 = glow3; self.accent = accent; self.isMonochrome = isMonochrome
    }
    public var glows: [RGB] { [glow1, glow2, glow3] }

    /// Animatable form: lets Canvas/MeshGradient effects cross-fade palettes (Animatable views).
    public typealias Vector = AnimatablePair<AnimatablePair<RGB, RGB>, AnimatablePair<RGB, RGB>>
    public var vector: Vector {
        get { .init(.init(glow1, glow2), .init(glow3, accent)) }
        set { glow1 = newValue.first.first; glow2 = newValue.first.second
              glow3 = newValue.second.first; accent = newValue.second.second }
    }

    // Brand / semantic palettes for activities without artwork.
    public static let afterglow = AmbientPalette(glow1: CrannyColor.iris, glow2: CrannyColor.rose,
                                                 glow3: CrannyColor.lagoon, accent: RGB(hex: 0xA996FF))
    public static let timer = AmbientPalette(glow1: CrannyColor.ember, glow2: RGB(hex: 0xFFB347),
                                             glow3: CrannyColor.rose, accent: RGB(hex: 0xFF9A6B))
    public static let charging = AmbientPalette(glow1: CrannyColor.success, glow2: RGB(hex: 0x9CF06B),
                                                glow3: CrannyColor.lagoon, accent: CrannyColor.success)
    public static let lowBattery = AmbientPalette(glow1: CrannyColor.danger, glow2: CrannyColor.ember,
                                                  glow3: CrannyColor.rose, accent: RGB(hex: 0xFF6961))
    public static func calendar(_ c: RGB) -> AmbientPalette {
        let (h, s, v) = c.hsb
        return .init(glow1: c.luminous, glow2: RGB(h: (h + 0.06).truncatingRemainder(dividingBy: 1), s: s, v: v).luminous,
                     glow3: RGB(h: (h + 0.94).truncatingRemainder(dividingBy: 1), s: s * 0.8, v: v).luminous,
                     accent: c.legibleOnBlack())
    }
    /// Accent source "System": follow the macOS accent colour.
    @MainActor public static func system() -> AmbientPalette {
        let ns = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return calendar(RGB(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)))
    }
    public static let mono = AmbientPalette(glow1: RGB(0.78, 0.80, 0.86), glow2: RGB(0.55, 0.58, 0.66),
                                            glow3: RGB(0.90, 0.90, 0.95), accent: RGB(0.94, 0.94, 0.96), isMonochrome: true)

    // MARK: Extraction — pure CoreGraphics + tiny k-means on a 24×24 thumbnail.
    // Run off the main actor; cache by track identifier; ≈ 0.3 ms per artwork.

    public static func extract(from image: CGImage, minAccentContrast: Double = 4.5) -> AmbientPalette {
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return .afterglow }

        var samples: [RGB] = []
        samples.reserveCapacity(side * side)
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
            samples.append(RGB(Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255))
        }
        guard samples.count > 16 else { return .afterglow }

        // k-means, k = 5, deterministic seeds → same artwork always yields the same palette.
        let k = 5
        var centers = (0..<k).map { samples[$0 * samples.count / k] }
        var counts = [Int](repeating: 0, count: k)
        for _ in 0..<8 {
            var sums = [RGB](repeating: .zero, count: k)
            counts = [Int](repeating: 0, count: k)
            for s in samples {
                var best = 0, bestD = Double.infinity
                for (j, c) in centers.enumerated() {
                    let d = (s - c).magnitudeSquared
                    if d < bestD { bestD = d; best = j }
                }
                sums[best] = sums[best] + s; counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 { centers[j] = sums[j].scaled(1 / Double(counts[j])) }
        }

        // Rank by population × colourfulness; near-black / near-white clusters barely count.
        let total = Double(samples.count)
        func score(_ c: RGB, _ w: Double) -> Double {
            let (_, s, v) = c.hsb
            let penalty = (v < 0.12 || (s < 0.08 && v > 0.9)) ? 0.15 : 1
            return w * (0.25 + c.chroma) * penalty
        }
        let ranked = zip(centers, counts).filter { $0.1 > 0 }
            .map { (c: $0.0, w: Double($0.1) / total) }
            .sorted { score($0.c, $0.w) > score($1.c, $1.w) }

        if (ranked.map(\.c.chroma).max() ?? 0) < 0.10 {
            return .mono    // greyscale artwork: honest silver light, no invented colour
        }
        var picks: [RGB] = []
        for cand in ranked.map(\.c) {
            let h = cand.hsb.h
            if picks.allSatisfy({ let d = abs($0.hsb.h - h); return d > 0.06 && d < 0.94 }) { picks.append(cand) }
            if picks.count == 3 { break }
        }
        while picks.count < 3, let base = picks.first?.hsb {   // single-hued art → analogous neighbours
            let shift = picks.count == 1 ? 0.07 : -0.07
            picks.append(RGB(h: (base.h + shift + 1).truncatingRemainder(dividingBy: 1), s: base.s, v: base.v))
        }
        let vivid = ranked.map(\.c).max { $0.chroma < $1.chroma } ?? picks[0]
        return .init(glow1: picks[0].luminous, glow2: picks[1].luminous, glow3: picks[2].luminous,
                     accent: vivid.legibleOnBlack(ratio: minAccentContrast))
    }
}
```
```swift
import SwiftUI

// Every effect is a pure function of (time, palette, energy, intensity): no per-particle state,
// no timers. TimelineView supplies time; pausing it costs nothing. No Metal shaders are needed
// (the offline Metal toolchain is not assumed) — MeshGradient on macOS 15+, Canvas otherwise.

public enum AmbientEffect: String, CaseIterable, Sendable {
    case aurora   // soft curtains of album colour rising from the bottom edge (default)
    case motes    // slow rising specks of light, brighter on loud passages
    case tide     // three luminous wave lines along the bottom edge, audio-driven amplitude
    case halo     // a single bloom behind the hero (lowest cost; default in Low Power Mode)
    case none
}

/// Deterministic per-index pseudo-random in 0..<1 (stateless particles).
@inline(__always) func hash01(_ i: Int, _ salt: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: i &* 0x9E3779B1 &+ salt &* 0x85EBCA77)
    x ^= x >> 33; x = x &* 0xFF51AFD7ED558CCD; x ^= x >> 33; x = x &* 0xC4CEB9FE1A85EC53; x ^= x >> 33
    return Double(x % 10_000) / 10_000
}

// MARK: - Aurora (MeshGradient, macOS 15+)

@available(macOS 15.0, *)
struct AuroraMesh: View {
    var time: Double
    var palette: AmbientPalette
    var energy: Double
    var intensity: Double

    var body: some View {
        // 4 × 4 mesh. Row 0–1 stay black so the header band remains pure notch-black;
        // rows 2–3 carry the light. Interior points drift on incommensurate sines → no visible loop.
        let t = Float(time)
        let e = Float(energy)
        func drift(_ i: Int, _ amp: Float) -> Float {
            let fi = Float(i)
            return amp * sin(t * (0.21 + 0.05 * fi) + fi * 1.7)
        }
        let swell = 0.08 + 0.06 * e                          // louder → light climbs higher
        let points: [SIMD2<Float>] = [
            [0, 0], [0.33, 0], [0.67, 0], [1, 0],
            [0, 0.42], [0.33 + drift(1, 0.05), 0.40 + drift(2, 0.03)], [0.67 + drift(3, 0.05), 0.42 + drift(4, 0.03)], [1, 0.42],
            [0, 0.72 - swell], [0.30 + drift(5, 0.08), 0.70 - swell + drift(6, 0.06)],
            [0.70 + drift(7, 0.08), 0.68 - swell + drift(8, 0.06)], [1, 0.74 - swell],
            [0, 1], [0.33 + drift(9, 0.04), 1], [0.67 + drift(10, 0.04), 1], [1, 1],
        ]
        let a = 0.85 * intensity * (0.8 + 0.2 * energy)
        let g = palette.glows
        let clear = Color.black.opacity(0)
        let colors: [Color] = [
            clear, clear, clear, clear,
            clear, g[1].color(a * 0.10), g[2].color(a * 0.10), clear,
            g[0].color(a * 0.35), g[1].color(a * 0.55), g[2].color(a * 0.50), g[0].color(a * 0.30),
            g[2].color(a * 0.70), g[0].color(a * 0.95), g[1].color(a * 0.90), g[2].color(a * 0.65),
        ]
        return MeshGradient(width: 4, height: 4, points: points, colors: colors,
                            background: .clear, smoothsColors: true, colorSpace: .perceptual)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Aurora fallback (Canvas, macOS 14)

struct AuroraCanvas: View {
    @Environment(\.crannySnapshot) private var snapshot
    var time: Double
    var palette: AmbientPalette
    var energy: Double
    var intensity: Double

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: !snapshot) { ctx, size in
            guard intensity > 0 else { return }
            ctx.addFilter(.blur(radius: max(10, size.height * 0.10)))
            ctx.blendMode = .plusLighter
            let w = Double(size.width), hgt = Double(size.height)
            for (i, c) in palette.glows.enumerated() {
                let fi = Double(i)
                let phase: Double = time * (0.09 + 0.035 * fi) * 2 * .pi
                let base: Double = hgt * (0.62 + 0.10 * fi)
                let amp: Double = hgt * (0.09 + 0.06 * energy) * (1 - 0.2 * fi)
                let f1: Double = 2 * .pi * (0.75 + 0.35 * fi)
                let f2: Double = 2 * .pi * (1.9 + 0.2 * fi)
                var path = Path()
                path.move(to: CGPoint(x: -40, y: hgt + 40))
                var x: Double = -40
                while x <= w + 40 {
                    let u: Double = x / max(w, 1)
                    let y1: Double = amp * sin(u * f1 + phase)
                    let y2: Double = amp * 0.45 * sin(u * f2 - phase * 1.4)
                    path.addLine(to: CGPoint(x: x, y: base + y1 + y2))
                    x += 10
                }
                path.addLine(to: CGPoint(x: w + 40, y: hgt + 40))
                path.closeSubpath()
                let a: Double = 0.55 * intensity * (0.75 + 0.25 * energy)
                let grad = Gradient(stops: [.init(color: c.color(0), location: 0),
                                            .init(color: c.color(a), location: 0.35),
                                            .init(color: c.color(a * 0.25), location: 0.75),
                                            .init(color: c.color(0), location: 1)])
                ctx.fill(path, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: base - amp * 1.6),
                                                     endPoint: CGPoint(x: 0, y: hgt)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Motes

struct MotesCanvas: View {
    @Environment(\.crannySnapshot) private var snapshot
    var time: Double
    var palette: AmbientPalette
    var energy: Double
    var intensity: Double
    var count = 36

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: !snapshot) { ctx, size in
            guard intensity > 0 else { return }
            ctx.blendMode = .plusLighter
            let glows = palette.glows
            let hgt = Double(size.height), w = Double(size.width)
            for i in 0..<count {
                let speed: Double = 5 + 9 * hash01(i, 1)                 // pt/s, slow on purpose
                let life: Double = hgt + 24
                let travel: Double = (time * speed + hash01(i, 2) * life).truncatingRemainder(dividingBy: life)
                let y: Double = hgt + 12 - travel
                let sway: Double = sin(time * (0.4 + hash01(i, 4)) + hash01(i, 5) * 6.28) * 7
                let x: Double = hash01(i, 3) * w + sway
                let r: Double = 0.8 + 1.6 * hash01(i, 6)
                let twinkle: Double = 0.55 + 0.45 * sin(time * (1.2 + 2 * hash01(i, 7)) + Double(i))
                let edgeFade: Double = min(1, travel / 30) * min(1, (life - travel) / 40)
                let a: Double = intensity * (0.25 + 0.45 * hash01(i, 8)) * twinkle * edgeFade * (0.7 + 0.6 * energy)
                let c = glows[i % glows.count]
                let center = CGPoint(x: x, y: y)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)),
                         with: .radialGradient(Gradient(colors: [c.color(a * 0.5), c.color(0)]),
                                               center: center, startRadius: 0, endRadius: r * 3))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                         with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Tide

struct TideCanvas: View {
    @Environment(\.crannySnapshot) private var snapshot
    var time: Double
    var palette: AmbientPalette
    var energy: Double
    var intensity: Double

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: !snapshot) { ctx, size in
            guard intensity > 0 else { return }
            ctx.blendMode = .plusLighter
            let w = Double(size.width), hgt = Double(size.height)
            for (i, c) in palette.glows.enumerated() {
                let fi = Double(i)
                let amp: Double = (3 + 7 * energy) * (1 - 0.25 * fi)
                let baseY: Double = hgt - 10 - 5 * fi
                let freq: Double = 2 * .pi * (2 + fi * 0.6)
                let speed: Double = 1.1 + 0.4 * fi
                var p = Path()
                var x = 0.0
                while x <= w {
                    let u: Double = x / w
                    let env: Double = sin(u * .pi)                        // taper at both ends
                    let y: Double = baseY - env * amp * sin(u * freq + time * speed)
                    if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += 6
                }
                let a: Double = intensity * (0.7 - 0.15 * fi)
                var bloom = ctx
                bloom.addFilter(.blur(radius: 3))
                bloom.stroke(p, with: .color(c.color(a * 0.6)), lineWidth: 4)
                ctx.stroke(p, with: .color(c.color(a)), lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Halo (bloom behind album art / timer ring; also in compact wings)

public struct Halo: View {
    public var color: RGB
    public var energy: Double = 0
    public var intensity: Double = 1
    public init(color: RGB, energy: Double = 0, intensity: Double = 1) {
        self.color = color; self.energy = energy; self.intensity = intensity
    }
    public var body: some View {
        GeometryReader { g in
            RadialGradient(colors: [color.color(0.55 * intensity * (0.8 + 0.4 * energy)), color.color(0)],
                           center: .center, startRadius: 0, endRadius: min(g.size.width, g.size.height) / 2)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Spectrum (compact visualiser)

/// Real levels when the media module has an audio tap (Core Audio process tap, macOS 14.2+,
/// needs the "System Audio Recording" permission); otherwise an honest "breathing" pattern that
/// never pretends to be beat-accurate. Settings ▸ Media ▸ Visualizer: Live · Ambient · Off.
public struct SpectrumBars: View {
    public var levels: [Double]
    public var color: RGB
    public var barWidth: CGFloat = 3
    public var spacing: CGFloat = 2
    public var maxHeight: CGFloat = 14

    public init(levels: [Double], color: RGB, barWidth: CGFloat = 3, spacing: CGFloat = 2, maxHeight: CGFloat = 14) {
        self.levels = levels; self.color = color; self.barWidth = barWidth; self.spacing = spacing; self.maxHeight = maxHeight
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = levels.count
            let total = CGFloat(n) * barWidth + CGFloat(max(n - 1, 0)) * spacing
            var x = (size.width - total) / 2
            for v in levels {
                let h = max(barWidth, CGFloat(min(max(v, 0), 1)) * maxHeight)
                let r = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: barWidth / 2), with: .color(color.color))
                x += barWidth + spacing
            }
        }
        .frame(width: CGFloat(levels.count) * (barWidth + spacing), height: maxHeight)
        .accessibilityHidden(true)
    }

    public static func ambient(time: Double, playing: Bool, bars: Int = 5) -> [Double] {
        guard playing else { return Array(repeating: 0.18, count: bars) }
        return (0..<bars).map { i in
            let f = Double(i)
            let a: Double = 0.3 * sin(time * (3.1 + f * 0.7) + f) * sin(time * (1.3 + f * 0.37) + f * 2)
            return 0.35 + a + 0.2 * sin(time * 7.3 + f * 1.7)
        }
    }
}

// MARK: - Ember burst (one-shot delight: timer done, file dropped, charger connected)

public struct EmberBurst: View {
    public var progress: Double          // 0 → 1 over ~0.9 s (keyframeAnimator / TimelineView)
    public var origin: UnitPoint = .top
    public var palette: AmbientPalette
    public var count = 18

    public init(progress: Double, origin: UnitPoint = .top, palette: AmbientPalette, count: Int = 18) {
        self.progress = progress; self.origin = origin; self.palette = palette; self.count = count
    }

    public var body: some View {
        Canvas { ctx, size in
            guard progress > 0, progress < 1 else { return }
            ctx.blendMode = .plusLighter
            let o = CGPoint(x: origin.x * size.width, y: origin.y * size.height)
            let ease: Double = 1 - pow(1 - progress, 3)
            for i in 0..<count {
                let angle: Double = .pi * (0.1 + 0.8 * hash01(i, 11))     // fan downward from the notch
                let dist: Double = (40 + 60 * hash01(i, 12)) * ease
                let gravity: Double = 18 * progress * progress
                let p = CGPoint(x: o.x + cos(angle) * dist, y: o.y + sin(angle) * dist + gravity)
                let r: Double = (1.2 + 1.8 * hash01(i, 13)) * (1 - progress * 0.6)
                let a: Double = (1 - progress) * (0.6 + 0.4 * hash01(i, 14))
                let c = palette.glows[i % 3]
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                         with: .radialGradient(Gradient(colors: [c.color(a * 0.6), c.color(0)]),
                                               center: p, startRadius: 0, endRadius: r * 3))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                         with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Energy budget

public struct EffectBudget: Sendable, Equatable {
    public var isVisible: Bool         // window on screen AND island not closed
    public var isOpen: Bool
    public var lowPower: Bool          // ProcessInfo.isLowPowerModeEnabled || thermalState >= .serious
    public var fullscreenFront: Bool   // a fullscreen app/video owns this display
    public var reduceMotion: Bool
    public var onBattery = false

    public init(isVisible: Bool, isOpen: Bool, lowPower: Bool, fullscreenFront: Bool, reduceMotion: Bool, onBattery: Bool = false) {
        self.isVisible = isVisible; self.isOpen = isOpen; self.lowPower = lowPower
        self.fullscreenFront = fullscreenFront; self.reduceMotion = reduceMotion; self.onBattery = onBattery
    }

    /// nil = paused (TimelineView stops ticking → zero CPU/GPU). Reduce Motion FREEZES a pleasant
    /// frame instead of removing the light: colour stays, movement goes.
    public var minimumInterval: Double? {
        guard isVisible, !fullscreenFront, !reduceMotion else { return nil }
        if lowPower { return nil }
        if onBattery { return isOpen ? 1.0 / 30 : 1.0 / 15 }
        return isOpen ? 1.0 / 60 : 1.0 / 30
    }
    /// Effect actually drawn: Low Power downgrades everything to the static halo.
    public func effective(_ e: AmbientEffect) -> AmbientEffect { lowPower && e != .none ? .halo : e }
}

// MARK: - Backdrop

/// Animatable over the palette: when the album changes, call
/// `withAnimation(theme.anim.colorShift) { palette = new }` and the light cross-fades.
public struct AmbientBackdrop: View, Animatable {
    public var effect: AmbientEffect
    public var palette: AmbientPalette
    public var energy: Double
    public var intensity: Double
    public var budget: EffectBudget
    public var restingTime: Double = 7.3     // the frozen frame used when paused

    public init(effect: AmbientEffect, palette: AmbientPalette, energy: Double, intensity: Double, budget: EffectBudget) {
        self.effect = effect; self.palette = palette; self.energy = energy; self.intensity = intensity; self.budget = budget
    }

    public var animatableData: AnimatablePair<AmbientPalette.Vector, AnimatablePair<Double, Double>> {
        get { .init(palette.vector, .init(energy, intensity)) }
        set { palette.vector = newValue.first; energy = newValue.second.first; intensity = newValue.second.second }
    }

    public var body: some View {
        let interval = budget.minimumInterval
        TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil)) { tl in
            let t = interval == nil ? restingTime : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            layer(time: t)
        }
    }

    @ViewBuilder private func layer(time t: Double) -> some View {
        switch budget.effective(effect) {
        case .aurora:
            if #available(macOS 15.0, *) {
                AuroraMesh(time: t, palette: palette, energy: energy, intensity: intensity)
            } else {
                AuroraCanvas(time: t, palette: palette, energy: energy, intensity: intensity)
            }
        case .motes: MotesCanvas(time: t, palette: palette, energy: energy, intensity: intensity)
        case .tide:  TideCanvas(time: t, palette: palette, energy: energy, intensity: intensity)
        case .halo:
            Halo(color: palette.glow1, energy: energy, intensity: intensity * 0.6)
                .scaleEffect(x: 1.4, y: 0.9, anchor: .bottom)
                .offset(y: 40)
        case .none:  Color.clear
        }
    }
}

public extension EnvironmentValues {
    /// Canvas effects render asynchronously on screen (off the main thread). Set to `true` for
    /// ImageRenderer snapshots (Settings thumbnails, tests), which need synchronous rendering.
    @Entry var crannySnapshot = false
}
```

### A.7 `Delight.swift` and `AppIcon.swift`
```swift
import SwiftUI

/// "Satellite" split: when a SECOND live activity appears, a small black bubble buds off the
/// trailing edge of the island with a liquid neck (metaball), then separates. Pure Canvas:
/// blur + alphaThreshold — no Metal. Crisp shapes are drawn on top so only the neck is "gooey".
/// Drive `progress` 0 → 1 with `theme.anim.peekIn`; Reduce Motion → satellite just fades in.
public struct SatelliteSplit: View {
    public var island: NotchMetrics
    public var diameter: CGFloat = 22
    public var gap: CGFloat = 6
    public var progress: Double            // 0 = inside the island edge, 1 = detached at `gap`

    public init(island: NotchMetrics, diameter: CGFloat = 22, gap: CGFloat = 6, progress: Double) {
        self.island = island; self.diameter = diameter; self.gap = gap; self.progress = progress
    }

    public var body: some View {
        Canvas { ctx, size in
            let shape = NotchShape(metrics: island).path(in: CGRect(origin: .zero, size: size))
            let right = size.width / 2 + island.width / 2
            let start = right - diameter / 2 - 2                       // tucked inside the trailing wing
            let cx = start + (gap + diameter + 2) * CGFloat(progress)    // → detached, `gap` pt away
            let cy = island.topOffset + min(island.height, diameter + 6) / 2
            let bubble = Path(ellipseIn: CGRect(x: cx - diameter / 2, y: cy - diameter / 2, width: diameter, height: diameter))
            // Liquid neck: the gooey layer is clipped to the strip between island edge and bubble,
            // so the island's own outline is never fattened by the threshold.
            var neck = ctx
            neck.clip(to: Path(CGRect(x: right - 1, y: 0, width: max(cx - right + 1, 0), height: size.height)))
            neck.drawLayer { layer in
                layer.addFilter(.alphaThreshold(min: 0.4, color: .black))
                layer.addFilter(.blur(radius: 8))
                layer.fill(shape, with: .color(.black))
                layer.fill(bubble, with: .color(.black))
            }
            ctx.fill(shape, with: .color(.black))
            ctx.fill(bubble, with: .color(.black))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```
```swift
import SwiftUI
import AppKit
import CoreGraphics

/// App icon "Afterglow" — a crevice of light. A night-indigo squircle; a black notch-shaped
/// crevice hangs from the top edge; warm-to-violet light pours out beneath it; one bright mote.
/// Flat fallback for macOS 14/15 drawn with CoreGraphics only (radial gradients, no blur filters),
/// rendered to PNGs by a build script → AppIcon.appiconset. macOS 26+ uses the layered .icon.
public enum CrannyIconRenderer {
    /// Draws into a context whose origin is bottom-left (standard CG). `side` = canvas edge (e.g. 1024).
    public static func draw(in ctx: CGContext, side s: CGFloat, monochrome: Bool = false) {
        let inset = s * 100 / 1024                  // macOS icon grid: 824/1024 body
        let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let b = body.width
        let squircle = Path(roundedRect: body, cornerRadius: b * 0.225, style: .continuous).cgPath
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        func cg(_ c: RGB, _ a: CGFloat = 1) -> CGColor {
            let m = monochrome ? RGB(c.luminance, c.luminance, c.luminance).scaled(1.4) : c
            return CGColor(colorSpace: space, components: [m.r, m.g, m.b, a]) ?? CGColor(gray: 0.5, alpha: a)
        }

        // Drop shadow (macOS 14/15 icons carry their own)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -b * 0.012), blur: b * 0.03, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle); ctx.setFillColor(cg(CrannyColor.night)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(squircle); ctx.clip()
        // Body gradient: indigo top → night bottom
        let bg = CGGradient(colorsSpace: space, colors: [cg(RGB(hex: 0x1E1640)), cg(RGB(hex: 0x07060D))] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

        // Light pouring out of the crevice: a fan of aurora curtains (elliptical radial gradients,
        // additive) that start under the notch's lower edge and fade toward the bottom.
        ctx.setBlendMode(.plusLighter)
        let top = body.maxY
        let notchH = b * 0.15
        let source = CGPoint(x: body.midX, y: top - notchH)
        let curtains: [(RGB, CGFloat, CGFloat, CGFloat)] = [     // colour, x offset, half-width, alpha
            (CrannyColor.lagoon, -0.30, 0.13, 0.40),
            (CrannyColor.iris,   -0.15, 0.16, 0.75),
            (CrannyColor.rose,    0.02, 0.17, 0.80),
            (CrannyColor.ember,   0.17, 0.14, 0.70),
            (CrannyColor.iris,    0.31, 0.12, 0.45),
        ]
        for (c, dx, hw, a) in curtains {
            ctx.saveGState()
            ctx.translateBy(x: source.x + dx * b, y: source.y)
            ctx.scaleBy(x: hw / 0.62, y: 1)                    // ellipse: narrow, tall
            let g = CGGradient(colorsSpace: space, colors: [cg(c, a), cg(c, a * 0.4), cg(c, 0)] as CFArray,
                               locations: [0, 0.4, 1])!
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: b * 0.62, options: [])
            ctx.restoreGState()
        }
        // Warm core right under the slit
        let core = CGGradient(colorsSpace: space, colors: [cg(RGB(hex: 0xFFC9A3), 0.95), cg(CrannyColor.ember, 0.5), cg(CrannyColor.ember, 0)] as CFArray,
                              locations: [0, 0.35, 1])!
        ctx.saveGState()
        ctx.translateBy(x: source.x, y: source.y); ctx.scaleBy(x: 2.2, y: 1)
        ctx.drawRadialGradient(core, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: b * 0.11, options: [])
        ctx.restoreGState()
        ctx.setBlendMode(.normal)

        // The crevice (notch tab) — the very NotchShape the app uses, flipped into CG space,
        // with a thin rim of light on its lower edge ("light leaking from under a door").
        let m = NotchMetrics(width: b * 0.40, height: notchH, bottomRadius: b * 0.06, topCorner: b * 0.045)
        let notchRect = CGRect(x: body.minX, y: 0, width: b, height: b)
        var flip = CGAffineTransform(translationX: 0, y: top).scaledBy(x: 1, y: -1)
        if let p = NotchShape(metrics: m).path(in: notchRect).cgPath.copy(using: &flip) {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: b * 0.03, color: cg(CrannyColor.ember, 0.9))
            ctx.addPath(p); ctx.setStrokeColor(cg(RGB(hex: 0xFFD2B0), 0.9)); ctx.setLineWidth(b * 0.010); ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(p); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        }

        // One bright mote (the "cranny" catching light).
        let mote = CGPoint(x: body.midX + b * 0.16, y: top - b * 0.58)
        let mg = CGGradient(colorsSpace: space, colors: [cg(.white, 1), cg(RGB(hex: 0xFFD7B8), 0.5), cg(.white, 0)] as CFArray,
                            locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(mg, startCenter: mote, startRadius: 0, endCenter: mote, endRadius: b * 0.045, options: [])

        // Top inner highlight for depth
        ctx.addPath(squircle); ctx.setLineWidth(b * 0.006)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16)); ctx.strokePath()
        ctx.restoreGState()
    }

    public static func cgImage(side: Int, monochrome: Bool = false) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(in: ctx, side: CGFloat(side), monochrome: monochrome)
        return ctx.makeImage()
    }
}

/// Menu-bar extra glyph (template image, 18 × 14 pt): a rounded screen outline with a filled
/// notch tab — reads as "the top of your Mac" without using any Apple product artwork.
@MainActor public func crannyMenuBarImage() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { rect in
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.25), xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1.5
        NSColor.black.setStroke(); outline.stroke()
        let tab = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 0.5, width: 7, height: 4.5), xRadius: 2, yRadius: 2)
        NSColor.black.setFill(); tab.fill()
        NSRect(x: 5.5, y: 0.5, width: 7, height: 2).fill()      // square top edge → reads as a notch
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "Cranny"
    return img
}
```

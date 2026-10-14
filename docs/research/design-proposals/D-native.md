# Cranny Design System: Direction A, "Apple-native precision"

> *Make it look as if Apple had shipped a Dynamic Island for the Mac.* Restraint, exact geometry, SF Pro, system materials, Liquid Glass used sparingly on macOS 26+, and motion that matches the iPhone Dynamic Island springs.

Status: proposal v1 · 2026‑10‑14 · deployment target macOS 14.0. Newer APIs are gated with `#available`.
Everything in this document is original work for Cranny (MIT). It contains no NotchNook, boring.notch (GPL), Alcove or Atoll code, assets or UI text. Competitor apps were studied only through public reviews, product pages and issue trackers.

**Verified companion PoC** (scratch only, not in the repo):
`…/scratchpad/poc/design-native/`
- `src/Tokens.swift`, `Geometry.swift`, `NotchShape.swift`, `Motion.swift`, `Accent.swift`, `Components.swift`, `Effects.swift`, `Icon.swift`. These are the token and primitive code shown below. They compile with `swiftc -swift-version 6 -target arm64-apple-macos14.0` and produce zero warnings.
- `src/Render.swift`, a harness that renders every state to `out/states-compact.png`, `out/states-open.png`, `out/states-external.png`, `out/corner-zoom.png`, `out/morph-steps.png` and `out/icon-*.png`. It also prints the geometry table and the WCAG contrast audit (`out/audit.txt`).
- `tools/apicheck/*.swift` typechecks every other API this document recommends against the macOS 14 target: haptics, `sensoryFeedback`, `numericText`, `symbolEffect`, `blurReplace`, `phaseAnimator`, `TextRenderer`, `MeshGradient`, `glassEffect`/`GlassEffectContainer`/`glassEffectID`, `ConcentricRectangle`, accessibility actions, `onKeyPress`, `MenuBarExtra`, `SettingsLink`, the staged per-axis morph, the hover-intent tracker and the NSPanel set-up.
- `icon/Cranny.icon`, a layered Icon Composer document. `actool` compiled it to `Assets.car` + `Cranny.icns` without errors.
- `tools/seam`, a pixel test proving the ear and body union has no anti-aliasing seam.

---

## 0. TL;DR

1. **One black shape, four numbers.** Every state (closed, hover, compact, peek, HUD, open) is a `NotchGeometry(bodyWidth, height, earRadius, bottomRadius)`. A single animatable `NotchShape` morphs between them. Its bottom corners use Apple's own continuous corner (`UnevenRoundedRectangle(style: .continuous)`) and it has concave "ears" at the screen edge. The panel never resizes, so the shape never jitters.
2. **The closed state is the hardware.** It is drawn exactly inside the camera housing, measured from `NSScreen.auxiliaryTopLeft/RightArea` and `safeAreaInsets`. Every notch-anchored dimension scales by `unit = notchHeight / 32`. A calibration sheet fine-tunes width by ±8 pt.
3. **Live activities follow the HIG compact rules.** Leading and trailing slots are symmetric and snug against the camera. One datum per side. A second concurrent activity gets the *minimal* form on the other side. Hovering expands to a 52 pt-per-row *peek*.
4. **The Nook is a 2-row cell grid.** Cells are 56 pt with 8 pt gutters and 12 pt padding (Compact/Standard/Roomy densities). Cards use radius 20, concentric with the 32 pt outer corner. The header lives *in the menu-bar band*, wrapped around the camera: tabs on the left, pin and settings on the right.
5. **Colour is information.** Pure black, white text at four fixed opacities (label, secondary and tertiary all measure ≥ 5.2 : 1 on black and on cards; quaternary is reserved for disabled text), **one** accent at a time (System, Album art or Mono, lifted to ≥ 4.5 : 1 on black), and Apple's dark semantic colours for meaning only.
6. **Motion uses `spring(duration:bounce:)` everywhere, tuned to the Dynamic Island.** Examples: open 0.44 s/0.20, close 0.36/0.06, activity-in 0.50/0.30. Content leaves *before* the shape retracts. Widgets radiate outward from the camera with an 18 ms stagger. Reduce Motion turns the big morphs into dissolves.
7. **Hover intent is a contract.** It combines dwell, a pass-through speed, exit hysteresis and a close grace period. Hover never steals focus. Cranny hides in full screen, and peeks appear only on the display with the pointer. Each of these targets a complaint documented in competing apps.
8. **Liquid Glass appears only where Cranny floats without a hardware anchor:** the floating island and the HUD on notch-less displays, and the tutorial tips. It never appears inside the black notch.
9. **Accessibility is designed in from the start.** The spec covers VoiceOver labels, actions and announcements, full keyboard navigation, in-app Text Size, Increase Contrast, Reduce Transparency and Differentiate Without Color.
10. **App icon:** "Light from the nook", a graphite slab whose top edge carries a precise notch with a cool light spill beneath it. It ships as a layered Icon Composer file (verified with actool) plus a CoreGraphics flat fallback.

---

## 1. Research: what exists and where users complain

### 1.1 What these products look like (public material only)

| Product | Visual language (as observed or described) | Notes for Cranny |
|---|---|---|
| **iPhone Dynamic Island** (Apple HIG, *Live Activities*, updated Dec 2025) | Opaque black, corner radius 44 pt. Compact presentation is two elements, leading and trailing, "snug against the camera", balanced in width (52.33 × 36.67 pt each on 393-pt phones). Minimal presentation is a detached circle or oval. Expanded is 371–408 × 84–160 pt. A **key line** separates the island from dark content. Animations ≤ 2 s; numeric content transitions; "animate existing elements to new positions rather than remove and re-add". | Our grammar. The proportions are reused: slot ≈ 1.4 × band height. Concentric margins. Key line. |
| **NotchNook** (lo.cafe, commercial) | A software notch expands into a black panel (the "Nook") with widget tabs and a file Tray. Compact live activities flank the camera (artwork left, waveform right). Version 1.2 moved the volume and brightness HUD into the notch. Settings include dividers, padding, transparency and height. | Same feature space. Section 1.2 lists where it falls short. |
| **Alcove** (commercial) | Described as mimicking the iPhone Dynamic Island as closely as possible: fluid transitions, swipe gestures, customizable HUDs, Lock Screen widgets. | Closest to our direction. Reviewers praise its fidelity. A German review found switching between calendar and music limited. |
| **boring.notch** (GPL, *not* used for code) | Music-first: artwork, visualizer, shelf, mirror, calendar, battery. Its issue tracker is a rich source of UX failure modes (§1.2). | Read for problems only. |
| **Atoll** (GPL) | A boring.notch derivative that adds lock-screen widgets, system stats and many activities. It works on notch-less Macs by auto-hiding. | Feature creep is the risk to avoid. |
| **MediaMate** | Replaces the HUD with four styles, including a "Notch" style that slightly widens the notch. Per-display style. Floating panel on external displays. Reviewers call it "stable and well designed". | Per-display presentation (floating on external monitors) is the right call. |

### 1.2 Documented complaints, and Cranny's design answer

| # | Complaint (source) | Cranny's answer (section) |
|---|---|---|
| C1 | NotchNook drains the battery and runs at high CPU. The developer suggested rolling back to 1.4.6. Reports describe ">100 %" CPU on macOS 26. *(MacRumors forum and Setapp reviews, via search excerpts.)* | **Zero work when closed.** No timers, `TimelineView` or Canvas redraws while closed. The visualizer runs only while visible (≤ 30 fps). The ambient field runs ≤ 20 fps and only while the Nook is open. Energy budget §5.9. |
| C2 | NotchNook "doesn't hide properly when watching a movie". The Now Playing preview covers full-screen video *(MacStories; Setapp review)*. boring.notch #239, #663, #1278, #814 and #522 cover full-screen hiding, title-bar ghosts and Quick Look. | **Full-screen aware by default** (§4.8). On a full-screen Space the notch collapses to closed and only the HUD may appear. |
| C3 | NotchNook "always looks like a notch" on an external display, which reads as fake *(MacStories)*. | Notch-less displays choose **Pill handle, Transparent or Floating island** (glass on 26+) (§4.6). |
| C4 | Widgets are reordered "by repeatedly clicking arrows, not drag-and-drop", and the app feels unpolished *(Digital Trends / Yahoo Tech, 2024)*. | **WYSIWYG grid editor** in Settings: drag to reorder, drag the edge to resize in cells (§7.1). |
| C5 | The tray offers only two drop zones (Tray, AirDrop) *(MacStories, Digital Trends)*. | The Tray shows **pipeline drop targets** while dragging, such as "Drop to compress" (§6.4.9). |
| C6 | The expanded-to-notch transition is "a little less than smooth", and permission requests are "off-putting" *(Root Nation review, via search excerpt; the page itself returned 403)*. boring.notch #316 reports a close animation that "jiggles" and does not fit the real notch; #303 asks to disable the "wobbly" animation. | Content leaves **before** the shape retracts. Close is nearly critically damped (bounce 0.06). The closed geometry *is* the hardware outline. **Just-in-time permissions**: nothing is asked at first launch (§7.2). Animation speed setting (§5.1). |
| C7 | Hover flicker and focus stealing (boring.notch #381, #175, #94). A popover inside the notch closes the whole notch (#720). | **Hover-intent contract** (§5.8): dwell, pass-through speed, hysteresis, close grace and "holds-open" conditions. The non-activating panel never becomes key on hover. |
| C8 | The notch jumps between screens and sneak peeks appear on every monitor (boring.notch #348, #1415). | **Display policy** (§4.8): one primary display, and peeks appear only where the pointer is. |
| C9 | Brightness HUD flicker (boring.notch #1110). "Menu bar height" mode overshoots the menu bar (#308). | The HUD has its own state with the `hudLevel` snappy animation and no re-layout. The band height is *measured*, never assumed. |
| C10 | Feature redundancy with macOS (Control Center, media keys) *(Pplware)*. | Restraint: each surface has one job. Defaults ship with three widgets, not nine. |

---

## 2. Principles

1. **Hardware first.** Closed means invisible. The shape starts and ends *exactly* at the camera housing, so every expansion appears to grow out of the hardware. No decoration is ever drawn on the closed notch.
2. **One continuous object.** There is only one shape, and it never fades or pops between states; it changes size. Content lives inside the shape and never outside it. Elements that persist across states move (matched geometry) rather than disappear and reappear (HIG).
3. **Glanceable, then actionable.** The compact state shows one datum per side, medium weight or heavier. Peek gives you a single row with at most three controls. The Nook holds everything else. Depth is opt-in through hover or click, never forced.
4. **Concentric precision.** Every radius derives from the one outside it: inner = outer − inset. The layout uses a 4 pt grid, continuous corners and symmetric slots, with the camera always at the optical centre.
5. **Colour is information.** Surfaces are black and type is white. One accent at a time, from the album art, the system accent or none. Semantic colours (green, orange, red) mean only what they mean on iOS.
6. **Calm by default.** No sounds, no ambient motion when idle, no permission prompts until a feature needs one, nothing in full screen. Every animation lasts under 0.6 s and can be interrupted.
7. **Everyone can use it.** Hover is never the only way in. Every glyph has a label and every state is reachable from the keyboard. System accessibility settings are honoured automatically, with no Cranny-specific switches.

**What this improves over NotchNook, concretely:** C1–C10 above. Specifically: a hardware-exact morph (C6), the hover-intent contract (C7), full-screen and multi-display policy (C2, C8), floating presentation on external displays (C3), a drag-and-resize grid editor (C4), pipeline drop targets (C5), just-in-time permissions (C6), an energy budget (C1), defined activity-concurrency rules (§6.5), measured AA contrast (§3.1) and a full accessibility spec (§9).

---

## 3. Tokens (Swift)

All tokens live in a **`CrannyDesign`** library target inside `CrannyKit`. It depends only on SwiftUI and AppKit. Feature modules import `CrannyDesign` and **never write literal colours, sizes, radii or animations.** The code below matches the compiled PoC.

### 3.1 Colour

```swift
/// The notch is always drawn on true black in Dark appearance, whatever the system
/// appearance (the hardware cut-out is black in both). Every text token passes WCAG AA
/// (4.5:1) on `surface` AND on `fill1` cards — verified by the PoC's contrast audit.
public struct CrannyPalette: Equatable, Sendable {
    // Surfaces
    public var surface: Color        // #000 — must vanish into the hardware notch
    public var fill1: Color          // card / widget well
    public var fill2: Color          // hover, secondary button, scrubber track
    public var fill3: Color          // pressed, selected segment, text-field well
    // Lines
    public var hairline: Color       // dividers, card edge (Increase Contrast or "flat with dividers")
    public var stroke: Color         // control outlines, dashed drop targets
    public var keyline: Color        // 1 px outer edge of peek/open shapes over dark content
    // Text & glyphs (white at fixed opacities → composite identically on every fill)
    public var label: Color          // 21:1
    public var secondaryLabel: Color // ≥ 8.4:1
    public var tertiaryLabel: Color  // ≥ 5.2:1 — still legal for small text
    public var quaternaryLabel: Color// disabled / placeholder only (exempt from AA)
    // Accent + semantic
    public var accent: Color
    public var onAccent: Color
    public var success: Color        // charging, Join call, done
    public var warning: Color        // timer (iOS convention), low-power
    public var danger: Color         // ≤ 10 % battery, recording, destructive
    public var info: Color           // links, AirDrop, Bluetooth
    public var caution: Color        // Low Power Mode battery, brightness (coloured HUD)

    public static func make(contrast: ColorSchemeContrast, accent: Color, onAccent: Color = .black) -> CrannyPalette {
        let hi = contrast == .increased
        func w(_ a: Double) -> Color { Color(.sRGB, white: 1, opacity: a) }
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r/255, green: g/255, blue: b/255) }
        return CrannyPalette(
            surface: Color(.sRGB, white: 0, opacity: 1),
            fill1: w(hi ? 0.12 : 0.07), fill2: w(hi ? 0.18 : 0.11), fill3: w(hi ? 0.26 : 0.16),
            hairline: w(hi ? 0.30 : 0.10), stroke: w(hi ? 0.50 : 0.22), keyline: w(hi ? 0.40 : 0.08),
            label: w(1.0), secondaryLabel: w(hi ? 0.84 : 0.68),
            tertiaryLabel: w(hi ? 0.70 : 0.50), quaternaryLabel: w(hi ? 0.46 : 0.28),
            accent: accent, onAccent: onAccent,
            // Apple dark-appearance system colours; accessible variants under Increase Contrast.
            success: hi ? rgb(48, 219, 91)  : rgb(48, 209, 88),
            warning: hi ? rgb(255, 179, 64) : rgb(255, 159, 10),
            danger:  hi ? rgb(255, 105, 97) : rgb(255, 69, 58),
            info:    hi ? rgb(64, 156, 255) : rgb(10, 132, 255),
            caution: hi ? rgb(255, 212, 38) : rgb(255, 214, 10))
    }
}
```

**Measured contrast** (PoC `contrastAudit()`, WCAG 2.x, white at opacity *a* composited over the fill):

| on → | surface #000 | fill1 | fill2 |
|---|---|---|---|
| label | 21.0 | 18.8 | 17.0 |
| secondaryLabel | 9.4 | 9.0 | 8.4 |
| tertiaryLabel | 5.3 | 5.3 | 5.2 |
| quaternaryLabel (disabled only) | 2.3 | 2.5 | 2.5 |
| *Increase Contrast:* secondary / tertiary | 14.5 / 10.0 | 12.0 / 8.7 | 10.1 / 7.5 |

Semantic colours on black: success 10.4, warning 10.2, danger 6.2, info 5.8, caution 14.9. **All of them meet AA for text.**

#### Accent strategy

* **One accent at a time.** Appearance ▸ Accent offers **System** (default), **Album art** or **Monochrome**.
* **System accent:** `NSColor.controlAccentColor` resolved under `.darkAqua` and lifted toward white until it reaches ≥ 4.5 : 1 on black (Graphite stays grey).
* **Album art:** a 24 × 24 thumbnail is bucketed into 12 hue sectors, ignoring greys and near-blacks. The winner is chosen by saturation × brightness, saturation is capped at 0.75 and brightness floored at 0.78, then the colour is lifted to ≥ 4.5 : 1. Greyscale art falls back to System. The PoC lifts pure `#0000FF` from 2.4 to 4.7 and navy `#1B2A6B` from 1.6 to 5.0. Track changes interpolate the accent over 0.6 s (`.smooth`).
* **Where the accent appears:** visualizer bars, the scrubber fill on hover, checkboxes and toggles in the Nook, the focus ring, selected chips, the keyline tint while music plays, and the ambient field.
* **Where it never appears:** body text, large fills, the default HUD, and anything with a semantic meaning (Join is always green, the timer always orange).

```swift
public enum AccentSource: String, CaseIterable, Codable, Sendable { case system, albumArt, monochrome }

public enum AccentMath {
    public static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat { /* WCAG relative luminance */ }
    /// Lift toward white until ≥ minContrast on black (4.5 text, 3.0 bars/rings).
    public static func liftedForBlack(_ c: NSColor, minContrast: CGFloat = 4.5) -> NSColor
    /// Dominant vibrant colour of artwork; nil for greyscale art → caller falls back to .system.
    public static func albumAccent(from image: CGImage) -> NSColor?
    @MainActor public static var systemAccentOnBlack: NSColor
}
```
(The full implementation, about 60 lines and tested, is in `src/Accent.swift`.)

### 3.2 Typography

SF Pro is used for words. **SF Pro Rounded with monospaced digits** is used for live numbers, so countdowns never jitter, and SF Mono for code. Sizes are anchored to macOS body text (13 pt). Nothing is ever smaller than 10 pt.

| Style | Size / weight / design | Digits | Use |
|---|---|---|---|
| `display` | 34 semibold rounded | mono | Timer face, big numbers |
| `numeral` | 26 semibold rounded | mono | Calendar date, battery % in peek |
| `title` | 15 semibold (−0.1 tracking) | — | Track title, event title |
| `headline` | 13 semibold | — | Widget headers, peek titles, tabs |
| `body` | 13 regular | — | Notes, to-dos |
| `callout` | 12 regular | — | Artist, secondary lines |
| `caption` | 11 medium | mono | Times, metadata, file names |
| `micro` | 10 semibold, +0.6 tracking, UPPERCASE | mono | Weekday "TUE", section labels |
| `compact` | 13 semibold rounded | mono | Values inside the band ("4:59", "82%") |
| `compactLabel` | 12 medium | mono | "in 4m" inside the band |
| `code` | 12 regular SF Mono | — | Notes code mode |

```swift
public enum CrannyTextStyle: CaseIterable, Sendable {
    case display, numeral, title, headline, body, callout, caption, micro, compact, compactLabel, code
    public struct Spec: Sendable { public let size: CGFloat; public let weight: Font.Weight
        public let design: Font.Design; public let monoDigits: Bool; public let tracking: CGFloat }
    public var spec: Spec { /* table above */ }
    /// Band styles scale with the notch (unit); Nook styles with the user's Text Size.
    public var scalesWithNotch: Bool { self == .compact || self == .compactLabel }
    public func font(scale: CGFloat) -> Font {
        let s = spec
        let f = Font.system(size: (s.size * scale).rounded(.toNearestOrEven), weight: s.weight, design: s.design)
        return s.monoDigits ? f.monospacedDigit() : f
    }
}

/// macOS has no system Dynamic Type for third-party UI → in-app Text Size (Appearance).
public enum CrannyTextSize: String, CaseIterable, Codable, Sendable {
    case small, standard, large, extraLarge     // 0.92 · 1.0 · 1.12 · 1.24
}

extension View {   // usage: Text(title).crannyFont(.title)
    public func crannyFont(_ style: CrannyTextStyle) -> some View { modifier(CrannyFontModifier(style: style)) }
}
```
Rules:
- Numbers that change use `.contentTransition(.numericText(countsDown:))` (macOS 14).
- Titles are single-line with tail truncation. In the Nook, a title that overflows marquees after a 1.5 s hover, which is the only place a marquee is allowed. Under Reduce Motion it never marquees; the full title appears in a `.help()` tooltip.
- Russian strings run 20–35 % longer, so compact slots never contain free text except `compactLabel`, which uses abbreviations: "in 4m" / "4 мин". Test with pseudo-localisation at 1.4×.

### 3.3 Spacing, radii, strokes, elevation

```swift
public enum Space {   // 4-pt grid with 2/6 half-steps for optical tweaks
    public static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 6, m: CGFloat = 8
    public static let l: CGFloat = 12, xl: CGFloat = 16, xxl: CGFloat = 20, xxxl: CGFloat = 24, huge: CGFloat = 32
}

public enum Radius {   // always .continuous; inner = outer − inset (HIG "concentric placement")
    public static let open: CGFloat = 32         // Nook bottom corners
    public static let card: CGFloat = 20         // 32 − 12 padding
    public static let inner: CGFloat = 8         // 20 − 12 card padding (artwork, wells, fields)
    public static let tile: CGFloat = 12         // 56-pt launcher hover tile
    public static let artPeek: CGFloat = 10      // 22 (peek corner) − 12
    public static let artCompact: CGFloat = 5    // 20-pt artwork in the band
    public static let chip: CGFloat = 6
    public static let focusRingOutset: CGFloat = 3
    public static func concentric(_ outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat { max(outer - inset, minimum) }
}
// Notch-anchored radii (closed 10u, hover 12u, compact 13u, ears 4–10u) live in NotchLayout and scale with `unit`.
// On macOS 26+, inner shapes may use `ConcentricRectangle()` inside a `.containerShape(.rect(cornerRadius:))` card.

public enum ButtonShapeStyle: String, CaseIterable, Codable, Sendable { case capsule, rounded } // Appearance ▸ Buttons

public enum StrokeWidth {
    public static func hairline(displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) } // exactly 1 px
    public static let regular: CGFloat = 1
    public static let dashedDrop: CGFloat = 1.5   // dash [5, 4]
    public static let focusRing: CGFloat = 2
    public static let scrubber: CGFloat = 4       // 8 while hovered/dragged
    public static let hudBar: CGFloat = 6
    public static let ring: CGFloat = 3           // compact progress rings
    public static let timerRing: CGFloat = 6      // Nook timer face
}

public enum Elevation {   // closed & compact: none — the shape is part of the bezel
    public static let peek = [CrannyShadow(color: .black.opacity(0.22), radius: 1.5, y: 1),
                              CrannyShadow(color: .black.opacity(0.28), radius: 14, y: 6)]
    public static let open = [CrannyShadow(color: .black.opacity(0.25), radius: 2, y: 1),
                              CrannyShadow(color: .black.opacity(0.35), radius: 28, y: 12)]
}
public enum Glow {
    public static let albumOpacity: Double = 0.30, albumRadius: CGFloat = 36   // halo behind artwork
    public static let ambientOpacity: Double = 0.22, ambientVividOpacity: Double = 0.40
}
```

### 3.4 Environment root

```swift
/// Applied once at the root of everything hosted in the notch panel.
public struct CrannyNotchEnvironment: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    public var accent: Color, textSize: CrannyTextSize, unit: CGFloat, buttonShape: ButtonShapeStyle
    public func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .dark)                       // the notch is always dark
            .environment(\.cranny, .make(contrast: contrast, accent: accent))
            .environment(\.crannyTextScale, textSize.scale)
            .environment(\.crannyNotchUnit, unit)
            .environment(\.crannyButtonShape, buttonShape)
            .tint(accent)
    }
}
// Feature code reads tokens with @Environment(\.cranny) private var c → c.secondaryLabel, c.fill1 …
```
The hosting `NSPanel` also sets `appearance = NSAppearance(named: .darkAqua)`, so any AppKit-backed control inside it (text views, menus) resolves to dark.

---

## 4. Geometry of the notch

### 4.1 Measuring the hardware

```swift
public struct NotchMetrics: Equatable, Sendable {
    public var hasNotch: Bool
    public var notchWidth: CGFloat     // camera housing width at the top edge; 0 without a notch
    public var bandHeight: CGFloat     // notch height (= menu-bar height on notched Macs) or menu-bar height
    public var screenWidth: CGFloat
    public var displayScale: CGFloat
    /// 1.0 on a 32 pt notch (14″/16″ MacBook Pro at default scaling). The physical notch is constant,
    /// so its height in points encodes the display scaling. Notch-anchored values × unit; Nook content is not.
    public var unit: CGFloat { min(max(bandHeight / 32, 0.8), 1.25) }

    @MainActor public static func measure(_ screen: NSScreen) -> NotchMetrics {
        let f = screen.frame
        let l = screen.auxiliaryTopLeftArea ?? .zero, r = screen.auxiliaryTopRightArea ?? .zero
        let top = screen.safeAreaInsets.top
        if top > 0, l.width > 0, r.width > 0 {
            return .init(hasNotch: true, notchWidth: f.width - l.width - r.width, bandHeight: top,
                         screenWidth: f.width, displayScale: screen.backingScaleFactor)
        }
        // No notch: the band is the menu bar — measured (24 pt classic; 30 pt measured on this macOS 27 external display).
        let menuBar = max(22, f.maxY - screen.visibleFrame.maxY)
        return .init(hasNotch: false, notchWidth: 0, bandHeight: menuBar, screenWidth: f.width, displayScale: screen.backingScaleFactor)
    }
}
```
Re-measure on `NSApplication.didChangeScreenParametersNotification`. Display scaling ("Larger Text" or "More Space") changes `bandHeight`, and through it `unit`: a 37 pt notch gives u = 1.156 and everything scales coherently (render 17 in `states-external.png`).

> Note: `visibleFrame` excludes the Dock as well. Measure the menu bar only from the **top** inset, as above (`f.maxY − visibleFrame.maxY`), never from the height difference.

### 4.2 One shape, four numbers

```swift
public struct NotchGeometry: Equatable, Sendable {
    public var bodyWidth: CGFloat      // excludes the two ears
    public var height: CGFloat
    public var earRadius: CGFloat      // concave flare where the top edge meets the menu bar
    public var bottomRadius: CGFloat   // convex continuous corners
    public var totalWidth: CGFloat { bodyWidth + 2 * earRadius }
}
```

**Reference sizes.** These are on a 14″ MacBook Pro at default scaling (notch N = 185 pt, band H = 32 pt, u = 1), and are the numbers printed by the PoC harness:

| State | bodyWidth | height | ear | bottom r | Rendered size (W×H) |
|---|---|---|---|---|---|
| **closed** | N + fineTune | H | 0 | 10u | 185 × 32 (inside the housing) |
| **hover "breath"** | N + 16u | H + 3u | 4u | 12u | 209 × 35 |
| **compact**: slots `.glyph`/`.short` | N + 2 · max(slots) · u | H | 6u | 13u | 301 × 32 |
| **compact**: `.medium` (timer, meeting) | ″ | H | 6u | 13u | 333 × 32 |
| **HUD**: `.wide` | ″ | H | 6u | 13u | 373 × 32 |
| **peek**, 1 row | clamp(N + 240u, 380, 460) | H + 52·rows + 8 | 8u | 22 | 441 × 92 (2 rows: 441 × 144) |
| **open**: default 10 cells | grid.width(cols) + 2·pad | H + 6 + grid.height + pad | 10u | 32 | 676 × 170 |
| **open**: 12 cells (max on 14″) | ″ | ″ | 10u | 32 | 804 × 170 |
| *37 pt notch, closed / compact* | 200 / 320 | 37 | 0 / 6.9 | 11.6 / 15.0 | u = 1.156 |
| *No notch, handle* | 76 | 5 | 2 | 2.5 | 80 × 5 + keyline |
| *No notch, compact with centre label* | label + 2·slot | H (30) | 5.6 | 12.2 | 229 × 30 |

Slot widths (× u) are a slot = outer margin 12 + content + gap 8 to the notch:

```swift
public enum SlotWidth: CGFloat, Sendable, Comparable, CaseIterable {
    case none = 0
    case glyph = 40     // 20-pt artwork / icon
    case short = 52     // 5-bar visualiser, "82%", battery ring
    case medium = 68    // "4:59", "in 4m", Join capsule
    case wide = 88      // HUD level bar (64 pt)
}
```

Rules, all from the HIG compact guidance:
- **Slots are symmetric.** The body is N + 2·max(leading, trailing), so the camera stays centred and the halves balance.
- **Content hugs the camera.** Leading content aligns *trailing* and trailing content aligns *leading*, with an 8u gap to the housing. Narrow content never floats at the outer edge.
- **Compact height = band height.** The compact activity lives in the menu-bar line and never pushes down; only peek and open grow downward.

```swift
public enum NotchLayout {
    public static let headerGap: CGFloat = 6

    public static func closed(_ m: NotchMetrics, fineTune: CGFloat = 0, handle: HandleStyle = .pill) -> NotchGeometry {
        guard m.hasNotch else { return handle.geometry(m) }
        return .init(bodyWidth: m.notchWidth + fineTune, height: m.bandHeight, earRadius: 0, bottomRadius: 10 * m.unit)
    }
    public static func hover(_ m: NotchMetrics, fineTune: CGFloat = 0, handle: HandleStyle = .pill) -> NotchGeometry {
        var g = closed(m, fineTune: fineTune, handle: handle); let u = m.unit
        if m.hasNotch { g.bodyWidth += 16 * u; g.height += 3 * u; g.earRadius = 4 * u; g.bottomRadius = 12 * u }
        else { g.bodyWidth += 24; g.height += 3; g.bottomRadius += 1.5 }
        return g
    }
    public static func compact(_ m: NotchMetrics, leading: SlotWidth, trailing: SlotWidth, centerLabel: CGFloat = 0) -> NotchGeometry {
        let u = m.unit, slot = max(leading, trailing).rawValue * u
        let middle = m.hasNotch ? m.notchWidth : max(centerLabel, 12)
        return .init(bodyWidth: middle + 2 * slot, height: m.bandHeight, earRadius: 6 * u, bottomRadius: 13 * u)
    }
    public static func peek(_ m: NotchMetrics, rows: Int = 1) -> NotchGeometry {
        let u = m.unit, w = min(max((m.hasNotch ? m.notchWidth : 180) + 240 * u, 380), 460)
        return .init(bodyWidth: w, height: m.bandHeight + CGFloat(rows) * 52 + 8, earRadius: 8 * u, bottomRadius: 22)
    }
    public static func open(_ m: NotchMetrics, columns: Int, grid: NookGrid = .init()) -> NotchGeometry {
        let cols = min(columns, maxColumns(m, grid: grid))
        return .init(bodyWidth: grid.width(cells: cols) + 2 * grid.padding,
                     height: m.bandHeight + headerGap + grid.height + grid.padding,
                     earRadius: 10 * m.unit, bottomRadius: Radius.open)
    }
    /// The Nook never exceeds 55 % of the screen or 880 pt, so menu-bar extras stay reachable.
    public static func maxColumns(_ m: NotchMetrics, grid: NookGrid = .init()) -> Int {
        let maxW = min(m.screenWidth * 0.55, 880)
        return max(4, Int((maxW - 2 * grid.padding + grid.gutter) / (grid.cell + grid.gutter)))
    }
    public static func hud(_ m: NotchMetrics) -> NotchGeometry { compact(m, leading: .wide, trailing: .wide) }
}
```
Max columns: 12 on a 1512-pt 14″, 13 on a 2560-pt external display, 10 on a 1280-pt screen.

### 4.3 The shape (SwiftUI, animatable)

The bottom corners use **Apple's own continuous curve**: we call `UnevenRoundedRectangle(style: .continuous)` rather than approximate a squircle. The ears are quarter-circle concave fillets that overlap the body by 0.5 pt, so the union has no anti-aliasing seam (verified pixel-exact in `tools/seam`). An `openTop` variant draws only the sides, ears and bottom; it is used for the 1 px keyline, so no line ever runs along the screen edge.

```swift
public struct NotchShape: Shape {
    public var bodyWidth: CGFloat, height: CGFloat, earRadius: CGFloat, bottomRadius: CGFloat
    public var openTop: Bool = false        // keyline variant

    public init(_ g: NotchGeometry, openTop: Bool = false) {
        bodyWidth = g.bodyWidth; height = g.height; earRadius = g.earRadius; bottomRadius = g.bottomRadius
        self.openTop = openTop
    }

    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(bodyWidth, height), .init(earRadius, bottomRadius)) }
        set { bodyWidth = newValue.first.first; height = newValue.first.second
              earRadius = newValue.second.first; bottomRadius = newValue.second.second }
    }

    public func path(in rect: CGRect) -> Path {
        let w = max(bodyWidth, 0), h = max(height, 0)
        guard w > 0.5, h > 0.5 else { return Path() }
        let e = min(max(earRadius, 0), h, w / 2)
        let r = min(max(bottomRadius, 0), h * 0.66, w / 2 * 0.66)      // room for the continuous ramp
        let L = rect.midX - w / 2, R = rect.midX + w / 2, T = rect.minY  // top-centred in a fixed canvas
        let body = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0),
            style: .continuous).path(in: CGRect(x: L, y: T, width: w, height: h))
        var p = openTop ? Self.removingTopEdge(of: body, topY: T, earDepth: e) : body
        guard e > 0.01 else { return p }
        let k: CGFloat = 0.5523                                          // cubic ≈ quarter circle
        if openTop {
            p.move(to: .init(x: L, y: T + e))
            p.addCurve(to: .init(x: L - e, y: T), control1: .init(x: L, y: T + e - k * e), control2: .init(x: L - e + k * e, y: T))
            p.move(to: .init(x: R, y: T + e))
            p.addCurve(to: .init(x: R + e, y: T), control1: .init(x: R, y: T + e - k * e), control2: .init(x: R + e - k * e, y: T))
        } else {
            let o: CGFloat = 0.5                                         // overlap → no seam
            p.move(to: .init(x: L - e, y: T)); p.addLine(to: .init(x: L + o, y: T))
            p.addLine(to: .init(x: L + o, y: T + e)); p.addLine(to: .init(x: L, y: T + e))
            p.addCurve(to: .init(x: L - e, y: T), control1: .init(x: L, y: T + e - k * e), control2: .init(x: L - e + k * e, y: T))
            p.closeSubpath()
            p.move(to: .init(x: R + e, y: T))
            p.addCurve(to: .init(x: R, y: T + e), control1: .init(x: R + e - k * e, y: T), control2: .init(x: R, y: T + e - k * e))
            p.addLine(to: .init(x: R - o, y: T + e)); p.addLine(to: .init(x: R - o, y: T))
            p.closeSubpath()
        }
        return p
    }

    /// Rebuilds `path` without segments on the screen edge (y == topY); sides start below the ears.
    /// Note: SwiftUI emits zero-radius corners as degenerate curves at the corner point — they must be
    /// moved too, or a stub runs up into the ear (bug found and fixed in the PoC render).
    private static func removingTopEdge(of path: Path, topY: CGFloat, earDepth e: CGFloat) -> Path {
        var out = Path()
        func drop(_ p: CGPoint) -> CGPoint { abs(p.y - topY) < 0.01 ? CGPoint(x: p.x, y: topY + e) : p }
        var current = CGPoint.zero, start = CGPoint.zero
        func onTop(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.y - topY) < 0.01 && abs(b.y - topY) < 0.01 }
        path.forEach { el in
            switch el {
            case .move(let to): out.move(to: drop(to)); current = to; start = to
            case .line(let to): if onTop(current, to) { out.move(to: drop(to)) } else { out.addLine(to: drop(to)) }; current = to
            case .quadCurve(let to, let c): out.addQuadCurve(to: drop(to), control: drop(c)); current = to
            case .curve(let to, let c1, let c2): out.addCurve(to: drop(to), control1: drop(c1), control2: drop(c2)); current = to
            case .closeSubpath: if !onTop(current, start) { out.addLine(to: drop(start)) }; current = start
            }
        }
        return out
    }
}
```

Every state renders through one container:

```swift
public struct NotchSurface<Content: View>: View {
    @Environment(\.cranny) private var c
    @Environment(\.colorSchemeContrast) private var contrast
    public var geometry: NotchGeometry; public var showsKeyline: Bool; public var keylineTint: Color?
    @ViewBuilder public var content: () -> Content
    public var body: some View {
        let shape = NotchShape(geometry)
        ZStack(alignment: .top) {
            shape.fill(c.surface)
            content().frame(width: geometry.bodyWidth, height: geometry.height, alignment: .top).clipShape(shape)
            if showsKeyline || contrast == .increased {   // HIG: key line on dark backgrounds, tinted with content
                NotchShape(geometry, openTop: true)
                    .stroke((keylineTint ?? .white).opacity(contrast == .increased ? 0.45 : 0.14), lineWidth: 1)
            }
        }
    }
}
```
* **Keyline:** shown in peek and open (stroke 1 pt, white 14 %), tinted with the album accent while music plays, and always on (45 %) under Increase Contrast. It is never shown in closed or compact, where the shape must read as hardware.
* **Shadow:** none in closed and compact. `Elevation.peek` and `Elevation.open` are applied to the `NotchSurface`. The panel canvas includes a 40 pt shadow margin.

### 4.4 Ears: the concave curves at the menu bar

The ear is what makes the shape look *attached to the screen edge* rather than pasted on. It grows with the state: 0 (closed, so nothing escapes the housing) → 4u (hover) → 6u (compact) → 8u (peek) → 10u (open). Because ears are part of `animatableData`, they swell during the morph like the meniscus of a liquid, which is the "Dynamic Island" feel. Ears are skipped (radius 0) for the floating island.

### 4.5 Why closed = exact hardware, and calibration

* `closed.bodyWidth = notchWidth + fineTune` with ear 0 and r 10u. Here 10u is slightly *larger* than the housing's own corner, so the drawn shape stays inside the cut-out at the corners. Closed is therefore invisible, and the first frame of any morph grows *out of* the hardware. This avoids the boring.notch #316 failure, where the close animation does not fit the real notch.
* **Settings ▸ Appearance ▸ Calibrate notch…** opens a sheet that freezes the real notch in "hover" state and draws a 1 px accent outline of `closed` over the hardware. A slider (−8…+8 pt, 0.5 pt steps, with an `.alignment` haptic detent at 0) adjusts `fineTune` until the outline vanishes. The value is stored per display model (`CGDisplayModelNumber`).

### 4.6 Displays without a notch

`Appearance ▸ On displays without a notch:`

| Style | Closed | Compact / peek / open | When to choose |
|---|---|---|---|
| **Pill** (default) | 76 × 5 black tab hanging from the top edge. Ear 2, r 2.5, 1 px white 18 % keyline so it is visible on a dark menu bar. Hover zone 160 × 12. | Same attached shape. Compact uses the camera-less centre for a **label** (e.g. the track title, `compactLabel`, max 160 pt). | Most people |
| **Transparent** | Invisible. Same hover zone. | Same as Pill. | Minimalists ("hide when idle") |
| **Floating island** | Invisible (hover zone 200 × 10 at the top edge). | A detached island 6 pt below the menu bar: `UnevenRoundedRectangle` with **all four corners** rounded (compact: capsule, r = h/2; peek: 22; open: 32) and no ears. On macOS 26+: `.glassEffect(.regular.tint(.black.opacity(0.55)), in: shape)` inside a `GlassEffectContainer`, so compact → peek → open morph as glass (`glassEffectID`). macOS 14/15: `.ultraThinMaterial` + black 55 %. Reduce Transparency: opaque black. | External monitors (fixes C3) |

### 4.7 Hit zones (Fitts)

* **Entry zone** = shape bounds inflated by 4 pt horizontally and extended to the very top pixel. The top edge of the screen has effectively infinite depth, so throwing the pointer up is accurate.
* **Exit zone** (while open) = shape inflated by 14 pt on each side and at the bottom (hysteresis). Leaving it starts a 0.30 s grace period; re-entering cancels.
* **Drag zone** (dragging a file) = shape inflated to 40 pt below the band and ±80 pt wide. Entering it opens the Tray immediately, with no dwell.
* Outside the shape the panel is click-through (`ignoresMouseEvents` toggled from the hit test), so the fixed canvas (≈ 980 × 310 pt: 880 pt max body + ears + 40 pt shadow margins; Roomy Notes-focus height 264 + margin) never blocks the menu bar.

### 4.8 Window and display policy (constraints the design relies on)

* There is one borderless `NSPanel` (`.nonactivatingPanel`, level `.statusBar`, `.canJoinAllSpaces/.stationary/.fullScreenAuxiliary/.ignoresCycle`, `appearance = .darkAqua`) **per display**. It has a **fixed size**: the largest possible geometry plus the 40 pt shadow margin, ≈ 980 × 310 pt. Only the shape animates and the window never resizes, which removes a whole class of jiggle and flicker bugs (C6, C7).
* **Full screen:** when the display's active Space is full screen, the shape stays closed. Only the HUD may appear, if enabled; activities queue silently. Quick Look full screen counts too.
* **Displays:** Settings ▸ General ▸ *Show on* offers Built-in display (default when present), Display with pointer, All displays, or a specific display. **Peeks and alerts appear only on the display with the pointer** (C8).
* **Screen sharing:** *Hide from screen sharing and recordings* (default off) sets `sharingType = .none`. **Demo mode** (menu bar extra) never hides, ignores full screen and the inactivity timeout, and freezes the clock-dependent content: ideal for recordings.

---

## 5. Motion

### 5.1 Springs per transition

Apple does not publish Dynamic Island constants. These values were tuned by eye against iPhone screen recordings, and the PoC typechecks them. `spring(duration:bounce:)` is SwiftUI's perceptual-duration spring (macOS 14). Bounce 0 means critically damped.

| Kind | Animation | Why |
|---|---|---|
| **open** (closed/compact → Nook) | `.spring(duration: 0.44, bounce: 0.20)` | A confident, slightly elastic expansion, like the island's long-press expand. |
| **close** | `.spring(duration: 0.36, bounce: 0.06)` | Crisp retraction into the camera. It nearly settles without overshoot, so it never "jiggles" (C6). |
| **activityIn** (closed → compact) | `.spring(duration: 0.50, bounce: 0.30)` | The Dynamic Island "drop": the most playful moment, used rarely. |
| **activityOut** | `.spring(duration: 0.34, bounce: 0)` | |
| **peekIn / peekOut** | `.spring(0.40, 0.24)` / `.spring(0.32, 0.04)` | |
| **hoverIn / hoverOut** (breath) | `.spring(0.30, 0.40)` / `.spring(0.30, 0)` | Tiny (3 pt) and springy, so it says "alive" without moving much. |
| **tab** (Nook ⇄ Tray selection capsule) | `.snappy(duration: 0.28)` | Matches macOS segmented controls. |
| **contentIn / contentOut** | `.smooth(0.26).delay(0.06)` / `.easeOut(0.12)` | Content trails the shape in and leads it out. |
| **contentSwap** (track change, value change) | `.smooth(0.30)` + `.blurReplace` / `.numericText()` | |
| **hudIn / hudLevel / hudOut** | `.spring(0.32, 0.26)` / `.snappy(0.16)` / `.spring(0.34, 0)` | The level must track key repeat (≈ 30 Hz) with no lag. |
| **focusWidget** (widget → full width) | `.spring(0.42, 0.16)` | |
| **press / hover** (controls) | `.spring(0.18, 0.30)` scale 0.94 / `.easeOut(0.12)` | |
| **snapBack** (after rubber band) | `.spring(0.40, 0.18)` or a velocity-matched `interpolatingSpring` | |

```swift
public enum CrannyMotion {
    public enum Kind: CaseIterable, Sendable {
        case open, close, activityIn, activityOut, peekIn, peekOut, hoverIn, hoverOut, tab,
             contentIn, contentOut, contentSwap, hudIn, hudLevel, hudOut, focusWidget, press, hover, snapBack
    }
    /// Settings ▸ Appearance ▸ Animation speed — multiplies durations, keeps bounce.
    public enum Speed: String, CaseIterable, Codable, Sendable { case relaxed, standard, quick } // 1.2 · 1.0 · 0.75

    public static func animation(_ kind: Kind, reduceMotion: Bool = false, speed: Speed = .standard) -> Animation
    /// Reduce Motion: open/close/focus become 0.20 s easeInOut dissolves at the final size.
    public static func morphsShape(_ kind: Kind, reduceMotion: Bool) -> Bool
    /// Widgets radiate outward from the camera: 18 ms per column of distance from the centre, max 4 steps.
    public static func stagger(column: Int, of columns: Int, reduceMotion: Bool) -> Double
    /// iOS-style rubber band: (1 − 1/(x·c/d + 1))·d, c = 0.55.
    public static func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient c: CGFloat = 0.55) -> CGFloat
    /// Hand the gesture's velocity to the spring so a release never "restarts".
    public static func release(velocity: CGFloat, remaining distance: CGFloat) -> Animation {
        let v = abs(distance) < 0.5 ? 0 : Double(velocity / distance)
        return .interpolatingSpring(duration: 0.40, bounce: 0.14, initialVelocity: v)
    }
}
```
(Full bodies are in `src/Motion.swift`.) **Everything is interruptible.** The state machine always sets the newest target, and SwiftUI springs retarget while preserving velocity. Animations are never queued. Every motion lasts under 0.6 s, well inside the HIG's 2 s limit for live activity animations.

### 5.2 Choreography

**Open** (from closed or compact), with t in seconds:

| t | Shape | Content |
|---|---|---|
| 0 | `open` spring starts: width, height, ears and radius together | Compact slot content `contentOut` (0.12) |
| 0.06 | | Header (tabs, actions) `contentIn` |
| 0.06 + stagger | | Widgets `contentIn`, **radiating from the camera outward**: the centre column first, then 18 ms per column of distance (max 72 ms). Transition: blur 6 → 0, scale 0.96 → 1 anchored `.top`, opacity 0 → 1 |
| 0.15 | | Ambient field fades in over 0.5 s (if enabled) |
| ≈ 0.45 | settled | settled |

**Close:** content `contentOut` at t = 0 (no stagger). The shape starts `close` at t = 0.04, so the content is mostly gone before the shape retracts and the camera "swallows" an empty shape. The compact content returns with `contentIn` at ≈ 0.22.

**Activity in:** `activityIn` on the shape. Slot content enters with `crannySlot`, growing *out of the camera edge*: scale 0.6 → 1 anchored at the inner edge, blur 4 → 0, delay 0.08.

**Peek in:** `peekIn` on the shape. Compact elements that also exist in the peek row (artwork, visualizer) **move** with `matchedGeometryEffect` rather than cross-fade (HIG: preserve layout). The new row content uses `contentIn`.

**Tab switch:** the selection capsule uses `matchedGeometryEffect` with `.snappy(0.28)`. The outgoing page fades and slides 12 pt opposite to the direction of travel (0.12 s); the incoming page slides in from 12 pt (`contentIn`). If the pages differ in size, the shape follows with `focusWidget`.

**HUD:** `hudIn` (from closed or compact). Level changes use `hudLevel`. When the user presses past 0 % or 100 %, the bar **rubber-bands by 2 pt** toward the limit and springs back (`snapBack`), giving precise "you're at max" feedback. After 1.5 s idle, `hudOut` restores the previous presentation.

### 5.3 Transitions (code)

```swift
public struct BlurScale: ViewModifier {
    var blur: CGFloat, scale: CGFloat, opacity: Double, anchor: UnitPoint
    public func body(content: Content) -> some View { content.blur(radius: blur).scaleEffect(scale, anchor: anchor).opacity(opacity) }
}
extension AnyTransition {
    public static func crannyContent(reduceMotion: Bool, anchor: UnitPoint = .top) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: BlurScale(blur: 6, scale: 0.96, opacity: 0, anchor: anchor),
                                 identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)),
            removal:   .modifier(active: BlurScale(blur: 3, scale: 0.98, opacity: 0, anchor: anchor),
                                 identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)))
    }
    /// Compact slots grow out of the camera edge.
    public static func crannySlot(edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .modifier(active: BlurScale(blur: 4, scale: 0.6, opacity: 0, anchor: anchor),
                         identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor))
    }
}
```
Use `.contentTransition(.numericText(countsDown: true))` for countdowns, `.contentTransition(.symbolEffect(.replace))` for play/pause glyphs, `.symbolEffect(.bounce, value:)` once when a device connects, and `.transition(.blurReplace)` for artwork swaps. All of these are macOS 14 and typechecked.

### 5.4 Optional refinement: staged morph (v1.1)

The Dynamic Island appears to widen slightly before it drops. You cannot get two springs for one `AnimatablePair`, but nesting two `Animatable` views gives each axis its own transaction (typechecked in `tools/apicheck/Staged.swift`):

```swift
struct StagedNotch: View, Animatable {               // owns width + ears + radius
    var width: CGFloat, height: CGFloat, ear: CGFloat, radius: CGFloat
    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(width, .init(ear, radius)) }
        set { width = newValue.first; ear = newValue.second.first; radius = newValue.second.second }
    }
    var body: some View { HeightStage(width: width, height: height, ear: ear, radius: radius) }
}
private struct HeightStage: View, Animatable {      // owns height
    var width: CGFloat, height: CGFloat, ear: CGFloat, radius: CGFloat
    nonisolated var animatableData: CGFloat { get { height } set { height = newValue } }
    var body: some View { NotchShape(.init(bodyWidth: width, height: height, earRadius: ear, bottomRadius: radius)).fill(.black) }
}
// open:  withAnimation(.spring(duration: 0.40, bounce: 0.22)) { w = target.w }
//        withAnimation(.spring(duration: 0.46, bounce: 0.16).delay(0.03)) { h = target.h }
// close: height first (0.30, 0.04), width 30 ms later (0.36, 0.06) → "retracts up, then in".
```
(`nonisolated` is required under Swift 6, because `View` is main-actor isolated.) Ship v1 with the single spring, then A/B the staged version.

### 5.5 Gestures and rubber-banding

| Gesture (two-finger trackpad scroll events over the shape) | Live feedback | Commit | Result |
|---|---|---|---|
| Horizontal swipe on compact, peek or media widget | Content follows the finger, `rubberBand(dx, limit: 24)` | \|dx\| ≥ 40 pt or \|v\| ≥ 400 pt/s | Next/previous track (*Invert* setting). The artwork slides out and the new one slides in. `.generic` haptic |
| Swipe **down** on closed or compact | Shape height follows `rubberBand(dy, limit: 12)` | 24 pt or 300 pt/s | Open the Nook |
| Swipe **up** on open | Shape follows up to −12 | ″ | Close |
| Swipe **up** on compact or peek | ″ | ″ | **Dismiss** the activity until its next meaningful change (auto-unhide) |
| Release below threshold | — | — | `CrannyMotion.release(velocity:remaining:)` springs back with the gesture's velocity |

Accumulate `NSEvent.scrollingDeltaX/Y` only for `hasPreciseScrollingDeltas` (trackpad, not mouse wheels). Use `phase` and `momentumPhase` to detect begin and end, and ignore momentum after a commit.

### 5.6 Reduce Motion

| Normal | With Reduce Motion |
|---|---|
| open / close / focus morph with bounce | **Dissolve at the final size** (0.20 s easeInOut). The shape does not travel across the screen. |
| compact / peek / HUD morphs (small) | Kept, but `bounce: 0` and 0.18 s easeInOut |
| blur and scale content transitions | Opacity only |
| Widget stagger | None |
| Visualizer bars | Static dots (paused shape) |
| Ambient field, marquee, typing effect, timer-finished pulse | Off |
| Rubber band | Kept (it is direct manipulation), with no overshoot on release |

The value is read from `@Environment(\.accessibilityReduceMotion)` and, in AppKit code, `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` plus `accessibilityDisplayOptionsDidChangeNotification`.

### 5.7 Staggering

Only the Nook staggers, outward from the camera. Peek rows stagger at 30 ms top to bottom, with a maximum of 3 rows. Nothing else staggers. Lists such as to-dos and events never stagger on open, to avoid a "slot machine" effect.

### 5.8 Hover intent (the anti-flicker contract)

```
closed ──enter entryZone──▶ hover(breath)
hover ──dwell 120 ms ∧ pointer speed < 1400 pt/s──▶ open        (Hover-to-open mode)
hover ──click──▶ open                                          (Click mode: breath only)
hover ──leave──▶ closed
compact ──dwell 180 ms──▶ peek ──click──▶ open(focused widget)
open ──leave exitZone (shape + 14 pt)──▶ grace 300 ms ──▶ closed/compact
grace ──re-enter──▶ open
open ──holdsOpen (pinned · dragging · text field focused · menu/popover open · Demo)──▶ never auto-closes
open ──Inactivity timeout (default off; 5–60 s)──▶ close
```

```swift
public enum HoverIntent {
    public static let openDwell: TimeInterval = 0.12        // Settings ▸ General ▸ Hover delay (0–0.5 s)
    public static let peekDwell: TimeInterval = 0.18
    public static let closeGrace: TimeInterval = 0.30
    public static let exitInflation: CGFloat = 14
    public static let entryInflation: CGFloat = 4
    public static let passThroughSpeed: CGFloat = 1400      // pt/s — travelling to a menu, not aiming
    public static let peekAutoDismiss: TimeInterval = 2.6
    public static let hudAutoDismiss: TimeInterval = 1.5
}
```
A `HoverIntentTracker` sketch is typechecked in `tools/apicheck/Intent.swift`. It uses a global `NSEvent` mouse monitor, computes speed from event timestamps, and drives dwell and grace with cancellable `Task.sleep`. **The panel is non-activating.** It becomes key only when the user clicks into a text field (Notes, To-dos), and resigns key on close, returning focus to the previous app (C7).

### 5.9 Energy budget

| State | Allowed work |
|---|---|
| closed, nothing playing | **None**: no timers, no `TimelineView`, no Canvas. Event-driven only. |
| compact Now Playing | Visualizer Canvas ≤ 30 fps while visible. Paused when the display sleeps, under full screen, or when Reduce Motion is on. |
| open | 120/60 fps only during morphs. Ambient `TimelineView(.animation(minimumInterval: 1/20, paused:))` runs only while open and is paused in Low Power Mode. |
| Target | Activity Monitor "Energy Impact" < 1.0 average while idle. This is a release gate. |

---

## 6. Layouts

### 6.1 The open Nook

```
 ◜ear                                    menu-bar band (H = 32u)                                    ear◝
 ┌──────────────────────────────────┬──────────── camera housing ────────────┬──────────────────────────────┐
 │ 12 [▣ Nook | ▤ Tray] ·············│              (never draw here)          │·········· [📌] [⚙︎] 12       │  ← header IN the band
 │                                   └────────────────────────────────────────┘                               │  6 pt headerGap
 │ 12 ┌──── Media 5 cells ─────────┐ 8 ┌─ Calendar 3 ─┐ 8 ┌ Apps 2 ┐                                    12  │
 │    │ 120 pt = 2 rows × 56 + 8   │   │               │   │ ▢  ▢  │                                        │
 │    └────────────────────────────┘   └───────────────┘   └────────┘                                        │
 │                                                                                          12 (padding)    │
 ╰──────────────────────────────────────────────── r 32 continuous ────────────────────────────────────────╯
```

* **Header (in the band).** The tab switcher sits to the left of the camera and the actions to the right (*Pin*, *Settings*). Both hug the outer padding, so the camera area stays empty. This follows the HIG instruction to "wrap content tightly around the camera". On notch-less displays the same layout applies and the centre stays empty for consistency.
  * Tabs: `CrannyTabs`, a capsule track `fill1` with 2 pt inset. The selected segment is `fill3` and the label `headline` (13 semibold). Segment height 22 and icon + title. With Text Size XL, titles collapse to icons and gain tooltips.
  * Actions: `NotchIconButtonStyle`, 28 × 24 hit area, 13 pt semibold glyph, `secondaryLabel` (pin when on: `label` + `fill2` well). Button shape follows *Appearance ▸ Buttons: Capsule / Rounded*.
* **Grid:** always **2 rows**. *Notes focus* (§6.4.5) temporarily uses 3.

| Density | cell | gutter | padding | grid height | card radius | Nook height (H = 32) |
|---|---|---|---|---|---|---|
| Compact | 52 | 6 | 10 | 110 | 22 | 158 |
| **Standard** | **56** | **8** | **12** | **120** | **20** | **170** |
| Roomy | 64 | 10 | 14 | 138 | 18 | 190 |

```swift
public struct NookGrid: Equatable, Sendable {
    public var density: NookDensity = .standard, rows: Int = 2, dividers: Bool = false
    public var cell: CGFloat { density.cell }
    public var gutter: CGFloat { dividers ? density.gutter * 2 + 1 : density.gutter } // flat style: hairline in the gutter
    public var padding: CGFloat { density.padding }
    public func width(cells: Int) -> CGFloat { CGFloat(cells) * cell + CGFloat(max(cells - 1, 0)) * gutter }
    public var height: CGFloat { CGFloat(rows) * cell + CGFloat(rows - 1) * gutter }
    public var cardRadius: CGFloat { Radius.concentric(Radius.open, inset: padding) }
}
```
* **Widget styles** (*Appearance ▸ Widgets*):
  * **Cards** (default): `fill1` cards with radius 20.
  * **Flat with dividers**: no fills, 1 px `hairline` dividers centred in a double gutter. This covers the "dividers between widgets" option.
* **Default Nook:** Media 5 + Calendar 3 + Apps 2 = **10 cells → 656 pt body (676 with ears)**. Max columns = `NotchLayout.maxColumns` (12 on a 14″). If the user's layout exceeds the maximum, trailing widgets move to a second *page*: a "›" chevron appears at the trailing edge and a two-finger swipe pages horizontally.
* **Translucent background** (Appearance option, default off): the band stays pure black to blend with the hardware. Below the band, the Nook fill becomes `black 72 %` over `.ultraThinMaterial` (glass on 26+), joined by a 24 pt vertical gradient mask. Reduce Transparency forces opaque.

### 6.2 Widget size table (cells wide × 2 rows)

| Widget | min | default | max | Notes |
|---|---|---|---|---|
| Media | 4 | **5** | 6 | <5 cells: 72 pt artwork, transport moves under the title |
| Calendar | 2 | **3** | 5 | 2 cells: "next event" only |
| Apps & Shortcuts (Launcher) | 1 column | **2** | 6 | each column = 2 tiles |
| Mirror | 2 | 2 | 3 | |
| Notes | 3 | 4 | 8 | focus mode → full width × 3 rows |
| To-dos | 2 | 3 | 6 | |
| Timer | 2 | 2 | 3 | |
| AirDrop | 2 | 2 | 2 | also auto-shown in the Tray |
| Tray (mini shelf) | 3 | 4 | 8 | the full Tray is a tab |

### 6.3 Shared card anatomy

`CrannyCard(cells:grid:)` has width `grid.width(cells)` and height `grid.height` (120). Inner padding is 12 and the radius 20 is set as the `containerShape`, so inner `ContainerRelativeShape` / `ConcentricRectangle` (macOS 26) stay concentric. **Widgets have no title bars.** Content identifies itself (artwork, date, icons), as in Apple's widgets. A hover over any card shows a 20 pt *overflow* button (`ellipsis`, `tertiaryLabel`) in the top-trailing corner. It holds widget-specific settings, *Resize*, *Remove* and *Edit Nook…*.

### 6.4 Widgets

**6.4.1 Media** (5 cells = 312 × 120; content 288 × 96)
```
┌────────────────────────────────────────────┐
│ ┌────────┐  Midnight Window          ⌁AirPl│  title 15 semibold · artist 12 secondary · AirPlay route 12 pt tertiary
│ │  art   │  The Example Band                │
│ │ 96×96  │  ━━━━━━━━━━━━──────────────────  │  scrubber 4 pt (8 on hover, accent fill on hover), times caption mono tertiary
│ │  r 8   │  1:24                     −2:11  │
│ └────────┘        ⏮     ⏯      ⏭          │  TransportButtonStyle 30 / 36 / 30 pt hit, glyph 15 / 20 / 15 semibold
└────────────────────────────────────────────┘
```
* Album glow: the artwork casts its accent at 30 %, blur 18, scale 1.08, behind the art (Appearance ▸ *Album glow*, default on).
* Click the artwork to open the source app. Scroll horizontally (trackpad) or drag the scrubber to seek. Space plays or pauses while the card has keyboard focus.
* No session: a placeholder `music.note` 28 pt in a `fill2` well, "Not Playing" `callout` secondary, and a *Open Music* text button.

**6.4.2 Calendar** (3 cells = 184 × 120)
```
TUE  14 October                       micro red (danger) + headline
12  13  (14)  15  16                  day strip: −N…+N days (Settings: days behind/ahead 0–3); today = white capsule, black text
▍Design review            10:30       3 pt calendar-colour capsule · caption medium · time caption mono secondary
▍Lunch with Ana           13:00       past events today: tertiary (option "Show past events")
```
* Events scroll vertically with a 12 pt fade mask at the bottom. Click an event to open Calendar.app. When an event has a meeting URL (Zoom, Meet, Teams, Webex), a **Join** capsule appears (`success`, `video.fill`, 20 pt high).
* Empty: "No more events today" (tertiary) and the first event tomorrow.
* No permission: an inline "Show your events" button triggers the Calendar permission. This is the only place it is ever asked (just-in-time).

**6.4.3 Apps & Shortcuts (Launcher)** (columns of 2 tiles)
* Tile 56 × 56: app icon 36 pt; on hover, a `fill2` r 12 well; app name in `.help()`. Running apps get a 4 pt dot under the icon (`secondaryLabel`), Dock-style.
* A **Shortcut** tile is a 36 pt continuous squircle. Its fill is a hue derived from a stable hash of the shortcut name, holding the user-chosen SF Symbol or the first letter (`headline`, white). It runs via `shortcuts run`, and the tile shows a progress ring until the run ends.
* Edit mode: tiles wiggle (Reduce Motion: no wiggle, a "–" badge instead), a trailing **+** tile adds items, and drag to reorder.

**6.4.4 Mirror** (2 cells, 120 × 120)
* Off: `camera.fill` 22 pt, `secondaryLabel` "Mirror". One click starts the camera.
* On: the preview fills the card, clipped to r 20 and mirrored by default (option). A top-trailing 24 pt round button on `black 50 %` opens the camera menu.
* The camera stops when the Nook closes or the widget scrolls off. The system's green camera indicator is the privacy cue, and we add nothing that competes with it.

**6.4.5 Notes** (4 cells; focus mode = full Nook width × 3 rows = 184 pt grid)
* The header row (20 pt) contains:
  * the note title (`headline`; double-click to rename);
  * the notes menu (`chevron.down`), which lists notes and offers New, Rename and Delete;
  * the code-mode toggle `chevron.left.forwardslash.chevron.right`;
  * the focus toggle `arrow.up.left.and.arrow.down.right`.
* Body: `NSTextView` (TextKit 2) at 13 pt `body`, line height 1.3, insertion point tinted `accent`.
* **Code mode:** 12 pt SF Mono with Markdown highlighting. Headings use `label` semibold; emphasis is rendered; inline code sits on a `fill2` background with r 4; links use `info`. Fenced code blocks use Cranny's own syntax palette, chosen to keep ≥ 4.5 : 1 on black: keyword `#FF7AB8`, type `#62D6FF`, string `#FF9466`, number `#E8C66C`, function `#A6E37A`, comment `tertiaryLabel` italic.
* **Typing effect** (Appearance ▸ *Typing effect*, default on): newly inserted characters appear in `accent` and fade to `label` over 300 ms, through NSTextView *temporary attributes* stepped by a single display-link-driven animator. It is off under Reduce Motion. For **read-only** animated text (peek titles, onboarding), use a SwiftUI `TextRenderer` (macOS 15) that reveals glyphs with opacity and a 3 pt rise. This is typechecked as `TypingRenderer` in `tools/apicheck/Check.swift`, with a plain fade on macOS 14.
* **Focus mode:** `focusWidget` spring. The other widgets `contentOut`, the shape grows to all columns × 3 rows, and Esc or the toggle returns. While a note is focused the Nook **holds open**.

**6.4.6 To-dos** (3 cells)
* Rows are 22 pt: a 16 pt circle (`stroke secondary`; checked = `accent` fill + black checkmark) and `body` text. The header shows "3 left" in `caption`.
* Completing a row strikes it through and moves it to `tertiaryLabel`. After 1.2 s it collapses with `contentOut`; under Reduce Motion it collapses immediately with no strike animation.
* The last row is a "New To-do" placeholder (`plus`, tertiary). Return adds the next row; ⌫ on an empty row deletes it.

**6.4.7 Timer** (2 cells, 120 × 120)
* Running: an 88 pt ring with a 6 pt stroke in `warning` (orange, the iOS Timer convention). Inside sits the remaining time (22 pt semibold rounded, mono digits) and the label in `caption`. Hovering shows pause and stop buttons.
* Idle: four preset chips (1 · 5 · 10 · 25 min). Scrolling over the face adjusts in 1-minute steps, with an `.alignment` haptic per detent.
* Finished: the ring pulses twice (`phaseAnimator`, off under Reduce Motion), the notch auto-peeks "Timer done" for 2.6 s, and the chosen system sound plays (§8.3).

**6.4.8 AirDrop target** (2 cells)
* A 1.5 pt dashed `stroke` border `[5, 4]` with r 8 (concentric), the glyph `dot.radiowaves.up.forward` at 22 pt in `info`, and "AirDrop" in `caption`.
* Drag-over: a solid `info` border with an `info` 15 % fill, scale 1.03 (`press` spring), and an `.alignment` haptic. On drop, show the AirDrop sharing picker (`NSSharingService(named: .sendViaAirDrop)`).

**6.4.9 Files Tray** (tab; full Nook width)
```
┌─ Tray ───────────────────────────────────────────────────────────┐ ┌ AirDrop ┐
│ [▢]  [▣✓]  [▢]   [▢]   …  (horizontal shelf, 72×88 tiles)         │ │  ⦿))    │
│ Report.pdf  IMG_2041…  design-v3…  notes.md                       │ │ AirDrop │
│ (Compress) (Convert ▾) (Zip) (Copy Path) (AirDrop) (✦ My pipeline)│ └─────────┘
└──────────────────────────────────────────────────────────────────┘
```
* Tile 72 × 88: a QuickLook thumbnail (48 pt, r 6) and the name (`caption`, middle-truncated). Selection shows a `fill2` r 8 well and a 14 pt accent check badge. Hovering shows a remove ✕ (16 pt circle, top-trailing).
* Interaction: ⌘/⇧ multi-select, Space for Quick Look, drag out to copy (⌥ to move). The context menu holds Open, Reveal in Finder, Quick Look, Copy Path, Share…, Remove.
* **Pipeline chips:** a 22 pt capsule row (`fill2`, `caption` `label`) that shows only the actions valid for the selection:
  * images: Compress, Convert ▾ (PNG/JPEG/HEIC), Resize ▾;
  * any file: Zip; archives: Unzip;
  * Copy Path, AirDrop;
  * user pipelines (✦ `wand.and.stars`), which are chains such as "Resize 50 % → JPEG 80 % → Copy".
* Running: the tile dims to 50 % behind a `ProgressRing`. The result tile slides in with an accent "new" dot; errors show a `danger` badge with a tooltip.
* **While dragging into the notch** (improves C5), the shape opens straight to the Tray with large drop zones: **Keep in Tray** (wide), **AirDrop** (2 cells), and **one drop zone per pinned pipeline** (2 cells each), e.g. "Drop to compress". Entering a zone gives an `.alignment` haptic and highlights it in `accent` 15 %.

### 6.5 Live activities: compact anatomy

```
 ◜ │ 12u │ leading content │ 8u │ ████ camera housing (N) ████ │ 8u │ trailing content │ 12u │ ◝
     outer   aligned → camera                                      aligned ← camera
```
```swift
public struct CompactActivityLayout<Leading: View, Center: View, Trailing: View>: View {
    @Environment(\.crannyNotchUnit) private var u
    var metrics: NotchMetrics; var geometry: NotchGeometry; var slot: SlotWidth
    let leading: Leading, center: Center, trailing: Trailing
    public var body: some View {
        let s = slot.rawValue * u
        let middle = max(geometry.bodyWidth - 2 * s, 0)            // camera, or the centre label without a notch
        HStack(spacing: 0) {
            leading.frame(width: s - 20 * u, alignment: .trailing).padding(.leading, 12 * u).padding(.trailing, 8 * u)
            Color.clear.frame(width: middle).overlay { center }   // never EmptyView().frame(): it collapses the gap
            trailing.frame(width: s - 20 * u, alignment: .leading).padding(.leading, 8 * u).padding(.trailing, 12 * u)
        }
        .frame(height: metrics.bandHeight)
    }
}
```

| Activity | Slot | Leading | Trailing | Peek row (52 pt) | Auto-peek |
|---|---|---|---|---|---|
| **Now Playing** | `.short` | Artwork 20u, r 5u | 5-bar visualizer 23 × 16 pt (3 pt bars, 2 pt gaps) in `accent`; paused → 3 pt dots | Artwork 40 r 10 · title `headline` / artist `callout` · ⏮ ⏯ ⏭ | On song change (option, 2.6 s) |
| **Meeting soon** | `.medium` | Calendar-colour dot 7 pt + "in 4m" `compactLabel` | **Join** capsule 34 × 20 `success` with black `video.fill` (if link), else start time | Title · "10:30–11:00 · Room 4" · Join | N min before (Settings, default 5) |
| **Meeting in progress** | `.medium` | Elapsed ring 18 pt in the calendar colour | "12m left" `compact` | Title · elapsed/remaining · Join | — |
| **Timer** | `.medium` | Ring 18 pt `warning` | "4:59" `compact` `warning` | Ring 40 · label · ⏸ ⏹ | 1 min left (option), finished |
| **Charging** | `.short` | `bolt.fill` `success` | "82%" `compact` | Battery glyph · `numeral` % · "Charging · 1 h 20 m to full" | Plug in / unplug (2 s) |
| **Low battery** | `.short` | `battery.25percent` (10 %: `battery.0percent`) `danger` | "10%" `danger` | … + *Low Power Mode* toggle | 20 % and 10 % |
| **Bluetooth device** | `.short` | Device glyph (`airpodspro`, `airpodsmax`, `beats.headphones`, `headphones`) | Battery ring 20 pt `success` (< 20 %: `caution`) | Device name · L / R / Case rings with % | On connect (2.6 s) |
| **HUD** | `.wide` | Level glyph (`speaker.wave.3.fill` with `variableValue`, `sun.max.fill`, `light.max`) | `LevelBar` 64u × 6 | — | On key press |

**Interaction**
* **Hover** (180 ms) → peek. **Click** a compact or peek → open the Nook focused on the related widget.
* **Embedded controls** (Join, ⏯) are directly clickable. Each has a ≥ 32 × 24 hit area padded beyond the glyph, a hover `fill2`, and a press scale.
* **Swipe up** dismisses the activity. It **auto-unhides** on the next meaningful change: a new track, the timer under 1 min, a meeting starting.

**Concurrency rules** (HIG "minimal" presentation, adapted to the Mac):
1. Priorities:
   * **P0 HUD**: transient. It replaces everything for 1.5 s, then restores.
   * **P1 alerts**: meeting soon, charging, low battery, device connected, timer done, song change. Each auto-peeks once, on the pointer's display only.
   * **P2 ongoing**: timer running, meeting in progress, Now Playing.
   * **P3 passive**: paused media, which is hidden after 30 s by default.
2. **One ongoing activity:** compact (leading + trailing).
3. **Two:** split. The higher priority takes the **leading** slot in its *minimal* form (Now Playing: artwork + bars; Timer: `timer` glyph + "4:59"). The second takes the **trailing** slot. Both slots use `.medium` so the halves balance. *(Render 6 in `states-compact.png`.)*
4. **Three or more:** the two highest show. Hover peek lists all of them as stacked 52 pt rows (max 4; peek height = H + 52·n + 8).

### 6.6 Peek anatomy

The band row stays as the compact (elements persist and move). Below it, each 52 pt row is laid out as:

`[12] [visual 40 × 40, r 10] [12] [title headline / subtitle callout, flex] [8] [≤ 3 controls, 30 pt hit] [12]`

The width is 380–460 pt (441 on a 14″). Peek always has the keyline and `Elevation.peek`. Rows that have no controls (Charging) end with the value in `numeral`.

### 6.7 HUD replacement

* The geometry is `hud` (373 × 32 on a 14″). Leading holds the 13 pt semibold glyph with `variableValue` (`speaker.wave.3.fill`, or `speaker.slash.fill` when muted, with the bar dimmed to `tertiaryLabel`). Trailing holds `LevelBar`: a 64u × 6 capsule with a `fill3` track. The bar fill is **`label` (white) by default**. *Coloured HUD* (option) uses `accent` for volume, `caution` for brightness and `info` for the keyboard backlight.
* Fine steps (⌥⇧) animate in quarter increments with the same `hudLevel` snappy spring.
* *Show percentage* (option) adds "62" in `caption` mono before the bar.
* When the output device changes, the leading glyph becomes the device glyph with one `.symbolEffect(.bounce)`.
* On notch-less displays the HUD uses the display's handle style. With *Floating*, it appears as a glass capsule.
* VoiceOver: `LevelBar` exposes `accessibilityValue("62 percent")`. While VO is on, changes are announced (debounced 0.5 s).

---

## 7. Settings, onboarding, menu bar extra

### 7.1 Settings window

The window uses a SwiftUI `Settings` scene with a `NavigationSplitView` laid out like System Settings. Built with the macOS 26 SDK, the sidebar and toolbar automatically get the system's Liquid Glass treatment; we add none ourselves. The minimum size is 760 × 540 and the size and selected pane are restored. A `.searchable` field sits at the top of the sidebar. **It searches every setting by title and keywords** and jumps to and highlights the row, which NotchNook lacks.

```
┌───────────────┬──────────────────────────────────────────────────────────────┐
│ 🔍 Search      │  ┌──────────────── Live preview stage (176 pt) ─────────────┐ │
│               │  │ ▔▔▔ menu bar ▔▔▔▔▔▔▔[  real notch views, 1:1  ]▔▔▔▔▔▔▔▔ │ │
│ ⚙︎ General     │  │                                                          │ │
│ 🎨 Appearance  │  │       ( Closed · Activity · Peek · Open · HUD )           │ │
│               │  └──────────────────────────────────────────────────────────┘ │
│ ▦ Nook & Widgets│  Form (.grouped)                                            │
│ ◉ Live Activities│ ┌──────────────────────────────────────────────────────┐   │
│ 🔊 HUD         │  │ Accent                     [System ▾]                │   │
│               │  │ Album glow                                    [◯━]   │   │
│ ▤ Tray         │  │ Notch on other displays    [Pill ▾]                 │   │
│ ✋ Gestures    │  │ Calibrate notch…                              ›      │   │
│               │  └──────────────────────────────────────────────────────┘   │
│ ♫ Media        │                                  Reset Appearance…          │
│ 📅 Calendar    │                                                              │
│ ✦ Shortcuts   │                                                              │
│ ⓘ About        │                                                              │
└───────────────┴──────────────────────────────────────────────────────────────┘
```

* **Sidebar:** each section has a 20 × 20 rounded-square icon (r 5, continuous) with a white SF Symbol on a semantic colour, as in System Settings. Groups:
  * General, Appearance
  * Nook & Widgets, Live Activities, HUD
  * Tray, Gestures
  * Media, Calendar, Shortcuts
  * About
* **Live preview stage** (top of Appearance, Nook & Widgets, Live Activities, HUD and Gestures):
  * It renders the **real** notch views from the same modules, at 1:1 so the type is crisp, over a miniature menu bar and a neutral gradient, with demo data.
  * A segmented control picks the state. Every change animates with the real springs.
  * In Gestures, the stage loops a ghost two-finger swipe demonstration (off under Reduce Motion).
* **Controls:**
  * `Form { … }.formStyle(.grouped)`, toggles as `.switch` with `.controlSize(.small)` (System Settings convention), pickers `.menu`.
  * Sliders show value labels and tick marks at meaningful stops (hover delay 0 / 0.12 / 0.25 / 0.5 s).
  * Every section ends with "Reset ‹Section›…". General → *Reset All Settings…* is destructive (red, confirmation alert).
* **Nook & Widgets: WYSIWYG grid editor** (fixes C4). This is a 1:1 Nook with dashed cell guides.
  * Widgets are tiles you **drag to reorder**. Drag the trailing edge to **resize in cells**; it snaps to cell boundaries with an `.alignment` haptic per cell and shows a "4 cells" tooltip.
  * A library strip below lists hidden widgets to drag in.
  * The keyboard alternative: select a tile, then ⌘← / ⌘→ moves it and ⌥← / ⌥→ resizes it. Every move is announced to VoiceOver.
* **Section contents** (every feature in the inventory is mapped):
  * **General:** Launch at login (`SMAppService.mainApp`), Show on (displays), Open on (Hover / Click), Hover delay, Close when pointer leaves, Inactivity timeout, Hide in full screen, Hide from screen sharing, Keyboard shortcut to open, Check for updates (GitHub Releases, daily, plus a "Check now" button), Reset All.
  * **Appearance:** Accent, Text size, Animation speed, Album glow, Ambient light (Off / Subtle / Vivid), Translucent background, Buttons (Capsule / Rounded), Notch on other displays, Calibrate notch…, Demo mode.
  * **Nook & Widgets:** the grid editor, Density, Widget style (Cards / Flat with dividers), per-widget options (Calendar days behind/ahead and past events; Mirror camera and mirroring; Notes typing effect).
  * **Live Activities:** a toggle per activity, minutes before a meeting, peek on song change, hide paused media after N seconds, auto-unhide, quick peek on hover.
  * **HUD:** Replace system HUD (asks for Accessibility permission here, just in time), Coloured HUD, Show percentage, Volume/Brightness/Keyboard toggles.
  * **Tray:** keep files after quit, max items, pipelines editor (list + chain builder), AirDrop zone.
  * **Gestures:** swipe to change track, invert, vertical swipe to open/close/dismiss, haptic feedback.
  * **Media:** preferred source, visualizer on/off.
  * **Calendar:** calendars to show, meeting-link detection.
  * **Shortcuts:** pick shortcuts and their symbols.
  * **About:** version, licence (MIT), acknowledgements, links.

### 7.2 Onboarding (welcome) and tutorial

**Welcome window:** 600 × 520, hidden title bar, centred, five steps with a page dot indicator. Back / Continue buttons sit bottom-trailing, Continue is the default button (↩). Every step can be skipped.

1. **Meet Cranny.** At the same moment, *the real notch* plays `activityIn` with a waving-hand glyph and "Hi". Copy: "Look up — that's Cranny." An arrow points to the top of the screen. This is the moment of delight: the product introduces itself where it lives.
2. **How should it open?** Two large option cards, **Hover** and **Click**, each with a looping 3-second animation of a mini notch (static frames under Reduce Motion). A "Try it now" line ticks green when the user actually opens the real notch.
3. **Pick a starting Nook.** Three presets shown as live mini Nooks (Music · Productivity · Minimal). Each is editable later.
4. **Permissions: only for what you use.** One row per feature, *each optional*, each explaining its benefit in one line. Each Allow button triggers the system prompt in context:
   * Calendar: meetings and the calendar widget.
   * Camera: Mirror.
   * Accessibility: HUD and media keys.
   * Bluetooth: headphone battery.
   * Automation: Music/Spotify control where needed.

   Nothing is requested before this step, and skipping is fine. Features ask again only when used (fixes C6).
5. **You're set.** A Launch at login toggle (on), "Take the 1-minute tour" (primary), "Done".

**Interactive tutorial (coach marks *in the real notch*):**
* A small floating tip bubble sits 10 pt under the notch. It uses glass on 26+, black 85 % on 14/15, and Reduce Transparency gives opaque black. The bubble holds one sentence and a step counter "2 of 4".
* The steps:
  1. "Rest the pointer on the notch" (completes on open);
  2. "Swipe left or right with two fingers to change track" (completes on swipe; skipped if nothing is playing);
  3. "Drag any file onto the notch" (completes on drop);
  4. "Pin to keep it open" (completes on pin).
* Each completion gives a `.levelChange` haptic and a checkmark `symbolEffect(.bounce)`.
* *Skip tour* is always visible, and the tour can be replayed from Settings ▸ About and from the menu bar extra.

### 7.3 Menu bar extra

`MenuBarExtra` with `.menuBarExtraStyle(.menu)`: a standard native menu, nothing custom.
* Icon: an original 16 × 16 template glyph, a rounded rectangle outline with a filled notch tab at its top edge, drawn as a vector template image. The fallback is the SF Symbol `rectangle.topthird.inset.filled` (macOS 12+). In Demo mode a small dot badge marks the icon.
* Items:
  * Open Nook ⌃⌥N (user-configurable)
  * Pin Open
  * —
  * Pause Live Activities ▸ For 1 Hour · Until Tomorrow · Resume
  * Show On ▸ (displays, checkmarks)
  * Demo Mode
  * —
  * Settings… ⌘, (`SettingsLink`)
  * Check for Updates…
  * Take the Tour
  * —
  * About Cranny
  * Quit Cranny ⌘Q
* *Hide menu bar icon* is an option. Re-launching the app from Finder or Spotlight then opens Settings, so the user can never get locked out.

---

## 8. Iconography, haptics, sounds, app icon

### 8.1 SF Symbols

These are verified on this machine with `NSImage(systemSymbolName:)`. Minimum macOS comes from the system's `name_availability.plist`. Rendering is `.hierarchical`, weight semibold at 13 pt in the band and medium in the Nook.

| Use | Symbol | min macOS |
|---|---|---|
| Play / pause / prev / next | `play.fill` `pause.fill` `backward.fill` `forward.fill` | 10.15 |
| AirPlay route | `airplayaudio` (use `airplay.audio` only on 15+) | 10.15 |
| Visualizer fallback / audio | `waveform` | 10.15 |
| AirPods / Pro / Max / Gen 3 | `airpods` · `airpodspro` · `airpodsmax` · `airpods.gen3` (`airpods.pro`/`.max` names only on 15+, `airpods.gen4` 15.2+) | 11–12.1 |
| Other headphones | `beats.headphones` · `headphones` | 12 / 10.15 |
| Volume | `speaker.wave.3.fill` (variable value) · `speaker.slash.fill` | 11 |
| Brightness / keyboard light | `sun.max.fill` · `sun.min.fill` · `light.max` | 10.15 |
| Battery | `battery.100percent.bolt` · `battery.25percent` · `battery.0percent` · `bolt.fill` | 14 / 10.15 |
| Calendar / Join | `calendar` · `video.fill` | 10.15 |
| Timer | `timer` · `timer.circle.fill` | 10.15 / 13 |
| Notes / code mode / to-dos | `note.text` · `chevron.left.forwardslash.chevron.right` · `checklist` · `checkmark.circle.fill` · `circle` | 11 / 12 / 12 |
| Mirror | `camera.fill` · `arrow.triangle.2.circlepath.camera` | 10.15 / 11 |
| Tabs | `square.grid.2x2.fill` (Nook) · `tray.full.fill` (Tray) | 10.15 |
| Tray actions | `tray.and.arrow.down.fill` · `doc.zipper` · `photo.badge.arrow.down` · `link` · `doc.on.doc` · `square.and.arrow.up` · `wand.and.stars` (pipelines) | 10.15–14 |
| AirDrop zone | `dot.radiowaves.up.forward` *(there is no public "airdrop" symbol; verified missing)* | 12 |
| Pin / settings | `pin.fill` · `pin.slash` · `gearshape.fill` | 10.15 / 11 |
| Gestures (settings) | `hand.draw` · `arrow.left.and.right` · `arrow.up.and.down` · `hand.tap` | 10.15–11 |
| Displays | `macbook` (14) · `laptopcomputer` · `display.2` | 11–14 |
| Accessibility (onboarding) | `accessibility` | 14 |
| Menu bar fallback | `rectangle.topthird.inset.filled` | 12 |

### 8.2 Haptics

Haptics use `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime:)`. Haptics only reach the user while a finger is on a Force Touch trackpad, so they are *never* the sole feedback. *Gestures ▸ Haptic feedback* (default on) disables all of them.

| Event | Pattern |
|---|---|
| Nook opens via hover dwell or swipe commit | `.levelChange` |
| Swipe commits a track change | `.generic` |
| Drag enters a drop zone (Tray, AirDrop, pipeline) | `.alignment` |
| File dropped / pipeline finished | `.generic` |
| Grid editor snaps to a cell; calibration slider at 0; timer scroll detent | `.alignment` |
| Tutorial step complete | `.levelChange` |

For SwiftUI-state-driven cases, `.sensoryFeedback(.alignment / .levelChange, trigger:)` (macOS 14) is equivalent.

### 8.3 Sounds

**None by default.** Cranny is silent.
* **Timer finished:** a user-selectable *system* alert sound (`NSSound(named:)`, e.g. "Glass") or None. We ship no audio assets.
* **HUD:** if the user has macOS's "Play feedback when volume is changed" enabled, Cranny's HUD replacement must respect it by playing the same system feedback. This is a TODO for the HUD module; see Risks.

### 8.4 App icon: "Light from the nook"

The concept: a deep graphite slab (the Mac's display at night). Its top edge carries a precise, slightly-too-large notch, and a cool light (mint → cyan → indigo, a touch of violet) spills from beneath it, as if the Nook were opening. It is calm and geometric, and recognisable at 16 px as "dark tile, notch, light". It shares no shapes or colours with any competitor's icon.

**macOS 26+ layered version (Icon Composer `.icon`).** This was verified: `actool --compile … --app-icon Cranny Cranny.icon` produces `Assets.car` + `Cranny.icns` with no errors. **The first group in the file is the top-most.**

```json
{
  "fill" : { "automatic-gradient" : "display-p3:0.12000,0.12500,0.15000,1.00000" },
  "groups" : [
    { "name" : "Notch",
      "layers" : [ { "name" : "notch", "image-name" : "notch.svg", "glass" : true } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.6 },
      "translucency" : { "enabled" : false, "value" : 0 },
      "specular" : true },
    { "name" : "Light",
      "layers" : [ { "name" : "glow", "image-name" : "glow.svg", "glass" : false, "blend-mode" : "plus-lighter" } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 } }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
```
* `notch.svg` is a 1024 canvas: the notch path is 372 × 132 with ears r 24 and bottom corners r 52, hanging from y = 0.
* `glow.svg` holds two radial gradients: core `#9EFFEB` → `#54C7F2` → transparent `#4D73FF` at (512, 150) with r 380, and violet `#9E73FF` at 65 % at (662, 330).
* With glass on, the notch picks up the system specular edge, which gives the "precision" highlight.
* Appearance variants in Icon Composer:
  * **Dark:** unchanged.
  * **Tinted / Clear:** the glow group becomes monochrome white at 55 % (`fill-specializations` / per-appearance opacity), and the notch stays a glass silhouette.

**Flat fallback (macOS 14/15 asset catalog)** is drawn in CoreGraphics by `CrannyIconDrawing.draw(in:canvas:)` (`src/Icon.swift`). It renders 16–1024 px PNGs for the `AppIcon` set. Steps:
1. Follow the macOS icon grid: an 824 pt body with 100 pt margins and a continuous r 185.4 squircle (from SwiftUI's `RoundedRectangle(style: .continuous).path(in:).cgPath`).
2. Draw a drop shadow (0, −10, blur 28, 45 %).
3. Fill the slab with a linear gradient `P3(0.20, 0.21, 0.25)` → `P3(0.055, 0.058, 0.07)`.
4. Add three radial light lobes: a mint core, violet, and a faint magenta.
5. Draw the notch with the **same `NotchShape`** as the app, flipped into CG space.
6. Stroke a 4 pt mint rim along the notch outline (the `openTop` path).
7. Stroke the edge with a 10 % white highlight.

The output is `out/icon-1024.png`, `icon-16/32/64/128.png`.

---

## 9. Accessibility

| Setting / need | Behaviour |
|---|---|
| **Reduce Motion** | See §5.6: dissolves instead of big morphs, no bounce, no blur or scale, no stagger, marquee, ambient, typing effect or pulses. |
| **Reduce Transparency** | Floating glass becomes opaque black. The translucent Nook option is forced off. Ambient field and album glow are off. Tutorial bubble is opaque. |
| **Increase Contrast** | `CrannyPalette.make(contrast: .increased)`: stronger fills and text (tertiary ≥ 7.5 : 1), **keyline always on (45 %)**, 1 px `hairline` border on every card, dividers 30 %, Apple's accessible semantic variants. |
| **Differentiate Without Color** | States never rely on colour alone. Low battery adds an exclamation badge, Join always carries the `video.fill` glyph *and* a "Join" label in peek, the timer-finished state adds "Done" text, past events get strikethrough as well as being dimmed. |
| **VoiceOver** | See below. |
| **Keyboard** | See below. |
| **Text size** | In-app Text Size (S / M / L / XL = 0.92 / 1 / 1.12 / 1.24) scales all Nook and peek text. Card heights grow with it: cell size × scale, rounded to 4 pt. Band text scales with `unit`, because it must fit the hardware. Settings and onboarding use standard system sizes. |
| **Pointer accessibility** | Hover delay up to 0.5 s and a click-to-open mode. Hit targets are ≥ 28 × 24 in the Nook and ≥ 32 × 24 for embedded compact controls. |

**VoiceOver**
* The panel is an `accessibilityElement(children: .contain)` labelled "Cranny".
* Closed: "Cranny, collapsed" with the action "Open".
* Compact: one combined element. Its label is the activity ("Now playing: Midnight Window by The Example Band"), its value the live datum ("2 minutes 11 seconds left"), and it has named actions ("Play/Pause", "Next track", "Open Nook", "Dismiss").
* Every icon-only button has an `accessibilityLabel`. Sliders (scrubber, HUD, timer) get `accessibilityAdjustableAction`. Tabs carry `.isSelected`.
* **Announcements:** `AccessibilityNotification.Announcement(…).post()` fires only for P1 alerts (meeting soon, timer done, device connected, low battery), rate-limited to one per 10 s.
* **Hover-to-open is automatically treated as click-to-open while VoiceOver runs** (`accessibilityVoiceOverEnabled`).

**Keyboard**
* A global shortcut (default ⌃⌥N) opens the Nook *and* makes the panel key, with focus on the first widget.
* ← → ↑ ↓ move focus between widgets in grid order. Tab and ⇧Tab move between controls inside a widget. Return / Space activates. ⌘1 / ⌘2 switch tabs. ⌘↩ toggles Notes focus. Esc closes, restoring the previous app's focus.
* Focus ring: `crannyFocusRing`, a 2 pt `accent` stroke on a radius concentric with the focused card (r + 3, outset 3). The system focus effect is disabled on those elements to avoid double rings.

**Localisation (English + Russian)**
* Use String Catalogs (`.xcstrings`). All copy is sentence case. Numbers and durations go through `Duration.formatted` / `DateComponentsFormatter`, never concatenation.
* The compact band uses abbreviations that are tested for both languages.

---

## 10. Risks and trade-offs of this direction

1. **Restraint can read as "less" than competitors.** A black, white and one-accent palette with no ambient motion by default may demo worse than flashier apps. *Mitigation:* the moments of delight are concentrated in motion: the activity drop, outward stagger, the album accent, the rubber-band "max" bump. Ambient light (Subtle/Vivid) and the coloured HUD are one toggle away.
2. **Hardware fidelity depends on values we can't query.** The housing's exact corner radius and any per-model differences are unknown. *Mitigation:* the closed shape sits *inside* the cut-out (radius 10u ≥ hardware), a calibration sheet adjusts it, and values are stored per display model. Test on 14″, 16″, 13″/15″ Air and every scaling mode.
3. **Spring values are tuned by eye.** Apple publishes no Dynamic Island numbers. *Mitigation:* every value lives in one `CrannyMotion` table, the Animation speed setting covers taste, and the staged morph is an A/B option.
4. **Liquid Glass is 26+ only and must not appear on black.** The look therefore differs slightly on 14/15 (material fallback) for floating surfaces only. *Mitigation:* glass is limited to surfaces with no hardware anchor. The attached notch is identical on every OS.
5. **Covering the menu bar.** An open 676 pt Nook hides menu titles and status items. This is inherent to the category. *Mitigation:* the 55 % width cap, close-on-leave with grace, and no auto-open on pass-through.
6. **Hover-intent heuristics can feel slow** to power users (120 ms dwell) or twitchy to others. *Mitigation:* the hover delay slider, click mode, and a trackpad swipe-down to open instantly.
7. **SF Pro Rounded for numerals may feel "iOS"** on a Mac. *Mitigation:* rounded is used only for live numbers, matching Apple's own Mac widgets and Lock Screen clock.
8. **Album-art accents can clash or wash out.** *Mitigation:* the saturation cap, the contrast lift and a greyscale fallback. The accent never colours text, and *Monochrome* is available.
9. **Energy.** Visualizer Canvas and ambient `TimelineView` cost CPU. *Mitigation:* the budget in §5.9 is a release gate, with Instruments measurements on every release.
10. **Russian text length** in fixed-width cells risks truncation. *Mitigation:* free text never appears in compact slots, pseudo-localisation tests run at 1.4×, and cards grow with Text Size.
11. **HUD replacement** needs Accessibility permission (an event tap) and must mirror the system's volume-feedback sound and steps exactly. Getting this wrong is very noticeable. Ship it as opt-in v1.
12. **No offline Metal.** Effects are limited to SwiftUI gradients, MeshGradient (15+) and Canvas. That is consistent with this direction's restraint, but rules out shader-heavy "wow" effects. A runtime `MTLDevice.makeLibrary(source:)` path is possible but out of scope.

---

## Appendix A: verification log

| Claim | How it was verified |
|---|---|
| Token, geometry, shape, motion, accent, component, effect and icon code | `swiftc -swift-version 6 -target arm64-apple-macos14.0 -parse-as-library src/*.swift` builds and runs with zero diagnostics (`poc/design-native/render`). |
| Every state renders as described | `render out` → `states-compact.png` (10 states), `states-open.png` (Nook, dark desktop, dividers, Tray), `states-external.png` (handle, centre label, 37 pt notch), `morph-steps.png`, `corner-zoom.png`. |
| Contrast numbers | `contrastAudit()` output in `out/audit.txt`. |
| No ear/body seam | `tools/seam`: rendered at 4×, every pixel in the overlap columns is 0.0 (solid black). |
| Keyline excludes the screen edge | Found and fixed a bug: SwiftUI emits zero-radius corners as degenerate curves at the corner point. Re-rendered `corner-zoom.png`. |
| `glassEffect`, `Glass.regular/.clear/.tint/.interactive`, `GlassEffectContainer`, `glassEffectID`, `glassEffectTransition(.matchedGeometry)`, `ConcentricRectangle`, `containerShape` (26) · `MeshGradient`, `TextRenderer` (15) · `sensoryFeedback`, `numericText`, `symbolEffect(.bounce/.variableColor/.replace)`, `blurReplace`, `phaseAnimator`, `onKeyPress`, `focusEffectDisabled`, `accessibilityAdjustableAction`, `AccessibilityNotification.Announcement`, `MenuBarExtra(.menu)`, `SettingsLink`, `openSettings`, `Text(timerInterval:)` (14) · `NSHapticFeedbackManager` patterns, `NSWorkspace` accessibility flags | `tools/apicheck/Check.swift` typechecks for the macOS 14 target, with `#available` gates for 15 and 26. Declarations were also read in `SwiftUICore.swiftinterface` (e.g. `Glass`, `ConcentricRectangle`). |
| Staged per-axis morph | `tools/apicheck/Staged.swift` typechecks (needs `nonisolated animatableData` under Swift 6). |
| Hover-intent tracker and NSPanel set-up | `tools/apicheck/Intent.swift` typechecks. |
| `SMAppService.mainApp`, `NSSharingService(named: .sendViaAirDrop)`, precise scroll deltas, momentum phase, `CGDisplayModelNumber`, screen-change notification | `tools/apicheck/Misc.swift` typechecks. |
| SF Symbols exist, with min OS | `tools/symbols` plus `/System/Library/CoreServices/CoreGlyphs.bundle/…/name_availability.plist`. `airdrop`, `bluetooth` and `shortcuts` are **not** public symbols. |
| Icon Composer file | `actool --compile <abs path> --platform macosx --minimum-deployment-target 14.0 --app-icon Cranny Cranny.icon` → `Assets.car` + `Cranny.icns`. Note: actool runs as a shared server, so **pass absolute paths** (relative paths resolve against another process's cwd). |
| Screen metrics | On this Mac (clamshell, MSI 2560 × 1440 external display): no notch, menu bar measured 30 pt. Notched values come from public model specs and must be confirmed on hardware. |

## Appendix B: sources

- Apple Human Interface Guidelines, *Live Activities* (updated 2025-12-16): compact, minimal and expanded anatomy; Dynamic Island 44 pt radius; dimensions; key line; concentric margins; animation ≤ 2 s. developer.apple.com/design/human-interface-guidelines/live-activities
- MacStories, "NotchNook and MediaMate: Two Apps to Add a Dynamic Island to the Mac": external display "always looks like a notch", fullscreen covering, tray with two zones. macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/
- Digital Trends (Alex Blake, 2024) via Yahoo Tech, "MacBook notch redeemed": reordering widgets by clicking arrows; "surprising amount of control". tech.yahoo.com/computing/articles/macbook-notch-redeemed-130056005.html
- iMore (Daryl Baxter): NotchNook UI walkthrough; 1.2 moves volume and brightness HUD into the notch. imore.com/apps/mac-apps/…
- Pplware: stability and battery reports; redundancy with macOS. pplware.sapo.pt/apple/notchnook-dar-utilidade-ao-notch-no-mac/
- MacRumors forum "NotchNook" thread and Setapp NotchNook customer reviews: battery drain and CPU, does not hide properly during movies. *Via search excerpts; both pages refused direct fetch (403/404).*
- Root Nation NotchNook review: transition back to the notch "less than smooth", permission prompts off-putting. *Via search excerpt; the page returned 403.*
- TheBoredTeam/boring.notch GitHub issues (read for UX failure modes only; no code used): #316, #303, #381, #175, #94, #720, #239, #663, #814, #522, #1278, #348, #1415, #1110, #308, #1079.
- Alcove: tryalcove.com; ifun.de hands-on review; AlternativeTo listing.
- Atoll (Ebullioscopic/Atoll) README and listing; MediaMate (MacStories, as above).

# Cranny Design System

> **Hardware-true, calm when closed, alive when open.** One black shape that grows out of the camera housing, colour that always means something, light as an optional layer, and every action reachable without hover.

| | |
|---|---|
| Status | **v1.0, adopted** (2026-10-14); aligned with ARCHITECTURE.md by the review of the same day, amended for the Metal decision (ARCHITECTURE D13: §5.6, Appendix B.2), synced with the repo after WP0 (effect clock, shipped shader files, icon), synced after phases B and C with the refinements the implementation made and the review approved (ARCHITECTURE.md §10 "As built"), synced after phase D with the design owner's rulings R1–R5 (§4.4, §4.6, §5.5, §7.3, §9.2, §10, §13, §16) and the fixes that followed them, and synced after phase E with rulings E1–E4 (§4.6, §9.1, §9.2, §11.1, §12.1) and the fixes that followed them. Still-open questions are ARCHITECTURE.md §10.20. See ARCHITECTURE.md's "Changelog". This file is the single source of truth for every pixel, colour and animation in Cranny. |
| Applies to | The notch surfaces (closed, compact, peek, HUD, open Nook, Tray), Settings, onboarding and the tutorial, the menu bar extra, the app icon. |
| Platform | Deployment target macOS 14.0. Newer APIs (`MeshGradient`, `TextRenderer` 15+; Liquid Glass 26+) only behind `#available`, always with a designed fallback. |
| Code | Every Swift block in this file is copied verbatim from a scratch package that builds with **zero errors and zero warnings** under Swift 6 / macOS 14 / the four CrannyKit upcoming features, with **both** default isolations (nonisolated and `MainActor`). See Appendix C. |
| Effects | **Metal shaders** for the light layer and its moments: SwiftUI stitchable `colorEffect` / `layerEffect` / `distortionEffect` compiled from `CrannyEffects/Shaders/*.metal` (ARCHITECTURE D13, §5.6). Each has a designed **pure-SwiftUI fallback** (MeshGradient, Canvas, gradients, shadows; time from `EffectClock`), used under Reduce Motion, Low Power / thermal and when shaders are unavailable. Appearance ▸ Quality ▸ **Efficient** swaps the Metal light for a simpler **Core Animation** light that the window server animates, with no Metal in Cranny (§5.7). No videos, GIFs or Lottie. |
| Clean room | Original work for Cranny (MIT). No NotchNook, boring.notch (GPL), Alcove or Atoll code, assets, names or UI text. Competitors were studied only through public reviews, product pages and issue-tracker titles. |

**Contents.** 0 Decision record · 1 Principles · 2 Tokens · 3 Geometry & the NotchShape · 4 Motion · 5 The light layer · 6 The open Nook · 7 Widgets · 8 Tray & pipelines · 9 Live activities · 10 HUD · 11 Settings · 12 Onboarding & tutorial · 13 Menu bar extra · 14 Symbols, haptics, sound · 15 App icon · 16 Accessibility · 17 Copy & localisation · 18 What's better than NotchNook · Appendix A Components · Appendix B Ambient layer · Appendix C Verification.

---

## 0. Decision record

Three directions were proposed: **A "Apple-native precision"**, **B "Expressive Ambient"** and **C "Calm power-user"**. Each was read in full and scored 1–10.

### 0.1 Scores

| Criterion | A · Native precision | B · Expressive Ambient | C · Calm power-user |
|---|:-:|:-:|:-:|
| Cohesion & craft | **9** | 7.5 | 8.5 |
| Feasibility in SwiftUI (no offline Metal) | **9** | 7 | 8 |
| Delight | 6.5 | **9.5** | 5.5 |
| Accessibility | 9 | 8 | **9.5** |
| Differentiation from NotchNook | 6.5 | **9** | 8 |
| Information clarity | **9** | 7 | 8.5 |
| **Total (/60)** | **49.0** | 48.0 | 48.0 |
| Backbone suitability (craft and feasibility weighted ×1.5) | **58.0** | 55.25 | 56.25 |

**A, Native precision (winner, backbone).**
- Strongest system thinking: one shape, four numbers; closed equals the hardware cutout; concentric radii; HIG compact rules (symmetric slots, content snug against the camera); a hover-intent contract; measured contrast; an energy budget treated as a release gate. Every complaint it cites maps to a section.
- Most feasible: every API was typechecked against the macOS 14 target, including a staged-morph option and a seam test for the ears.
- Weaknesses: its delight lives in motion alone, and the "ambient light" setting is named but never specified. Splitting two activities across the leading and trailing slots breaks the rule that both slots describe one thing. It uses `video.fill`, which Apple restricts to FaceTime. The open bounce (0.20) and the activity drop (0.30) risk the "wobbly" complaint that tops competitor issue trackers. The keyline is drawn by rewriting path elements, which is fragile.

**B, Expressive Ambient.**
- The most distinctive identity: "light is information". It has per-activity colour, a contrast audit against the worst-case glow (it found that Vivid needs its own token set), an honest visualizer that never fakes beat accuracy, a real energy budget and a satellite with a liquid neck.
- Weaknesses: its closed state draws 4-pt ears outside the hardware outline, a visible black flare on the menu bar that contradicts its own "1 pt inside" rule. Its underglow is a blurred *fill*, which would capture clicks (the window server catches any drawn pixel; R1 §4.1). The 64-pt cells make the default Nook 736 pt wide. Four dials (Ambience × Effect × Motion × Accent) plus eight delight moments create a large QA and energy matrix.

**C, Calm power-user.**
- The best keyboard model (global shortcut, ⌘K palette, hold-⌘ hints, type-to-capture, a VoiceOver rotor) and the best Settings UX: a live preview fed by *draft* settings, "Show on Notch", per-row reset, and Permissions and Keyboard panes. It also brings a never-two-HUDs rule, attention to SF Symbol restrictions and spring physics it actually measured.
- Weaknesses: it under-delivers on delight. Its default shortcut ⌃⌥Space collides with macOS "Select next input source", which Russian-layout users (one of our two locales) press daily. Its semantic colours resolve through dynamic `NSColor` inside a forced-dark view, which is fragile. Its 66 % width cap covers more of the menu bar.

### 0.2 What was grafted onto the backbone

| Idea | From | Where |
|---|---|---|
| The optional **light layer**: aurora, motes, tide and halo; per-activity palettes; k-means palette extraction; underglow; progress rim; honest visualizer modes; capped delight moments | B | §5, App. B |
| **Smoked** cards, a `lit` token set, and a contrast audit against the worst-case glow | B | §2.1 |
| A **Motion** dial (Calm / Standard / Lively, plus C's Instant) and the rule "never overshoot when shrinking into the hardware" | B + C | §4 |
| **Floating island** as the default on displays without a notch | B + C | §3.5 |
| Menu-bar courtesy; no open while a mouse button is down; longer dwell in full screen | B | §4.6 |
| Keyboard model, ⌘K command palette, hold-⌘ hints, type-to-capture, pages, keyboard-driven layout editing | C | §6, §16 |
| Settings live preview with **Show on Notch** (C proposed draft settings; Cranny applies settings instantly and previews them live, with a 10-s Undo for Reset All — ARCHITECTURE D14); simulate chips (B); per-row reset, a dot on non-default values, Permissions and Keyboard panes, search | C + B | §11 |
| Never two HUDs; a Carbon hot key that needs no Accessibility permission; awareness of symbol restrictions; spring physics measured, not guessed | C | §10, §14, §4.1 |
| Ears **unioned** into one outline, so the keyline is a plain stroke | C | §3.3 |
| Excluded apps; Demo mode that redacts calendar titles | C | §11 |

### 0.3 Conflicts and how they were resolved

| # | Topic | A | B | C | **Decision** (why) |
|---|---|---|---|---|---|
| 1 | Geometry bounce | open .20, activity .30 | open .14, close 0 | open .08, close 0 | **Standard: open .14 (0.5 % overshoot ≈ 2 pt), activity drop .24 (2.5 %), anything that shrinks 0.** The drop stays alive without the wobble users complain about most. Calm / Lively / Instant dial. |
| 2 | Hover delay | 120 ms | 120 ms | 220 ms | **120 ms default** plus pass-through speed, ⌥ suppression, mouse-button check and 400 ms in full screen. Presets 0 / 120 / 220 / 450 ms. |
| 3 | No-notch default | attached pill | floating pill | floating island | **Floating island** (a fake notch reads as fake on external displays). Attached and Off are options; the handle can be hidden until hover. |
| 4 | Card fill | white 7 % | smoked | white 6 % | **Smoked, white 0.10 at 80 %** (#141414 over black, nearly the tone of A’s 7 % white). It dims light underneath instead of washing out. |
| 5 | Text opacities | .68 / .50 | .68 / .52 | .70 / .55 | **.70 / .55**: tertiary 6.2:1 on cards and 5.45:1 over the worst Subtle glow. |
| 6 | Grid | 56/8/12, r 32 | 64/8/12, r 30 | 56/8/10, r 28 | **56 / 8 / 12, panel 32, card 20, inner 8.** The panel radius changes per density so cards stay at 20 (C's idea). |
| 7 | Slot widths | 40/52/68/88 | 48/72/104 | 40/62/96 | **40 / 52 / 68 / 92.** Wide gets +4 pt so the HUD fits a glyph and a 64-pt bar. |
| 8 | Two activities | split slots | satellite | satellite | **Satellite** (the Mac analogue of iOS "minimal"). The liquid neck plays only in Standard and Lively. |
| 9 | Accent | System | per activity | System + swatches | **Automatic** (album art while music plays, else system accent) · System · 8 swatches · Monochrome. Semantic colours never change. |
| 10 | Ambient default | off | Subtle | off | **Subtle**, only while the Nook is open, ≤ 30 fps, automatically off in Low Power Mode and with Reduce Transparency. |
| 11 | Global shortcut | ⌃⌥N | ⌥⌘N | ⌃⌥Space | **⌃⌥N**. ⌥⌘N is Finder's New Smart Folder and ⌃⌥Space switches input sources. Registered via Carbon `RegisterEventHotKey`, so no Accessibility permission. |
| 12 | Uppercase labels | yes | yes | no | Section labels use **sentence case** (`eyebrow`). UPPERCASE (`micro`) is limited to tokens of 4 characters or fewer ("TUE", "LIVE"); uppercase Cyrillic runs long. |
| 13 | Liquid Glass | floating island by default | settings only | controls | Notch surfaces are **opaque black by default**. "Glass island" (26+, no-notch only, `lit` tokens, audited) and "Translucent background" are opt-in. The attached notch never uses glass. |
| 14 | Keyline | rewritten open path | gradient mask | rim × openness | **Stroke of the unioned outline × openness, masked to start below the band.** Always on under Increase Contrast; tinted with the album accent. |
| 15 | Join glyph | `video.fill` | `video.fill` | `person.2.wave.2.fill` | **`person.2.wave.2.fill` plus a "Join" label.** `video*` symbols may only refer to FaceTime (`symbol_restrictions.strings`, verified). |
| 16 | Click-through | toggle `ignoresMouseEvents` | toggle | toggle | **Never assign `ignoresMouseEvents`.** Per-pixel pass-through is verified (R1). Light outside the shape is a coloured `.shadow`, which passes clicks through. |
| 17 | Nook max width | 55 % / 880 | screen − 96 | 66 % | **min(55 % of the screen, 880 pt)**, so menu-bar extras stay reachable. |
| 18 | Visualizer | 5 bars | 5 bars + modes | 4 bars | **5 bars**; Live (opt-in permission) / **Ambient** (default) / Static / Off. |
| 19 | Timer colour | orange | ember | accent | **`warning` orange** in every form (the iOS convention), so a timer is recognisable at a glance. |
| 20 | HUD height | band | band + 16 chin | band | **Band only.** The HUD never covers content. |

---

## 1. Principles

Each principle comes with a test that a build either passes or fails.

1. **Hardware-true.** Closed *is* the camera housing: drawn 0.5 pt inside it, never decorated, never shadowed. Every expansion grows out of the hardware and lands back on it exactly.
   *Test:* at rest, no Cranny pixel is visible outside the cutout; close overshoot is 0.
2. **One continuous object.** There is one shape, six animatable numbers and no window resizing. Elements that persist across states *move* (matched geometry) rather than vanish and reappear. Content lays out at its final size and is revealed by the clip.
   *Test:* no frame pops, and no text reflows during a morph.
3. **Glanceable, then actionable.** Compact shows one datum per side. Peek shows one row per activity with at most three controls. The Nook holds the rest. You go deeper on purpose: hover, click, keyboard or swipe.
   *Test:* every compact state can be read in under 0.5 s; no compact slot holds free text.
4. **Colour is information; light is optional.** Surfaces are black, text is white at fixed opacities, there is one accent at a time, and semantic colours mean what they mean on iOS. Ambient light comes only from something real (the album, the event, the timer) and never sits behind text without a card or a scrim.
   *Test:* every text token meets ≥ 4.5:1 in the audit (§2.1), including over worst-case light.
5. **Calm when closed, alive when open.** Nothing loops in your peripheral vision except a visualizer while audio actually plays. Light and delight live inside the Nook you opened. There are no sounds by default.
   *Test:* Energy Impact < 1.0 while idle; zero timers while closed.
6. **Intent over proximity.** Cranny opens on dwell, click, shortcut or swipe, never on a pointer passing through. It closes after you leave plus a grace period, never while you type, drag, pin or use a menu.
   *Test:* moving to a display above, or reaching for a menu, never opens it.
7. **Nothing is hover-only.** Every action has a click, keyboard and VoiceOver path. Holding ⌘ shows the shortcuts in place.
   *Test:* every feature passes a keyboard-only run and a VoiceOver-only run.
8. **Native, on every supported OS.** Cranny uses system controls in Settings, SF Symbols and continuous corners, honours every accessibility display option live, and asks for permissions only when a feature needs them. On macOS 14 it must look intentional, not degraded.
   *Test:* snapshot suites pass on 14, 15, 26 and 27.

---

## 2. Tokens

### 2.0 Placement and rules

- **Where:** `CrannyKit/Sources/CrannyCore/DesignSystem/`, in the files `Color.swift`, `Typography.swift`, `Layout.swift`, `Motion.swift`, `Notch.swift`, `Theme.swift` and `Components.swift`. Appendix B is split: `AmbientPalette` and `EffectBudget` live in `CrannyCore/DesignSystem/AmbientPalette.swift` (Media, the shell and Effects share them); `AuroraField` and every other effect live in `CrannyEffects`.
- **Naming in UI text:** "Nook" is this document's internal name for the open panel and stays in code identifiers, but it never appears in UI copy (ARCHITECTURE D20): the panel is "Cranny" ("Open Cranny"), the grid page is **Home**, the Settings pane is **Layout & Widgets**.
- **Isolation:** pure value types are declared `nonisolated`, so the files compile unchanged whether the module defaults to `nonisolated` or to `MainActor`.
- **Rules:**
  1. Feature modules never write literal colours, sizes, radii or animations.
  2. They read `@Environment(\.cranny)` only, and never raw accessibility flags.
  3. Every Cranny surface applies `.crannyThemeRoot(theme)` exactly once at its root: the notch panel, the Settings preview stage and the onboarding stage.
  4. The hosting `NSPanel` sets `appearance = NSAppearance(named: .darkAqua)`, so AppKit-backed controls inside it resolve to dark.
- **Two worlds:** the notch is always dark. Settings, onboarding and menus are ordinary windows and use **system** colours and text styles, so they follow Light/Dark.

### 2.1 Colour

**Palette variants.** The theme root picks one automatically:
- `standard` when Ambient light is Off or Subtle;
- `lit` with Vivid light or the glass island;
- `highContrast` under Increase Contrast;
- `opaque` under Reduce Transparency.

| Token | standard | lit | highContrast | opaque | Use |
|---|---|---|---|---|---|
| `surface` | #000 | #000 | #000 | #000 | The shape. Equal to the hardware notch; never tinted. |
| `card` | white .10 @ 80 % | white .10 @ 88 % | white .14 opaque | white .09 opaque | Widget card ("smoked") |
| `cardHover` | white .15 @ 80 % | white .15 @ 88 % | white .20 | white .13 | Card under the pointer |
| `control` | white 11 % | 11 % | 20 % | 11 % | Buttons, chips, segmented track, scrubber and HUD track |
| `controlHover` / `controlPressed` | 16 % / 22 % | 16 / 22 | 26 / 32 | 16 / 22 | Hover; pressed; selected segment or row |
| `well` | white 6 % | 6 % | 12 % | 6 % | Inset text fields (search, palette) |
| `scrim` | black 55 % | 62 % | 80 % | 100 % | Under text that sits directly on light |
| `hairline` | white 10 % | 12 % | 34 % | 12 % | Card edge (1 px), flat-style dividers |
| `stroke` | white 24 % | 26 % | 62 % | 26 % | Outlines, idle dashed drop zones |
| `keyline` | white 14 % | 18 % | 45 % | 16 % | Rim of peek and open, × openness |
| `label` | white 100 % | 100 % | 100 % | 100 % | Titles, values |
| `secondaryLabel` | 70 % | 76 % | 86 % | 70 % | Artist, times, inactive tabs |
| `tertiaryLabel` | 55 % | 62 % | 74 % | 55 % | Metadata, comments, past events |
| `quaternaryLabel` | 32 % | 36 % | 50 % | 32 % | Placeholders and disabled text only |

**Contrast audit.** WCAG 2.x, sRGB "over" compositing, computed by the harness. "Worst glow" assumes the brightest permitted light pixel (grey 0.92 at the level's alpha cap: Subtle 0.45, Vivid 0.80) directly under the card.

| Text on → | black | card | card over worst glow | control on card |
|---|:-:|:-:|:-:|:-:|
| standard label / secondary / tertiary | 21.0 / 9.96 / 6.27 | 18.4 / 9.32 / 6.16 | 14.5 / 7.85 / **5.45** | 13.5 / 7.47 / 5.24 |
| lit (Vivid) label / secondary / tertiary | 21.0 / 11.8 / 7.85 | 18.0 / 10.7 / 7.46 | 13.8 / 8.63 / **6.30** | 13.2 / 8.33 / 6.11 |
| highContrast label / secondary / tertiary | 21.0 / 15.2 / 11.1 | 15.6 / 11.8 / 9.12 | (cards opaque) | 8.12 / 6.53 / 5.34 |
| opaque label / secondary / tertiary | 21.0 / 9.96 / 6.27 | 17.9 / 9.18 / 6.11 | (no light) | 13.1 / 7.28 / 5.14 |

Two cases where text sits on something other than a card:
- **Flat widget style with Subtle light:** text on `scrim` over the worst glow measures 13.3 / 7.36 / **5.18** (label / secondary / tertiary).
- **Glass island** (`lit` tokens) over a pure white wallpaper: 10.4 / 6.82 / **5.15**.

`quaternaryLabel` measures 2.7–3.3 (5.3 under Increase Contrast) and may never carry information.

**Semantic colours** (dark-appearance values, with accessible variants under Increase Contrast). They are used only for their meaning, and always together with a glyph or text cue (§16).

| Token | Standard | Increase Contrast | On black / on card | Meaning |
|---|---|---|:-:|---|
| `success` | #30D158 | #30DB5B | 10.4 / 9.1 | Charging, Join, done, meeting in progress |
| `warning` | #FF9F0A | #FFB340 | 10.2 / 8.9 | Timer (always), last minute, the first low-battery warning, a device battery below 20 % |
| `danger` | #FF453A | #FF6961 | 6.2 / 5.4 | The final low-battery warning, failed pipeline, destructive actions, today's weekday |
| `info` | #409CFF | #70B7FF | 7.4 / 6.5 | Links, AirDrop, Bluetooth |
| `caution` | #FFD60A | #FFD426 | 14.9 / 13.0 | Low Power Mode, brightness (coloured HUD) |

**Brand ramp "Afterglow"** (icon, onboarding, About, fallback light): mint #9EFFEB · lagoon #2ED3C6 · sky #54C7F2 · iris #8B6CFF · rose #FF4F8B · ember #FF7A45 · night #0B0A14 · graphite #1E2026.

**Accent strategy**
- **Sources** (Appearance ▸ Accent):
  - **Automatic** (default): the album accent while media plays, otherwise the system accent.
  - **System:** `controlAccentColor` resolved in Dark appearance; Graphite stays grey.
  - **Swatch:** 8 curated colours, each ≥ 7.4:1 on cards.
  - **Monochrome:** white only. This is the "disable colours" option.
- **Guard:** the resolved accent is lifted until it reaches ≥ 4.5:1 on a card, or ≥ 7:1 under Increase Contrast. Measured examples: #0000FF → #7373FF (4.9), navy #1B2A6B → #5A79FF (4.9), deep red #720C14 → #F52535 (4.5), system blue #0A84FF → #2692FF (5.8; 7.5 under Increase Contrast).
- **Track changes:** the accent cross-fades with `colorShift` (0.8 s).
- **Where accent appears:** scrubber and progress fills, rings, the visualizer, checkboxes and toggles, the focus ring, an armed drop target, the selected-file ring, the code-mode toggle and the keyline tint.
- **Where it never appears:** body text, card or panel fills, the default HUD, and anything that has a semantic meaning (Join is always green, the timer always orange).

**Swatches** (on black / on card): blue #5CA8FF 8.5/7.4 · teal #4FD1C4 11.3/9.8 · green #66D487 11.3/9.9 · yellow #F5C452 12.9/11.3 · orange #FF9E5C 10.3/9.0 · pink #FF80B5 9.0/7.9 · purple #B89EFF 9.4/8.2 · graphite #C7C7CC 12.5/10.9.

**Notes code-mode syntax** (on card): keyword #FF7AB8 7.6 · type #62D6FF 11.0 · string #FF9466 8.5 · number #E8C66C 11.1 · function #A6E37A 12.1 · link #6BB3FF 8.3. Comments use `tertiaryLabel` italic (6.2) and headings use `label` semibold.

```swift
// CrannyCore/DesignSystem/Color.swift
// Colour tokens. The notch surfaces are ALWAYS dark (they extend the black hardware
// notch). Settings, onboarding and menus are ordinary windows and use system colours.
import SwiftUI
import AppKit

// MARK: - RGB: palette math (sRGB 0…1), animatable

/// sRGB triple used for contrast math, accents and ambient palettes. It is
/// `VectorArithmetic`, so palettes cross-fade inside Canvas/MeshGradient effects.
public nonisolated struct RGB: Hashable, Sendable, VectorArithmetic {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(white w: Double) { self.init(w, w, w) }
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public var color: Color { color(1) }
    public func color(_ opacity: Double) -> Color {
        Color(.sRGB, red: Self.clamp(r), green: Self.clamp(g), blue: Self.clamp(b), opacity: opacity)
    }
    public var nsColor: NSColor {
        NSColor(srgbRed: Self.clamp(r), green: Self.clamp(g), blue: Self.clamp(b), alpha: 1)
    }
    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    // VectorArithmetic
    public static var zero: RGB { RGB(0, 0, 0) }
    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func - (a: RGB, b: RGB) -> RGB { RGB(a.r - b.r, a.g - b.g, a.b - b.b) }
    public mutating func scale(by k: Double) { r *= k; g *= k; b *= k }
    public var magnitudeSquared: Double { r * r + g * g + b * b }

    // WCAG 2.x
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(Self.clamp(r)) + 0.7152 * lin(Self.clamp(g)) + 0.0722 * lin(Self.clamp(b))
    }
    /// Contrast ratio 1…21.
    public func contrast(with o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// `self` drawn at `alpha` over `background` (sRGB "over"; matches how the tokens composite).
    public func over(_ background: RGB, alpha: Double) -> RGB {
        RGB(r * alpha + background.r * (1 - alpha), g * alpha + background.g * (1 - alpha), b * alpha + background.b * (1 - alpha))
    }

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

    /// Brighten, then desaturate, until the colour reaches `ratio` against `background`.
    /// Used for every FOREGROUND mark derived from content (accent, calendar colour).
    public func legible(on background: RGB = .black, ratio: Double = 4.5) -> RGB {
        var (h, s, v) = hsb
        s = min(s, 0.85); v = max(v, 0.72)
        var out = RGB(h: h, s: s, v: v)
        var guardrail = 0
        while out.contrast(with: background) < ratio && guardrail < 40 {
            if v < 1 { v = min(1, v + 0.04) } else { s = max(0, s - 0.05) }
            out = RGB(h: h, s: s, v: v); guardrail += 1
        }
        return out
    }
    /// Label colour to place ON a filled accent (prominent button, Join capsule).
    public var onColor: RGB { contrast(with: .black) >= contrast(with: .white) ? .black : .white }
    /// Glows read as light: saturated and bright, never neon-white (ambient layer only).
    public var luminous: RGB {
        let (h, s, v) = hsb
        return RGB(h: h, s: min(max(s, 0.45), 0.90), v: min(max(v, 0.75), Glow.maxBrightness))
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
}

// MARK: - Palette (surfaces, lines, text, semantic)

/// One palette per contrast/transparency situation. Text is white at fixed opacities, so it
/// composites identically on every surface. Values are audited in DESIGN.md §2.1.
public nonisolated struct CrannyPalette: Equatable, Sendable {
    public nonisolated enum Variant: String, CaseIterable, Sendable {
        case standard       // default (ambience Off or Subtle)
        case lit            // ambience Vivid, or the glass floating island: denser cards, lifted text
        case highContrast   // System ▸ Accessibility ▸ Increase contrast
        case opaque         // System ▸ Accessibility ▸ Reduce transparency
    }

    /// Raw numbers (white level / opacity) so the contrast audit and the colours share one source.
    public nonisolated struct Spec: Equatable, Sendable {
        public var cardWhite: Double, cardOpacity: Double, cardHoverWhite: Double
        public var control: Double, controlHover: Double, controlPressed: Double, well: Double
        public var scrim: Double, hairline: Double, stroke: Double, keyline: Double
        public var label: Double, secondary: Double, tertiary: Double, quaternary: Double
        /// Card composited over pure black (the colour text actually sits on in the worst-lit case).
        public var cardOverBlack: RGB { RGB(white: cardWhite * cardOpacity) }
    }

    public let variant: Variant
    public let spec: Spec

    // Surfaces
    public var surface: Color { .black }                                         // = hardware notch, never tinted
    public var card: Color { Color(.sRGB, white: spec.cardWhite, opacity: spec.cardOpacity) }   // smoked widget card
    public var cardHover: Color { Color(.sRGB, white: spec.cardHoverWhite, opacity: spec.cardOpacity) }
    public var control: Color { white(spec.control) }                            // buttons, chips, tracks
    public var controlHover: Color { white(spec.controlHover) }
    public var controlPressed: Color { white(spec.controlPressed) }              // pressed + selected segment/row
    public var well: Color { white(spec.well) }                                  // inset text fields
    public var scrim: Color { Color(.sRGB, white: 0, opacity: spec.scrim) }      // under text placed directly on light
    // Lines
    public var hairline: Color { white(spec.hairline) }                          // card edge, flat-style dividers
    public var stroke: Color { white(spec.stroke) }                              // outlines, idle dashed drop zones
    public var keyline: Color { white(spec.keyline) }                            // rim of peek/open (× openness)
    // Text & glyphs
    public var label: Color { white(spec.label) }
    public var secondaryLabel: Color { white(spec.secondary) }
    public var tertiaryLabel: Color { white(spec.tertiary) }
    public var quaternaryLabel: Color { white(spec.quaternary) }                 // placeholders / disabled only
    // Semantic (dark-appearance values; accessible variants under Increase Contrast)
    public var success: Color { SemanticColor.success.rgb(variant == .highContrast).color }
    public var warning: Color { SemanticColor.warning.rgb(variant == .highContrast).color }
    public var danger: Color { SemanticColor.danger.rgb(variant == .highContrast).color }
    public var info: Color { SemanticColor.info.rgb(variant == .highContrast).color }
    public var caution: Color { SemanticColor.caution.rgb(variant == .highContrast).color }
    // Prominent controls: the ONE primary action of a card is filled white with black content (icon buttons, chips)
    public var prominentFill: Color { .white }
    public var onProminent: Color { .black }

    private func white(_ a: Double) -> Color { Color(.sRGB, white: 1, opacity: a) }

    public static func make(_ v: Variant) -> CrannyPalette {
        switch v {
        case .standard:
            return .init(variant: v, spec: .init(
                cardWhite: 0.10, cardOpacity: 0.80, cardHoverWhite: 0.15,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 0.55, hairline: 0.10, stroke: 0.24, keyline: 0.14,
                label: 1.0, secondary: 0.70, tertiary: 0.55, quaternary: 0.32))
        case .lit:
            return .init(variant: v, spec: .init(
                cardWhite: 0.10, cardOpacity: 0.88, cardHoverWhite: 0.15,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 0.62, hairline: 0.12, stroke: 0.26, keyline: 0.18,
                label: 1.0, secondary: 0.76, tertiary: 0.62, quaternary: 0.36))
        case .highContrast:
            return .init(variant: v, spec: .init(
                cardWhite: 0.14, cardOpacity: 1.0, cardHoverWhite: 0.20,
                control: 0.20, controlHover: 0.26, controlPressed: 0.32, well: 0.12,
                scrim: 0.80, hairline: 0.34, stroke: 0.62, keyline: 0.45,
                label: 1.0, secondary: 0.86, tertiary: 0.74, quaternary: 0.50))
        case .opaque:
            return .init(variant: v, spec: .init(
                cardWhite: 0.09, cardOpacity: 1.0, cardHoverWhite: 0.13,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 1.0, hairline: 0.12, stroke: 0.26, keyline: 0.16,
                label: 1.0, secondary: 0.70, tertiary: 0.55, quaternary: 0.32))
        }
    }
}

/// Semantic colours mean only what they mean on iOS. Never decorative.
public nonisolated enum SemanticColor: String, CaseIterable, Sendable {
    case success    // charging, Join, done, "live" (meeting in progress)
    case warning    // timer (iOS convention), last minute, ≤ 20 % battery
    case danger     // ≤ 10 % battery, failed pipeline, destructive
    case info       // links, AirDrop, Bluetooth
    case caution    // Low Power Mode, brightness (coloured HUD)

    public func rgb(_ highContrast: Bool) -> RGB {
        switch self {
        case .success: RGB(hex: highContrast ? 0x30DB5B : 0x30D158)
        case .warning: RGB(hex: highContrast ? 0xFFB340 : 0xFF9F0A)
        case .danger:  RGB(hex: highContrast ? 0xFF6961 : 0xFF453A)
        case .info:    RGB(hex: highContrast ? 0x70B7FF : 0x409CFF)
        case .caution: RGB(hex: highContrast ? 0xFFD426 : 0xFFD60A)
        }
    }
}

/// Brand ramp "Afterglow": app icon, onboarding, About, and the fallback ambient palette.
public nonisolated enum BrandColor {
    public static let mint     = RGB(hex: 0x9EFFEB)
    public static let lagoon   = RGB(hex: 0x2ED3C6)
    public static let sky      = RGB(hex: 0x54C7F2)
    public static let iris     = RGB(hex: 0x8B6CFF)
    public static let rose     = RGB(hex: 0xFF4F8B)
    public static let ember    = RGB(hex: 0xFF7A45)
    public static let night    = RGB(hex: 0x0B0A14)
    public static let graphite = RGB(hex: 0x1E2026)
}

// MARK: - Accent

/// Settings ▸ Appearance ▸ Accent. One accent at a time, for state and progress only
/// (scrubber, rings, visualizer, toggles, focus ring, armed drop target) — never body
/// text, never large fills, never anything with a semantic meaning.
public nonisolated enum AccentSource: Codable, Hashable, Sendable {
    case automatic              // album art while media plays, otherwise the system accent (default)
    case system                 // NSColor.controlAccentColor, lifted for black
    case swatch(AccentSwatch)   // curated, all ≥ 7:1 on black
    case monochrome             // white only ("disable colours")
}

public nonisolated enum AccentSwatch: String, CaseIterable, Codable, Sendable {
    case blue, teal, green, yellow, orange, pink, purple, graphite
    public var rgb: RGB {
        switch self {
        case .blue:     RGB(hex: 0x5CA8FF)
        case .teal:     RGB(hex: 0x4FD1C4)
        case .green:    RGB(hex: 0x66D487)
        case .yellow:   RGB(hex: 0xF5C452)
        case .orange:   RGB(hex: 0xFF9E5C)
        case .pink:     RGB(hex: 0xFF80B5)
        case .purple:   RGB(hex: 0xB89EFF)
        case .graphite: RGB(hex: 0xC7C7CC)
        }
    }
}

public nonisolated enum AccentResolver {
    /// The accent actually drawn. Guarded against the darkest surface it sits on (a card over
    /// black): ≥ 4.5:1, or ≥ 7:1 with Increase Contrast.
    public static func resolve(_ source: AccentSource, albumAccent: RGB?, systemAccent: RGB,
                               palette: CrannyPalette.Spec, increaseContrast: Bool) -> RGB {
        let raw: RGB = switch source {
        case .automatic: albumAccent ?? systemAccent
        case .system: systemAccent
        case .swatch(let s): s.rgb
        case .monochrome: .white
        }
        return raw.legible(on: palette.cardOverBlack, ratio: increaseContrast ? 7 : 4.5)
    }

    /// `NSColor.controlAccentColor` resolved in Dark appearance (Graphite stays grey).
    @MainActor public static func systemAccent() -> RGB {
        var out = RGB(hex: 0x0A84FF)
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            if let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                out = RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            }
        }
        return out
    }
}

// MARK: - Notes code mode

/// Syntax palette for Notes "code mode" (Markdown + common languages). Each ≥ 4.5:1 on `card`.
public nonisolated enum SyntaxPalette {
    public static let keyword  = RGB(hex: 0xFF7AB8)
    public static let type     = RGB(hex: 0x62D6FF)
    public static let string   = RGB(hex: 0xFF9466)
    public static let number   = RGB(hex: 0xE8C66C)
    public static let function = RGB(hex: 0xA6E37A)
    public static let link     = RGB(hex: 0x6BB3FF)
    /// Comments use `tertiaryLabel` + italic; headings use `label` + semibold.
}
```

### 2.2 Typography

SF Pro is used for words. **SF Pro Rounded with monospaced digits** is used for live numbers, so countdowns never jitter, and SF Mono for code. Nothing is ever smaller than 10 pt. macOS gives third-party apps no Dynamic Type, so Cranny ships its own **Text size** setting: Small 0.92 · Standard 1.0 · Large 1.12 · Extra Large 1.24. It scales every Nook and peek style **and grows the grid cell** (§2.3). Band styles scale with the notch unit instead, because the band is hardware height.

| Style | Size / weight / design | Line | Digits | Use |
|---|---|---|---|---|
| `display` | 28 semibold rounded, −0.3 | 32 | mono | Focused timer, big numbers in a peek |
| `numeral` | 22 semibold rounded, −0.2 | 26 | mono | Timer ring, battery % in peek, calendar date |
| `title` | 15 semibold, −0.1 | 20 | | Track title, event title, peek primary line |
| `headline` | 13 semibold | 16 | | Widget headers, tabs, note title |
| `body` | 13 regular | 17 | | Notes, to-dos: the minimum size for sentences |
| `callout` | 12 regular | 15 | | Artist, secondary lines |
| `caption` | 11 medium, +0.1 | 14 | mono | Times, metadata, file names, chips |
| `eyebrow` | 11 semibold, +0.2, sentence case | 13 | | Section labels ("Up next") |
| `micro` | 10 semibold rounded, +0.6, UPPERCASE | 12 | mono | Weekday "TUE", "LIVE", badges, counts (≤ 4 characters) |
| `compact` | 13 semibold rounded (× unit) | 16 | mono | Values in the band: "4:59", "82%" |
| `compactLabel` | 12 medium rounded (× unit) | 14 | mono | Short labels in the band: "in 4m" |
| `code` | 12 regular SF Mono | 16 | mono | Notes code mode |

Rules:
- Changing numbers use `.contentTransition(.numericText(countsDown:))` (or `(value:)`).
- Titles are a single line with tail truncation; file names truncate in the middle.
- In the Nook, an overflowing track title marquees after a 1.5 s hover: **one pass** to its end and back (30 pt/s, a 1-s pause at the end), then it rests until the next hover or a new title. That is the only marquee anywhere; nothing loops, and it never runs under Reduce Motion or Motion ▸ Instant (it truncates, and a `.help` tooltip shows the full title).
- Settings and onboarding use system text styles (`.body`, `.title2`, …), not these tokens.

```swift
// CrannyCore/DesignSystem/Typography.swift
// SF Pro for words, SF Pro Rounded with monospaced digits for live numbers, SF Mono for code.
// macOS has no Dynamic Type for third-party UI, so Cranny ships its own Text Size setting.
import SwiftUI

/// Settings ▸ Appearance ▸ Text size. Scales every Nook/peek style AND grows the grid cell.
public nonisolated enum CrannyTextSize: String, CaseIterable, Codable, Sendable {
    case small, standard, large, extraLarge
    public var scale: CGFloat {
        switch self {
        case .small: 0.92
        case .standard: 1
        case .large: 1.12
        case .extraLarge: 1.24
        }
    }
}

public nonisolated enum CrannyTextStyle: String, CaseIterable, Sendable {
    case display       // 28 semibold rounded, mono digits — focused timer, big peek numbers
    case numeral       // 22 semibold rounded, mono digits — timer ring, calendar date, battery % in peek
    case title         // 15 semibold — track title, event title, peek primary line
    case headline      // 13 semibold — widget headers, tabs, note title
    case body          // 13 regular — notes, to-dos (minimum size for sentences)
    case callout       // 12 regular — artist, secondary lines
    case caption       // 11 medium, mono digits — times, metadata, file names, chips
    case eyebrow       // 11 semibold, sentence case — section labels ("Up next")
    case micro         // 10 semibold rounded, UPPERCASE — weekday "TUE", badges (≤ 4 characters)
    case compact       // 13 semibold rounded, mono digits — values in the band ("4:59", "82%")
    case compactLabel  // 12 medium rounded, mono digits — short labels in the band ("in 4m")
    case code          // 12 regular SF Mono — Notes code mode

    public nonisolated enum Scaling: Sendable { case textSize, notchUnit }

    public nonisolated struct Spec: Equatable, Sendable {
        public let size: CGFloat
        public let weight: Font.Weight
        public let design: Font.Design
        public let lineHeight: CGFloat
        public let tracking: CGFloat
        public let monoDigits: Bool
        public let uppercase: Bool
    }

    public var spec: Spec {
        switch self {
        case .display:      Spec(size: 28, weight: .semibold, design: .rounded,    lineHeight: 32, tracking: -0.3, monoDigits: true,  uppercase: false)
        case .numeral:      Spec(size: 22, weight: .semibold, design: .rounded,    lineHeight: 26, tracking: -0.2, monoDigits: true,  uppercase: false)
        case .title:        Spec(size: 15, weight: .semibold, design: .default,    lineHeight: 20, tracking: -0.1, monoDigits: false, uppercase: false)
        case .headline:     Spec(size: 13, weight: .semibold, design: .default,    lineHeight: 16, tracking: 0,    monoDigits: false, uppercase: false)
        case .body:         Spec(size: 13, weight: .regular,  design: .default,    lineHeight: 17, tracking: 0,    monoDigits: false, uppercase: false)
        case .callout:      Spec(size: 12, weight: .regular,  design: .default,    lineHeight: 15, tracking: 0,    monoDigits: false, uppercase: false)
        case .caption:      Spec(size: 11, weight: .medium,   design: .default,    lineHeight: 14, tracking: 0.1,  monoDigits: true,  uppercase: false)
        case .eyebrow:      Spec(size: 11, weight: .semibold, design: .default,    lineHeight: 13, tracking: 0.2,  monoDigits: false, uppercase: false)
        case .micro:        Spec(size: 10, weight: .semibold, design: .rounded,    lineHeight: 12, tracking: 0.6,  monoDigits: true,  uppercase: true)
        case .compact:      Spec(size: 13, weight: .semibold, design: .rounded,    lineHeight: 16, tracking: 0,    monoDigits: true,  uppercase: false)
        case .compactLabel: Spec(size: 12, weight: .medium,   design: .rounded,    lineHeight: 14, tracking: 0,    monoDigits: true,  uppercase: false)
        case .code:         Spec(size: 12, weight: .regular,  design: .monospaced, lineHeight: 16, tracking: 0,    monoDigits: true,  uppercase: false)
        }
    }

    /// Band styles must fit the hardware row, so they scale with the notch unit (display
    /// scaling), never with Text Size. Everything else follows Text Size.
    public var scaling: Scaling { self == .compact || self == .compactLabel ? .notchUnit : .textSize }

    public func pointSize(textSize: CrannyTextSize, notchUnit: CGFloat) -> CGFloat {
        let k = scaling == .notchUnit ? notchUnit : textSize.scale
        return max((spec.size * k).rounded(), 10)          // nothing is ever smaller than 10 pt
    }

    public func font(textSize: CrannyTextSize = .standard, notchUnit: CGFloat = 1) -> Font {
        let s = spec
        let f = Font.system(size: pointSize(textSize: textSize, notchUnit: notchUnit), weight: s.weight, design: s.design)
        return s.monoDigits ? f.monospacedDigit() : f
    }
}

public struct CrannyFontModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    public let style: CrannyTextStyle
    public init(_ style: CrannyTextStyle) { self.style = style }

    public func body(content: Content) -> some View {
        let s = style.spec
        let size = style.pointSize(textSize: theme.textSize, notchUnit: theme.notchUnit)
        let lineHeight = s.lineHeight * size / s.size
        content
            .font(style.font(textSize: theme.textSize, notchUnit: theme.notchUnit))
            .tracking(s.tracking)
            .lineSpacing(max(0, lineHeight - size * 1.2))
            .textCase(s.uppercase ? .uppercase : nil)
    }
}

public extension View {
    /// `Text(track.title).crannyFont(.title)` — font, tracking, line height and case in one call.
    func crannyFont(_ style: CrannyTextStyle) -> some View { modifier(CrannyFontModifier(style)) }
}

// MARK: - SF Symbol glyph styles (DESIGN.md §14.1 "Rendering")

/// How an SF Symbol is drawn where it is not inside a button style (which sizes its own glyph) or next to text
/// (which takes the text's `crannyFont`). Band glyphs scale with the notch unit, like the band text styles; Nook
/// glyphs follow Text Size.
public nonisolated enum CrannySymbolStyle: String, CaseIterable, Sendable {
    case band          // 13 semibold × notch unit — one glyph in a compact wing (now playing, charging, flash)
    case nook          // 13 medium × text size — a glyph inside the open Nook
    case peekVisual    // 18 semibold × text size — a glyph filling the 40-pt visual of a peek row
    case widgetState   // 20 medium × text size — the glyph of an empty / permission / error state (§6.8)
    case dropZone      // 22 medium × text size — the glyph of a drop zone (Tray, AirDrop, pipelines)

    /// Point size before scaling, and weight.
    public var spec: (size: CGFloat, weight: Font.Weight) {
        switch self {
        case .band: (13, .semibold)
        case .nook: (13, .medium)
        case .peekVisual: (18, .semibold)
        case .widgetState: (20, .medium)
        case .dropZone: (22, .medium)
        }
    }

    /// `.band` scales with the notch unit (the band is hardware height); everything else with Text Size.
    public var scaling: CrannyTextStyle.Scaling { self == .band ? .notchUnit : .textSize }

    /// The scaled point size (never below 10 pt).
    public func pointSize(textSize: CrannyTextSize, notchUnit: CGFloat) -> CGFloat {
        let k = scaling == .notchUnit ? notchUnit : textSize.scale
        return max((spec.size * k).rounded(), 10)
    }

    /// The symbol font at that size.
    public func font(textSize: CrannyTextSize = .standard, notchUnit: CGFloat = 1) -> Font {
        .system(size: pointSize(textSize: textSize, notchUnit: notchUnit), weight: spec.weight)
    }
}

public struct CrannySymbolModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    public let style: CrannySymbolStyle
    public init(_ style: CrannySymbolStyle) { self.style = style }
    public func body(content: Content) -> some View {
        content.font(style.font(textSize: theme.textSize, notchUnit: theme.notchUnit))
    }
}

public extension View {
    /// `Image(systemName: "bolt.fill").crannySymbol(.band)` — the glyph's size and weight from the theme.
    func crannySymbol(_ style: CrannySymbolStyle) -> some View { modifier(CrannySymbolModifier(style)) }
}
```

### 2.3 Spacing, radii, strokes, hit targets, elevation, glow, grid

- **Spacing:** a 4-pt grid with 2/6-pt half steps: 2 · 4 · 6 · 8 · 12 · 16 · 20 · 24 · 32.
- **Radii:** always `.continuous` and always concentric (inner = outer − inset):
  - panel 32 → card 20 → inner 8;
  - peek 22 → peek artwork 10;
  - tile 12, chip 6, rounded button 8, key cap 4;
  - band-anchored radii (closed 10u, hover 12u, compact 13u, ears 4–10u) live in `NotchLayout`.
  - On macOS 26+, inner shapes may use `ConcentricRectangle()` inside a card's `.containerShape(...)`.
- **Strokes:**
  - hairline = exactly 1 device pixel; regular and keyline 1;
  - dashed drop zone 1.5 with dash [5, 4]; focus ring 2;
  - scrubber 4 (6 while hovered or dragged), HUD bar 6;
  - rings: 2.5 in the band, 5 in widgets.
- **Hit targets:** at least 28 × 24 inside the Nook and 32 × 24 for embedded controls in the band. The macOS minimum is 20. A button's hit area is its own frame, so a smaller visual (the 22-pt chip, a 24-pt icon button's well, a text link) gets its room inside the button style (`CrannyChipButtonStyle`, `CrannyIconButtonStyle`, `CrannyLinkButtonStyle`) or its label; a frame or content shape added outside a `Button` or `Menu` does not widen it. An icon button whose well is smaller than 28 × 24 (the Timer's ring buttons, the Notes header) draws the well centred in a button of at least 28 × 24 that takes clicks over its whole frame; 28- and 32-pt icon buttons keep their size and their shaped hit area.
- **Elevation:**
  - none for closed and compact (a shadow would reveal the seam);
  - peek: two layers (22 % r 1.5 y 1, and 28 % r 14 y 6);
  - open: two layers (25 % r 2 y 1, and 35 % r 28 y 12), scaled by openness;
  - a dragged tray tile uses 50 % r 12 y 6.
  - The canvas keeps a 48-pt transparent margin.
- **Glow:**
  - album halo 30 % at r 36;
  - underglow 30 % at r 36, y 10 (Vivid only, drawn as a coloured shadow);
  - alpha caps for the light layer: Subtle 0.45, Vivid 0.80; maximum glow brightness 0.95.

| Density | cell | gutter | padding | card padding | panel r | card r | inner r | Open, 10 cells (14″) | Max columns (14″) |
|---|---|---|---|---|---|---|---|---|---|
| Compact | 52 | 6 | 10 | 10 | 30 | 20 | 10 | 594 × 158 | 14 |
| **Standard** | **56** | **8** | **12** | **12** | **32** | **20** | **8** | **656 × 170** | **12** |
| Roomy | 64 | 10 | 14 | 12 | 34 | 20 | 8 | 758 × 190 | 10 |
| Standard at XL text | 68 | 8 | 12 | 12 | 32 | 20 | 8 | 776 × 194 | 10 |

```swift
// CrannyCore/DesignSystem/Layout.swift
// Spacing, radii, strokes, hit targets, elevation, glow and the Nook cell grid.
import SwiftUI

/// 4-pt grid with 2/6-pt half steps for optical tweaks.
public nonisolated enum Space {
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

/// Always `.continuous`. Nested radii are concentric: inner = outer − inset.
/// Notch-anchored radii (closed, hover, compact, ears) live in `NotchLayout` and scale with `unit`.
public nonisolated enum Radius {
    public static let panel: CGFloat = 32        // open Nook bottom corners (Standard density)
    public static let peek: CGFloat = 22         // peek / quick-peek bottom corners
    public static let card: CGFloat = 20         // = panel − padding (all densities)
    public static let inner: CGFloat = 8         // = card − card padding: artwork, wells, thumbnails
    public static let tile: CGFloat = 12         // 56-pt launcher hover well
    public static let artPeek: CGFloat = 10      // 40-pt artwork in a peek row (22 − 12)
    public static let artCompact: CGFloat = 5    // 20-pt artwork in the band (× unit)
    public static let control: CGFloat = 8       // "Rounded" button shape
    public static let chip: CGFloat = 6
    public static let keycap: CGFloat = 4
    public static let focusRingOutset: CGFloat = 3

    public static func concentric(_ outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
        max(outer - inset, minimum)
    }
}

public nonisolated enum StrokeWidth {
    /// Exactly one device pixel (0.5 pt on Retina).
    public static func hairline(_ displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) }
    public static let regular: CGFloat = 1
    public static let keyline: CGFloat = 1
    public static let emphasis: CGFloat = 1.5         // dashed drop zones
    public static let dash: [CGFloat] = [5, 4]
    public static let focus: CGFloat = 2              // keyboard focus ring (accent)
    public static let scrubber: CGFloat = 4           // 6 while hovered or dragged
    public static let scrubberActive: CGFloat = 6
    public static let hudBar: CGFloat = 6
    public static let ringCompact: CGFloat = 2.5      // rings in the band
    public static let ring: CGFloat = 5               // rings in widgets (timer)
}

/// Minimum interactive sizes (macOS minimum is 20 × 20).
public nonisolated enum HitTarget {
    public static let nook = CGSize(width: 28, height: 24)       // any control inside the Nook
    public static let band = CGSize(width: 32, height: 24)       // embedded controls in compact (Join, ⏯)
    public static let preferred: CGFloat = 28
}

// MARK: - Elevation & glow

public nonisolated struct CrannyShadow: Equatable, Sendable {
    public let opacity: Double, radius: CGFloat, y: CGFloat
    public init(opacity: Double, radius: CGFloat, y: CGFloat) { self.opacity = opacity; self.radius = radius; self.y = y }
    public static let none = CrannyShadow(opacity: 0, radius: 0, y: 0)
}

/// Closed and compact have NO shadow: the shape is part of the bezel and a shadow would reveal
/// the seam. SwiftUI `.shadow` pixels are click-through for the window server (R1 §4.1).
public nonisolated enum Elevation {
    public static let peek: [CrannyShadow] = [.init(opacity: 0.22, radius: 1.5, y: 1), .init(opacity: 0.28, radius: 14, y: 6)]
    public static let open: [CrannyShadow] = [.init(opacity: 0.25, radius: 2, y: 1), .init(opacity: 0.35, radius: 28, y: 12)]
    public static let lifted: [CrannyShadow] = [.init(opacity: 0.50, radius: 12, y: 6)]     // dragged tray tile
    /// Transparent margin the fixed canvas keeps around the largest shape (shadow + underglow).
    public static let canvasMargin: CGFloat = 48
}

public nonisolated enum Glow {
    /// Halo behind artwork in the Media widget and peek (album accent).
    public static let albumHaloOpacity: Double = 0.30
    public static let albumHaloRadius: CGFloat = 36
    /// Coloured light spilling onto the desktop below the open Nook. Vivid only; drawn as a
    /// coloured `.shadow` so it stays click-through.
    public static let underglow = CrannyShadow(opacity: 0.30, radius: 36, y: 10)
    /// Hard caps that the contrast audit assumes. Effects must clamp to these.
    public static let maxBrightness: Double = 0.95
    public static func ambientAlphaCap(_ level: AmbienceLevel) -> Double {
        switch level {
        case .off: 0
        case .subtle: 0.45
        case .vivid: 0.80
        }
    }
}

public extension View {
    /// Two-layer elevation, scaled by `amount` (0 closed … 1 open).
    func crannyElevation(_ layers: [CrannyShadow], amount: Double = 1) -> some View {
        let a = layers.first ?? .none
        let b = layers.count > 1 ? layers[1] : .none
        return self
            .shadow(color: .black.opacity(a.opacity * amount), radius: a.radius, x: 0, y: a.y * amount)
            .shadow(color: .black.opacity(b.opacity * amount), radius: b.radius, x: 0, y: b.y * amount)
    }
}

// MARK: - Buttons

/// Settings ▸ Appearance ▸ Buttons.
public nonisolated enum ButtonShapeStyle: String, CaseIterable, Codable, Sendable { case capsule, rounded }

public nonisolated struct CrannyButtonShape: Shape {
    public var style: ButtonShapeStyle
    public init(_ style: ButtonShapeStyle) { self.style = style }
    public func path(in r: CGRect) -> Path {
        let radius = style == .capsule ? min(r.width, r.height) / 2 : Radius.control
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r)
    }
}

// MARK: - The Nook grid

/// Settings ▸ Appearance ▸ Density.
public nonisolated enum NookDensity: String, CaseIterable, Codable, Sendable {
    case compact, standard, roomy
    public var cell: CGFloat { switch self { case .compact: 52; case .standard: 56; case .roomy: 64 } }
    public var gutter: CGFloat { switch self { case .compact: 6; case .standard: 8; case .roomy: 10 } }
    public var padding: CGFloat { switch self { case .compact: 10; case .standard: 12; case .roomy: 14 } }
    public var cardPadding: CGFloat { switch self { case .compact: 10; case .standard: 12; case .roomy: 12 } }
    /// Panel radius per density keeps the CARD radius at 20 everywhere (concentric).
    public var panelRadius: CGFloat { Radius.card + padding }
}

/// Settings ▸ Appearance ▸ Widgets: smoked cards (default) or flat with hairline dividers.
public nonisolated enum WidgetStyle: String, CaseIterable, Codable, Sendable { case cards, flat }

public nonisolated struct NookGrid: Equatable, Sendable {
    public var density: NookDensity
    public var textSize: CrannyTextSize
    public var style: WidgetStyle
    public var rows: Int
    /// Settings ▸ Appearance ▸ Panel padding (±4 pt on top of the density). Radii stay concentric.
    public var paddingTune: CGFloat

    public init(density: NookDensity = .standard, textSize: CrannyTextSize = .standard,
                style: WidgetStyle = .cards, rows: Int = 2, paddingTune: CGFloat = 0) {
        self.density = density; self.textSize = textSize; self.style = style; self.rows = rows
        self.paddingTune = min(max(paddingTune, -4), 4)
    }

    /// Larger text grows the cell (rounded to 4 pt), so content never clips.
    public var cell: CGFloat { (density.cell * max(textSize.scale, 1) / 4).rounded() * 4 }
    /// Flat style puts a 1-px divider in the middle of a double gutter.
    public var gutter: CGFloat { style == .flat ? density.gutter * 2 + 1 : density.gutter }
    public var padding: CGFloat { density.padding + paddingTune }
    public var headerGap: CGFloat { 6 }
    public var panelRadius: CGFloat { Radius.card + padding }    // = density.panelRadius when the tune is 0
    public var cardRadius: CGFloat { Radius.concentric(panelRadius, inset: padding) }
    public var innerRadius: CGFloat { Radius.concentric(cardRadius, inset: density.cardPadding) }

    public func width(cells n: Int) -> CGFloat { CGFloat(n) * cell + CGFloat(max(n - 1, 0)) * gutter }
    public var height: CGFloat { CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gutter }
}
```

### 2.4 Theme and environment

```swift
// CrannyCore/DesignSystem/Theme.swift
// One environment value. Feature modules read `@Environment(\.cranny)` and never
// write literal colours, sizes, radii or animations, and never read raw a11y flags.
import SwiftUI

/// Settings ▸ Appearance ▸ Ambient light (the optional "Afterglow" layer, DESIGN.md §5).
public nonisolated enum AmbienceLevel: String, CaseIterable, Codable, Sendable, Comparable {
    case off, subtle, vivid
    public var intensity: Double { switch self { case .off: 0; case .subtle: 0.55; case .vivid: 1 } }
    private var rank: Int { switch self { case .off: 0; case .subtle: 1; case .vivid: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public nonisolated enum AmbientEffect: String, CaseIterable, Codable, Sendable {
    case aurora   // MeshGradient (15+) / Canvas curtains (14) — default
    case motes    // slow rising specks
    case tide     // luminous wave lines along the bottom edge
    case halo     // one static bloom (Low Power Mode fallback)
}

public nonisolated struct CrannyTheme: Equatable, Sendable {
    // User settings
    public var accent: RGB = RGB(hex: 0x409CFF)        // already resolved by AccentResolver
    public var textSize: CrannyTextSize = .standard
    public var density: NookDensity = .standard
    public var widgetStyle: WidgetStyle = .cards
    public var buttonShape: ButtonShapeStyle = .capsule
    public var panelPaddingTune: CGFloat = 0               // ±4 pt (Appearance ▸ Panel padding)
    public var motion: MotionPersonality = .standard
    public var ambience: AmbienceLevel = .subtle
    public var effect: AmbientEffect = .aurora
    public var translucentBackground = false
    public var glassIsland = false                       // Liquid Glass island (26+); set by the panel only on floating-style displays
    public var hapticsEnabled = true
    public var notchUnit: CGFloat = 1
    // System state — resolved by CrannyThemeRoot, never set by features
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    public var differentiateWithoutColor = false
    public var voiceOverRunning = false

    public init() {}

    public var effectiveAmbience: AmbienceLevel {
        if reduceTransparency { return .off }
        if increaseContrast || widgetStyle == .flat { return min(ambience, .subtle) }
        return ambience
    }
    public var paletteVariant: CrannyPalette.Variant {
        if increaseContrast { return .highContrast }
        if reduceTransparency { return .opaque }
        if effectiveAmbience == .vivid || glassIsland { return .lit }
        return .standard
    }
    public var palette: CrannyPalette { .make(paletteVariant) }
    public var grid: NookGrid { NookGrid(density: density, textSize: textSize, style: widgetStyle, paddingTune: panelPaddingTune) }
    public var accentColor: Color { accent.color }
    public var accentContrast: Double { increaseContrast ? 7 : 4.5 }
    public var allowsUnderglow: Bool { effectiveAmbience == .vivid }

    public func animation(_ k: CrannyMotion.Kind) -> Animation? {
        CrannyMotion.animation(k, personality: motion, reduceMotion: reduceMotion)
    }

    /// Symbols may animate (DESIGN.md §14.1: no symbol effects under Reduce Motion; §4.2: none under Instant).
    public var animatesSymbols: Bool { !reduceMotion && motion != .instant }
    /// The content transition of a glyph that toggles (pin, play/pause, the HUD glyph):
    /// `.contentTransition(theme.symbolReplace)` — `.symbolEffect(.replace)`, or `.identity` when symbols must not move.
    public var symbolReplace: ContentTransition { animatesSymbols ? .symbolEffect(.replace) : .identity }
}

public extension EnvironmentValues {
    @Entry var cranny: CrannyTheme = CrannyTheme()
}

/// Apply once at the root of every Cranny surface (notch panel, Settings preview stage,
/// onboarding stage). Merges user settings with the live system accessibility state.
public struct CrannyThemeRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    public var base: CrannyTheme
    public init(_ base: CrannyTheme) { self.base = base }

    public func body(content: Content) -> some View {
        var t = base
        t.reduceMotion = base.reduceMotion || reduceMotion
        t.reduceTransparency = base.reduceTransparency || reduceTransparency
        t.increaseContrast = base.increaseContrast || contrast == .increased
        t.differentiateWithoutColor = base.differentiateWithoutColor || differentiateWithoutColor
        t.voiceOverRunning = base.voiceOverRunning || voiceOver
        t.accent = t.accent.legible(on: t.palette.spec.cardOverBlack, ratio: t.accentContrast)
        return content
            .environment(\.cranny, t)
            .environment(\.colorScheme, .dark)     // the notch is always dark
            .tint(t.accent.color)
    }
}

public extension View {
    func crannyThemeRoot(_ theme: CrannyTheme) -> some View { modifier(CrannyThemeRoot(theme)) }
}
```

---

## 3. Geometry and the NotchShape

### 3.1 Measuring the hardware

- **Notch width** = `screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`. Use only the widths; the coordinate space of those rects is undocumented. **Band height** = `safeAreaInsets.top`.
- **No notch:** the band is the menu bar.
  1. Use `frame.maxY − visibleFrame.maxY` when it is > 0.
  2. Otherwise use the height of the Window Server layer-24 menu-bar window (R1).
  3. Fall back to 30.

  Never use `NSStatusBar.thickness` (it reports a stale 22; the menu bar is 30 pt on macOS 27).
- **Re-measure** on `NSApplication.didChangeScreenParametersNotification`. Display scaling changes the notch's size in points.
- **Unit:** `u = clamp(band / 32, 0.8, 1.25)`. Every band-anchored value (slots, band radii, ears, `compact` text) is multiplied by `u`. Nook content is not.
- **Fine-tune:** Settings ▸ Appearance ▸ **Notch fit**. Width ±10 pt in 0.5-pt steps (an `.alignment` haptic detent at 0), bottom radius ±3 pt.
  - While a slider is dragged, the real notch freezes in hover and shows a 1-px accent outline of the closed shape over the hardware, magnified 2× in a loupe.
  - Stored per display model.

### 3.2 One shape, six numbers

`NotchGeometry` holds `bodyWidth`, `height`, `bottomRadius`, `earRadius`, `topRadius` and `topInset`. It is itself `VectorArithmetic`, so it *is* the shape's `animatableData`, and one spring moves all six numbers together; the outline can never wobble out of sync.
- **Ears** are the concave flares where the top edge meets the screen. They grow 0 → 4u → 6u → 8u → 10u from closed to open, swelling like a meniscus during a morph, and fade out over the first 2 pt of `topInset`. Attached ⇄ floating is therefore a single morph.
- **Bottom corners** (and floating top corners) are Apple's continuous curve via `UnevenRoundedRectangle(style: .continuous)`.
- **Ears** are quarter-circle cubics with a 0.5-pt overlap, **unioned** (`Path.union`, macOS 14) into one outline. That means no anti-aliasing seam and a strokable keyline.
- **Cost:** measured at 0.64 µs per interpolated path (release), so animating it is free.
- **Fixed canvas:** the panel never resizes during a morph. Content is laid out at its final size, top-centred, and revealed by `clipShape(NotchShape(...))`.

```swift
// CrannyCore/DesignSystem/Notch.swift
// One shape, six animatable numbers, every state. The canvas window never resizes;
// only `NotchShape.animatableData` animates.
import SwiftUI
import AppKit

// MARK: - Measured hardware

public nonisolated struct NotchMetrics: Equatable, Sendable {
    public var hasNotch: Bool
    public var notchWidth: CGFloat     // camera-housing width (0 without a notch)
    public var bandHeight: CGFloat     // notch height on notched displays, else the menu-bar height
    public var screenWidth: CGFloat
    public var displayScale: CGFloat

    public init(hasNotch: Bool, notchWidth: CGFloat, bandHeight: CGFloat, screenWidth: CGFloat, displayScale: CGFloat = 2) {
        self.hasNotch = hasNotch; self.notchWidth = notchWidth; self.bandHeight = bandHeight
        self.screenWidth = screenWidth; self.displayScale = displayScale
    }

    /// 1.0 on a 32-pt notch (14″/16″ MacBook Pro, default scaling). The physical notch is fixed
    /// in pixels, so its height in points encodes display scaling: band-anchored sizes × unit.
    public var unit: CGFloat { min(max(bandHeight / 32, 0.8), 1.25) }

    /// Reference machine used by every table in DESIGN.md.
    public static let reference = NotchMetrics(hasNotch: true, notchWidth: 185, bandHeight: 32, screenWidth: 1512)

    /// Measure — never hard-code. Re-run on `NSApplication.didChangeScreenParametersNotification`.
    @MainActor public static func measure(_ screen: NSScreen) -> NotchMetrics {
        let f = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea,
           l.width > 0, r.width > 0, f.width - l.width - r.width > 0 {
            return NotchMetrics(hasNotch: true, notchWidth: f.width - l.width - r.width, bandHeight: top,
                                screenWidth: f.width, displayScale: screen.backingScaleFactor)
        }
        // No notch: the band is the menu bar. NSStatusBar.thickness is stale (22) — measure the top inset.
        let menuBar = f.maxY - screen.visibleFrame.maxY
        return NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: menuBar > 0 ? menuBar : 30,
                            screenWidth: f.width, displayScale: screen.backingScaleFactor)
    }
}

/// Settings ▸ Appearance ▸ On displays without a notch.
public nonisolated enum NoNotchStyle: String, CaseIterable, Codable, Sendable {
    case floatingIsland   // default: detached pill under the menu bar, all corners round
    case attached         // a small tab hanging from the top edge, with ears (notch look)
    case off              // Cranny does not appear on this display
}

// MARK: - Geometry (animatable)

public nonisolated struct NotchGeometry: VectorArithmetic, Sendable {
    public var bodyWidth: CGFloat      // black body, excluding ears
    public var height: CGFloat         // body height (below topInset)
    public var bottomRadius: CGFloat   // convex, continuous
    public var earRadius: CGFloat      // concave flare into the screen's top edge (attached only)
    public var topRadius: CGFloat      // convex top corners (floating only)
    public var topInset: CGFloat       // 0 = attached to the top edge; > 0 = floating island

    public init(bodyWidth: CGFloat, height: CGFloat, bottomRadius: CGFloat, earRadius: CGFloat,
                topRadius: CGFloat = 0, topInset: CGFloat = 0) {
        self.bodyWidth = bodyWidth; self.height = height; self.bottomRadius = bottomRadius
        self.earRadius = earRadius; self.topRadius = topRadius; self.topInset = topInset
    }

    public static var zero: NotchGeometry { .init(bodyWidth: 0, height: 0, bottomRadius: 0, earRadius: 0) }
    public static func + (a: Self, b: Self) -> Self {
        .init(bodyWidth: a.bodyWidth + b.bodyWidth, height: a.height + b.height, bottomRadius: a.bottomRadius + b.bottomRadius,
              earRadius: a.earRadius + b.earRadius, topRadius: a.topRadius + b.topRadius, topInset: a.topInset + b.topInset)
    }
    public static func - (a: Self, b: Self) -> Self {
        .init(bodyWidth: a.bodyWidth - b.bodyWidth, height: a.height - b.height, bottomRadius: a.bottomRadius - b.bottomRadius,
              earRadius: a.earRadius - b.earRadius, topRadius: a.topRadius - b.topRadius, topInset: a.topInset - b.topInset)
    }
    public mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        bodyWidth *= k; height *= k; bottomRadius *= k; earRadius *= k; topRadius *= k; topInset *= k
    }
    public var magnitudeSquared: Double {
        Double(bodyWidth * bodyWidth + height * height + bottomRadius * bottomRadius
               + earRadius * earRadius + topRadius * topRadius + topInset * topInset)
    }

    /// Ears fade out over the first 2 pt of detaching, so attached ⇄ floating is one morph.
    public var attachment: CGFloat { max(0, 1 - topInset / 2) }
    public var outerWidth: CGFloat { bodyWidth + 2 * max(earRadius, 0) * attachment }
    public var bottom: CGFloat { topInset + height }
    public var isFloating: Bool { topInset > 0.5 }
}

// MARK: - Shape

/// Centred horizontally in its rect and top-aligned. Host it in the FIXED canvas.
/// Bottom (and floating top) corners use Apple's continuous curve via `UnevenRoundedRectangle`;
/// the ears are quarter-circle cubics unioned into ONE outline (macOS 14 `Path.union`), so a
/// stroke (the keyline) never shows an internal seam.
public nonisolated struct NotchShape: Shape {
    public var geometry: NotchGeometry
    public init(_ geometry: NotchGeometry) { self.geometry = geometry }

    public var animatableData: NotchGeometry {
        get { geometry }
        set { geometry = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let g = geometry
        let w = max(g.bodyWidth, 0), h = max(g.height, 0)
        guard w > 0.5, h > 0.5 else { return Path() }
        let body = CGRect(x: rect.midX - w / 2, y: rect.minY + max(g.topInset, 0), width: w, height: h)
        let rb = min(max(g.bottomRadius, 0), h / 2, w / 2)
        let rt = min(max(g.topRadius, 0), h - rb, w / 2)
        let base = UnevenRoundedRectangle(topLeadingRadius: rt, bottomLeadingRadius: rb,
                                          bottomTrailingRadius: rb, topTrailingRadius: rt,
                                          style: .continuous).path(in: body)
        let e = min(max(g.earRadius, 0) * g.attachment, h - rb, body.minX - rect.minX)
        guard e > 0.25 else { return base }

        let k: CGFloat = 0.4477                              // 1 − 0.5523: cubic ≈ quarter circle
        var ears = Path()
        for side in [-1.0, 1.0] as [CGFloat] {
            let x0 = side < 0 ? body.minX : body.maxX       // body edge
            let xo = x0 + side * e                          // ear tip on the screen edge
            let lap = -side * 0.5                           // overlap into the body: no AA seam
            ears.move(to: CGPoint(x: xo, y: body.minY))
            ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY))
            ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY + e))
            ears.addLine(to: CGPoint(x: x0, y: body.minY + e))
            ears.addCurve(to: CGPoint(x: xo, y: body.minY),
                          control1: CGPoint(x: x0, y: body.minY + e * k),
                          control2: CGPoint(x: xo - side * e * (1 - k), y: body.minY))
            ears.closeSubpath()
        }
        return base.union(ears)
    }
}

// MARK: - Compact slots

/// Width of ONE side slot (outer margin 12 + content + 8 gap to the camera), × unit.
/// Both sides always take the wider class, so the camera stays optically centred.
public nonisolated enum SlotWidth: Int, CaseIterable, Comparable, Sendable {
    case none, glyph, short, medium, wide
    public var base: CGFloat {
        switch self {
        case .none: 0
        case .glyph: 40     // 20-pt artwork, a glyph, a 16-pt ring
        case .short: 52     // 5-bar visualizer, "82%"
        case .medium: 68    // "4:59", "in 4m", Join capsule, battery ring + value
        case .wide: 92      // HUD: glyph | level bar 64 (+ optional value)
        }
    }
    public func points(unit: CGFloat) -> CGFloat { (base * unit).rounded() }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Per-state geometry

public nonisolated struct NotchLayout: Equatable, Sendable {
    public var metrics: NotchMetrics
    public var noNotchStyle: NoNotchStyle
    public var widthTune: CGFloat      // Settings ▸ Appearance ▸ Notch fit: −10…+10 pt, 0.5 steps
    public var radiusTune: CGFloat     // −3…+3 pt
    public var grid: NookGrid

    public static let peekRow: CGFloat = 52
    /// The visual at the start of a peek row: artwork, ring or glyph well (DESIGN.md §9.3).
    public static let peekVisual: CGFloat = 40
    public static let satelliteDiameter: CGFloat = 24

    public init(metrics: NotchMetrics, noNotchStyle: NoNotchStyle = .floatingIsland,
                widthTune: CGFloat = 0, radiusTune: CGFloat = 0, grid: NookGrid = NookGrid()) {
        self.metrics = metrics; self.noNotchStyle = noNotchStyle
        self.widthTune = widthTune; self.radiusTune = radiusTune; self.grid = grid
    }

    public var u: CGFloat { metrics.unit }
    public var band: CGFloat { metrics.bandHeight }
    public var isFloating: Bool { !metrics.hasNotch && noNotchStyle == .floatingIsland }
    /// The compact/HUD row: the hardware notch height, or a pill inside the menu bar.
    public var rowHeight: CGFloat { isFloating ? max(band - 6, 22) : band }
    public var rowInset: CGFloat { isFloating ? 3 : 0 }
    /// The Nook header row lives in the band (tabs left of the camera, actions right).
    public var headerHeight: CGFloat { max(band, 28) }

    /// The content-free middle: the camera housing, or a label/gap on displays without a notch.
    public func middle(label: CGFloat = 0) -> CGFloat {
        metrics.hasNotch ? metrics.notchWidth + widthTune : max(label, 12)
    }

    /// CLOSED: exactly the cutout, inset 0.5 pt per side so anti-aliasing never peeks out.
    public var closed: NotchGeometry {
        if metrics.hasNotch {
            let r = min(max((0.30 * band).rounded(), 6), 12) + radiusTune
            return .init(bodyWidth: metrics.notchWidth + widthTune - 1, height: band - 0.5, bottomRadius: r, earRadius: 0)
        }
        switch noNotchStyle {
        case .floatingIsland: return .init(bodyWidth: 64, height: 5, bottomRadius: 2.5, earRadius: 0, topRadius: 2.5, topInset: 4)
        case .attached:       return .init(bodyWidth: 64, height: 5, bottomRadius: 2.5, earRadius: 2)
        case .off:            return .zero
        }
    }

    /// HOVER "breath": acknowledges the dwell before anything opens.
    public var hover: NotchGeometry {
        var g = closed
        if metrics.hasNotch {
            g.bodyWidth += 12 * u; g.height += 3 * u; g.earRadius = 4 * u; g.bottomRadius += 2 * u
        } else if noNotchStyle != .off {
            g.bodyWidth += 24; g.height += 3; g.bottomRadius = g.height / 2
            if isFloating { g.topRadius = g.height / 2 } else { g.earRadius = 3 }
        }
        return g
    }

    /// COMPACT live activity: band height, widened symmetrically by two slots.
    public func compact(_ slot: SlotWidth, label: CGFloat = 0) -> NotchGeometry {
        let w = middle(label: label) + 2 * slot.points(unit: u)
        let h = rowHeight
        if isFloating { return .init(bodyWidth: w, height: h, bottomRadius: h / 2, earRadius: 0, topRadius: h / 2, topInset: rowInset) }
        return .init(bodyWidth: w, height: h, bottomRadius: 13 * u, earRadius: 6 * u)
    }

    /// HUD: the widest compact form. It never adds height, so it never covers content.
    public var hud: NotchGeometry { compact(.wide) }

    /// PEEK: the compact row stays, 52-pt rows grow below it.
    public func peek(rows: Int = 1) -> NotchGeometry {
        let base = metrics.hasNotch ? metrics.notchWidth + widthTune : 180
        let w = min(max(base + 240 * u, 380), 460)
        let h = rowHeight + CGFloat(min(max(rows, 1), 4)) * Self.peekRow + 8
        if isFloating { return .init(bodyWidth: w, height: h, bottomRadius: Radius.peek, earRadius: 0, topRadius: Radius.peek, topInset: rowInset) }
        return .init(bodyWidth: w, height: h, bottomRadius: Radius.peek, earRadius: 8 * u)
    }

    /// OPEN: grid-driven; never narrower than the header needs, never wider than `maxWidth`.
    public func open(columns: Int, rows: Int = 2) -> NotchGeometry {
        var gr = grid; gr.rows = rows
        let cols = min(max(columns, 1), maxColumns)
        let width = min(max(gr.width(cells: cols) + 2 * gr.padding, middle() + 2 * 160), maxWidth)
        let h = headerHeight + gr.headerGap + gr.height + gr.padding
        if isFloating {
            return .init(bodyWidth: width, height: h, bottomRadius: gr.panelRadius, earRadius: 0, topRadius: gr.panelRadius, topInset: 6)
        }
        return .init(bodyWidth: width, height: h, bottomRadius: gr.panelRadius, earRadius: 10 * u)
    }

    /// The Nook never exceeds 55 % of the screen or 880 pt, so menu-bar extras stay reachable.
    public var maxWidth: CGFloat { min(metrics.screenWidth * 0.55, 880) }
    public var maxColumns: Int {
        max(4, Int((maxWidth - 2 * grid.padding + grid.gutter) / (grid.cell + grid.gutter)))
    }

    /// Second concurrent activity: a detached black circle 6u beside the compact body.
    public func satelliteFrame(beside compact: NotchGeometry, in canvas: CGRect) -> CGRect {
        let d = Self.satelliteDiameter * u
        let x = canvas.midX + compact.bodyWidth / 2 + 6 * u
        let y = canvas.minY + rowInset + (rowHeight - d) / 2
        return CGRect(x: x, y: y, width: d, height: d)
    }

    /// Fixed canvas (panel) size: the largest shape (Notes focus = 3 rows) + margins.
    /// Resize it only while closed, when layout settings change (R1 §4.3).
    public var canvasSize: CGSize {
        let o = open(columns: maxColumns, rows: 3)
        return CGSize(width: (o.outerWidth + 2 * Elevation.canvasMargin).rounded(.up),
                      height: (o.bottom + Elevation.canvasMargin).rounded(.up))
    }
}
```

### 3.3 State geometry: reference 14″ MacBook Pro (notch 185 × 32, screen 1512 pt, u = 1)

These numbers are printed by the harness. "Outer W" includes the ears.

| State | Body W × H | Bottom r | Ear | Outer W | Shadow | Keyline | Notes |
|---|---|---|---|---|---|---|---|
| **closed** | 184 × 31.5 | 10 | 0 | 184 | none | none | Cutout −0.5 pt per side; r = clamp(0.30·band, 6, 12) + tune |
| **hover "breath"** | 196 × 34.5 | 12 | 4 | 204 | none | none | Shown during the dwell; tells you it noticed |
| **compact · glyph** | 265 × 32 | 13 | 6 | 277 | none | none | Artwork, a single glyph |
| **compact · short** | 289 × 32 | 13 | 6 | 301 | none | none | Now Playing, charging, low battery |
| **compact · medium** | 321 × 32 | 13 | 6 | 333 | none | none | Timer, meeting, Bluetooth device |
| **HUD (wide)** | 369 × 32 | 13 | 6 | 381 | none | none | Never taller than the band |
| **satellite** | Ø 24 | — | — | — | none | none | 6u beyond the compact body's edge, vertically centred in the band |
| **peek · 1 row** | 425 × 92 | 22 | 8 | 441 | peek | × 1 | Width = clamp(N + 240u, 380, 460); rows of 52 + 8 bottom |
| **peek · 2 rows** | 425 × 144 | 22 | 8 | 441 | peek | × 1 | At most 4 rows |
| **open · 10 cells** (default) | 656 × 170 | 32 | 10 | 676 | open | × 1 | Band 32 + gap 6 + grid 120 + padding 12 |
| **open · 12 cells** (max) | 784 × 170 | 32 | 10 | 804 | open | × 1 | Max = min(55 % of screen, 880) |
| **open · Notes focus** (3 rows) | 784 × 234 | 32 | 10 | 804 | open | × 1 | Temporary; holds the Nook open |
| Canvas (fixed panel) | 900 × 282 | | | | | | Largest shape + 48-pt margins; resized only while closed |

**Other displays** (illustrative; always measured at runtime):

| Display | u | closed | compact · short | HUD | peek | open (10) | Max columns · canvas |
|---|---|---|---|---|---|---|---|
| 16″ MBP (185 × 32, 1728 pt) | 1.0 | 184 × 31.5 | 289 × 32 | 369 × 32 | 425 × 92 | 656 × 170 | 13 · 964 × 282 |
| 13″ Air (185 × 32, 1470 pt) | 1.0 | 184 × 31.5 | 289 × 32 | 369 × 32 | 425 × 92 | 656 × 170 | 12 · 900 × 282 |
| 14″ "Larger Text" (≈ 214 × 37) | 1.156 | 213 × 36.5, r 11 | 334 × 37, r 15 | 426 × 37 | 460 × 97 | 656 × 175 | 11 · 840 × 287 |
| External, **floating island** (menu bar 30) | 0.94 | handle 64 × 5, 4 pt below the edge | 110 × 24 capsule, inset 3 | 184 × 24 | 405 × 84, all corners 22 | 656 × 168, all corners 32, inset 6 | 13 · 944 × 286 |
| External, **attached** (menu bar 30) | 0.94 | tab 64 × 5, ears 2 | 110 × 30, r 12.2, ears 5.6 | 184 × 30 | 405 × 90 | 656 × 168 | 13 · 963 × 280 |

**Slots** (one side; both sides always take the wider class so the camera stays optically centred), × u:

| Class | Width | Content budget (− 12 outer − 8 gap) | Used by |
|---|---|---|---|
| `glyph` | 40 | 20 | 20-pt artwork, a single glyph, a 16-pt ring |
| `short` | 52 | 32 | 5-bar visualizer, "82%" |
| `medium` | 68 | 48 | "4:59", "in 4m" / "4 мин", Join capsule, device battery (12-pt ring + "84%" = 45 pt) |
| `wide` | 92 | 72 | HUD level bar 64 + inset |

### 3.4 Closed equals the hardware

The closed shape is drawn 0.5 pt inside the measured cutout, with a radius slightly larger than the housing's own corner. At rest it is invisible, and the first frame of any morph grows *out of* the camera. This fixes the "close animation does not fit the real notch" and "slides sideways, revealing the real notch" failures: width and height are symmetric about the notch centre, and close has zero bounce.

### 3.5 Displays without a notch

| Setting | Closed | Compact / HUD / peek / open | Notes |
|---|---|---|---|
| **Floating island** (default) | 64 × 5 handle pill, 4 pt below the top edge, all corners round | A pill *inside* the menu-bar band (height band − 6, inset 3, capsule). Peek and open are detached panels with all corners round (22 / 32). | Doesn't pretend to be hardware. Handle: **Visible** (default) or **Hidden until hover** (alpha 0, so it is click-through; hover is geometric). |
| **Attached** | 64 × 5 tab with 2-pt ears, flush with the top edge | Same states as a hardware notch, with a 12-pt (or label-width) virtual middle | For people who like the notch look |
| **Off** | — | — | Cranny does not appear on this display |

- **The middle:** without a camera, the compact middle is a 12-pt gap or a **label** (`compactLabel`, max 160 pt, e.g. the track title). In the open header the empty camera zone shows **time and date** (`eyebrow`, secondary), so the centre is never dead space.
- **Glass island** (macOS 26+, opt-in, floating style only): `Color.clear.glassEffect(.regular.tint(.black.opacity(0.75)), in: shape)` with the `lit` palette, audited at 5.15:1 tertiary over a pure white wallpaper. It is off under Reduce Transparency and Increase Contrast, and on macOS 14/15 it falls back to opaque black.
- **Handle visibility** (Appearance): **Visible** (default) or **Hidden until hover** — the "transparent handle": drawn at alpha 0, so it is click-through, while hover stays geometric and still breathes it in.
- **Hide when idle** (General, off by default; `general.hideHandleWhenIdle` + `general.handleIdleDelay`, default 10 s, range 3–60 s): after that long with no activity and no hover, the handle fades out (`hoverOut`); a swipe up on the handle does the same immediately. The next activity, or the pointer entering the entry zone, brings it back (auto-unhide).

### 3.6 Window and input contract (from R1; the design depends on it)

- **Panels:** one `NSPanel` per display, keyed by display UUID.
  - Style `[.borderless, .nonactivatingPanel]` **passed at init**; level `.statusBar + 1`.
  - Collection behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`.
  - `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded`, `canBecomeKey` → true, `animationBehavior = .none`.
  - `NSHostingView` with `sizingOptions = []` and `safeAreaRegions = []`.
- **Click-through is per pixel.** Never assign `ignoresMouseEvents` (it is tri-state; an explicit `false` captures the whole rectangle).
  - Alpha-0 pixels and SwiftUI `.shadow` pass clicks, moves and drags through. Any drawn pixel, even at alpha 0.001, captures them.
  - Consequences: light outside the shape must be a coloured `.shadow`, and an enlarged drop zone during a file drag is an `opacity(0.001)` fill that is removed afterwards.
- **Hit zones:**
  - Entry: the shape + 4 pt on each side, extended above `frame.maxY` (the pointer's y can equal maxY).
  - Exit while open: the shape + 14 pt, then a 300 ms grace period.
  - File-drag proximity: the shape + 80 pt wide and 40 pt below the band.
  - A root-view `hitTest` override keeps SwiftUI gestures from firing outside the shape.
- **Focus:**
  - The panel becomes key only when opened by the keyboard, when a text field is clicked, or when a Tray tile is clicked.
  - Key status for typing holds the panel open. A Tray tile click takes key status for the selection only: Space, ⌘C and ⌘⌫ reach the Tray and never the frontmost app, yet the panel still closes when the pointer leaves, after the grace period. Typing in a text field afterwards holds it open as usual.
  - On close, `orderOut` + `orderFrontRegardless` hands key status back to the previous window.
  - ⌘A/C/V/X/Z work because the SwiftUI `App` lifecycle installs a main menu with Edit (verified by `scripts/smoke.sh`, ARCHITECTURE D12); R1's hidden Edit menu is the fallback only if a future SDK drops it.
- **Full screen** is detected per R1: the menu-bar window is missing on that display, and another app's window covers it.

### 3.7 Display and full-screen policy

- **Show on:** Built-in display (default when present) · Display with the pointer · All displays · Chosen displays (the last connected one cannot be unchecked; with none connected Cranny uses the primary display and the row says so). Each display has its own **style** (Automatic / Island / Attached / Off; Automatic = the hardware notch where there is one, else Appearance ▸ "On displays without a notch") and its own toggles for **activities, peeks and HUD**. An explicit Off hides Cranny on any display, notched ones included. Turning a display back on (Show On ▸ or the table) resets a notched display to Automatic and any other to Floating island.
- **Peeks**, alerts and the HUD appear only on the display that has the pointer; when that display shows no Cranny, they use the primary display's.
- **In full-screen apps:** Hide everything · **Alerts and HUD only** (default) · Show all. Hovering there needs a 400 ms dwell. **Excluded apps** (a list) behave like full screen.
- **Screen sharing:** Demo mode acts as Pin plus "Show all" (never auto-closes or hides, including over full-screen apps), mutes every Cranny sound and can redact calendar titles and note text. `sharingType = .none` is not used, because it is unreliable on macOS 15+.

---

## 4. Motion

### 4.1 The spring table (Standard personality)

All springs are `.spring(duration:bounce:)` (perceptual duration, macOS 14). The physics below come from the SDK's `Spring(duration:bounce:)`, and overshoot was sampled on a 0 → 1 step. **The rule: geometry may overshoot when it grows, and never when it shrinks back into the hardware.** Every animation is interruptible: springs retarget with velocity preserved, and nothing is queued. Every duration is well under the HIG's 2-second cap.

| Token | duration / bounce | ζ | stiffness / damping | settles | overshoot (Lively) | Used for |
|---|---|---|---|---|---|---|
| `open` | 0.42 / 0.14 | 0.86 | 223.8 / 25.7 | 0.74 s | **0.50 %** (1.75 %) | closed/compact/peek → open |
| `close` | 0.34 / **0** | 1.00 | 341.5 / 37.0 | 0.50 s | **0** | any → closed (lands exactly) |
| `resize` | 0.40 / 0.10 | 0.90 | 246.7 / 28.3 | 0.68 s | 0.15 % (0.63 %) | open → open: tab or page height, Notes focus |
| `activityIn` | 0.46 / 0.24 | 0.76 | 186.6 / 20.8 | 0.90 s | **2.54 %** (6.81 %) | closed → compact: the "drop" |
| `activityOut` | 0.30 / 0 | 1.00 | 438.6 / 41.9 | 0.50 s | 0 | compact → closed |
| `activitySwap` | 0.30 / 0.04 | 0.96 | 438.6 / 40.2 | 0.50 s | 0 | slot class change (music → meeting) |
| `peekIn` | 0.38 / 0.14 | 0.86 | 273.4 / 28.4 | 0.68 s | 0.50 % (1.75 %) | compact → peek |
| `peekOut` | 0.28 / 0 | 1.00 | 503.6 / 44.9 | 0.50 s | 0 | peek → compact |
| `hoverIn` | 0.26 / 0.20 | 0.80 | 584.0 / 38.7 | 0.51 s | 1.52 % (4.60 %) | the hover breath (3 pt) |
| `hoverOut` | 0.24 / 0 | 1.00 | 685.4 / 52.4 | 0.40 s | 0 | breath → closed |
| `satellite` | 0.38 / 0.18 | 0.82 | 273.4 / 27.1 | 0.71 s | 1.11 % (3.49 %) | second activity buds off |
| `hudIn` | 0.30 / 0.16 | 0.84 | 438.6 / 35.2 | 0.56 s | 0.77 % (2.54 %) | first key press |
| `hudLevel` | 0.16 / 0 | 1.00 | 1542 / 78.5 | 0.30 s | 0 | the bar follows key repeat (~30 Hz) |
| `hudOut` | 0.30 / 0 | 1.00 | 438.6 / 41.9 | 0.50 s | 0 | 1.5 s after the last change |
| `tab` | 0.26 / 0 | 1.00 | 584.0 / 48.3 | 0.40 s | 0 | page content |
| `tabIndicator` | 0.30 / 0.10 | 0.90 | 438.6 / 37.7 | 0.52 s | 0.15 % | selection capsule (matched geometry) |
| `press` | 0.18 / 0.20 | 0.80 | 1218 / 55.9 | 0.37 s | 1.52 % | button scale 0.94 |
| `commit` | 0.30 / 0 | 1.00 | 438.6 / 41.9 | 0.50 s | 0 | drop accepted, checkbox, armed target |
| `listReorder` | 0.32 / 0.06 | 0.94 | 385.5 / 36.9 | 0.54 s | 0.02 % | to-do completion, tray insert, grid reorder |
| `snapBack` | 0.36 / 0.12 | 0.88 | 304.6 / 30.7 | 0.63 s | 0.30 % | released gesture below threshold |
| `contentIn` | easeOut 0.22, **delay 0.06** | | | | | content after the shape is ~25 % open |
| `contentOut` | easeIn 0.10 | | | | | content leaves *before* the shape shrinks |
| `contentSwap` | smooth 0.30 | | | | | artwork, value and activity swaps (with `.blurReplace`) |
| `colorShift` | easeInOut 0.80 | | | | | accent and light palette on a track change |
| `ambientIn` / `ambientOut` | easeOut 0.50, delay 0.10 / easeIn 0.20 | | | | | the light layer fills, then drains |
| `hover` | easeOut 0.12 | | | | | fills on hover |

Overshoot in points: `open` 0.5 % of a 472-pt widening is about 2.4 pt, and `activityIn` 2.5 % of a 105-pt widening is about 2.6 pt. Both are visible as life, never as wobble.

### 4.2 Personalities and Reduce Motion

| Setting | Effect |
|---|---|
| **Standard** (default) | The table above |
| **Calm** | Every bounce × 0: everything is critically damped. Effects still run; delight moments play their reduced variants (§5.5). |
| **Lively** | Bounce × 1.5, capped at 0.35. Anything that lands is still 0. |
| **Instant** | No animation at all (`nil`), even without Reduce Motion; no delight moments (§5.5) |
| **Reduce Motion** (system) | `open`, `close` and `resize` **do not travel**: old and new shapes cross-fade at their final sizes (easeInOut 0.20). For a resize only the outlines cross-fade; the content stays in place, so keyboard focus and VoiceOver survive. Small morphs (activity, peek, HUD, satellite) keep morphing, with easeInOut 0.18 and no bounce. The hover breath and HUD level animation are off. Content transitions are opacity only. No stagger, marquee, typing effect, pulse, ember or neck. The light layer **freezes on a resting frame**: the colour stays, the movement goes. Rubber-banding stays (it is direct manipulation) but releases without overshoot. |

```swift
// CrannyCore/DesignSystem/Motion.swift
// Every animation in Cranny comes from this table. Rule: geometry may overshoot when it
// GROWS; it never overshoots when it SHRINKS back into the hardware.
import SwiftUI

/// Settings ▸ Appearance ▸ Motion. Scales bounce only; durations are fixed.
public nonisolated enum MotionPersonality: String, CaseIterable, Codable, Sendable {
    case calm       // no bounce anywhere
    case standard   // default
    case lively     // bounce × 1.5 (capped at 0.35)
    case instant    // no animation at all
    public var bounceScale: Double {
        switch self {
        case .calm, .instant: 0
        case .standard: 1
        case .lively: 1.5
        }
    }
}

public nonisolated enum CrannyMotion {
    public nonisolated enum Kind: String, CaseIterable, Sendable {
        // Shape geometry
        case open, close, resize, activityIn, activityOut, activitySwap
        case peekIn, peekOut, hoverIn, hoverOut, satellite, hudIn, hudLevel, hudOut
        // Content
        case contentIn, contentOut, contentSwap, tab, tabIndicator, colorShift, ambientIn, ambientOut
        // Controls & direct manipulation
        case hover, press, commit, listReorder, snapBack
    }

    public nonisolated enum Curve: Equatable, Sendable {
        case spring(duration: Double, bounce: Double)
        case easeOut(Double), easeIn(Double), easeInOut(Double), smooth(Double)
    }

    public nonisolated struct Spec: Equatable, Sendable {
        public let curve: Curve
        public let delay: Double
        /// Shrinking toward the hardware: bounce is forced to 0 for every personality.
        public let lands: Bool
        init(_ curve: Curve, delay: Double = 0, lands: Bool = false) { self.curve = curve; self.delay = delay; self.lands = lands }
    }

    /// The Standard table (DESIGN.md §4.1).
    public static func spec(_ k: Kind) -> Spec {
        switch k {
        case .open:          Spec(.spring(duration: 0.42, bounce: 0.14))
        case .close:         Spec(.spring(duration: 0.34, bounce: 0), lands: true)
        case .resize:        Spec(.spring(duration: 0.40, bounce: 0.10))
        case .activityIn:    Spec(.spring(duration: 0.46, bounce: 0.24))
        case .activityOut:   Spec(.spring(duration: 0.30, bounce: 0), lands: true)
        case .activitySwap:  Spec(.spring(duration: 0.30, bounce: 0.04))
        case .peekIn:        Spec(.spring(duration: 0.38, bounce: 0.14))
        case .peekOut:       Spec(.spring(duration: 0.28, bounce: 0), lands: true)
        case .hoverIn:       Spec(.spring(duration: 0.26, bounce: 0.20))
        case .hoverOut:      Spec(.spring(duration: 0.24, bounce: 0), lands: true)
        case .satellite:     Spec(.spring(duration: 0.38, bounce: 0.18))
        case .hudIn:         Spec(.spring(duration: 0.30, bounce: 0.16))
        case .hudLevel:      Spec(.spring(duration: 0.16, bounce: 0))
        case .hudOut:        Spec(.spring(duration: 0.30, bounce: 0), lands: true)
        case .contentIn:     Spec(.easeOut(0.22), delay: 0.06)
        case .contentOut:    Spec(.easeIn(0.10))
        case .contentSwap:   Spec(.smooth(0.30))
        case .tab:           Spec(.spring(duration: 0.26, bounce: 0))
        case .tabIndicator:  Spec(.spring(duration: 0.30, bounce: 0.10))
        case .colorShift:    Spec(.easeInOut(0.80))
        case .ambientIn:     Spec(.easeOut(0.50), delay: 0.10)
        case .ambientOut:    Spec(.easeIn(0.20))
        case .hover:         Spec(.easeOut(0.12))
        case .press:         Spec(.spring(duration: 0.18, bounce: 0.20))
        case .commit:        Spec(.spring(duration: 0.30, bounce: 0))
        case .listReorder:   Spec(.spring(duration: 0.32, bounce: 0.06))
        case .snapBack:      Spec(.spring(duration: 0.36, bounce: 0.12))
        }
    }

    /// Reduce Motion: big morphs become dissolves at the final size (see `morphsShape`),
    /// small morphs lose their bounce, nothing scales/blurs/slides.
    public static func reducedSpec(_ k: Kind) -> Curve? {
        switch k {
        case .open, .close, .resize: .easeInOut(0.20)
        case .activityIn, .activityOut, .activitySwap, .peekIn, .peekOut, .satellite, .hudIn, .hudOut: .easeInOut(0.18)
        case .hoverIn, .hoverOut, .hudLevel: nil
        case .contentIn: .easeOut(0.15)
        case .contentOut: .easeIn(0.08)
        case .contentSwap, .tab, .tabIndicator: .easeInOut(0.15)
        case .colorShift: .easeInOut(0.30)
        case .ambientIn, .ambientOut: .easeInOut(0.20)
        case .hover, .press: .easeOut(0.08)
        case .commit, .listReorder, .snapBack: .easeOut(0.18)
        }
    }

    public static func animation(_ k: Kind, personality: MotionPersonality = .standard,
                                 reduceMotion: Bool = false) -> Animation? {
        if personality == .instant { return nil }
        if reduceMotion { return reducedSpec(k).map { make($0) } }
        let s = spec(k)
        var curve = s.curve
        if case .spring(let d, let b) = curve {
            let bounce = s.lands ? 0 : min(b * personality.bounceScale, 0.35)
            curve = .spring(duration: d, bounce: bounce)
        }
        let a = make(curve)
        return s.delay > 0 ? a.delay(s.delay) : a
    }

    private static func make(_ c: Curve) -> Animation {
        switch c {
        case .spring(let d, let b): .spring(duration: d, bounce: b)
        case .easeOut(let d): .easeOut(duration: d)
        case .easeIn(let d): .easeIn(duration: d)
        case .easeInOut(let d): .easeInOut(duration: d)
        case .smooth(let d): .smooth(duration: d)
        }
    }

    /// With Reduce Motion, open/close/resize do not travel: the old and new shapes cross-fade
    /// at their final sizes. Small morphs (compact, peek, HUD) still morph, without bounce.
    public static func morphsShape(_ k: Kind, reduceMotion: Bool) -> Bool {
        !(reduceMotion && (k == .open || k == .close || k == .resize))
    }

    /// Widgets enter radiating outward from the camera: `ring` = |column distance from the
    /// centre| in widget order. 18 ms per ring, at most 4 rings (72 ms).
    public static func stagger(ring: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(min(max(ring, 0), 4)) * 0.018
    }

    /// iOS-style rubber band: resistance grows with distance and never hard-stops.
    public static func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient c: CGFloat = 0.55) -> CGFloat {
        guard limit > 0 else { return 0 }
        let sign: CGFloat = offset < 0 ? -1 : 1
        return sign * (1 - 1 / (abs(offset) * c / limit + 1)) * limit
    }

    /// The gulp, the one delight that is shape motion (DESIGN.md §5.5: a file caught). Never under Instant; under
    /// Calm and Reduce Motion its variant is "no gulp, the haptic stays". The other moments (first light, song change,
    /// timer done, charger connected) and their Calm / Reduce Motion variants are timed by CrannyEffects.
    public nonisolated enum Delight {
        /// The bottom edge rises `gulpDepth` in `gulpSwallowDuration` …
        public static let gulpSwallow = Animation.easeIn(duration: gulpSwallowDuration)
        /// … and lands back over the rest of the 0.25-s moment, without bounce (it shrinks toward the hardware).
        public static let gulpRecover = Animation.spring(duration: gulpRecoverDuration, bounce: 0)

        /// How far the gulp lifts the shape's bottom edge (pt).
        public static let gulpDepth: CGFloat = 3
        /// Down in 0.07 s, back over the rest of the 0.25-s moment.
        public static let gulpSwallowDuration: Double = 0.07
        public static let gulpRecoverDuration: Double = 0.18
    }
}

// MARK: - Hover intent (the anti-flicker contract)

public nonisolated enum HoverIntent {
    /// Settings ▸ General ▸ Hover delay.
    public nonisolated enum Delay: String, CaseIterable, Codable, Sendable {
        case instant, short, standard, long
        public var seconds: Double { switch self { case .instant: 0; case .short: 0.12; case .standard: 0.22; case .long: 0.45 } }
    }
    public static let defaultDelay = Delay.short
    public static let peekDwell: Double = 0.18           // compact → peek
    public static let fullScreenDwell: Double = 0.40     // in a full-screen Space (tabs/toolbars live up there)
    public static let closeGrace: Double = 0.30          // leave the exit zone this long before closing
    public static let entryInflation: CGFloat = 4        // + the very top pixel row (mouse y == frame.maxY)
    public static let exitInflation: CGFloat = 14        // hysteresis while open
    public static let passThroughSpeed: CGFloat = 1200   // pt/s: travelling to a menu or display, not aiming
    public static let dragProximity = CGSize(width: 80, height: 40)   // file drag opens the Tray, no dwell
    public static let menuBarCourtesy: CGFloat = 24      // pointer this close beside the wings → wings retract
    public static let peekAutoDismiss: Double = 2.6
    public static let hudAutoDismiss: Double = 1.5

    /// Pure decision function (unit-tested). The shell calls it from its pointer monitor.
    public static func shouldOpen(dwell: Double, pointerSpeed: CGFloat, delay: Delay,
                                  mouseButtonDown: Bool, optionHeld: Bool,
                                  isFileDrag: Bool, fullScreenSpace: Bool) -> Bool {
        if isFileDrag { return true }
        if mouseButtonDown || optionHeld { return false }
        if pointerSpeed > passThroughSpeed { return false }
        return dwell >= (fullScreenSpace ? max(delay.seconds, fullScreenDwell) : delay.seconds)
    }
}

/// Two-finger trackpad gestures over the shape (precise scroll deltas only, R1 §6).
public nonisolated enum GestureSpec {
    public static let trackSwipeCommit: CGFloat = 40       // pt of finger travel …
    public static let trackSwipeVelocity: CGFloat = 400    // … or pt/s at release
    public static let pullOpen: CGFloat = 24               // swipe down on closed/compact
    public static let pushClose: CGFloat = 18              // swipe up on open/compact/peek
    public static let verticalVelocity: CGFloat = 300
    public static let horizontalTravel: CGFloat = 24       // rubber-band limit for content
    public static let verticalTravel: CGFloat = 20         // rubber-band limit for the shape
    public static let axisLock: CGFloat = 1.6              // dominant axis ≥ 1.6 × the other
    public static let cooldown: Double = 0.15              // one gesture per touch sequence
    public static let limitBump: CGFloat = 2               // HUD bar overshoot when pressing past 0 / 100 %
}

// MARK: - Transitions

/// Blur + scale + fade. Content materialises out of the notch and leaves before the shape shrinks.
public nonisolated struct BlurScale: ViewModifier {
    public var blur: CGFloat, scale: CGFloat, opacity: Double, anchor: UnitPoint
    public func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale, anchor: anchor).opacity(opacity)
    }
}

public extension AnyTransition {
    /// Nook/peek content. Reduce Motion → opacity only.
    static func crannyContent(reduceMotion: Bool, anchor: UnitPoint = .top) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: BlurScale(blur: 6, scale: 0.96, opacity: 0, anchor: anchor),
                                 identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)),
            removal: .modifier(active: BlurScale(blur: 3, scale: 0.98, opacity: 0, anchor: anchor),
                               identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)))
    }
    /// Compact slot content grows out of the camera edge (anchored on the camera side).
    static func crannySlot(edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .modifier(active: BlurScale(blur: 4, scale: 0.6, opacity: 0, anchor: anchor),
                         identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor))
    }
    /// Tab/page switch: symmetric, direction-aware ±12 pt slide + fade (never "fades one way, slides the other").
    static func crannyTab(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 12 : -12).combined(with: .opacity),
                           removal: .offset(x: forward ? -12 : 12).combined(with: .opacity))
    }
}
```

### 4.3 Choreography (t in seconds from the trigger)

**Open** (dwell met, click, shortcut or swipe commit)

| t | Shape | Content |
|---|---|---|
| 0 | `open` begins: width, height, ears and radius together; shadow and keyline ramp with openness | Compact slot content `contentOut` (0.10). Album art does **not** fade: it flies (matched geometry) from the 20-pt slot to the media card. |
| 0.06 | | Header (tabs, actions) `contentIn` with `crannyContent`: blur 6 → 0, scale 0.96 → 1 anchored top |
| 0.06 + stagger | | Widgets `contentIn`, **radiating outward from the camera**: the centre column first, then 18 ms per ring, at most 4 rings (72 ms) |
| 0.10 | | The light layer `ambientIn` fills from the bottom edge up (backdrop sized to the *current* shape) |
| ≈ 0.45 | visually settled | settled. A focus ring appears only if opened by keyboard. |

**Close:** content `contentOut` at 0 with no stagger, and the light drains (`ambientOut`). The shape starts `close` at 0.04, so the camera "swallows" an empty shape. When the animation is logically complete, any compact activity returns with `crannySlot` at about 0.22, and key status is handed back.

**Activity in:** `activityIn` on the shape. Slot content grows out of the camera edge (`crannySlot`: scale 0.6 → 1 anchored on the camera side, blur 4 → 0) at +0.08. **Activity out:** the reverse with `activityOut`; content leaves first.

**Activity swap** (for example Now Playing → meeting): the old content `contentOut`, slot width `activitySwap`, new content `crannySlot`.

**Peek:** `peekIn` grows 52-pt rows downward. Elements that also exist in the row (artwork, visualizer) **move** with matched geometry (20 → 40 pt artwork). Only new elements use `contentIn`. Peek rows stagger 30 ms top to bottom. An auto-peek retracts after 2.6 s unless hovered.

**Satellite:** a second ongoing activity buds off the trailing edge with `satellite`. In Standard and Lively a liquid neck connects them for the first 0.38 s. It is drawn by the `liquidNeck` layer shader of §5.6; the fallback is Canvas blur + `alphaThreshold`. Both are clipped to the strip between the shape and the bubble. In Calm and Reduce Motion it simply fades in.

**HUD:** the first key press runs `hudIn`. Later presses animate **only** the bar (`hudLevel`) and the number (`.numericText`); the shape never moves. Pressing past 0 % or 100 % rubber-bands the bar by 2 pt and springs it back (`snapBack`). After 1.5 s idle, `hudOut` restores the previous presentation.

**Tab or page switch:** the selection capsule moves with matched geometry and `tabIndicator`. Content uses `crannyTab(forward:)`: a symmetric ±12-pt slide plus fade with `tab`. If the pages differ in height, the shape uses `resize`.

**Notes focus:** the other widgets `contentOut`, the shape `resize`s to all columns × 3 rows, and Notes expands with matched geometry. Esc or ⌘↩ reverses it.

**Song change:** the artwork swaps with `.blurReplace` and `contentSwap`. The accent and light palette cross-fade (`colorShift`), and the tide or aurora gets a 0.6-s energy ripple. With shaders, the radial `songRipple` distortion from the camera is added (§5.6). If the Nook is closed, it auto-peeks (option).

### 4.4 Gestures and rubber-banding

These are two-finger trackpad scrolls over the shape, using precise deltas only. The phase-aware recognizer runs in `NotchPanel.sendEvent`, ignores momentum, fires once per touch sequence with a 0.15-s cooldown, and locks to an axis once one axis is 1.6× the other.

| Gesture | Where | Live feedback | Commit | Result |
|---|---|---|---|---|
| Horizontal swipe | compact Now Playing, a peek row (the one under the fingers), the Media artwork or title | Content follows `rubberBand(dx, 24)`; the next/previous glyph fades in at the leading edge | 40 pt or 400 pt/s | Next/previous track (*Invert* setting); the old artwork slides out 24 pt and the new one blur-replaces in; `.alignment` haptic at the threshold |
| Swipe **down** | closed, compact | Shape height + `rubberBand(dy, 20)` | 24 pt or 300 pt/s | Open, carrying the gesture velocity: the `open` spring (its bounce scaled by the motion personality, so Calm lands without overshoot) starts at the fingers' speed as a share of the bottom edge's travel per second, at most 8 per second (overshoot ≈ 0.7 %, Lively 2.2 %); Reduce Motion (a dissolve) and Instant ignore it |
| Swipe **up** | open | The shape follows, up to −20 | 18 pt | Close |
| Swipe **up** | compact, peek | Content lifts by the rubber-banded distance | 18 pt | **Dismiss** the activity under the fingers (on a peek with several rows, that row) until its next meaningful change (auto-unhide) |
| Swipe **up** | closed handle (no notch) | | 18 pt | Hide the handle until the next activity |
| Release below the threshold | | | | `snapBack` with the gesture's velocity |

The Nook has no horizontal page-swipe: horizontal swipes belong to media. A horizontal scroll over the scrubber previews the position as it moves and seeks once on release (a cancelled scroll seeks nothing); over the artwork or title it changes track. Directions are the fingers' physical motion; *Invert* flips only the track change.

### 4.5 Staggering

Only the Nook staggers, outward from the camera. Peek rows stagger 30 ms. Lists (events, to-dos, tray tiles) never stagger on open, to avoid a slot-machine effect.

### 4.6 Hover intent (the anti-flicker contract)

```
closed ──enter entry zone──▶ breath (hoverIn)
breath ──dwell ≥ delay (120 ms) ∧ speed < 1200 pt/s ∧ no mouse button ∧ no ⌥──▶ open     [Hover mode]
breath ──click──▶ open                                                                    [Click mode: breath only]
breath ──leave──▶ closed (hoverOut)
compact ──dwell 180 ms──▶ peek ──click──▶ open, focused on the related widget
open ──leave exit zone (+14 pt)──▶ grace 300 ms ──▶ closed / compact
grace ──re-enter──▶ open
open ──a menu opened from the panel closes with the pointer where it hung
       (within the menus' own size of where it opened, +32 pt)──▶ the region from the exit zone to the pointer
       (+14 pt) counts as inside for 300 ms; then, or when the pointer leaves it or comes back, the usual grace 300 ms
open ──holds open: pinned · typing · dragging · a drop still arriving · menu/popover/sheet open · palette, edit or focus mode · Demo──▶ never auto-closes
open ──Tray tile clicked (key for the selection only)──▶ still closes on leave after the grace (§3.6)
open ──inactivity timeout (off by default; 5–60 s)──▶ close
file drag within proximity ──▶ open straight to the Tray catch state (no dwell)
full-screen Space ──▶ dwell ≥ 400 ms
VoiceOver running ──▶ hover never opens; click, shortcut or VO action does
```

**Menus from the panel** (design ruling E3): while a menu tracks, the panel is held open. After a menu opened from the panel closes (Mirror's camera menu, a card's ⋯ menu), the panel stays open while the pointer remains inside the region the menu occupied, plus the 32-pt control allowance, so the pointer that picked an item is not "outside" while it rests or moves there. The usual close grace starts only when the pointer leaves that region (or comes back to the panel, where ordinary hover applies). Closing the panel (Esc, the hot key) ends the region at once, also while the pointer rests in it. If the pointer's position cannot be read, the region ends at a safety check one grace after the menu closed. AppKit tells a menu's size but not where it hung, so "the region the menu occupied" is every place it can have hung: its size around the control it opened from and around the item picked, +32 pt, on the panel's screen. After a pick that holds the whole menu, wherever it opened; it never reaches another display or beyond the menu's size from the control or the item (ARCHITECTURE §4.5; the design owner is asked to confirm this reading, §10.20 #30). A menu from elsewhere (the menu bar extra, a Settings pop-up), a menu dismissed by a click far from where it opened, a menu of unknown size and one that ends off the panel's screen leave nothing, and the usual grace starts at once.

**Menu-bar courtesy:** while the pointer is in the band within 24 pt *beside* the compact wings (reaching for a menu or status item under them), the wings retract with `activityOut` and return 1.5 s after the pointer leaves the band. Pointer moves along the rest of the menu bar, or on another display's menu bar, do nothing. A pointer inside the hover zone is never courtesy, so while a satellite shows (it sits in the right-hand strip) courtesy works only on the left. The HUD ignores courtesy.

**Unattended opens:** when the panel opens while the pointer is elsewhere and nobody used the keyboard or a click (Welcome's Done, the Tray opening after a slow drop, a module asking to open), it closes after 3 s unless the pointer comes in, like a panel the pointer left. VoiceOver users are exempt.

### 4.7 Energy budget (a release gate)

| State | Allowed work |
|---|---|
| Closed, nothing playing | **None**: no timers, no `TimelineView`, no Canvas. Event-driven only. |
| Compact Now Playing | Visualizer ≤ 30 fps on AC, ≤ 20 fps on battery, only while audio plays; static otherwise |
| Peek | The tide or row visuals only for the peek's lifetime |
| Open | Light layer ≤ 30 fps on AC, 20 fps on battery, timed by `EffectClock` (CrannyCore), which wakes only at that rate. `TimelineView(.animation(minimumInterval:))` and `.periodic` are not used for effects: they keep SwiftUI redrawing at the display's refresh rate (ARCHITECTURE §9.2) |
| Open, Appearance ▸ Quality ▸ Efficient | The light is Core Animation layers and looping animations that the window server runs, asking for the same 30 / 20 fps (`preferredFrameRateRange`; a 240-Hz external display was measured compositing at its own rate, §5.7); Cranny does no work per frame and holds no GPU memory |
| Low Power Mode, `thermalState ≥ .serious` | Light becomes a static halo (0 fps) |
| Full-screen app in front, panel occluded, Reduce Motion | Paused (Reduce Motion keeps a frozen frame) |
| **Targets** | Activity Monitor Energy Impact < 1.0 idle; open plus aurora ≤ 3 % CPU; no hitches at 120 Hz. Measured with Instruments before each release. Open plus aurora cost ≈ 5–10 % at WP0 on a 240-Hz display; since the light draws through its own Metal layer (§5.6) a Debug build measures 1.5–2.6 % with effects forced on (phase C, floating island; after phase D the attached notch shape on the same Mac measured 4.0–5.0 %, the same as before phase D). The Instruments run on a 120-Hz MacBook is still due (ARCHITECTURE §10.20). |

---

## 5. The light layer ("Afterglow")

An optional layer, grafted from proposal B: **the Nook is a black crevice that light leaks out of**. The colour comes from what is happening. It is never random, never on the closed or compact shape, and never behind text without a card or a scrim.

### 5.1 Controls and defaults

- **Ambient light:** Off · **Subtle** (default; light alpha capped at 0.45) · Vivid (alpha cap 0.80; switches to the `lit` tokens and allows the underglow).
- **Effect:** **Aurora** (default) · Motes · Tide. Halo is the automatic Low Power fallback.
- **Quality:** **Detailed** (default: the Metal light of §5.6) · Efficient (the Core Animation light of §5.7: simpler, no GPU memory in Cranny and no work per frame). Footnote: "Efficient draws a simpler light that uses much less memory." (Battery is not promised: on the 240-Hz display it was measured on, the window server did about as much more work as Cranny saved, §5.7.) Disabled with Ambient light Off, like Effect.
- Increase Contrast and the Flat widget style cap the light at Subtle. Reduce Transparency turns it off.
- **Album glow** (default on): a halo behind the artwork in the Media widget and the peek row, in the album accent at 30 %, r 36, scale 1.08.
- **Underglow** (Vivid only): coloured light spilling onto the desktop below the open Nook, as a `.shadow` of the shape in `glow1` at 30 %, r 36, y 10. It is click-through.
- **Progress rim** (off by default): playback progress drawn as a 1.5-pt accent line along the *lower* outline of compact Now Playing, as a `trim(0…progress)` of the outline. The same path carries a one-shot green sweep when a charger connects.
- **Keyline tint:** while music plays, the keyline takes the album accent.

### 5.2 Palette per activity

| Source | Light (`glow1…3`) | Accent |
|---|---|---|
| Media | `AmbientPalette.extract(artwork)`: deterministic k-means (k 5) on a 24 × 24 thumbnail, ranked by population × colourfulness, three hue-distinct glows clamped `luminous` (s 0.45–0.90, v ≤ 0.95); greyscale art → an honest silver `.mono` | Most chromatic cluster, guarded legible. 0.021 ms per artwork (release); cached by track ID; off the main actor |
| Meeting | `AmbientPalette.tinted(calendar colour)` | Calendar colour, guarded |
| Timer | `.timer` (ember → amber → rose) | `warning` |
| Charging / low battery | `.charging` / `.lowBattery` | `success` / `danger` |
| Nothing | `tinted(system accent)` (Accent = Automatic or System); `.afterglow` (Accent = Swatch); `.mono` (Monochrome) | the resolved accent |

### 5.3 Effects

All effects are pure functions of time, palette, energy and intensity. They hold no per-particle state and no timers; `EffectClock(minimumInterval:)` supplies time at the budget's rate and stops entirely while paused, so pausing costs nothing. The backdrop is framed to the shape's **current** bounds, so the light rises with the bottom edge as the Nook opens. Each effect is drawn by a **Metal shader** (§5.6, primary). Each also has a **SwiftUI fallback** with the same look, palette mapping and alpha ceiling. The fallback is used under Reduce Motion (frozen resting frame), under Low Power / `thermalState ≥ .serious` (the static halo) and when shaders are unavailable.

| Effect | Metal shader (§5.6) | SwiftUI fallback | Look | Parameters |
|---|---|---|---|---|
| **Aurora** | `auroraField`: domain-warped fBm curtains coloured by the palette stops | `MeshGradient` 4 × 4 (15+); macOS 14: Canvas with 3 blurred sine curtains, normal blending | Curtains of content colour rising from the bottom; the top 40 % stays black, so the band merges with the hardware | Interior points drift on incommensurate sines (0.21–0.71 rad/s, amplitude 3–8 %); louder audio lifts the light by up to 6 % |
| **Motes** | `motesField`: the same 36 hash-seeded specks, evaluated per pixel | Canvas, 36 stateless hash-seeded particles | Slow rising specks that twinkle | Speed 5–14 pt/s; radius 0.8–2.4; twinkle 1.2–3.2 Hz × 0.45 amplitude |
| **Tide** | `tideField`: 3 layered sine lines with soft, tapered edges + bloom | Canvas, 3 tapered sine strokes + 3-pt bloom | Luminous wave lines along the bottom edge | Amplitude 3–10 pt × energy; also used in the song-change peek |
| **Halo** | `haloGlow`: Gaussian radial falloff, dithered. Used by First light; the automatic Low Power halo is always the fallback | `RadialGradient` | One static bloom | Low Power Mode and thermal fallback |

**Audio energy:** real RMS (60 ms attack, 300 ms release) only when the user enables **Live** visualizer mode, which asks for System Audio Recording permission on macOS 14.2+ via a Core Audio process tap. Otherwise energy is 0 and the visualizer runs in **Ambient** mode: an honest breathing pattern, labelled as such in Settings.

### 5.4 Translucency

- **Default: opaque black.** The shape must be indistinguishable from the hardware.
- **Translucent background** (opt-in):
  - The band stays opaque black, so there is never a seam around the camera.
  - Below the band the fill ramps over 24 pt to **72 % black** over glass: `glassEffect(.regular.tint(.black.opacity(0.35)))` on 26+, `NSVisualEffectView(.hudWindow, .behindWindow)` on 14/15.
  - Cards stay smoked.
  - Forced off by Reduce Transparency.
- **Liquid Glass** is never used on the attached shape. Settings, menus and onboarding get it automatically from system controls on 26+.

### 5.5 Delight moments

All are original and capped: at most one plays at a time; none play in full screen, while the panel is covered, while the screen is locked or while Live Activities are paused; and none play under Motion ▸ Instant. Under Calm and under Reduce Motion each moment plays its variant from the last column instead (design ruling R2): First light fades in statically, Timer done shows the static ember glow, Charger connected lights the rim at once and the satellite split fades. Song change (colour only, carried by the palette cross-fade) and File caught (no gulp; the haptic stays) draw no moment then, so they are not scheduled and never keep the stage from a moment that shows. The ambient light is not a moment: under Calm it keeps moving.

**Quality ▸ Efficient** (§5.7): every moment plays its variant from the last column, as under Calm and Reduce Motion, because the animated designs are Metal shaders or Canvases and either would give Cranny the GPU memory that setting saves. The song change is the exception: the Core Animation light lifts once with the palette cross-fade (§5.7). The gulp, the to-do check and the HUD bump are shape motion and unchanged.

**Who triggers what** (ARCHITECTURE §3.6, §4.6 step 7): feature modules cannot import `CrannyEffects`, so an activity only *names* its moment (`LiveActivity.delight`: Timer done → `.emberBurst`, Charging → `.chargeSweep`); the shell adds `.songRipple`, `.firstLight` and `.gulp`, applies the caps above, and CrannyNotchUI draws the moment from `CrannyEffects`. The to-do check and its Lively motes are drawn inside the To-dos widget; the drop, satellite neck and HUD bump are motion owned by NotchUI and the HUD.

**Engines.** First light, Song change, Timer done, Charger connected and Satellite split are drawn by Metal shaders (§5.6). The last column below is unchanged. Under Low Power / thermal, or when shaders are unavailable, the same moments use their SwiftUI fallback, which is the design as originally written: Canvas particles, `trim` sweep, Canvas blur neck, energy-only ripple, radial fade.

| Moment | What happens | Calm / Reduce Motion |
|---|---|---|
| **The drop** | `activityIn`'s 2.5 % overshoot as an activity appears | Calm: no overshoot |
| **First light** | The first open per session: the light fills outward from the camera over 1.0 s | Static fade |
| **Song change** | Palette cross-fade plus a tide or aurora ripple | Colour only |
| **Timer done** | An ember burst (18 stateless particles, 0.9 s) fans out of the notch; the ring pulses twice (`phaseAnimator`) | Static ember glow; ring colour only |
| **File caught** | The shape "gulps" (height −3 pt, spring back over 0.25 s) and plays a `.generic` haptic | No gulp; haptic stays |
| **Charger connected** | A green sweep along the lower rim | Instant rim |
| **Satellite split** | The liquid neck, 0.38 s | Fade |
| **To-do done** | The check draws itself (trim 0 → 1, 0.25 s); Lively adds six motes | Instant check |
| **HUD at a limit** | A 2-pt rubber-band bump | Kept, with no overshoot |

### 5.6 Metal shaders

Since ARCHITECTURE D13, the light is drawn by SwiftUI **stitchable** Metal functions in `CrannyEffects/Shaders/*.metal`, loaded with `ShaderLibrary.bundle(.module)`. Each shader is a pure function of its uniforms and holds no state, timer or clock. The SwiftUI designs of §5.3–§5.5 and Appendix B.1 are the **fallback specification**: same palette mapping, black band, peak alpha and motion scale. The fallback is not a degraded mode. The plumbing is in Appendix B.2.

**Rules for every shader**

1. **Which path.** `ShaderEffects.usesShader(budget)`. The shader path runs only when the Metal library is available and neither Reduce Motion nor Low Power / `thermalState ≥ .serious` is on.
   - Reduce Motion: the fallback freezes on its resting frame.
   - Low Power / thermal: `budget.effective(_:)` turns the light into the static SwiftUI halo.
   - Closing, occlusion and full screen only **pause** time on the current path. They never switch paths, so nothing jumps.
   - Appearance ▸ Quality ▸ Efficient: no shader runs and the library is never loaded; the light is the Core Animation light of §5.7 and the moments play their still variants (snapshots keep the paths above).
2. **Failure is silent in SwiftUI.** A missing function, or a uniform list that does not match the signature, renders **transparent** with no error [VERIFIED].
   - `ShaderEffects.isAvailable` checks once that `default.metallib` is bundled, loads on this Mac's GPU and lists every `requiredFunctions` name. If not, it logs one `.info` line and every effect uses its fallback.
   - Each function has a render test.
   - Launching with `-CrannyDisableShaders YES` forces the fallbacks (QA, energy A/B).
3. **Uniforms come only from the caller.** The common set is:
   - `.boundingRect`: the view's rect, so size = `bounds.zw`.
   - `time`: seconds from the effect's `EffectClock`, `mod 3600`.
   - Palette **stops**: `.colorArray(palette.glows)` → `device const half4 *stops, int count`. Shaders accept 1–5 stops; `AmbientPalette` supplies 3. `accent` is a foreground colour and never lights.
   - `energy`: 0…1, §5.3.
   - `intensity`: `AmbienceLevel.intensity`, Subtle 0.55 and Vivid 1. It scales structure and contrast, never the ceiling.
   - `cap`.
4. **Alpha cap.** Every light-emitting shader returns through `cranny::light(rgb, alpha, cap)`. The output is premultiplied, alpha is clamped to `cap`, and every channel is clamped to `Glow.maxBrightness` (0.95).
   - Ambient effects pass `cap = Glow.ambientAlphaCap(level)`.
   - One-shot moments pass `Glow.ambientAlphaCap(max(level, .subtle))`, so they still show at Subtle strength when Ambient light is Off.
   - The contrast audit of §2.1 therefore holds on both paths. The liquid neck is surface, not light: opaque black, no cap.
5. **No banding.** The aurora, tide, halo and first light end with `.crannyDithered(scale: displayScale)`. This adds ±0.5 LSB of interleaved-gradient noise per *pixel* (a texture-free stand-in for blue noise) to the premultiplied colour, so dim light over black shows no rings.
6. **Frame rate.**
   - **Ambient:** time comes from `EffectClock(minimumInterval: budget.minimumInterval)`, giving **≤ 30 fps on AC, ≤ 20 fps on battery**, and 0 when paused (§4.7).
   - **Moments:** the same rates (1/30 s on AC, 1/20 s on battery), whether the Nook is open or not, only for their lifetime (≤ 1.0 s), after which the view is removed. The liquid neck follows the satellite spring for 0.38 s.
   - **Budget:** GPU ≤ 1.5 ms per frame at the largest open size. The aurora returns early in the black top 40 %.
7. **Never on content.** Shaders apply to light layers only, never to text, cards, artwork or controls. Light layers keep `.allowsHitTesting(false)` and `.accessibilityHidden(true)`.

**The ambient layer.** In the open panel the aurora, motes, tide and halo are drawn by a dedicated Metal layer (ARCHITECTURE D13): one full-screen triangle per frame whose fragment function calls the same field code as the stitchable function below, paced by the same budget, so SwiftUI does no work per frame. Snapshots and stages that composite the light keep the stitchable path (`ambientLightRendering(.inline)`). Cranny never asks for the discrete GPU.

**The effects** (signatures in App. B.2; the numbers are the shipped values):

- **Aurora: `auroraField`** (`Aurora.metal`). A `.colorEffect` on a `Rectangle` framed to the shape. Uniforms: bounds, time, stops, energy, intensity, cap. The reference implementation is in App. B.2.
  - **Black band:** uv = position in bounds. The shader returns clear for uv.y ≤ 0.40, so the band stays black.
  - **Domain:** p = (1.2 · uv.x · aspect, 0.5 · uv.y). It is anisotropic, which makes the curtains tall.
  - **Domain warp:** two warp levels of 3-octave value-noise fBm, q then r = fbm(p + 1.5 · intensity · q + drift). Drifts are 0.04–0.07 units/s, periods of about 15–25 s, matching the mesh's 0.21–0.71 rad/s.
  - **Folds:** f = smoothstep(0.25, 0.75, fbm(p + 2r, 4 octaves)).
  - **Vertical rays:** 0.55 + 0.45 · smoothstep(0.3, 0.7, fbm(5 · p.x + 1.5 · r.y, 0.08 t)).
  - **Rise:** smoothstep(0.40, 0.70 − 0.06 · energy, uv.y), so louder audio lifts the light by up to 6 %, as in §5.3.
  - **Colour:** a ramp through the stops at 0.15 + 0.7 f + 0.3 (q.x − 0.5).
  - **Alpha:** cap · (0.8 + 0.2 · energy) · rise · rays · mix(0.45, 1, f). That is ≈ 0.8 · cap at energy 0, the mesh's peak.
  - **Then:** dithered.
  - **Fallback:** `MeshGradient` (15+) / Canvas curtains (14), App. B.1.
- **Tide: `tideField`** (`Tide.metal`). A `.colorEffect` over the shape bounds. Uniforms: bounds, time, stops, energy, intensity, cap.
  - **Lines:** three lines, i = 0…2, line i in stop i. Baseline at 0.80 + 0.06·i of the height.
  - **Amplitude:** A = (3 + 7 · energy) · (1 − 0.2 · i) pt.
  - **Wave:** y(x) = base + A · [sin(kx + ωt + φ) + 0.45 · sin(1.9kx − 1.4ωt)], with k = 2π(0.75 + 0.35 i)/width and ω = 2π(0.09 + 0.035 i). These are the rates of the Canvas fallback.
  - **Profile:** slope-corrected distance d; taper τ = sin(π · u)^0.6, so the lines thin and fade toward both ends. Core = 1 − smoothstep(0.5τ, 1.25τ, d), with d in pt: a soft edge with no hard stroke. Bloom = 0.35 · exp(−(d/3)²).
  - **Alpha:** cap · (0.55 + 0.45 · intensity) · (core + bloom) · τ, summed additively and premultiplied, then clamped.
  - **Then:** dithered.
  - **Fallback:** Canvas strokes.
- **Motes: `motesField`** (`Motes.metal`). A `.colorEffect`. Uniforms: bounds, time, stops, energy, intensity, cap.
  - **Layout:** the same 36 stateless motes, as 12 columns × 3, each seeded by `cranny::hash(column · 3 + j)`.
  - **Cost:** a pixel evaluates only the 9 motes of its own and the two neighbouring columns (sway ≤ 4 pt is less than a column).
  - **Motion:** x = column centre ± 30 % + 4 pt · sin(0.6t + seed). Each mote rises at 5–14 pt/s · (1 + 0.3 · energy) and wraps below the bottom edge.
  - **Look:** radius 0.8–2.4 pt; twinkle 1 − 0.45 · (½ + ½ sin(2πft + seed)) with f = 1.2–3.2 Hz; profile exp(−(d/r)²) + 0.25 · exp(−(d/3r)²).
  - **Fade:** to 0 in the top 40 % (smoothstep 0.40 → 0.60).
  - **Colour:** stop (index mod count).
  - **Alpha:** cap · (0.6 + 0.4 · intensity) · profile · twinkle.
  - **Fallback:** the Canvas particles.
- **Halo: `haloGlow`** (`Halo.metal`). A `.colorEffect`. Uniforms: bounds, center, radius, glow, cap.
  - **Alpha:** 0.6 · cap · exp(−2.8 · (d/R)²). This Gaussian falloff has no crease where a two-stop gradient ends. Then dithered.
  - **Used by:** First light, and by any caller that asks for `.halo` while shaders are allowed. The **automatic** Low Power / thermal halo is always the fallback `RadialGradient` (glow1 at 0.6 · cap → clear, r 260, centred bottom), per rule 1.
- **First light** (`FirstLight`, reuses `haloGlow`). The ambient layer is masked by `haloGlow` (white, cap 1), centred on the camera. Its radius eases out from 0 to the shape's diagonal over 1.0 s. A second `haloGlow` in glow1 at 0.5 · cap rides the front as a crest. Fallback: radial fade. Reduce Motion: static fade (§5.5).
- **Song change: `songRipple`** (`Ripple.metal`). A `.distortionEffect` on the **ambient layer only**, for 0.6 s from the track change. `maxSampleOffset` = amplitude. Uniforms: center (the camera, top centre), time since trigger, amplitude 6 pt, wavelength λ 56 pt, speed 480 pt/s.
  - **Wave:** radial from the camera. For r = |p − c| and front = speed · t, the shader returns p − dir · A · sin(2π(r − front)/λ) · exp(−((r − front)/λ)²) · (1 − t/0.6)².
  - **Also:** the fallback's energy pulse (energy + 0.5 · (1 − t/0.6)²) still plays underneath.
  - **Fallback:** that energy pulse alone. Reduce Motion: colour cross-fade only.
- **Satellite split: `liquidNeck`** (`LiquidNeck.metal`). A `.layerEffect` on a layer holding the two black bodies (the trailing end of the shape and the satellite bubble), clipped to the strip between them. `maxSampleOffset` = 2 · reach + 1 pt. Uniforms: reach, progress (0…1 over 0.38 s), fill (the surface black).
  - **Field:** a point joins the surface when some line through it meets solid surface on both sides within 2 · reach in total: 12 directions 15° apart, 1.5-pt steps refined by 3 bisections, and 4 rotated-grid samples per pixel for the edge. So a lone convex body never swells, and every neck point lies on a segment that joins both bodies (nothing floats).
  - **Output:** fill · max(layer alpha, coverage). Bodies closer than 2 · reach merge with a concave neck that thins and snaps as the bubble moves away.
  - **Reach:** 7 pt · (1 − smoothstep(0.7, 1, progress)), so the neck is gone at 0.38 s.
  - **Fallback:** Canvas blur of radius 1.6 · reach, `alphaThreshold(min: 0.55)` (above 0.5, so straight edges stay just inside the bodies), a 0.3-pt blur for anti-aliasing, and the bodies drawn again on top so the blur never erodes them. Calm / Reduce Motion: fade.
- **Timer done: `emberBurst`** (`Ember.metal`). A `.colorEffect` on a 280 × 140-pt rect centred under the shape's bottom edge, inside the panel canvas. Uniforms: bounds, origin (the shape's bottom edge, under the camera), time since trigger (0…0.9 s), stops (`.timer`: ember → amber → rose), cap.
  - **Particles:** 18 stateless embers, seeded by `cranny::hash(i)`. Each travels in a direction within ±75° of straight down at 70–160 pt/s, with drag (distance = v · (1 − e^(−3t))/3) and gravity of 22 pt/s².
  - **Shape:** radius 1.2–2.6 pt, drawn as a capsule along the velocity (0.05-s trail).
  - **Life and colour:** life 0.55–0.9 s, fade (1 − t/life)², flicker 0.75 + 0.25 · sin(19t + seed). Profile core exp(−(d/r)²) + 0.4 · exp(−(d/3r)²); the stop is picked by seed.
  - **Output:** summed and clamped.
  - **Fallback:** the same 18 particles in a Canvas. Reduce Motion: static ember glow.
- **Charger connected: `chargeSweep`** (`ChargeSweep.metal`). A `.colorEffect` on the lower-outline stroke (the progress-rim path: a 1.5-pt core over a 4-pt soft under-stroke for bloom). Uniforms: bounds, progress (0 → 1 over 0.8 s), glow (`AmbientPalette.charging.glow1`, `success` green), cap.
  - **Arc length:** the lower outline is x-monotonic, so u = (x − minX)/width stands in for arc length.
  - **Head:** s = easeInOut(progress) · 1.2 − 0.1, travelling from leading to trailing.
  - **Light:** exp(−((u − s)/0.05)²) + 0.45 · smoothstep(s − 0.30, s, u) for u ≤ s (a head plus a fading tail).
  - **Alpha:** `color.a` · light, so the stroke's own coverage masks it.
  - **Fallback:** a green `trim` of the rim animated 0 → 1. Reduce Motion: instant rim.
- **Dither: `crannyDither`** (`Dither.metal`). The shared last `.colorEffect` pass of rule 5. Uniforms: amount (1 = ±0.5 LSB), scale (display scale). Code in App. B.2.

### 5.7 The efficient light (Core Animation)

Appearance ▸ Quality ▸ **Efficient** (`CoreSettings.ambientDetail`, carried in the theme as `ambientDetail`, so the panel, the Settings stage and the onboarding stage all follow it). **Detailed stays the default** and is exactly §5.3–§5.6.

**Why.** Any Metal work in the process makes the GPU driver charge its working set to Cranny while the light runs (≈ 240 MB on an M4 Max, freed 1–3 s after the last frame), and every frame of the Metal light wakes the app. SwiftUI's own animated Canvas, MeshGradient and shader paths do the same. The efficient light is built of plain Core Animation layers (radial `CAGradientLayer`s, `CAShapeLayer` strokes, static gradient masks) and looping `CAAnimation`s that the **window server's render server** draws and animates: Cranny builds them once when the light appears and does no work per frame, and never touches Metal (no device, no renderer, no shader; `EffectsPreparation` is skipped). It never uses SwiftUI Canvas, MeshGradient, shaders or layer filters.

**Costs** (measured, ARCHITECTURE §9.2): the open panel with the light keeps the size it has with Ambient light Off (≈ 34 MB instead of ≈ 268 MB, of which ≈ 225 MB was the GPU driver's working set), and the app's CPU while the light runs drops from ≈ 3.5 % to 0 % with no wake-up per frame (Debug). The animation's work moves to the window server: on a 240-Hz external display it composited the moving light for ≈ 3–5 % of a core more than the still one, against ≈ 1–2 % for the Metal light, whatever frame rate the animations asked for (the window server appears to composite at the display's rate while any of them runs; a MacBook's ProMotion display is where the 30 / 20 fps of `preferredFrameRateRange` is meant to take effect, not yet measured). So Efficient saves memory and Cranny's own wake-ups for certain, and CPU in all only roughly breaks even on such a display: the copy promises memory, not battery.

**What it looks like.** The palette mapping, the black band, the alpha ceiling and the motion scale of §5.3 hold; the structure is simpler:

| Effect | Efficient design | Motion |
|---|---|---|
| **Aurora** | Four wide glows on the bottom edge in stops 3 · 1 · 2 · 3 from left to right (the fallback mesh's bottom row) and four narrow rays above them in 1 · 2 · 3 · 1. Each is the radial gradient of an ellipse centred on the bottom edge, alpha full over its inner third and fading as 1 − smoothstep(0.3, 1, r) to its rim at ≈ 62 % of the height; peak alpha 0.70 for the glows and 0.35 + 0.30 · intensity for the rays, inside the cap. No domain warp, folds or fine rays | Each curtain drifts sideways (± 2 % of the width for the glows, ± 3–4 % for the rays; cycles of 29–59 s), breathes in height (× 0.82–1.05; 12–36 s) and, for the rays, in brightness (0.45–1; 8–30 s). Every period differs, so the light never visibly loops |
| **Motes** | The same 36 motes, seeded like §5.6's `motesField` (column, offset, radius 0.8–2.4 pt, colour stop, start); each a radial gradient of the shader's profile | Each rises from below the bottom edge to above the top at 5–14 pt/s in a 240-pt light (in proportion to the height in others), sways ± 4 pt (10.5-s cycle) and twinkles 1 ↔ 0.55 at 1.2–3.2 Hz. A static mask fades them out between 60 % and 40 % of the height |
| **Tide** | Three lines at 80 / 86 / 92 % of the height, line i in stop i, amplitude 3 · (1 − 0.2 · i) pt; the second harmonic at 2 k instead of 1.9 k, so each path repeats every wavelength. Strokes: a 1.5-pt core at 0.92 over blooms of 5 pt at 0.24 and 10 pt at 0.10, of the line's strength (0.55 + 0.45 · intensity). A static horizontal mask tapers them as sin(πu)^0.6 | Each line travels one wavelength to the left per 1 / (0.09 + 0.035 · i) s (11.1, 8.0 and 6.25 s), seamlessly |
| **Halo** | The fallback's 11-stop Gaussian (0.6 · exp(−2.8 · (d/R)²) to 1.5 R) | Static |

**Rules.**
- **Alpha cap:** each effect draws into one group layer composited at `Glow.ambientAlphaCap(level)` (group opacity); inside it every colour's alpha is ≤ 1, so overlapping light never passes the cap. Channels are clamped to `Glow.maxBrightness`. A render test checks every effect at both levels, and that the top 40 % stays clear.
- **The band:** the aurora and the motes lie under a static mask that is clear over the top 40 % (the aurora's from 40 % to 48 %, as `BandMask`); the tide lines sit at 80–92 %.
- **Frame rate:** every animation asks for the budget's rate (`preferredFrameRateRange`: 30 fps on AC, 20 on battery); the animations are installed again only when that rate changes. How often the window server composites is its own choice (see Costs).
- **Pause and rest:** one clock layer holds every looping animation. Closing, occlusion and full screen stop it (speed 0) where it is; it resumes from there. Reduce Motion and Motion ▸ Instant stop it on the resting frame (7.3 s); the first open also starts there.
- **Fill:** the rise from the bottom edge (`ambientIn` / `ambientOut`) is the same gradient mask as §5.3's SwiftUI paths, only while it shows anything; an opacity fade under Reduce Motion.
- **Colour:** palette, level and effect changes cross-fade the whole light with one Core Animation fade of the `colorShift` timing (0.8 s; 0.3 s under Reduce Motion; none under Instant), outside the clock, so a still light fades too. SwiftUI does not animate the palette then.
- **Energy:** live audio energy is not used (following it would need work per frame in the app); the light shows energy 0, also with the Live visualizer.
- **Moments:** First light fades in statically, Timer done shows the static ember glow, Charger connected lights the rim at once, the satellite fades (§5.5); a song change lifts the whole light by 3 % of its height (at most 8 pt) and lets it settle within 0.6 s, the shaders' energy pulse without the ripple's distortion.
- **Unchanged:** Low Power / thermal still draw the static SwiftUI halo; snapshots (`ambientLightRendering(.inline)`: tests, the gallery, `--qa-snapshot`) keep the SwiftUI paths; Ambient light Off draws nothing.
- **Known differences:** no dither (Core Animation’s gradients; faint steps may show in very dim light on some displays); broad curtains instead of domain-warped folds and fine rays; the light ignores the music.

---

## 6. The open Nook

### 6.1 Anatomy (14″, Standard, default layout)

```
 ◜ear 10                                     band = header (32)                                      ear 10◝
 ┌──────────────────────────────────┬──────────── camera housing (N) ─────────┬──────────────────────────────┐
 │12 (▣ Home | ▤ Tray 3 | ✎ Focus)  │      never draw here (time/date if       │   (⌕) (📌) (⚙︎)  12          │  ← header lives IN the band
 │                                   └────────── no notch) ───────────────────┘                              │  headerGap 6
 │12 ┌──────── Media · 5 cells (312) ─────────┐ 8 ┌── Calendar · 3 (184) ──┐ 8 ┌ Apps · 2 (120) ┐       12  │
 │   │ 120 = 2 rows × 56 + 8, r 20, padding 12 │   │                         │   │  ▢    ▢        │           │
 │   └─────────────────────────────────────────┘   └─────────────────────────┘   └────────────────┘           │
 │                                                                                              padding 12  │
 ╰──────────────────────────────────────────── r 32 continuous · keyline × openness ─────────────────────────╯
                                                   656 × 170 (676 with ears)
```

### 6.2 Header (in the band)

- **Leading: tabs and pages.**
  - A capsule track (`control`, 2-pt inset). Segments are 22 pt high with an icon and title (`headline`); the selected segment is `controlPressed` and moves with matched geometry.
  - Built-in pages are **Home** (the widget grid; code id `nook`) and **Tray**; the Tray shows a `micro` count badge.
  - Users can add up to **3 pages** (for example "Focus": Notes 4 · To-dos 3 · Timer 2 · Shortcuts 1).
  - If titles don't fit their zone (Russian, XL text), they collapse to icons with tooltips and VoiceOver labels; if even the icons don't fit (four or more pages at the minimum width), the header shows the selected page plus a ⌄ menu of all pages.
  - Tab icons are 13-pt semibold, as in the rest of the band. The Tray's count badge is a `micro` number on a `controlHover` capsule.
- **Trailing: actions.**
  - ⌕ Command palette (⌘K), 📌 Pin (`pin` / `pin.fill`; pinned shows a `control` well), ⚙︎ Settings (⌘,).
  - Plain icon buttons, drawn at 28 pt with 13-pt semibold glyphs inside a 32 × 28 hit area (the band's 32 × 24 minimum, §2.3); their shape follows Appearance ▸ Buttons.
- **Centre:** the camera zone (N + 16) stays empty. On displays without a notch it shows the time and date.
- **Takeovers:** while a HUD leads (§10) or the Pause Live Activities confirmation shows (§9.2), its views replace the tabs and actions for its lifetime (`contentSwap`), left and right of the camera zone. The open shape never changes.

### 6.3 Grid

- **Rows:** always 2 (3 only during Notes focus).
- **Widths:** a widget is an integer number of cells: `width(n) = n·cell + (n−1)·gutter`. The Nook's width is the sum of its visible widgets, clamped between the header minimum (N + 2·160) and `maxWidth`.
- **Overflow:** a layout that exceeds the maximum columns is refused in the editor ("2 cells over; move a widget to another page"). The Nook never scrolls horizontally.
- **Styles** (Appearance ▸ Widgets):
  - **Cards** (default): smoked `card` + 1-px `hairline`.
  - **Flat with dividers:** no fills; a 1-px `hairline` divider in a doubled gutter, inset 10 pt at top and bottom. The light layer is capped at Subtle and sits under a `scrim` in the grid area.
- **Padding fine-tune:** a panel padding of ±4 pt on top of the density. Radii follow automatically and stay concentric.

### 6.4 Command palette (⌘K)

- **Layout:** it replaces the grid area at the same height, so the shape does not move.
  - A 28-pt search field in a `well` (r 8), then up to 4 result rows of 22 pt each.
  - Each row: icon 16, title (`body`), kind (`caption`, tertiary) and its shortcut as a `KeyCap`.
- **What it searches:**
  - actions ("Start 25-minute timer", "New note", "Pause live activities for 1 hour", "Demo mode", "Clear Tray");
  - quick apps, Shortcuts.app shortcuts, notes, to-dos and Settings panes.
- **Empty query:** the shell lists only its four actions (Pause for 1 hour, Demo mode, Keep open, Show tutorial); its Settings panes appear once the user types. While the tutorial runs, "Skip tutorial" is a command too.
- **Keys:** ↑ ↓ ↩ navigate; Esc returns to the grid. Running a command returns the panel to the grid.
- While the light is on, a `scrim` sits behind the palette (and behind the catch zones, §8.3), so text never sits on light.

### 6.5 Hold ⌘ for hints

Holding ⌘ for 0.5 s makes `KeyCap` hints appear on every tab, action and quick-app tile (⌥1–⌥9): in the 32-pt band there is no room beside them, so the key cap replaces the glyph in place (§1.7). They disappear on release. VoiceOver gets the same shortcuts as accessibility hints instead. Hints for a focused widget's own commands need a widget-command contract that does not exist yet.

### 6.6 Edit layout (⌘E, or from Settings)

- **Visuals:** cards get a dashed `stroke` outline and an 8 × 24 resize handle on the trailing edge. Tiles wiggle; under Reduce Motion they show a "–" badge instead, which is also a remove button.
- **Pointer:**
  - Drag to reorder (`listReorder`).
  - Drag the handle to resize in whole cells. It snaps with an `.alignment` haptic per cell and shows a "4 cells" tooltip.
  - **Header while editing:** the open shape is exactly as wide as the page's widgets, so there is no room for a trailing "+" tile. The header's actions are replaced by "N cells left" (just N when the zone is narrow), an **Add widget** menu (the widget library) and **Done** (↩).
- **Keyboard:** ⌥← / ⌥→ move the focused widget; ⌥⇧← / ⌥⇧→ resize it. Every change is announced to VoiceOver, and so are a resize or removal from a card's ⋯ menu. ↩ or Esc finishes.

### 6.7 Widget sizes (cells wide × 2 rows)

| Widget | Min | **Default** | Max | What changes with width |
|---|---|---|---|---|
| Media | 4 | **5** | 6 | 4: 72-pt artwork, transport under the title · 5: 96-pt artwork + the ⌁ output menu · 6: + shuffle and repeat |
| Calendar | 2 | **3** | 5 | 2: next 2 events, times only · 3: header + rows + Join · 4: + day strip · 5: two columns, the selected day and the next (clamped to the days behind/ahead; ‹ › page both) |
| Quick Apps & Shortcuts | 1 column | **2** | 6 | Each column is 2 tiles; tiles that don't fit go into a "+N" tile |
| Mirror | 2 | **2** | 3 | 3: wider 4:3 preview |
| Notes | 3 | **4** | 8 | 3: the focus button moves into the ⌄ menu · ≥ 6: note list sidebar (1 cell at 6–7, 2 cells from 8 and in focus mode) + line numbers in code mode |
| To-dos | 2 | **3** | 6 | 2: no header counter |
| Timer | 2 | **2** | 3 | 3: presets column beside the ring |
| AirDrop | 1 | **2** | 2 | 1: icon only |
| Files (mini shelf) | 3 | **4** | 8 | Recent tray items; the full Tray is a page |

### 6.8 Shared card anatomy

`.crannyCard(cells:)` sizes a card to `grid.width(cells)` × `grid.height` (120) with padding 12 and radius 20. The radius is set as the `containerShape`, so inner `ContainerRelativeShape` / `ConcentricRectangle` stay concentric.
- **No title bars.** Content identifies itself (artwork, date, icons), as in Apple's widgets.
- **Overflow menu:** hovering a card shows a 20-pt `ellipsis` button (tertiary, top-trailing). It holds widget options, *Resize*, *Remove* and *Edit layout…*, and is also available from the keyboard (⌘. on a focused card opens the same commands as a list popover) and as a VoiceOver action.
- **Every widget defines these states:**
  - content;
  - **empty** (one line + one action);
  - **needs permission** (one-line why + an inline button: the only place in the notch that a permission is requested; Settings ▸ Permissions and the Welcome window are the others, and Settings panes link to Permissions instead of asking; at 2 cells, where a sentence and a capsule don't fit, the whole card is the button);
  - **loading** (≤ 300 ms: nothing; longer: a quiet 2.5-pt ring);
  - **error** (a `danger` glyph + one line + retry).
- **Hover:** a card fill change only, nothing moves. Press: controls only.

---

## 7. Widgets

Each widget is a VoiceOver container named after itself and a keyboard `focusSection()`. Tab moves between widgets and arrow keys move within one. All copy is original.

### 7.1 Media (5 cells · 312 × 120 · content 288 × 96)

```
┌──────────────────────────────────────────────── r 20 ┐
│ ┌──────────┐  Midnight Window                    ⌁   │  title (15 semibold) · ⌁ airplayaudio route menu (tertiary, 12)
│ │ artwork  │  The Example Band                       │  artist (callout, secondary) · halo behind art (album glow)
│ │  96 × 96 │  ━━━━━━━━━━━━━━━━──────────────────────  │  scrubber 4 → 6 pt on hover, accent fill
│ │   r 8    │  1:24                           −2:11   │  caption mono, tertiary
│ └──────────┘          ⏮       (⏸)       ⏭           │  28 plain · 32 prominent (white, black glyph) · 28 plain
└──────────────────────────────────────────────────────┘
```
- **Interactions:**
  - Click the artwork to open the source app (tooltip "Open in Music", the player named as Finder names it; "Open the player" while its name is not known yet).
  - Drag the scrubber, or scroll horizontally over it, to seek (`.levelChange` haptic at 10 % steps). A scroll previews the position as it moves and seeks once when the fingers lift.
  - A two-finger swipe over the artwork or title changes the track.
  - Artwork swaps with `.blurReplace`.
  - A title that does not fit marquees once after a 1.5-s hover (never under Reduce Motion or Instant).
  - From 5 cells the ⌁ route menu; at 6 cells shuffle and repeat (repeat-one is `repeat` with a "1" badge).
- **States:**
  - Playing.
  - Paused: the play glyph via `.contentTransition(.symbolEffect(.replace))`, and the visualizer goes static.
  - Nothing playing: the last source's icon + "Nothing playing" (callout, secondary) + a prominent **Play** if resumable, or "Open Music" as a text link (`info`).
  - Unsupported player: title only.
  - A source Cranny cannot control (read-only): no transport and no transport keys; the activity offers only "Open in …".
  - Missing artwork: an accent gradient + `music.note`.
- **Keyboard:** Space play/pause · ⌘← / ⌘→ previous/next · ← / → seek ±10 s while the scrubber is focused (it passes ⌘, ⌥ and ⌃ arrows on).
- **VoiceOver:** "Now playing: Midnight Window by The Example Band"; actions Play/Pause, Next, Previous, Open in app; the scrubber is adjustable (±10 s).

### 7.2 Calendar (3 cells · 184 × 120)

```
┌──────────────────────────────── r 20 ┐
│ TUE  14 October               ‹  ›   │  micro (danger) + headline · ‹ › change day within days behind/ahead
│ ▍ Design review         10:30        │  3 × 14 calendar-colour capsule · caption title · caption mono time (secondary)
│ ▍ Standup — now · 12m left  [⦿ Join] │  live/next event: two lines, success Join capsule (person.2.wave.2.fill + "Join")
│ ▍ Lunch with Ana        13:00        │  past events today: tertiary + strikethrough (option "Show today's past events")
└──────────────────────────────────────┘
```
- **Rows:** 18 pt, single line. Only the live or next event gets two lines ("Now · 12m left" or "In 4m", in the guarded event colour) and the **Join** capsule when a meeting link is found in the URL, location or notes (Zoom, Meet, Teams, Webex, FaceTime, Slack huddle, Whereby, GoTo, Jitsi, Chime; each can be switched off in Settings ▸ Calendar). While a meeting is live, the meeting that "Meeting soon" announces is featured too (two two-line rows, live first), so its Join is one click away. Only meeting-like events (timed, under 12 h) are featured.
  - **The Join capsule in a row** says "Join" (Russian «Войти», the only short form; the peek, the tooltip and VoiceOver keep «Подключиться (к встрече)»). A featured row picks the first layout that fits: Join or the start time beside both lines; Join as an 18-pt pill on the title line with the status line at full width below (the hit area still reaches 24 pt; the row stays 32 pt); the glyph alone. Rows without a link show their start time on the title line in the second layout.
- **Scrolling:** "+3 more" (`caption`) sits in the header line, between the date and ‹ › or the day strip, so a 3-cell card keeps three rows; the weekday and the day number are never cut short: to make room the date shortens first ("14 October" → "14 Oct." → "14"), then "+3 more" becomes "+3" (VoiceOver and the tooltip keep "+3 more") and gives way where even that does not fit (a 5-cell column beside ‹ ›), and last a weekday whose abbreviation is a whole word takes its short form (pt-PT "quarta" → "qua."). `DayHeaderFitTests` measures the lines in every language. The fade covers only a row that is cut off: cuts under 10 pt are hidden, larger ones fade over at most 12 pt. The list opens at the top and scrolls only as far as a featured row needs.
- **Day strip:** at ≥ 4 cells, a strip of the days behind/ahead appears (0–7 each, from Settings), with today as a white capsule with black text.
- **States:**
  - Empty: "No more events today" + tomorrow's first event (tertiary); at 2 cells only its start time ("Tomorrow 10:00"), the title in the tooltip and VoiceOver.
  - No permission: "Show your events" (inline button → the EventKit prompt, just in time; at 2 cells the whole card is the button). Settings ▸ Calendar never prompts: it offers "Permissions…".
  - All calendars hidden: "Calendars: 0 of 5 shown · Choose…".
- **Keyboard:** ↑ ↓ events · ↩ or Space open in Calendar · ⌘J join (the selection, else the live meeting, else the next one with a link) · ← → change day; at 5 cells ← → first move between the two columns, then page. The 2-cell widget is focusable too.
- **Birthdays:** the Birthdays calendar's checkbox in Settings ▸ Calendar's list (there is no separate row).

### 7.3 Quick Apps & Shortcuts (columns of 2 tiles)

- **App tiles:** 56-pt cells holding a 36-pt app icon (`NSWorkspace.icon(forFile:)`).
  - Hover: a `control` well (r 12) and a `.help` name.
  - Running apps get a 4-pt `secondaryLabel` dot under the icon, Dock-style.
- **Shortcut tiles:** a 29-pt continuous squircle (r 6.5) centred in the 36-pt icon cell, in the shortcut's colour or a stable hue hashed from its name, with its SF Symbol glyph or first letter (16 pt, white). macOS app icons carry transparent padding inside their 36-pt image, so the 29-pt body matches their visible size and a column of apps and shortcuts reads as one size (design ruling R1). The symbol comes from a curated list of SF Symbols (user content, so outside §14.1, each checked to exist and not be restricted).
  - Runs via `shortcuts run`.
  - While running: a 2.5-pt progress ring (≤ 8 fps, from the effect budget). Success: a check with `.symbolEffect(.bounce)`. Failure: a `danger` badge with a tooltip.
  - A result that no tile on screen shows (the shortcut sits in "+N", its page isn't showing, or it ran from ⌘K) flashes Done or Failed in the notch and is announced to VoiceOver (§16). Only runs the user started report anything; a run the user stopped reports nothing.
- **Overflow:** the Nook never scrolls, so tiles that don't fit go into a trailing **"+N"** tile whose menu (dropping down under the tile) lists them, with the combined run state of the shortcuts it holds.
- **Launching** an app closes the panel like a menu, except when the panel is pinned or in Demo mode. Demo mode hides shortcut names everywhere (tiles, tooltips, menus, ⌘K, VoiceOver).
- **Editing:**
  - Drag apps from Finder or the Dock onto the widget to add them (a drop with anything but apps goes to the Tray whole).
  - Edit mode does not wiggle: tiles get `xmark` remove badges, a dashed "+" tile adds items, and tiles drag to reorder (by their centre).
- **Keyboard:** arrows walk the tiles on screen, "+N" and "+"; ↩ or Space launch or open the menu; ⌥ + arrow moves a tile; ⌥1–⌥9 launch from anywhere in the Nook.

### 7.4 Mirror (2 cells · 120 × 120, frameless)

- **Off:** a dark gradient + `web.camera` (22) + "Preview camera" (caption, secondary). The whole card is the toggle: one click starts it (the camera permission is asked here on first use, never in onboarding). The panel stays open while the system asks and until the pointer, the focus or a click comes back to the card (at most 10 s).
- **On:** the preview fills the card (aspect-fill, r 20), mirrored by default.
  - A hover toolbar sits top-trailing: 24-pt circles on black 50 % with 12-pt glyphs, for flip (`flip.horizontal`) and, when there is more than one camera, a camera menu that lists every `AVCaptureDevice`, external and Continuity cameras included (a suspended one is listed as "(unavailable)").
- **Other states:** denied — "Camera access is off" and a chip **Allow…** («Разрешить…») that opens System Settings (its VoiceOver hint says so; the chip never says just "Settings", which means Cranny's own window). A suspended camera: if another camera works, the card returns to "Preview camera" (one click starts that one; the camera never switches by itself); only when every camera is suspended it says "Camera unavailable" (+ "The lid is closed" for the built-in camera). Errors use `web.camera` in `danger`.
- **Privacy:** never starts by itself; stops when the Nook closes or the page changes. The system's green camera indicator is the privacy cue, and Cranny adds nothing that competes with it.
- **VoiceOver:** "Camera preview, on".

### 7.5 Notes (4 cells · 248 × 120; focus = all columns × 3 rows)

```
┌──────────────────────────────────────────── r 20 ┐
│ deploy.md ⌄                       </>   ⤢   +    │  headline title (double-click or ⌘R to rename) · ⌄ note list · code toggle · focus · new (⌘N)
│ ## Release                                       │  body 13 / code 12 mono · insertion point in accent
│ let build = "1.4.2"                              │  code mode: SyntaxPalette, comments tertiary italic
│ retry(3) // flaky CI                             │
└──────────────────────────────────────────────────┘
```
- **Editor:** `NSTextView` with TextKit 2, line height 1.3 (the type tokens' fixed line heights), text directly on the card. The note list menu offers New, Rename and Delete. Delete confirms inside the card (Return deletes, Esc cancels); in the rename field Return commits and Esc cancels.
- **Saving:** at most 0.5 s after the first unsaved change. If a save fails, a warning in the header is a retry button; Cranny also retries after 5 s, 30 s and 2 min, then on the next edit or open.
- **Code mode:** Markdown plus common languages, auto-detected from a fence, shebang or extension (refreshed at most every 0.4 s while typing), or chosen in the menu. Line numbers (quaternary) appear at ≥ 6 cells. In very long notes (over 32 000 characters) a new character shows in the base colour for about a frame before its syntax colour lands; over 300 000 the note stays uncoloured.
- **Typing effect** (Appearance; on by default; off under Reduce Motion and Instant):
  - Newly typed characters appear in the accent and settle to `label` over 300 ms.
  - Implemented with TextKit 2 *rendering attributes* (`NSTextLayoutManager.addRenderingAttribute`), so the storage and undo stack are untouched, stepped by one display link and touching only the last ≤ 32 ranges.
  - Read-only animated text drawn by CrannyNotchUI or onboarding (tutorial bubble, welcome headlines) uses `CrannyEffects.TypewriterText`: a SwiftUI `TextRenderer` typewriter on 15+ and a plain fade on 14. Feature modules (peek rows) cannot import Effects and do not animate text.
- **Focus mode:** ⌘↩ or ⤢. The Nook holds open while a note is focused; Esc exits.
- **Type-to-capture:** if the Nook was opened by the shortcut and nothing is focused, the first printable key starts a new note or to-do (setting).

### 7.6 To-dos (3 cells)

- **Header:** "To-dos" (`eyebrow`) + "3 left" (`caption`, tertiary) while open to-dos exist; "All done" only when nothing is open and at least one to-do is checked; otherwise no count. After a failed save the header becomes §6.8's error ("! Couldn’t save your to-dos · Try again", shortened to "! Not saved" on narrow cards): one button with a tooltip, reachable by ↑ from the first row.
- **Rows:** 22 pt: a 16-pt circle (1.5-pt `stroke`; checked = accent fill with a black check that draws itself) + `body` text.
- **Completing:** the item is struck through, turns tertiary and, after 1.2 s, collapses with `listReorder` (option "Hide completed", on by default).
- **New items:** a trailing "New to-do" row (`plus`, quaternary). Return adds the next row, ⌫ on an empty row deletes it, Space toggles, ↩ on a selected row edits it, ⌘⌫ deletes it, ⌘↑ / ⌘↓ reorder. Esc while editing ends the edit first.
- **Options** (⋯ and Settings ▸ Layout & Widgets): Hide completed (a small switch, §11.3) and **Delete completed**, with Undo. Rows also have a context menu.

### 7.7 Timer (2 cells · 120 × 120)

- **Running:**
  - An 88-pt ring with a 5-pt stroke in `warning`. Remaining time inside (`numeral` 22) and the label in `caption`: the end time ("Ends 14:35" / «До 14:35»), or "Paused".
  - The digits roll (`.numericText(countsDown: true)`) only when the time jumps (start, +1 min, scroll, resume), never on a tick and never inside the last 10 s: rolling every second cost many times the CPU of the whole countdown (ARCHITECTURE §10.8).
  - Hover swaps the label for ⏸ and ⏹ (24 pt).
  - In the last 10 s the digits pulse once per second (Calm or Reduce Motion: colour only).
- **Idle:**
  - Preset chips 1 · 5 · 10 · 25 min in a 2 × 2 grid.
  - Scrolling over the face adjusts ±1 min (`.levelChange` per detent). At 2 cells scrolling, adjusting with VoiceOver or typing turns the presets into a set-up ring; at 3 cells the ring always shows the set-up value.
  - When focused you can type digits: "25" ↩ = 25 min, "90s" ↩ = 90 s (letters start nothing until a digit is typed).
  - VoiceOver: at 2 cells the face is one adjustable "Timer" element (value "Choose a duration") with one named action per preset (and the last duration); at 3 cells the preset chips stay separate buttons beside the ring.
- **Done:**
  - The ring pulses twice (`phaseAnimator`) and plays an ember burst; the widget shows "0:00" in `warning` with Stop and +1 min.
  - The notch auto-peeks "Timer done" with Stop and +1 min; the chosen *system* sound plays; VoiceOver announces it. Done lasts 1 min; a timer whose end was missed by more than a minute (asleep) ends silently.
  - The Start timer shortcut starts the last duration (default 5 min); while a timer runs it opens the panel on the Timer instead.
  - The timer keeps running as a live activity when the Nook closes.

### 7.8 AirDrop (2 cells)

- **Idle:** a `DropZone` with a dashed 1.5-pt `stroke` (r 8, concentric), `dot.radiowaves.up.forward` (22) and "AirDrop".
- **Drag over:** an `info` stroke (solid under Differentiate Without Color), `info` at 15 % fill, scale 1.03, `.bounce` and an `.alignment` haptic.
- **Drop:** shows the AirDrop picker (`NSSharingService(named: .sendViaAirDrop)`).
- **Click without files:** a tooltip, "Drop files here to send them with AirDrop".

### 7.9 Files (mini shelf, 4 cells)

The 6 most recent tray items as 44-pt thumbnails. It is also a drop target, and "Open Tray" (⌘2) jumps to the Tray page. Tiles behave as in §8.

---

## 8. Tray and pipelines

### 8.1 Tray page (full width)

```
┌──────────────────────────── files · (width − 2 cells) ───────────────────────────────┐ ┌ AirDrop · 2 ┐
│ ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐                                               │ │   ⦿))       │
│ │ QL │  │ QL✓│  │ QL✓│  │ ◔  │  │ QL │   tiles 64 × 66: 44-pt Quick Look thumb r 8   │ │  AirDrop    │
│ └────┘  └────┘  └────┘  └────┘  └────┘   + caption (11, middle-truncated)            │ └─────────────┘
│ Brief.pdf hero@2x… notch.heic assets.zip IMG_2041…                                   │
│ 2 selected  (⤡ Compress) (⟳ Convert ▾) (⇲ Resize ▾) (Zip) (🔗 Copy paths) (✦ Web export) … │  22-pt chips
└──────────────────────────────────────────────────────────────────────────────────────┘
```
- **Tiles:** `QLThumbnailGenerator` thumbnails. The row scrolls horizontally with a fade mask. A tile follows Text size: 64 × 66 at Standard, 72 × 68 at Large, 79 × 70 at Extra Large, with the caption clear of the selection ring; at Compact density the gap between the tile row and the chip row shrinks instead of the tiles.
  - Hover shows a remove ✕ (a 16-pt circle).
  - Selected: a `controlPressed` well (r 8), a 1.5-pt accent ring and a 14-pt check badge (the badge is not colour-only).
- **When nothing is selected,** the chip row shows "5 items · 48 MB" and **Clear** (⌥⌘⌫). While the selection runs a pipeline (or anything runs and nothing is selected), a **Stop** chip (tooltip "⌘.") leads the row.
- **Interaction:** click, ⌘-click and ⇧-click select; ⌘A selects all; Space opens Quick Look (in Cranny's own non-activating preview panel); ⌘C copies; ⌘⌫ removes (with nothing selected it hides the error tiles of failed drops); ⌘. stops running pipelines. A click makes the panel key for the selection (§3.6), so these keys work while the panel stays a hover panel. Drag out goes through AppKit `NSDraggingSource` with `NSURL` writers, so the receiving app gets the original file, not a temporary copy (R1 §5.3); copies the Tray owns can be moved out (a move or Trash removes the item), the user's linked files only copied or linked. The context menu holds Stop (while running), Open, Reveal in Finder, Quick Look, Copy Path, Share…, Remove.
- **Dropping again:** an unchanged file moves to the front (retention and the cap count from the new drop); an edited original is copied again and replaces the old copy. Files that cannot be kept get an error tile ("Couldn’t read “X”", "Couldn’t keep “X”"), the Tray page opens and VoiceOver hears it once. "Keep at most" applies as soon as it changes; one drop larger than the cap is kept whole.
- **Copy paths and copied text:** the notch confirms with one word, "Copied" / «Готово», beside the copy glyph `doc.on.doc`, which carries "copied" (design ruling E4; the longer "Path copied" / «Скопировано» did not fit the wing). Copy paths (the chip, the context menu, VoiceOver's action) also tells VoiceOver "Path copied" / "Paths copied" («Путь скопирован» / «Пути скопированы»), since VoiceOver does not read the glyph (§16). The Copy paths chip and the context menu keep `link` as the action's own icon.
- **Retention:** Until removed (default) · Clear on quit · Clear after 1 day.
- **Empty:** `tray.and.arrow.down.fill` + "Drop files on the notch to keep them here".

### 8.2 Pipelines

Chips are contextual: only actions valid for **every** selected item are shown, as 22-pt capsules (`control`, glyph + `caption` semibold).

| Selection | Built-in actions |
|---|---|
| Images | **Compress** (HEIC or JPEG at quality 0.8, keeps dimensions; a result that is not smaller is refused: "Already as small as it gets") · **Convert ▾** PNG / JPEG / HEIC / TIFF · **Resize ▾** 50 % · max 1600 · max 2048 |
| Archives (.zip) | **Unzip** |
| Anything | **Zip** · **Copy paths** · **AirDrop** · Share… · Reveal in Finder · Remove |
| More (the "…" chip, where the types allow) | Remove background · Copy text · Strip metadata · Make PDF · Compress video (refuses a bigger result too) · Share… · Reveal in Finder · Remove |
| User pipelines ✦ (`wand.and.stars`) | Saved chains, for example "Resize 50 % → JPEG 80 % → Copy path", built in Settings ▸ Tray |

- **Running:** the source tile dims to 50 % behind a 22-pt `ProgressRing` (accent). Pipelines run off the main actor and are cancellable (✕ on the ring).
- **Result:** written next to the source (or to Downloads for files the tray owns and temporary files). It is added as a linked item and slides in beside the source with `listReorder` and a 6-pt accent "new" dot. An **Undo** chip stays for 5 s (Undo moves the results to the Trash). If only some results could be placed, those are kept and the source tile says "Couldn’t save the result". A `.generic` haptic plays and a VoiceOver announcement is made.
- **Pinned pipelines** are three slots in Settings ▸ Tray, "Drop zone 1–3"; clearing one never moves the others.
- **Error:** a `danger` `exclamationmark` badge on the tile; its tooltip and accessibility value say what failed, in one line.

### 8.3 The drag "catch" state

When a file drag enters the proximity zone (§3.6), the shape opens straight to the Tray geometry with **drop zones**, filtered by the dragged `UTType`s. Zones are laid out in grid cells:

```
[ Keep in Tray  (wide, ≥ 4 cells) ] [ AirDrop · 2 ] [ Compress · 2 ] [ Zip · 2 ] [ ✦ Web export · 2 ]
```
- **Which zones:** Keep in Tray and AirDrop always appear, followed by up to 3 **pinned pipelines** that accept the types.
- **Arming:** the zone under the pointer arms: accent at 15 % fill, a solid stroke, scale 1.03, `.bounce` on its glyph and an `.alignment` haptic.
- **Dropping on an action** runs the pipeline directly and keeps the result in the Tray. The shape "gulps" (§5.5).
- **Hit zone:** while the drag lasts, the enlarged zone is an `opacity(0.001)` fill, removed on drag end (R1). A drag that starts in Cranny (a tile dragged out) never opens the catch state. A drop on an AirDrop zone always counts as taken.
- While the light is on, a `scrim` sits behind the zones.
- **Leaving** the zones without dropping closes after the grace period.

---

## 9. Live activities

### 9.1 Compact anatomy

```
 ◜ │12u│  leading content  │8u│ ████ camera housing (N) — never draw here ████ │8u│  trailing content │12u│ ◝
       aligned → camera                                                           aligned ← camera
```
- `CompactSlots` (Appendix A) builds this: both slots are the same width, content hugs the camera, and the outer 12u keeps content off the corner curve.
- **One activity, one datum per side.** Leading and trailing always describe the *same* activity.
- **No free text in compact,** except `compactLabel` abbreviations that are tested in every language ("in 4m" / "4 мин") and the confirmation flash's word.
- **Confirmation flashes** (`NotchControl.flash`: onboarding's "Hi", the Tray's "Copied", Quick Apps' "Done" / "Failed"; and the shell's pause confirmation word; design ruling E4): a glyph on the leading side and one short word on the trailing side. The word must fit the wing **by measured width, never by character count**: the medium or the wide slot (the narrower one that holds it), measured in the `compact` style at every notch unit from 0.8 to 1.25, in every language. A word that fits neither leaves the glyph alone in the wings; the word stays in the peek row, the open header and for VoiceOver. Examples that fit: "Copied" / «Готово» with `doc.on.doc` (the glyph says what was copied), "Done" / «Готово», "Failed" / «Ошибка», "Hi" / «Привет», "Paused" / «Пауза», "Resumed" / «Активны». A test renders every flash label in every language of the String Catalogs at those units and fails if one does not fit (ARCHITECTURE §4.7), so a new label is listed and measured before it ships; the glyph alone is a safety net at run time, not a design choice.
- **Compact height = band height.** Compact never pushes down; only peek and open grow.

### 9.2 Activities

| Activity | Slot | Leading | Trailing | Peek row (52 pt) | Shows / auto-peeks | Priority |
|---|---|---|---|---|---|---|
| **Now Playing** | short | Artwork 20u, r 5u (+ halo with Album glow) | 5-bar visualizer: 3-pt bars, 2-pt gaps, 4–16 pt tall, accent; paused → 3-pt static dots | Artwork 40 r 10 · title `headline` / artist `callout` · ⏮ ⏯ ⏭ (28) · 2-pt progress | While playing; peeks 2.6 s on a track change (option) | P2; paused → P3, hidden after 30 s, auto-unhides on resume |
| **Meeting soon** | medium | Calendar-colour dot 7 + "in 4m" (`compactLabel`; Russian «4 мин») | **Join** capsule 34 × 20, `success` with a black `person.2.wave.2.fill` (if there's a link), else the start time | Title · "10:30–11:00 · Room 4" · **Join** (prominent) · Dismiss | N min before (default 5), again at 1 min | P1 for 60 s from when each stage first shows (also when it shows late: after a wake, a launch, a raised lead time), then P2 |
| **Meeting in progress** | medium | Elapsed ring 16u in the calendar colour | "−12m" left or "+12m" elapsed (`compact`; "−1:30" from an hour on, the Media widget's sign convention); "12m left" (53 pt) does not fit the 48u slot. The full phrase is in the peek and VoiceOver | Title · elapsed / remaining bar (2 pt, `success`) · Join | During the event (option: elapsed or remaining) | P2 |
| **Timer** | medium | Ring 16u, 2.5 stroke, `warning` | "4:59" (`compact`; `warning` in the last minute) | Ring 40 · "Ends 14:35" (or "Paused") · ⏸ ⏹ · +1 min | While running; peeks at 1 min left (option; the only peek, a running timer never peeks on change) | P2 |
| **Timer done** | medium | `timer` in `warning` (+ `.bounce`) | "Done" | Stop · +1 min | Until dismissed or 1 min | P1 |
| **Charging** | short | `bolt.fill` in `success`; plugged in but not charging, `powerplug.fill` in `secondaryLabel` ("Plugged in" / "Not charging"); unplugged, the drawn battery with "On battery", no light, no sweep | "82%" (`compact`; falls back to `compactLabel`, then drops the space; never truncated, never below 10 pt) | Code-drawn battery 24 × 12 (exact fill) · `numeral` % · "1 h 20 m to full" | The peek duration (Live Activities, default 2.6 s) on plug / unplug | P1, transient |
| **Low battery** | short | First warning: `battery.25percent` + "!" in `warning`. Final warning: `battery.0percent` + "!" in `danger` (the role sets the colour, whatever the thresholds) | "10%" in the same colour | … + **Low Power Mode…** button (opens Battery settings; there is no public API to toggle it, ARCHITECTURE D18); when Low Power Mode is already on, the level in `numeral` and "Low Power Mode is on" in `caution` instead | At 20 % and 10 % (thresholds are the activity's option). A first warning lasts the peek duration; the final one stays on battery until the level is 3 % above it or power connects, so a gauge wobbling 10 ↔ 11 % never hides it | P1 |
| **Bluetooth device** | medium (ring + "84%" is 45 pt; `short` holds 32) | Device glyph: `airpodspro`, `airpodsmax`, `airpods`, `beats.headphones`, `earbuds`, `headphones` | 12-pt battery ring (`success`; < 20 % `warning`) + "84%", or ✓ when unknown | Name · L / R / Case rings with % | The peek duration on connect; the glyph bounces once per connection | P1, transient |
| **HUD** | wide | §10 | §10 | — | On key press | P0 |

**Interaction**
- **Hover** (180 ms) → peek (Settings: "Quick peek on hover"). **Click** compact or peek → open the Nook focused on the related widget.
- **Embedded controls** (Join, ⏯ in peek) are directly clickable. Hit areas are ≥ 32 × 24, padded beyond the glyph, with a hover `control` fill and a press scale. Compact has at most **one** interactive control (Join).
- **Swipe up** dismisses the activity until its next meaningful change: a new track, the last minute of a timer, a meeting starting.
- **Inactivity timeout** (Live Activities settings, 0 = never) collapses compact to closed but keeps the satellite.
- **Pause Live Activities** (menu bar extra, the Pause activities shortcut, ⌘K): for 1 hour · until tomorrow · until resumed. It silences activities, peeks and delight moments; the HUD still works.
  - **The Timer's done sound still plays** (design ruling R4): it is an alarm the user set. The Timer done activity itself follows the pause (no wings, no peek, no ember). Demo mode still mutes the sound (§14.3).
  - **Every pause or resume the user asks for confirms itself** (ruling R5), from the menu, the shortcut or ⌘K and for any duration, on the pointer's display, although activities are paused. The wings show `pause.fill` or `play.fill` with a short word, "Paused" / "Resumed" («Пауза» / «Активны»: each fits the wing by measured width, §9.1, which «Возобновлены» does not). Where that display shows peeks, a peek row spells out the sentence for the peek duration: "Live Activities paused for 1 hour" / "Live Activities paused until tomorrow" / "Live Activities paused" / "Live Activities resumed" («Активности приостановлены на 1 час» / «… до завтра» / «Активности приостановлены» / «Активности возобновлены»); the menu's status line uses the same sentences. While that display's panel is open, the confirmation takes the header row for the same time, as the HUD does (§10): the glyph left of the camera, the sentence right of it when it fits that side on one line, else the word, also when another alert leads. VoiceOver hears the sentence (§16). A pause that ends by itself, Reset All and Undo are not confirmed. Design ruling E1 keeps this split: the short word in the compact wings, the full sentence in the peek row, the open header and VoiceOver.

### 9.3 Peek anatomy

The band row stays exactly as it was in compact (its elements persist and move). Below it, each 52-pt row is laid out as:

`[12] [visual 40 × 40, r 10] [12] [title headline / subtitle callout, flexible] [8] [≤ 3 controls, 28-pt hit] [12]`

Peek is 380–460 pt wide (425 on a 14″) and always has the keyline and `Elevation.peek`. Rows without controls (Charging) end with their value in `numeral`. Hovering a row fills it with a `control` well (it is clickable: it opens the related widget).

### 9.4 Concurrency: priority and the satellite

- **Priority:**
  - **P0** HUD: transient; pre-empts everything for 1.5 s, then restores.
  - **P1** alerts: meeting soon, timer done, low battery, device connected, charging, song-change peek. Each peeks once, on the pointer's display only (or the primary display's panel when the pointer's display shows no Cranny). A confirmation flash ("Hi", "Copied") is P1 too but never peeks and is never announced; the Pause Live Activities confirmation is the exception (§9.2).
  - **P2** ongoing: meeting in progress, timer running, Now Playing.
  - **P3** passive: paused media.
- **One ongoing activity:** compact.
- **Two:** the higher one stays compact; the other becomes the **satellite**.
  - A Ø 24u black circle, 6u beyond the trailing edge, vertically centred in the band, showing its minimal glyph (ring, artwork or calendar dot).
  - Click it to swap the two. Swipe up on it to dismiss it.
- **Three or more:** the satellite shows the second-highest; a hover peek lists all of them as stacked rows (at most 4).
- **Transient P1 and P0** activities temporarily take the wings (`activitySwap`) and then hand them back.

---

## 10. HUD (volume, brightness, keyboard backlight)

```
 ◜╭──────────── 92 ─────────────┬═══════════ camera (185) ═══════════┬──────────── 92 ────────────╮◝
  │        (62)  🔊 13 pt       │                                     │  ━━━━━━━━━━━━──────  64u × 6 │   369 × 32 · r 13 · ears 6
  ╰─────────────────────────────┴═════════════════════════════════════┴────────────────────────────╯
```
- **Geometry:** `NotchLayout.hud` (369 × 32 on a 14″). It never adds height. On floating-island displays it is a 184 × 24 pill.
- **Leading:**
  - A 13-pt semibold glyph, hugging the camera: `speaker.wave.3.fill` with `variableValue`, `speaker.slash.fill` when muted (mute always wins), `sun.min.fill` below 50 % and `sun.max.fill` above, `light.max` (`light.min` at 0).
  - When the output device changes, the next unmuted volume HUD shows the device glyph with one `.bounce` (none under Reduce Motion or Instant). A device change never shows a HUD of its own.
  - Optional value "62" (`compactLabel`, secondary) before the glyph (*Show value*).
- **Trailing:** `LevelBar`, 64u × 6, with a `control` track.
  - Fill: **white by default**. Settings ▸ HUD ▸ Style ▸ Colors offers Mono · Accent · Semantic (Russian «Белый · Акцент · По назначению»; accent for volume, `caution` for brightness, `info` for the keyboard).
  - Muted: the bar shows `tertiaryLabel`.
- **Steps:** 16 standard steps. Fine steps (⌥⇧) move in quarter steps and show 16 tick marks; ticks always show under Differentiate Without Color or Increase Contrast.
- **Motion:** `hudIn`, then `hudLevel` on the bar and digits only, plus a 2-pt bump at 0 % and 100 %; `hudOut` after 1.5 s (adjustable 0.8–3 s).
- **Never two HUDs:** the replacement needs an Accessibility event tap to suppress the system HUD. Without it, Cranny draws **no** HUD, and Settings ▸ HUD explains why with a status pill and a button that opens System Settings. When Cranny would not draw a HUD right now (the display with the pointer has its HUD toggle off or shows no Cranny, or the panel is hidden), the key goes to macOS, which shows its own. When the HUD activity is off in Live Activities, Settings ▸ HUD says so ("The HUD is off in Live Activities") with a button to that pane.
- **Defaults:** Volume on; Brightness and Keyboard backlight **off** until the private paths are verified on a MacBook with the lid open (ARCHITECTURE §10.20).
- **Sound:** if "Play feedback when volume is changed" is on in macOS, Cranny plays the same system feedback.
- **VoiceOver:** "Volume, 62 percent" is posted once the value settles (0.5 s), only while VoiceOver runs.
- **Full screen:** the HUD is allowed under the default full-screen policy.
- **While the panel is open:** the HUD's leading and trailing views take the header row, left and right of the camera, replacing tabs and actions with `contentSwap` for the HUD's lifetime. The open geometry never changes (ARCHITECTURE §4.11). The Pause Live Activities confirmation (§9.2) takes the header the same way; a HUD that leads wins over it.

---

## 11. Settings window

### 11.1 Structure

- **Window:** an AppKit-managed `NSWindow` hosting a SwiftUI `NavigationSplitView` (not a SwiftUI `Settings` scene, so Cranny can open any pane programmatically from an agent app — ARCHITECTURE D11). The sidebar is 190–260 pt (default 210) with `.searchable(placement: .sidebar)`. Default size 860 × 620, minimum 780 × 560; size and pane are restored.
- **Opening:** opening Settings from the menu bar extra activates the app and orders the window front, in response to the user's click (cooperative activation).
- **Appearance:** Settings follows system Light/Dark. On macOS 26+ the sidebar and toolbar get Liquid Glass from the system, and Cranny adds none of its own.
- **Sidebar:** each row has a 20 × 20 rounded-square icon (r 5, continuous) with a white glyph on a system colour, as in System Settings.

| Group | Pane | Icon (glyph on colour) | Contents |
|---|---|---|---|
| — | **General** | `gearshape.fill` / gray | Launch at login (`SMAppService.mainApp`) · **Show on** (built-in / with the pointer / all / chosen displays; the last chosen display cannot be unchecked) + a **per-display table**: style Automatic · Island · Attached · Off, Activities, Peeks, HUD · **Open Cranny with** Hover / Click / Shortcut only · Hover delay (Instant 0 · **Short 120 ms** · Standard 220 · Long 450) · Hold ⌥ to pass over · Close when the pointer leaves (+ grace) · Close after inactivity (Never, 5–60 s) · Hide when idle (no-notch handle, after 3–60 s, default 10) · In full-screen apps (Hide / **Alerts & HUD only** / Show) · Excluded apps (named as Finder names them, never by bundle ID; an app no longer installed reads "App not installed" / «Приложение не установлено» and can still be removed; a row still being looked up shows no name yet; the remove button says "Remove ‹app›" / «Убрать «‹app›»» to VoiceOver) · **Demo mode** (+ redact calendar titles) · UI sounds (off) · Show menu bar icon · Updates: check daily via GitHub Releases, Check Now, include pre-releases · **Reset All Settings…** |
| — | **Appearance** | `paintbrush.fill` / purple | Accent (Automatic / System / swatches / Monochrome) · Text size · **Motion** (Calm / Standard / Lively / Instant) · **Ambient light** (Off / Subtle / Vivid) + Effect (Aurora / Motes / Tide) + Quality (Detailed / Efficient, §5.7) · Album glow · Underglow · Progress rim · Translucent background · Glass island (26+) · Buttons (Capsule / Rounded) · Widgets (Cards / Flat with dividers) · Density + panel padding ±4 · **Notch fit** (width ±10, radius ±3, live outline) · On displays without a notch (Floating island / Attached / Off) + handle (Visible / Hidden until hover) · Typing effect |
| — | **Keyboard** | `keyboard` / indigo | Shortcut recorders: **Open Cranny ⌃⌥N** (on), Open Tray, New note, Start timer, Toggle pin, Pause activities (off by default) · type-to-capture target (Notes / To-dos / Off; **Off on a fresh install**, design ruling E2, so a fresh install shows no warning: picking an onboarding preset that puts Notes on Home sets Notes, one with To-dos and no Notes sets To-dos, §12.1; an install from before the ruling keeps Notes; a value the user chose is never changed), with an inline warning while that widget is on no page ("The Notes widget isn’t on any page, so typing does nothing.", plus "No page has room for it; add a page first." when no page can take it): the text above a **Show in Layout & Widgets** button, which opens that pane at the widget's library entry on a page with room for it, or at Pages · read-only in-panel reference (the same data as the hold-⌘ overlay). Conflicts are flagged inline: registration failures, plus a best-effort match against the enabled system shortcuts (`com.apple.symbolichotkeys`). |
| Notch | **Layout & Widgets** | `square.grid.2x2.fill` / blue | **Grid editor on the preview stage** (§6.6) · pages (add, rename, reorder, up to 3 user pages; a "…" menu after "+" holds Rename, Symbol, Move left/right and Remove Page for mouse, keyboard and VoiceOver) · widget library ("+", with one-line descriptions) · per-widget options in a popover: Calendar days behind/ahead and past events, Mirror camera and mirroring, Notes typing effect and default mode, To-dos hide completed, Timer presets and sound, Media visualizer in the widget · opening the pane at a widget (the Keyboard warning, search, a deep link) shows a page that holds the widget or has room for it, so its Add works |
| Notch | **Live Activities** | `capsule.tophalf.filled` / pink | A **draggable priority list** (a dropped row takes the target's place within its priority class; also Move up / Move down in the row's menu, ⌥↑ / ⌥↓ and VoiceOver actions) with a toggle per activity and, under each, the activity's own options supplied by its module: peek on change (per activity) · meeting lead time (1–30 min, default 5) and show while in an event (elapsed / remaining) under the meeting rows · hide paused media after N s under Now Playing · peek at one minute left under Timer · thresholds under Low battery · "Show all Bluetooth devices" under Bluetooth. Global rows: peek duration · swipe up to dismiss · auto-unhide · quick peek on hover · satellite · Fold away after (compact inactivity; Never, …) · menu-bar courtesy |
| Notch | **HUD** | `speaker.wave.2.fill` / teal | Replace the system HUD (needs Accessibility; status pill + why; a row when the HUD is off in Live Activities, §10) · **Show the HUD for** Volume / Brightness / Keyboard backlight (the last two off by default) · **Style**: Colors (Mono / Accent / Semantic) · Show value · Show output device · Duration · a warning when a known HUD app competes |
| Notch | **Gestures** | `hand.draw.fill` / orange | Swipe sideways to change track (+ Invert) · Swipe down to open, up to close · Swipe up to dismiss an activity · Sensitivity · **Haptic feedback** + "Feel it" test button |
| Features | **Media** | `music.note` / red | Source status (the helper in use and the last error; `success` running, `warning` degraded, `danger` unavailable, `tertiary` not started) · ignore apps (named as Finder names them; an ignored app that is no longer installed reads "App not installed"; a player whose name is not known yet is not offered) · show browser media · Apple Events fallback for Music/Spotify (off; while on, one Automation row per installed player, named by Finder, with a small spinner until macOS's first answer, then Allowed, Allow…, Open System Settings… (denied) or "Open the app to allow" (the player is not running); players are looked up again when the section appears) · **Visualizer**: Live (asks for System Audio Recording, with a why-sheet) / **Ambient** / Static / Off · peek on track change · artwork in compact · Test media detection. No "source priority": macOS exposes only the system's current now-playing app (R2), so the ignore list is the control. |
| Features | **Calendar** | `calendar` / red | Calendars (a checkbox list with colours; the Birthdays calendar's box shows birthdays) · days behind / ahead · today's past events · meeting-link providers (the 10 of §7.2) · open meetings in the app or the browser · without access: "Permissions…" (never a prompt) |
| Features | **Shortcuts** | `square.2.layers.3d.fill` / indigo | One list of every tile in launcher order (apps and Shortcuts.app shortcuts; add, search, reorder with Move Up/Down, drag from Finder or the Dock; Customize… for symbol and color) · tile labels. An app row shows Finder's name, never a bundle ID; an app that is no longer installed has the one-line title "App not installed" / «Приложение не установлено» in orange and can still be removed; a row whose app is still being looked up shows no name yet |
| Features | **Tray** | `tray.full.fill` / green | Retention · max items · dropping on the notch opens the Tray · AirDrop zone · **pinned pipelines** (Drop zone 1–3) · **pipeline editor** (a chain builder: steps, reorder, a preview of the output name) · defaults: JPEG quality, max dimension, output location, zip naming |
| — | **Permissions** | `hand.raised.fill` / blue | Calendar · Camera · Accessibility · Automation (per installed media app, named as Finder names it; an app that is not installed has no row; a small spinner until macOS's first answer, never a wrong status) · Bluetooth · System Audio Recording (optional): a status pill (Granted / Not yet / Denied) + a one-line why + Grant… or Open System Settings |
| — | **About** | `info.circle.fill` / gray | The live icon · version · Check for Updates · release notes · GitHub · MIT licence · acknowledgements · **Replay tutorial** · Show welcome |

### 11.2 The live preview stage (the signature of Settings)

- **Placement:** a 176-pt band pinned at the top of every pane except Permissions and About.
- **What it renders:** the **real** notch views, fed by the **live** settings (every change applies instantly, ARCHITECTURE D14; Reset All has a 10-s Undo), over a miniature of the user's own wallpaper (`NSWorkspace.desktopImageURL(for:)`, read only when the file is outside Desktop, Documents, Downloads and removable volumes — reading those would raise a Files & Folders prompt from Settings; otherwise a neutral dark gradient) and a miniature menu bar.
  - Closed, compact, peek and HUD render at 1:1, so the type is crisp. The open Nook is scaled to fit (never below 0.75).
- **Controls:**
  - A segmented picker: Closed · Activity · Peek · Open · HUD. It auto-selects the state that is relevant to the pane.
  - **Simulate** chips: Song change · Timer · Meeting · Volume · Drop file.
  - **Show on Notch** plays the preview on the real notch for 5 s.
- **Behaviour:** every control change animates the stage with the real motion tokens, so nobody toggles blind. Under Reduce Motion it updates without looping demos.

### 11.3 Controls and conventions

- **Controls:** `Form { … }.formStyle(.grouped)`; `Toggle` with `.switch` and `.controlSize(.small)`; segmented pickers for ≤ 4 options, menu pickers otherwise; sliders always show their value with units and ticks at meaningful stops ("120 ms", "±0 pt"); steppers for minutes.
- **Footnotes:** every non-obvious row has a one-line footnote in `.secondary`.
- **Non-default values:** a 6-pt accent dot before the label marks a changed value. Every row that holds a value has **Reset to Default** in its context menu (VoiceOver gets the action only on changed rows; Launch at login and Reset All have none); every pane footer has **Reset ‹Pane›…**, which keeps the Live Activities pause and the last update check (records, not preferences). The conventions are Core's `crannySettingRow`, so module panes match.
- **Reset All Settings…** is destructive (red), asks for confirmation and offers undo for 10 s.
- **Search** matches pane names, row labels and localized keywords ("volume" → HUD, "external monitor" → displays, "dock" → Quick Apps). Picking a result opens the pane, scrolls to the row and highlights it with an accent wash that fades over 1 s.

---

## 12. Onboarding and the interactive tutorial

### 12.1 Welcome window

- **Window:** 640 × 480, hidden title bar, not resizable, centred.
  - The **top half** is a preview stage (216 / 132 pt): a dark desktop with the brand aurora at Subtle, which is a still frame under Reduce Motion and off under Reduce Transparency or with Ambient light off. One light at a time: while the stage's panel is open the desktop aurora fades out, and while the window is hidden the stage holds a resting frame.
  - The **bottom half** holds copy and controls on the system background.
- **Navigation:** progress dots + "Step 2 of 6" for VoiceOver. ↩ continues, ⌘[ goes back, Esc asks "Skip setup?" (the close button counts as Skip). Every step can be skipped. Launch at login is applied only on Done or when the tutorial starts.

| Step | Content | Interaction |
|---|---|---|
| 1 · Hello | The **real notch** plays `activityIn` with `hand.wave.fill` and "Hi" (`NotchControl.flash`) while the stage mirrors it. Headline: "Look up. That's Cranny." One sentence about what it does. | Continue |
| 2 · Open it your way | Three option cards: **Hover** (with delay presets), **Click**, **Shortcut only** (⌃⌥N). A click-through coach mark around the real notch whose sentence follows the chosen mode ("Rest the pointer here, or press ⌃⌥N." / "Click the notch, or press ⌃⌥N" / "Press the shortcut"). | Detects the *actual* opening of the real notch: ✓ (green, `.bounce`) per method; Continue enables after one |
| 3 · Gestures | Only if a trackpad is present. A practice notch on the stage with live rubber-banding and haptics. | Pull down to open; swipe sideways (skipped if nothing plays) |
| 4 · Pick a starting layout | Preset cards, each a true-proportion static miniature with one glyph per widget (the stage above shows the live panel for the picked preset): **Listener** (Media 5 · Calendar 3 · Apps 2, the default), **Maker** (Notes 4 · To-dos 3 · Timer 2 · Shortcuts 1), **Meetings** (Calendar 4 · Mirror 2 · Timer 2 · Apps 2), **Minimal** (Media 4, HUD). Picking a preset also sets Type to capture (design ruling E2): **Notes** when the preset puts Notes on Home (Maker); To-dos for a Home with To-dos and no Notes; otherwise the current target stays only while its widget is still on a page, else Off. So a preset never leads to the Settings ▸ Keyboard warning, and a fresh install that keeps Listener has Type to capture Off | Pick one; the stage updates |
| 5 · Permissions, only for what you chose | Rows for the features the preset needs, all **off**: Calendar, Accessibility (HUD), Automation (installed players only: they are looked up again when this step appears and whenever Cranny becomes active, so a player installed meanwhile is offered without a relaunch), Bluetooth. Automation and Bluetooth serve off-by-default switches (the Apple Events fallback, all Bluetooth devices), so their rows appear only while that switch is on; the switch asks itself when it is turned on. Each row says why and what Cranny does *not* do; the fallback Automation reason names no app ("Control playback in your media apps when other ways fail…" / «Управлять воспроизведением в плеерах…»). Camera is never asked here; Mirror asks on first use. | Allow triggers the system prompt then and there; "Later" is fine. A row whose Automation answer is still on its way shows a small spinner, never "Allow" for a player that may already be allowed |
| 6 · You're set | Launch at login (on) · Check for updates (on) · a cheat sheet of 6 keys | **Take the 1-minute tutorial** (primary) · Done (opens the Nook once) |

### 12.2 Interactive tutorial (in the real notch)

- **The tip:** a bubble 10 pt under the shape, using `.regularMaterial` (opaque under Reduce Transparency). It holds one sentence, a `KeyCap` where relevant, "2 of 5" (`micro`) and an always-visible **Skip tutorial**. The feature is "tutorial" / «обучение» in every string, never "tour".
- **Steps:** each completes on real detection, with a ✓ `.bounce`, an `.alignment` haptic and a VoiceOver announcement.
  1. "Rest the pointer on the notch, or press ⌃⌥N"
  2. "Drag any file onto the notch"
  3. "Swipe sideways with two fingers to change the track" (skipped if nothing plays)
  4. "Hold ⌘ to see every shortcut"
  5. "Pin it with 📌, then press Esc"
  - Steps 4 and 5 need the panel to be key: the tutorial asks for keyboard focus when the panel opens by any route (or is pinned). While the panel is closed their bubbles say "Open Cranny, then …".
- **Visibility:** the bubble and the coach mark show only under a real shape, and hide whenever the notch hides (locked screen, sleeping displays, Live Activities paused, a full-screen app in front unless the full-screen policy is Show all or Demo mode is on). The step they wait for is kept.
- **Ways out:** **Skip tutorial** on the bubble, and while it runs the same command in ⌘K and **Skip Tutorial** in the menu bar extra (§13); a step that waits 3 minutes ends the tutorial (with a VoiceOver announcement; nothing is recorded). Esc is not an exit: it is step 5's action and the notch's close key.
- **Step 1** follows the open mode: Hover "Rest the pointer on the notch, or press ⌃⌥N"; Click "Click the notch, or press ⌃⌥N"; Shortcut only "Press the shortcut" + key cap; no shortcut set "Click the notch".
- Replayable from the menu bar extra and from Settings ▸ About.

---

## 13. Menu bar extra

- **Scene:** `MenuBarExtra(isInserted:)` with `.menuBarExtraStyle(.menu)`: a standard native menu, nothing custom. The app is an agent (`LSUIElement = YES`) with no Dock icon.
- **Icon:** an original 18 × 14 template image: a rounded screen outline (1.5 pt) with a filled `NotchShape` tab at its top centre, drawn in code (`NSImage` drawing handler, `isTemplate = true`; no asset). The fallback symbol is `rectangle.topthird.inset.filled`. In Demo mode a 4-pt dot badge marks the icon. Its accessibility label is "Cranny".
- **Menu:**
  ```
  Open Cranny                      ⌃⌥N
  Keep Cranny Open                 (✓ when pinned)
  ───────────
  Pause Live Activities          ▸ For 1 Hour · Until Tomorrow · Until I Resume
                                   (while paused: "Live Activities paused until 8:50" + Resume Live Activities)
  Show On                        ▸ Display with the Pointer · ✓ Built-in Display · ✓ External Display · …
  Demo Mode
  ───────────
  Settings…                        ⌘,     (Button → AppControl.openSettings; no SwiftUI Settings scene)
  Check for Updates…               ("Checking for Updates…", "Update Available: Cranny x.y.z…")
  Show Tutorial
  Skip Tutorial                    (only while the tutorial runs)
  ───────────
  About Cranny
  Quit Cranny                      ⌘Q
  ```
- **Behaviour:** Open Cranny only opens (with a panel already open it opens again on the pointer's display with keyboard focus); only ⌃⌥N toggles. Show On ▸ lists "Display with the Pointer" with two or more displays, disables the last shown display's row, and turning on a display styled Off makes it Automatic (notched) or Floating island. **About Cranny** and **Check for Updates…** open Settings ▸ About, where the result shows inline; there is no alert. "Until Tomorrow" ends at the next local midnight. Each pause and Resume confirms itself in the notch and to VoiceOver (§9.2). **Skip Tutorial** ends the tutorial like the bubble's Skip tutorial, without recording it as completed.
- **Hide menu bar icon** (General): if the icon is hidden, launching the app again from Finder or Spotlight opens Settings, so nobody gets locked out.

---

## 14. Symbols, haptics, sound

### 14.1 SF Symbols

Every symbol below was verified on this machine against `name_availability.plist` (minimum macOS shown) and `symbol_restrictions.strings`. They are listed by role in `CrannySymbol` (`CrannyCore/DesignSystem/Symbols.swift`); a Core unit test checks that the list matches this table, that every name exists on macOS 14 and that none is restricted except the ⚑ product glyphs. Add a symbol to both before using it.

| Role | Symbols (minimum macOS) |
|---|---|
| Header, pages | `square.grid.2x2.fill` · `tray.full.fill` · `note.text` (11) · `magnifyingglass` · `pin` / `pin.fill` · `gearshape.fill` (11) · `ellipsis` · `plus` · `minus` (edit layout) · `xmark` · `chevron.down` · `checkmark` · `square.resize` (14, card size menu) |
| Media | `play.fill` · `pause.fill` · `backward.fill` · `forward.fill` · `shuffle` · `repeat` · `airplayaudio` · `music.note` · `music.note.list` · `waveform` |
| Calendar, meetings | `calendar` · `person.2.wave.2.fill` (12, Join) · `clock` · `mappin.and.ellipse` · `chevron.backward` / `chevron.forward` (day paging; they flip right to left) |
| Launcher | app icons via `NSWorkspace` (an app in a protected folder such as Downloads is drawn with macOS's generic app icon, because its bundle is never read) · `app.dashed` (12, placeholder: a missing app, the empty widget, ⌘K "Open …") · `square.2.layers.3d.fill` (14, the Quick Apps widget's identity glyph and the Shortcuts pane) |
| Mirror | `web.camera` (13) · `camera.fill` · `flip.horizontal` |
| Notes, to-dos | `chevron.left.forwardslash.chevron.right` (12) · `arrow.up.left.and.arrow.down.right` / `arrow.down.right.and.arrow.up.left` (focus) · `checklist` (12) · `circle` · `checkmark.circle.fill` |
| Timer | `timer` · `pause.fill` · `stop.fill` · `arrow.counterclockwise` |
| AirDrop, Tray | `dot.radiowaves.up.forward` (12; there is no public `airdrop` symbol) · `tray.and.arrow.down.fill` · `doc.zipper` (11) · `photo.badge.arrow.down` (14, compress) · `arrow.triangle.2.circlepath` (convert) · `square.resize` (14, resize) · `link` · `doc.on.doc` · `square.and.arrow.up` · `folder` · `eye` · `trash` · `archivebox` · `wand.and.stars` · `arrow.uturn.backward` (undo) · `arrow.up.forward.app` (11, open) · `checkmark` · `doc` · `doc.richtext` · `eye.slash` · `film` · `scissors` · `text.viewfinder` (12) · `xmark` · `exclamationmark` (pipeline steps and states) |
| HUD, power | `speaker.wave.3.fill` (variable value) · `speaker.slash.fill` · `sun.max.fill` · `sun.min.fill` · `light.max` · `light.min` · `bolt.fill` · `battery.100percent.bolt` · `battery.25percent` · `battery.0percent` (14) · `exclamationmark` · `powerplug.fill` (12, plugged in, not charging) |
| Devices | `airpodspro` (11) · `airpodsmax` (11.3) · `airpods` ⚑ · `airpods.gen3` ⚑ · `beats.headphones` ⚑ · `earbuds` (12) · `headphones` · `computermouse` (12) · `magicmouse` ⚑ (12) · `keyboard` · `rectangle.and.hand.point.up.left.filled` (12, trackpad) · `hifispeaker` · `gamecontroller` · `display` · `dot.radiowaves.left.and.right` (any other Bluetooth device) |
| Settings, onboarding | `gearshape.fill` · `paintbrush.fill` · `keyboard` · `capsule.tophalf.filled` (12) · `speaker.wave.2.fill` · `hand.draw.fill` · `hand.raised.fill` · `info.circle.fill` · `hand.wave.fill` · `cursorarrow.motionlines` · `cursorarrow.click` (11) · `sparkles` · `accessibility` ⚑ (14) · `laptopcomputer` · `display` · `exclamationmark.triangle.fill` (a warning row) · `minus.circle.fill` (remove a list entry) |
| Menu bar fallback | `rectangle.topthird.inset.filled` (12) |

- ⚑ **Restricted:** these may only refer to that product or feature: AirPods, Beats headphones, a Magic Mouse, Apple's Accessibility features. Use them only for exactly that.
- **Never use** `video`, `video.fill` or any `video.*` symbol (FaceTime only), `airplay.audio` (AirPlay only; use `airplayaudio`), `macbook*` (MacBook only; use `laptopcomputer`), `safari` or `message`.
- **Rendering:**
  - Hierarchical, white. Semibold at 13 pt in the band; medium in the Nook; transport glyphs at 48 % of the button size.
  - Symbols animate only on a state change: `.contentTransition(theme.symbolReplace)` for toggles, `.crannySymbolBounce(value:)` for an armed drop target, a device change or a completed step. There are no looping symbol effects, and none under Reduce Motion or Motion ▸ Instant (both helpers check `theme.animatesSymbols`).
  - Sizes come from `CrannySymbolStyle` (`.crannySymbol(_:)`): `band` 13 semibold × notch unit · `nook` 13 medium · `peekVisual` 18 semibold · `widgetState` 20 medium · `dropZone` 22 medium (Nook styles follow Text Size).

### 14.2 Haptics

Haptics use `NSHapticFeedbackManager.defaultPerformer.perform(_, performanceTime: .now)`. They reach the user only while a finger is on a Force Touch trackpad, so **every haptic has a visual counterpart**. Gestures ▸ Haptic feedback turns them all off.

| Event | Pattern |
|---|---|
| A gesture crosses its commit threshold (track, open, close, dismiss), fired once while the finger is still down | `.alignment` |
| A drag enters a drop zone · the grid editor snaps to a cell · the calibration slider crosses 0 · a tutorial step completes | `.alignment` |
| A value detent: scrubber at 10 % steps · timer minute · HUD reaching 0 or 100 | `.levelChange` |
| A drop is accepted · a pipeline finishes · a to-do is completed · the Nook opens by gesture | `.generic` |
| **Hover, peek, an activity arriving** | **never** |

### 14.3 Sound

**None by default; Cranny ships no audio files.**
- **Timer finished:** a user-chosen *system* alert sound (`NSSound(named:)`) or None. The picker shows each sound under its System Settings ▸ Sound name, in both languages, sorted by that name (the file "Glass" shows as "Crystal" / «Кристалл»); the setting stores the file name. It plays even while Live Activities are paused (§9.2, ruling R4).
- **HUD:** mirrors the system's "Play feedback when volume is changed".
- **UI sounds** (General ▸ UI sounds, `general.uiSounds`, off by default): "Pop" when a file is caught and "Tink" when a to-do is completed (both system sounds, played by name; never copied into the app).
- Demo mode mutes everything.

---

## 15. App icon: "Light from the nook"

**Concept.** A graphite slab (the Mac at night). Its top edge carries a precise notch silhouette, built from the **same `NotchShape`** as the app, and a soft fan of light spills from beneath it: a mint core, then sky, then iris, with a faint rose edge. It reads as "a small opening where useful things live". At 16 px it stays legible as a dark tile with a notch and a bright crescent. It shares no shapes or colours with any competitor's icon.

**Icon Composer (macOS 26+): `App/AppIcon.icon`** (the name must match `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, ARCHITECTURE §8.2; the verification below used the scratch name `Cranny.icon`). Compiled with `actool --app-icon AppIcon --minimum-deployment-target 14.0`, which produces `Assets.car` **and** a fallback `AppIcon.icns` for macOS 14/15. The first group is the top-most. The listing is the repo's `icon.json` as WP0 shipped it; the repo file wins if they ever differ.

```json
{
  "fill-specializations" : [
    {
      "value" : {
        "linear-gradient" : [
          "display-p3:0.17000,0.18000,0.22000,1.00000",
          "display-p3:0.05000,0.05000,0.07000,1.00000"
        ],
        "orientation" : { "start" : { "x" : 0.5, "y" : 0 }, "stop" : { "x" : 0.5, "y" : 1 } }
      }
    },
    {
      "appearance" : "dark",
      "value" : {
        "linear-gradient" : [
          "display-p3:0.04000,0.04000,0.05000,1.00000",
          "display-p3:0.02000,0.02000,0.03000,1.00000"
        ],
        "orientation" : { "start" : { "x" : 0.5, "y" : 0 }, "stop" : { "x" : 0.5, "y" : 1 } }
      }
    }
  ],
  "groups" : [
    {
      "name" : "Notch",
      "layers" : [ { "name" : "notch", "image-name" : "notch.png", "glass" : true } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.6 },
      "translucency" : { "enabled" : false, "value" : 0 },
      "specular" : true
    },
    {
      "name" : "Light",
      "layers" : [ { "name" : "light", "image-name" : "light.png", "glass" : false, "blend-mode" : "plus-lighter" } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
```
- **Layers are generated:** `scripts/render-icon.swift` (`make icon`) draws both PNGs with CoreGraphics; change the script, never the PNGs.
- **Notch group:** `notch.png` is a 1024 canvas with the notch path hanging from y = 0, built like `NotchShape` (continuous bottom corners, quarter-circle ears): body 0.40 × 0.15 of the 824-pt body width, ears 0.045, bottom radius 0.06. It is black. Glass is on, so the system's specular edge gives it the "precision" highlight.
- **Light group:** `light.png` (no background) holds two radial gradients:
  - the core #9EFFEB → #54C7F2 → transparent #8B6CFF at (512, 170), r 400, squashed 1.25× vertically;
  - a rose #FF4F8B lobe at 30 % at (650, 330), r 250.
  - A top fade (`destinationIn`, 12 % at y 40 → 100 % at the notch's bottom edge + 70), so the light seems to come from beneath the notch rather than beside its ears.
  - Blended plus-lighter, with glass off so the light stays soft.
- **Appearance variants:** **Dark** is a deeper fill (0.04 → 0.02), stored in `icon.json` as a `fill-specializations` entry for the dark appearance. **Tinted** and **Clear** let the system tint the light at 50 % while the notch silhouette carries the mark (WP-Final checks them on hardware).
- **Only two groups,** because Icon Composer warns when there are too many visible groups.

**In-app use:** About and onboarding show the compiled icon via `NSApp.applicationIconImage`; actool already generates the macOS 14/15 fallback, so v1 ships no second renderer.

**Flat fallback** (optional tooling, not built in v1: only if a build path ever skips actool; the layers come from `scripts/render-icon.swift`). `CrannyIconRenderer.draw(in: CGContext, side:)` uses CoreGraphics only, with no blur filters, so it renders identically at every size:
1. Follow the macOS icon grid: an 824-pt body centred on 1024, clipped by a continuous squircle (r 185.4, taken from `RoundedRectangle(style: .continuous).path(in:).cgPath`).
2. Draw a drop shadow: black 35 %, blur 28, y −10.
3. Fill the body with a P3 gradient from (0.20, 0.21, 0.25) to (0.055, 0.058, 0.07).
4. Add the light: the same two radial gradients with `plusLighter`.
5. Fill the notch path (from `NotchShape`, flipped into CG space) with black.
6. Stroke a 4-pt mint rim (#9EFFEB at 70 %) along the notch's *lower* outline: the product's keyline as a motif.
7. Stroke a 10 % white inner highlight along the squircle.

A build script could render 16–1024 px for an `AppIcon.appiconset`; it is needed only if a build path ever skips actool.

---

## 16. Accessibility

| Setting / need | Behaviour |
|---|---|
| **Reduce Motion** | §4.2: open, close and resize become dissolves at the final size; small morphs lose their bounce; no blur, scale, slide, stagger, marquee, typing effect, pulse, ember or neck; the light freezes on a resting frame; the visualizer shows static dots; rubber-banding releases without overshoot. |
| **Reduce Transparency** | The `opaque` palette. Translucent background, glass island, light layer and underglow are off. The tutorial bubble is opaque. |
| **Increase Contrast** | The `highContrast` palette: opaque cards, a 34 % hairline on every card, tertiary 9–11:1, quaternary 5.3:1, **keyline always on (45 %)**, accessible semantic variants, accent guarded at 7:1, light capped at Subtle, HUD ticks. |
| **Differentiate Without Color** | Colour is never the only carrier. Low battery adds "!" and a stepped glyph (`battery.25percent` at the first warning, `battery.0percent` at the final one); plugged in but not charging shows a plug, not a grey bolt; Join always has its glyph *and* "Join" text in peek and the Nook; a live meeting says "Now"; past events are struck through as well as dimmed; a timer's urgency is carried by its digits, not its colour; an armed drop zone turns its dash solid; selected files carry a check badge; pipeline errors show "!" with text; the HUD shows ticks and the value. |
| **Text size** (Cranny setting) | S / M / L / XL = 0.92 / 1 / 1.12 / 1.24 on every Nook and peek style, **and the cell grows** (56 → 68 at XL), so nothing clips. Band text follows the notch unit; at L and XL, compact text activities switch to their glyph form and the details move to the peek. |
| **VoiceOver** | See below. Hover-to-open turns off automatically while VoiceOver runs. |
| **Keyboard / Full Keyboard Access** | See below. Every action has a key path; nothing is hover-only. |
| **Pointer and motor** | Click-to-open mode; hover delay up to 450 ms; generous exit hysteresis (14 pt / 300 ms); "Close when the pointer leaves" can be turned off; Pin; hit targets ≥ 28 × 24 in the Nook and ≥ 32 × 24 in the band; every swipe has a click or key equivalent. |
| **Time limits** (WCAG 2.2.1) | Peek, HUD and inactivity durations are adjustable or can be disabled; Pin keeps the Nook open indefinitely. |
| **Flashing** (WCAG 2.3.1) | Nothing flashes more than once per second: the timer pulse is 1 Hz for at most 10 cycles, the visualizer ≤ 30 fps with smoothed amplitude, ambient drift < 0.2 Hz, and there are no full-panel brightness changes. |
| **Photosensitive art** | Album light is clamped (v ≤ 0.95, alpha caps), so a white album cover never floods the panel. |

**VoiceOver**
- **The panel** is one container labelled "Cranny".
  - Closed: "Cranny, collapsed" with the action "Open".
  - Opening posts a layout-changed notification and, on the panel's entrance only, puts focus on the widget the panel opened for, else the first widget.
- **Each live activity** is one element with a label, a value and named actions:
  - Label "Now playing: Midnight Window by The Example Band"; value "2 minutes 11 seconds left".
  - Actions: Play or Pause, Next track, Join meeting, Open, Dismiss.
- **Widgets** are containers; a **"Widgets" rotor** jumps between them.
- **Adjustable elements:** the scrubber (±10 s), the timer (±1 min) and the HUD level (`accessibilityAdjustableAction`). Tabs carry `.isSelected`.
- **Decorative layers** (light, halos, visualizer, satellite neck, key caps) are `accessibilityHidden`.
- **Announcements** (`AccessibilityNotification.Announcement`; alerts, results and the pause confirmation go through `services.announcer`):
  - **Alerts and results:** P1 alerts (timer done, meeting in 1 minute, device connected, low battery), pipeline completion, and the result of a Shortcuts run the user started when no tile on screen shows it (it sits in "+N", its page isn't showing, or it ran from ⌘K; design ruling R3): "Morning finished" / "Morning failed" («Быстрая команда «Утро» выполнена» / «… завершилась с ошибкой»). In Demo mode the result names no shortcut: "Shortcut finished" / "Shortcut failed" («Быстрая команда выполнена» / «Быстрая команда завершилась с ошибкой»). Nothing runs a shortcut by itself, and a run the user stopped says nothing. The tutorial also announces its steps (§12.2).
  - Alerts and results are rate-limited to one per 10 s across the whole app; one that comes too soon is dropped, not queued (the notch still shows it).
  - **Feedback**, the direct answer to the user's own action, is never rate-limited and does not count against the limit: layout changes (resizing or removing a card, from the editor or the ⋯ menu), Settings' Undo, the confirmation of Pause Live Activities and Resume (the sentence of §9.2), and the Tray's Copy paths ("Path copied" / "Paths copied", «Путь скопирован» / «Пути скопированы»), since the notch flash says only "Copied" / «Готово» and VoiceOver does not read its glyph (§8.1; the design owner is asked to confirm this addition, ARCHITECTURE §10.20 #30).
  - HUD values are announced only on settle, and only while VoiceOver runs.

**Keyboard map**

| Where | Keys |
|---|---|
| Anywhere | ⌃⌥N open/close the Nook with keyboard focus (rebindable; a Carbon hot key, no Accessibility permission) |
| In the Nook | Tab / ⇧Tab between widgets · arrows within a widget · ↩ / Space activate · ⌘1–⌘5 pages · ⌃Tab next page · ⌘K palette · hold ⌘ hints · ⌘P pin · ⌘E edit layout · ⌘. a focused card's commands · ⌘, Settings · Esc closes (after a text field being edited, a widget's own Cancel, and leaving the palette, focus mode or edit mode first) |
| Media | Space play/pause · ⌘← / ⌘→ previous/next · ← / → seek ±10 s on the scrubber |
| Calendar | ↑ ↓ events · ↩ / Space open · ⌘J join · ← → day (5 cells: column, then day) |
| Quick Apps | arrows over tiles, "+N" and "+" · ↩ / Space launch or open the menu · ⌥ + arrow move a tile · ⌥1–⌥9 launch |
| Notes | ⌘N new · ⌘R rename · ⌘[ / ⌘] previous/next note · ⌘↩ focus · ⌘/ code mode · in the delete confirmation ↩ deletes, Esc cancels |
| To-dos | ↩ new (on a selected row: edit) · Space toggle · ⌫ on an empty row deletes · ⌘⌫ delete · ⌘↑ / ⌘↓ reorder · ↑ from the first row selects a save error, ↩ / Space retries |
| Timer | Digits ↩ start ("25", "90s") · Space pause/resume · ⌫ reset |
| Tray | Arrows · ⇧ extend · ⌘A · Space Quick Look · ⌘C · ⌘⌫ remove (nothing selected: hide failed-drop tiles) · ⌘. stop runs · ⌥⌘⌫ clear |
| Focus ring | A 2-pt accent stroke, concentric (radius + 3, outset 3), shown only after keyboard interaction. The system focus effect is disabled on the same elements (`focusEffectDisabled()`) so rings never double up. |

---

## 17. Copy and localisation

- **Languages:** English (the source) and Russian ship today; the target set is every language macOS 27 ships (`scripts/l10n/languages.json`, ARCHITECTURE §8.7), in String Catalogs (`.xcstrings`) with translator comments. Apple's apps, panes and settings keep Apple's own names in every language (`scripts/l10n/apple-terms.py`).
- **Formatting:** numbers, dates and durations always go through `FormatStyle`, never concatenation (12/24-hour clock from the locale).
- **Right to left** (Arabic, Hebrew): the layout mirrors — tabs from the right, cards, the compact wings (glyph right of the camera, value left of it), the satellite beyond the left wing, Settings and Welcome — while the notch stays centred on the camera. Time-based media keeps its direction: ⏮ ⏯ ⏭, the scrubber with elapsed left and "−remaining" right, the playback rim; rings fill clockwise from 12 o'clock. ← / → and Move Left / Right go the way they point; day paging uses `chevron.backward` / `chevron.forward`; names and keys inside a sentence are bidi-isolated (ARCHITECTURE §8.7 rule 10).
- **Voice:** calm, plain and sentence case (title case only in standard AppKit chrome: the menu bar menu and the Settings window's menu items and push buttons), American English, ’ and “ ” in English and « » in Russian; the full rules are `docs/CONTRIBUTING.md` ▸ Copy, checked by `scripts/lint-copy.py`. No exclamation marks, no "Oops", no marketing words inside the product. Examples:
  - empty Media "Nothing playing"; Calendar "No more events today"; Tray "Drop files on the notch to keep them here";
  - permission rows "Show your events in Cranny. Cranny never edits or uploads them."
- **Length:** Russian runs 15–35 % longer.
  - Compact slots never hold free text except tested `compactLabel` abbreviations and a confirmation flash's word, which must fit the wing by measured width in every language (§9.1, design ruling E4).
  - Tab labels collapse to icons rather than truncate; titles truncate at the tail and file names in the middle.
  - Pseudo-localisation at 1.4× is meant to be part of the snapshot suite (not built yet; ARCHITECTURE §10.20).
- **Names:** Cranny's user-facing vocabulary is **Cranny** (the open panel: "Open Cranny"), **Home** (the widget page), **Layout & Widgets**, **Tray**, **live activity**, **peek**, **pipeline**. "Nook" is an internal code name only and never appears in UI text, because NotchNook labels its own panel tabs "Nook" and "Tray" (ARCHITECTURE D20). It uses no competitor product names or UI strings; `scripts/lint-copy.py` checks every catalog against the denylist in ARCHITECTURE §8.7 on every `make strings-check` and CI run. Russian terms follow the glossary there (ARCHITECTURE §8.7 rule 7), guarded by `TerminologyTests`: for example «Убрать» for taking an app or item off a list («Убрать приложение», «Убрать с полки»; «Удалить приложение» would read as uninstalling it) and «плеер» for a media app. An app is always named as Finder names it, never by its bundle ID; one that is gone reads "App not installed" / «Приложение не установлено».

---

## 18. What's better than NotchNook

1. **Hardware-exact morph.** Closed *is* the cutout (0.5 pt inside, calibrated per display model), close lands with zero bounce, and the morph is symmetric, so it never slides sideways or "jiggles". It renders at display rate from one fixed panel.
2. **Calm by contract.** There is an energy budget with zero work while closed, nothing over full-screen video by default, and an excluded-apps list.
3. **Intent, not proximity.** Dwell, pass-through speed, ⌥ suppression, button-down and full-screen rules, close grace and menu-bar courtesy prevent accidental opens. Click, shortcut and swipe are first-class.
4. **A real keyboard and VoiceOver story.** A global shortcut with no Accessibility permission, the ⌘K palette, hold-⌘ hints, type-to-capture, a rotor, adjustable controls and announcements. Nothing is hover-only.
5. **Light that means something.** An optional aurora, motes or tide in the album's or event's colour, contrast-audited against the worst case, with honest visualizer modes.
6. **A better external-display story.** A floating island instead of a fake notch, plus per-display styles and toggles.
7. **Settings you can see.** A live preview of the real views on your own wallpaper, Simulate chips, Show on Notch, search, per-row reset and a WYSIWYG grid editor (drag to reorder, drag to resize in cells), instead of reordering widgets with arrow buttons.
8. **A smarter Tray.** Multi-select, Quick Look, contextual pipelines, user-built chains, drop-on-action zones while dragging, and Undo.
9. **Defined concurrency.** A priority queue, a satellite for the second activity, swipe-to-dismiss and auto-unhide.
10. **Trust.** Just-in-time permissions with a Permissions pane, never two HUDs, no network except the update check, MIT-licensed and open source.

---

## Appendix A: Components (`CrannyCore/DesignSystem/Components.swift`)

These are the primitives every feature builds on: `NotchSurface`, `CompactSlots`, the card modifier, the focus ring, the icon button style, `LevelBar`, `ProgressRing`, `KeyCap` and `DropZone`.

```swift
// CrannyCore/DesignSystem/Components.swift
// The primitives every feature module builds on. They read tokens only.
import SwiftUI
import AppKit

// MARK: - NotchSurface: fill + clipped content + keyline + elevation (+ optional underglow)

/// Fills the FIXED canvas. Content states lay themselves out at their final size, top-centred,
/// and are revealed by the animated clip — text never reflows during a morph (R1 §7.2).
public struct NotchSurface<Content: View>: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    public var geometry: NotchGeometry
    public var band: CGFloat
    public var openness: Double                 // 0 closed/compact … 1 peek/open
    public var elevation: [CrannyShadow]
    public var keylineTint: Color?              // album accent while music plays
    public var underglow: Color?                // ambient glow1 (Vivid only)
    private let content: Content

    public init(geometry: NotchGeometry, band: CGFloat, openness: Double, elevation: [CrannyShadow] = Elevation.open,
                keylineTint: Color? = nil, underglow: Color? = nil, @ViewBuilder content: () -> Content) {
        self.geometry = geometry; self.band = band; self.openness = openness; self.elevation = elevation
        self.keylineTint = keylineTint; self.underglow = underglow; self.content = content()
    }

    public var body: some View {
        let shape = NotchShape(geometry)
        let p = theme.palette
        ZStack(alignment: .top) {
            if let underglow, theme.allowsUnderglow {
                // Coloured *shadow* = light on the desktop that stays click-through.
                shape.fill(Color.black)
                    .shadow(color: underglow.opacity(Glow.underglow.opacity * openness),
                            radius: Glow.underglow.radius, x: 0, y: Glow.underglow.y)
            }
            surfaceFill(shape, p)
                .crannyElevation(elevation, amount: openness)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
            // HIG key line: separates the shape from dark windows. Never along the screen
            // edge or beside the menu bar: masked to start below the band. Always present (alpha 0
            // while closed), so it morphs with the shape instead of appearing at the final size.
            shape.stroke((keylineTint ?? .white).opacity(theme.increaseContrast ? p.spec.keyline : p.spec.keyline * openness),
                         lineWidth: StrokeWidth.keyline)
                .mask(bandMask(fadeTo: 1))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Cranny"))   // a name, not a key (a key would be looked up in Bundle.main)
    }

    @ViewBuilder private func surfaceFill(_ shape: NotchShape, _ p: CrannyPalette) -> some View {
        let canGlass = !theme.reduceTransparency && !theme.increaseContrast
        if geometry.isFloating && theme.glassIsland && canGlass {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.75)), in: shape)
            } else {
                shape.fill(p.surface)
            }
        } else if theme.translucentBackground && canGlass {
            ZStack {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)), in: shape)
                } else {
                    VisualEffectBackdrop().clipShape(shape)
                }
                // The band stays pure black (no seam around the camera); below it 72 % black.
                shape.fill(p.surface).mask(bandMask(fadeTo: 0.72))
            }
        } else {
            shape.fill(p.surface)
        }
    }

    /// Opaque through the band, then a 6-pt ramp to `fadeTo` (layout-independent mask).
    private func bandMask(fadeTo: Double) -> some View {
        VStack(spacing: 0) {
            Color.white.frame(height: geometry.topInset + band).opacity(fadeTo == 1 ? 0 : 1)
            LinearGradient(colors: [.white.opacity(fadeTo == 1 ? 0 : 1), .white.opacity(fadeTo)],
                           startPoint: .top, endPoint: .bottom).frame(height: fadeTo == 1 ? 6 : 24)
            Color.white.opacity(fadeTo)
        }
    }
}

/// macOS 14/15 translucent backdrop.
public struct VisualEffectBackdrop: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Compact slots around the camera

/// leading | camera housing (never draw here) | trailing. Content hugs the camera.
public struct CompactSlots<Leading: View, Center: View, Trailing: View>: View {
    public var layout: NotchLayout
    public var slot: SlotWidth
    public var label: CGFloat
    private let leading: Leading, center: Center, trailing: Trailing

    public init(layout: NotchLayout, slot: SlotWidth, label: CGFloat = 0,
                @ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center,
                @ViewBuilder trailing: () -> Trailing) {
        self.layout = layout; self.slot = slot; self.label = label
        self.leading = leading(); self.center = center(); self.trailing = trailing()
    }

    public var body: some View {
        let u = layout.u, s = slot.points(unit: u)
        let outer = 12 * u, gap = 8 * u
        HStack(spacing: 0) {
            leading.frame(width: max(s - outer - gap, 0), alignment: .trailing)
                .padding(.leading, outer).padding(.trailing, gap)
            Color.clear.frame(width: layout.middle(label: label)).overlay { center }  // not EmptyView().frame()
            trailing.frame(width: max(s - outer - gap, 0), alignment: .leading)
                .padding(.leading, gap).padding(.trailing, outer)
        }
        .frame(height: layout.rowHeight)
        .padding(.top, layout.rowInset)
    }
}

// MARK: - Card

public struct CrannyCardModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    public var cells: Int
    public var hovered: Bool
    public var frameless: Bool          // Mirror: the preview IS the card

    public func body(content: Content) -> some View {
        let g = theme.grid, p = theme.palette
        let shape = RoundedRectangle(cornerRadius: g.cardRadius, style: .continuous)
        let carded = theme.widgetStyle == .cards && !frameless
        content
            .padding(frameless ? 0 : g.density.cardPadding)
            .frame(width: g.width(cells: cells), height: g.height, alignment: .topLeading)
            .background { if carded { shape.fill(hovered ? p.cardHover : p.card) } }
            .overlay {
                if carded {
                    shape.strokeBorder(p.hairline, lineWidth: theme.increaseContrast ? 1 : StrokeWidth.hairline(displayScale))
                }
            }
            .clipShape(shape)
            .containerShape(shape)          // inner ContainerRelativeShape stays concentric
            .animation(theme.animation(.hover), value: hovered)
    }
}

public extension View {
    func crannyCard(cells: Int, hovered: Bool = false, frameless: Bool = false) -> some View {
        modifier(CrannyCardModifier(cells: cells, hovered: hovered, frameless: frameless))
    }

    /// Keyboard focus: 2-pt accent ring, concentric (radius + 3, outset 3). Shown only after
    /// keyboard interaction; disable the system focus effect on the same element.
    func crannyFocusRing(_ focused: Bool, radius: CGFloat) -> some View {
        modifier(FocusRingModifier(focused: focused, radius: radius))
    }
}

struct FocusRingModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    var focused: Bool, radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius + Radius.focusRingOutset, style: .continuous)
                .strokeBorder(theme.accentColor, lineWidth: StrokeWidth.focus)
                .padding(-Radius.focusRingOutset)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Buttons

/// Icon button used everywhere in the notch. `.prominent` = the ONE primary action per card. A well smaller than
/// `HitTarget.nook` (the Timer's 24-pt ring buttons, Notes' header) is drawn centred in a button of at least 28 × 24
/// that takes clicks over its whole frame, as `CrannyChipButtonStyle` does (DESIGN.md §2.3, §16): a frame or content
/// shape added outside a `Button` does not widen it.
public struct CrannyIconButtonStyle: ButtonStyle {
    public enum Role: Sendable { case plain, filled, prominent }
    public var role: Role
    public var size: CGFloat
    public init(_ role: Role = .plain, size: CGFloat = HitTarget.preferred) { self.role = role; self.size = size }
    public func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, role: role, size: size)
    }

    struct IconButtonBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration, role: Role, size: CGFloat
        var body: some View {
            let p = theme.palette
            let fill: Color = switch role {
            case .prominent: p.prominentFill
            case .filled: configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control
            case .plain: configuration.isPressed ? p.controlPressed : hovered ? p.control : .clear
            }
            let widened = size < HitTarget.nook.width || size < HitTarget.nook.height
            configuration.label
                .font(.system(size: (size * 0.48).rounded(), weight: .semibold))
                .foregroundStyle(role == .prominent ? p.onProminent : p.label)
                .frame(width: size, height: size)
                .background(CrannyButtonShape(theme.buttonShape).fill(fill))
                .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
                .contentShape(widened ? AnyShape(Rectangle()) : AnyShape(CrannyButtonShape(theme.buttonShape)))
                .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
                .opacity(enabled ? (configuration.isPressed && theme.reduceMotion ? 0.7 : 1) : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
                .animation(theme.animation(.press), value: configuration.isPressed)
        }
    }
}

// MARK: - Level bar (HUD, scrubber) and progress ring

public struct LevelBar: View {
    @Environment(\.cranny) private var theme
    public var value: Double                // 0…1
    public var tint: Color?                 // nil = white (default HUD)
    public var thickness: CGFloat
    public var steps: Int                   // ticks drawn under DWC / Increase Contrast / fine steps
    public var showsTicks: Bool
    public var muted: Bool

    public init(value: Double, tint: Color? = nil, thickness: CGFloat = StrokeWidth.hudBar,
                steps: Int = 16, showsTicks: Bool = false, muted: Bool = false) {
        self.value = value; self.tint = tint; self.thickness = thickness
        self.steps = steps; self.showsTicks = showsTicks; self.muted = muted
    }

    public var body: some View {
        let p = theme.palette
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(p.control)
                Capsule(style: .continuous).fill(muted ? p.tertiaryLabel : (tint ?? p.label))
                    .frame(width: value <= 0 ? 0 : max(thickness, g.size.width * min(value, 1)))
                if showsTicks || theme.differentiateWithoutColor || theme.increaseContrast {
                    HStack(spacing: 0) {
                        ForEach(1..<max(steps, 2), id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: thickness)
        .animation(theme.animation(.hudLevel), value: value)
    }
}

public struct ProgressRing: View {
    @Environment(\.cranny) private var theme
    public var progress: Double, color: Color, lineWidth: CGFloat
    public init(progress: Double, color: Color, lineWidth: CGFloat) {
        self.progress = progress; self.color = color; self.lineWidth = lineWidth
    }
    public var body: some View {
        ZStack {
            Circle().stroke(theme.palette.control, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .crannyLeftToRight()        // clockwise from 12 o'clock in every language (a mirrored rotation starts at 6)
    }
}

// MARK: - Key cap (hold-⌘ hints, command palette, tutorial)

public struct KeyCap: View {
    @Environment(\.cranny) private var theme
    public var keys: String
    public init(_ keys: String) { self.keys = keys }
    public var body: some View {
        let p = theme.palette
        Text(keys)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(p.secondaryLabel)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(p.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).strokeBorder(p.hairline, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)       // shortcuts are exposed as accessibility hints instead
    }
}

// MARK: - Drop zone (Tray, AirDrop, pipelines)

public struct DropZone: View {
    @Environment(\.cranny) private var theme
    /// `title` is ALREADY localized by the caller (`String(localized:bundle: .module)`): a `LocalizedStringKey`
    /// passed into CrannyCore would be looked up in Bundle.main and stay English (ARCHITECTURE §3.2).
    public var symbol: String, title: String, targeted: Bool, tint: Color?
    public init(symbol: String, title: String, targeted: Bool, tint: Color? = nil) {
        self.symbol = symbol; self.title = title; self.targeted = targeted; self.tint = tint
    }
    public var body: some View {
        let p = theme.palette, r = theme.grid.innerRadius
        let armed = tint ?? theme.accentColor
        VStack(spacing: Space.s) {
            Image(systemName: symbol).crannySymbol(.dropZone)
                .crannySymbolBounce(value: targeted)        // armed: one bounce; none under Reduce Motion / Instant
            Text(title).crannyFont(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(targeted ? p.label : p.secondaryLabel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(targeted ? armed.opacity(0.15) : .clear))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
            .strokeBorder(targeted ? armed : p.stroke,
                          style: StrokeStyle(lineWidth: StrokeWidth.emphasis,
                                             dash: targeted && theme.differentiateWithoutColor ? [] : StrokeWidth.dash)))
        .scaleEffect(targeted && !theme.reduceMotion ? 1.03 : 1)
        .animation(theme.animation(.commit), value: targeted)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Symbol effects (DESIGN.md §14.1: only on a state change; none under Reduce Motion or Instant)

public extension View {
    /// `.symbolEffect(.bounce, options:, value:)` that plays only while `theme.animatesSymbols`. Under Reduce Motion
    /// or Motion ▸ Instant the effect is left out (not fed a constant), so switching either setting later does not
    /// look like a change and bounce a glyph that did not change.
    func crannySymbolBounce<V: Equatable>(value: V, options: SymbolEffectOptions = .default) -> some View {
        modifier(SymbolBounceModifier(value: value, options: options))
    }
}

struct SymbolBounceModifier<V: Equatable>: ViewModifier {
    @Environment(\.cranny) private var theme
    let value: V
    let options: SymbolEffectOptions

    func body(content: Content) -> some View {
        if theme.animatesSymbols {
            content.symbolEffect(.bounce, options: options, value: value)
        } else {
            content
        }
    }
}
```

## Appendix B: The light layer

### B.1 SwiftUI path: palette, budget, Aurora (the fallback specification)

This code holds palette extraction, the energy budget and the signature Aurora field. In the package it is split in two files: everything down to and including `EffectBudget` is `CrannyCore/DesignSystem/AmbientPalette.swift` (shared by Media, the shell and Effects); `AuroraField` is `CrannyEffects/AuroraField.swift` (add `import CrannyCore`). Motes and Tide follow the same pattern, a pure function of time, palette, energy and intensity drawn in a Canvas, using the parameters in §5.3.

Since ARCHITECTURE D13, this is the **SwiftUI path**: the fallback for Reduce Motion, Low Power / thermal and unavailable shaders (§5.6). WP0 put the shader branch of B.2 in front of `AuroraField`'s SwiftUI branches. The repo file `CrannyEffects/AuroraField.swift` is authoritative. It differs from the listing below by that branch, `@Environment(\.displayScale)` for the dither, a `#Preview`, and two guards and one retune from WP11 that both paths now share: a band mask keeps the top 40 % at alpha 0 (clear to 40 %, opaque from 48 %), and alpha is clamped (`cap · min(0.8 + 0.2 · energy, 1)`). The macOS 14 curtains were retuned to pass the parity bar against the shader: baselines at 0.54 + 0.10 · i of the height (was 0.62), per-curtain alpha 0.55 · min(0.8 + 0.2 · energy, 1) drawn at alpha / cap inside a layer at opacity cap, so overlapping curtains never pass the cap, and gradient stops 0 → a at 0.35 → 0.9 a at 0.75 → 0.8 a at 1, so the bottom stays lit (was a · 0.25 at 0.75 and 0 at 1). Time comes from `EffectClock` (CrannyCore), as below, not from `TimelineView(.animation(…))`, which kept SwiftUI redrawing at the display's refresh rate (§4.7).

```swift
// CrannyCore/DesignSystem/AmbientPalette.swift (AmbientPalette, EffectBudget) + CrannyEffects/AuroraField.swift
// — the optional "Afterglow" light layer.
// SwiftUI path, the fallback of the Metal shaders (§5.6): MeshGradient on macOS 15+, Canvas on macOS 14. No video.
import SwiftUI
import CoreGraphics
import AppKit

// MARK: - Palette from content

/// `glow1…3` are LIGHT (aurora, halo, underglow) and are clamped by `Glow` caps.
/// `accent` is a FOREGROUND mark and is contrast-guarded. Never put text on a glow without a card or scrim.
public nonisolated struct AmbientPalette: Equatable, Sendable {
    public var glow1: RGB, glow2: RGB, glow3: RGB
    public var accent: RGB
    public var isMonochrome: Bool

    public init(glow1: RGB, glow2: RGB, glow3: RGB, accent: RGB, isMonochrome: Bool = false) {
        self.glow1 = glow1; self.glow2 = glow2; self.glow3 = glow3; self.accent = accent; self.isMonochrome = isMonochrome
    }
    public var glows: [RGB] { [glow1, glow2, glow3] }

    /// Animatable form, so a track change cross-fades the light (`CrannyMotion.Kind.colorShift`).
    public typealias Vector = AnimatablePair<AnimatablePair<RGB, RGB>, AnimatablePair<RGB, RGB>>
    public var vector: Vector {
        get { .init(.init(glow1, glow2), .init(glow3, accent)) }
        set { glow1 = newValue.first.first; glow2 = newValue.first.second
              glow3 = newValue.second.first; accent = newValue.second.second }
    }

    // Palettes for activities without artwork (per-activity light, never random).
    public static let afterglow = AmbientPalette(glow1: BrandColor.iris, glow2: BrandColor.lagoon, glow3: BrandColor.rose, accent: RGB(hex: 0xA996FF))
    public static let timer = AmbientPalette(glow1: BrandColor.ember, glow2: RGB(hex: 0xFFB347), glow3: BrandColor.rose, accent: RGB(hex: 0xFF9F0A))
    public static let charging = AmbientPalette(glow1: RGB(hex: 0x30D158), glow2: RGB(hex: 0x9CF06B), glow3: BrandColor.lagoon, accent: RGB(hex: 0x30D158))
    public static let lowBattery = AmbientPalette(glow1: RGB(hex: 0xFF453A), glow2: BrandColor.ember, glow3: BrandColor.rose, accent: RGB(hex: 0xFF6961))
    public static let mono = AmbientPalette(glow1: RGB(0.78, 0.80, 0.86), glow2: RGB(0.55, 0.58, 0.66),
                                            glow3: RGB(0.90, 0.90, 0.95), accent: RGB(0.94, 0.94, 0.96), isMonochrome: true)
    /// Calendar event colour or the system accent → three analogous glows.
    public static func tinted(_ c: RGB) -> AmbientPalette {
        let (h, s, v) = c.hsb
        return .init(glow1: c.luminous,
                     glow2: RGB(h: (h + 0.06).truncatingRemainder(dividingBy: 1), s: s, v: v).luminous,
                     glow3: RGB(h: (h + 0.94).truncatingRemainder(dividingBy: 1), s: s * 0.8, v: v).luminous,
                     accent: c.legible())
    }

    /// Deterministic k-means (k = 5, 8 iterations) on a 24×24 thumbnail. ~0.1–0.3 ms.
    /// Run off the main actor; cache by track identifier; greyscale art → honest `.mono`.
    public static func extract(from image: CGImage) -> AmbientPalette {
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
            for j in 0..<k where counts[j] > 0 { var c = sums[j]; c.scale(by: 1 / Double(counts[j])); centers[j] = c }
        }
        func chroma(_ c: RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        let total = Double(samples.count)
        func score(_ c: RGB, _ w: Double) -> Double {
            let (_, s, v) = c.hsb
            let penalty = (v < 0.12 || (s < 0.08 && v > 0.9)) ? 0.15 : 1
            return w * (0.25 + chroma(c)) * penalty
        }
        let ranked = zip(centers, counts).filter { $0.1 > 0 }
            .map { (c: $0.0, w: Double($0.1) / total) }
            .sorted { score($0.c, $0.w) > score($1.c, $1.w) }
        if (ranked.map { chroma($0.c) }.max() ?? 0) < 0.10 { return .mono }

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
        let vivid = ranked.map(\.c).max { chroma($0) < chroma($1) } ?? picks[0]
        return .init(glow1: picks[0].luminous, glow2: picks[1].luminous, glow3: picks[2].luminous,
                     accent: vivid.legible())
    }
}

// MARK: - Energy budget (contract)

public nonisolated struct EffectBudget: Equatable, Sendable {
    public var isOpen: Bool             // ambient runs only while the Nook is open
    public var onScreen: Bool           // panel visible and not occluded (NSWindow.occlusionState)
    public var lowPower: Bool           // ProcessInfo.isLowPowerModeEnabled || thermalState ≥ .serious
    public var fullScreenFront: Bool
    public var reduceMotion: Bool
    public var onBattery: Bool
    public init(isOpen: Bool, onScreen: Bool, lowPower: Bool, fullScreenFront: Bool, reduceMotion: Bool, onBattery: Bool) {
        self.isOpen = isOpen; self.onScreen = onScreen; self.lowPower = lowPower
        self.fullScreenFront = fullScreenFront; self.reduceMotion = reduceMotion; self.onBattery = onBattery
    }
    /// nil = paused: the effect's clock (`EffectClock`) stops (zero cost). Reduce Motion FREEZES a resting frame.
    public var minimumInterval: Double? {
        guard isOpen, onScreen, !fullScreenFront, !reduceMotion, !lowPower else { return nil }
        return onBattery ? 1.0 / 20 : 1.0 / 30
    }
    /// Low Power Mode downgrades every effect to the static halo.
    public func effective(_ e: AmbientEffect) -> AmbientEffect { lowPower ? .halo : e }
}

// MARK: - Aurora (signature effect)

/// Curtains of content colour rising from the bottom edge of the open Nook. The top 40 % stays
/// black so the band merges with the hardware. Alpha is clamped to `Glow.ambientAlphaCap`.
public struct AuroraField: View, Animatable {
    public var palette: AmbientPalette
    public var level: AmbienceLevel
    public var energy: Double            // 0…1 (real RMS with permission, else 0)
    public var budget: EffectBudget
    public var restingTime: Double = 7.3

    public init(palette: AmbientPalette, level: AmbienceLevel, energy: Double, budget: EffectBudget) {
        self.palette = palette; self.level = level; self.energy = energy; self.budget = budget
    }

    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, Double> {
        get { .init(palette.vector, energy) }
        set { palette.vector = newValue.first; energy = newValue.second }
    }

    public var body: some View {
        let interval = budget.minimumInterval
        EffectClock(minimumInterval: interval) { date in
            let t = interval == nil ? restingTime : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            Group {
                if budget.effective(.aurora) == .halo {
                    RadialGradient(colors: [palette.glow1.color(cap * 0.6), .clear], center: .bottom, startRadius: 0, endRadius: 260)
                } else if #available(macOS 15.0, *) {
                    mesh(t)
                } else {
                    curtains(t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cap: Double { Glow.ambientAlphaCap(level) }

    @available(macOS 15.0, *)
    private func mesh(_ time: Double) -> some View {
        let t = Float(time), e = Float(energy)
        func drift(_ i: Int, _ amp: Float) -> Float { amp * sin(t * (0.21 + 0.05 * Float(i)) + Float(i) * 1.7) }
        let swell = 0.08 + 0.06 * e
        let points: [SIMD2<Float>] = [
            [0, 0], [0.33, 0], [0.67, 0], [1, 0],
            [0, 0.42], [0.33 + drift(1, 0.05), 0.40 + drift(2, 0.03)], [0.67 + drift(3, 0.05), 0.42 + drift(4, 0.03)], [1, 0.42],
            [0, 0.72 - swell], [0.30 + drift(5, 0.08), 0.70 - swell + drift(6, 0.06)],
            [0.70 + drift(7, 0.08), 0.68 - swell + drift(8, 0.06)], [1, 0.74 - swell],
            [0, 1], [0.33 + drift(9, 0.04), 1], [0.67 + drift(10, 0.04), 1], [1, 1],
        ]
        let a = cap * (0.8 + 0.2 * energy)
        let g = palette.glows, clear = Color.black.opacity(0)
        let colors: [Color] = [
            clear, clear, clear, clear,
            clear, g[1].color(a * 0.10), g[2].color(a * 0.10), clear,
            g[0].color(a * 0.35), g[1].color(a * 0.55), g[2].color(a * 0.50), g[0].color(a * 0.30),
            g[2].color(a * 0.70), g[0].color(a * 1.00), g[1].color(a * 0.90), g[2].color(a * 0.65),
        ]
        return MeshGradient(width: 4, height: 4, points: points, colors: colors,
                            background: .clear, smoothsColors: true, colorSpace: .perceptual)
    }

    /// macOS 14: three blurred sine curtains, normal blending (keeps the audited alpha cap).
    private func curtains(_ time: Double) -> some View {
        let palette = palette, cap = cap, energy = energy
        return Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
            ctx.addFilter(.blur(radius: max(10, size.height * 0.10)))
            let w = Double(size.width), hgt = Double(size.height)
            for (i, c) in palette.glows.enumerated() {
                let fi = Double(i)
                let phase = time * (0.09 + 0.035 * fi) * 2 * .pi
                let base = hgt * (0.62 + 0.10 * fi)
                let amp = hgt * (0.09 + 0.06 * energy) * (1 - 0.2 * fi)
                var path = Path()
                path.move(to: CGPoint(x: -40, y: hgt + 40))
                var x = -40.0
                while x <= w + 40 {
                    let u = x / max(w, 1)
                    path.addLine(to: CGPoint(x: x, y: base + amp * sin(u * 2 * .pi * (0.75 + 0.35 * fi) + phase)
                                                   + amp * 0.45 * sin(u * 2 * .pi * (1.9 + 0.2 * fi) - phase * 1.4)))
                    x += 10
                }
                path.addLine(to: CGPoint(x: w + 40, y: hgt + 40)); path.closeSubpath()
                let a = cap * 0.6 * (0.8 + 0.2 * energy)
                let grad = Gradient(stops: [.init(color: c.color(0), location: 0), .init(color: c.color(a), location: 0.35),
                                            .init(color: c.color(a * 0.25), location: 0.75), .init(color: c.color(0), location: 1)])
                ctx.fill(path, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: base - amp * 1.6), endPoint: CGPoint(x: 0, y: hgt)))
            }
        }
    }
}
```

### B.2 Metal shaders: `CrannyEffects/Shaders/` and `ShaderEffects.swift`

Verified in a copy of the CrannyKit layout (ARCHITECTURE Appendix C, "Metal pipeline"):
- every block below compiles with the Metal Toolchain, with 0 compiler warnings;
- the metallib is embedded in the universal Release app, and `ShaderEffects.isAvailable` is true inside it;
- the tests pass.

WP0 shipped every file below verbatim, including `Aurora.metal` and the aurora branch (commit `22c9ddf`, ARCHITECTURE §10.1). The listings are that starting point; **the repo files are authoritative**. WP11 tuned the aurora against the fallback, wrote the other seven functions against the signatures at the end (`liquidNeck` with the algorithm of §5.6), grew `CrannyShaders.h` into the shared helpers (noise, palettes, OKLab, dither, the ripple source, the layer's uniforms; each effect's field is one `static inline` function shared by both entry points), and added the ambient layer's `ambientVertex` and one fragment function per effect (`AmbientLayer.metal`, ARCHITECTURE D13). `requiredFunctions` is `stitchableFunctions` ∪ `layerFunctions`. The GPU is chosen without `MTLCreateSystemDefaultDevice` (the test below now asks `AmbientGPU`).

```metal
// CrannyEffects/Shaders/CrannyShaders.h — helpers shared by the CrannyEffects shaders (DESIGN.md §5.6).
// `#include "CrannyShaders.h"` resolves next to the .metal files; SwiftPM does not copy the header.
#pragma once
#include <metal_stdlib>
using namespace metal;

namespace cranny {

/// Interleaved gradient noise (Jimenez 2014) in 0..<1: a cheap, texture-free stand-in for blue noise.
static inline float ign(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

/// Stateless integer hash in 0...1 (seeds noise lattices and particles; nothing keeps per-particle state).
static inline float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}
static inline float hash21(float2 lattice) {
    int2 i = int2(floor(lattice));
    return hash(uint(i.x) * 1597334677U ^ uint(i.y) * 3812015801U);
}

/// Smooth value noise in 0...1.
static inline float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

/// Fractal Brownian motion: `octaves` of value noise (lacunarity 2, gain 0.5), normalised to 0...1.
static inline float fbm(float2 p, int octaves) {
    float sum = 0.0, amplitude = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amplitude * valueNoise(p);
        norm += amplitude;
        p = p * 2.0 + float2(17.0, 9.0);
        amplitude *= 0.5;
    }
    return sum / max(norm, 1e-4);
}

/// Piecewise-linear ramp through the palette stops (`.colorArray`, 1–5 entries), t in 0...1.
static inline half3 ramp(device const half4 *stops, int count, float t) {
    if (count <= 1) { return count == 1 ? stops[0].rgb : half3(0.0h); }
    float x = clamp(t, 0.0, 1.0) * float(count - 1);
    int i = min(int(x), count - 2);
    return mix(stops[i].rgb, stops[i + 1].rgb, half(x - float(i)));
}

/// The last line of every light-emitting shader: premultiplied output with alpha clamped to `cap`
/// (`Glow.ambientAlphaCap`) and every channel to `Glow.maxBrightness` (0.95).
static inline half4 light(half3 rgb, float alpha, float cap) {
    float a = clamp(alpha, 0.0, cap);
    return half4(half3(min(float3(rgb), 0.95) * a), half(a));
}

} // namespace cranny
```

```metal
// CrannyEffects/Shaders/Dither.metal — the shared last pass of every gradient-producing effect (DESIGN.md §5.6).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// Adds ±amount/2 LSB of 8-bit interleaved-gradient noise to premultiplied colour so that dim gradients over
/// black do not band. `scale` is the display scale (noise per pixel, not per point). Transparent stays transparent.
[[ stitchable ]] half4 crannyDither(float2 position, half4 color, float amount, float scale) {
    if (color.a <= 0.0h) { return color; }
    float n = (cranny::ign(floor(position * scale)) - 0.5) * amount / 255.0;
    float a = float(color.a);
    return half4(half3(clamp(float3(color.rgb) + n, 0.0, a)), color.a);
}
```

Reference implementation of the signature effect. At 880 × 260 pt it gives a peak alpha of 0.36 (Subtle, cap 0.45) and 0.64 (Vivid, cap 0.80), and alpha 0 in the top 40 %:

```metal
// CrannyEffects/Shaders/Aurora.metal — the signature effect (DESIGN.md §5.6). Fallback: AuroraField's SwiftUI path (App. B.1).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// Domain-warped fBm curtains rising from the bottom edge, coloured by the palette stops.
/// Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 auroraField(float2 position, half4 color, float4 bounds, float time,
                                   device const half4 *stops, int stopCount,
                                   float energy, float intensity, float cap) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    if (uv.y <= 0.40) { return half4(0.0h); }                       // the band stays black
    float2 p = float2(uv.x * bounds.z / max(bounds.w, 1.0) * 1.2, uv.y * 0.5);   // anisotropic: tall curtains
    float2 q = float2(cranny::fbm(p + float2(0.0, 0.05 * time), 3),
                      cranny::fbm(p + float2(5.2, 1.3) - float2(0.04 * time, 0.0), 3));
    float2 r = float2(cranny::fbm(p + 1.5 * intensity * q + float2(1.7, 9.2) + 0.07 * time, 3),
                      cranny::fbm(p + 1.5 * intensity * q + float2(8.3, 2.8) - 0.06 * time, 3));
    float f = smoothstep(0.25, 0.75, cranny::fbm(p + 2.0 * r, 4));
    float rays = 0.55 + 0.45 * smoothstep(0.3, 0.7, cranny::fbm(float2(5.0 * p.x + 1.5 * r.y, 0.08 * time), 3));
    float rise = smoothstep(0.40, 0.78 - (0.08 + 0.06 * energy), uv.y);  // louder audio lifts the light ≤ 6 %
    half3 rgb = cranny::ramp(stops, stopCount, 0.15 + 0.7 * f + 0.3 * (q.x - 0.5));
    return cranny::light(rgb, cap * (0.8 + 0.2 * energy) * rise * rays * mix(0.45, 1.0, f), cap);
}
```

```swift
// CrannyEffects/ShaderEffects.swift — the Metal library of CrannyEffects and the one switch between
// the shader path and the SwiftUI fallback (ARCHITECTURE D13, DESIGN.md §5.6).
import Foundation
import Metal
import SwiftUI
import os
import CrannyCore

private nonisolated let log = Log.logger(.effects)

enum ShaderEffects {
    /// `default.metallib`, compiled by SwiftPM from `Shaders/*.metal` into `CrannyKit_CrannyEffects.bundle`.
    static let library = ShaderLibrary.bundle(.module)

    /// Every stitchable function the effects call. A missing function renders TRANSPARENT without any
    /// error, so availability is checked once, up front. WP11 adds each function it ships.
    nonisolated static let requiredFunctions: Set<String> = ["crannyDither", "auroraField"]

    /// QA switch: launching with `-CrannyDisableShaders YES` forces every SwiftUI fallback.
    nonisolated static let disableKey = "CrannyDisableShaders"

    /// true when the metallib is bundled, loads on this Mac's GPU and contains every required function.
    nonisolated static let isAvailable: Bool = {
        guard let problem = unavailabilityReason() else { return true }
        log.info("Metal effects off (\(problem, privacy: .public)); using the SwiftUI fallbacks")
        return false
    }()

    nonisolated static func unavailabilityReason() -> String? {
        if UserDefaults.standard.bool(forKey: disableKey) { return "\(disableKey) is set" }
        guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib") else {
            return "default.metallib is not in the bundle"
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        guard let metalLibrary = try? device.makeLibrary(URL: url) else { return "default.metallib does not load" }
        let missing = requiredFunctions.subtracting(metalLibrary.functionNames)
        return missing.isEmpty ? nil : "missing " + missing.sorted().joined(separator: ", ")
    }

    /// The shader path runs only while animation is allowed: Reduce Motion, Low Power / thermal ≥ serious
    /// and an unavailable library always use the SwiftUI fallback.
    static func usesShader(_ budget: EffectBudget) -> Bool {
        isAvailable && !budget.reduceMotion && !budget.lowPower
    }
}

extension View {
    /// Last pass of every gradient-producing effect (aurora, tide, halo): ±0.5 LSB of noise against banding.
    func crannyDithered(scale: CGFloat) -> some View {
        colorEffect(ShaderEffects.library.crannyDither(.float(1), .float(scale)))
    }
}
```

The shader branch of `AuroraField`. It sits inside the same `EffectClock` and is used when `budget.effective(.aurora) != .halo && ShaderEffects.usesShader(budget)`:

```swift
// CrannyEffects/AuroraField.swift (since WP0) — the shader branch, placed in front of the SwiftUI branches.
import SwiftUI
import CrannyCore

/// The aurora through `auroraField` (Aurora.metal). Same inputs as the SwiftUI path; `time` comes from the
/// effect's clock (`EffectClock`), so `EffectBudget` still decides the frame rate.
@MainActor func auroraShader(palette: AmbientPalette, level: AmbienceLevel, energy: Double, time: Double,
                  displayScale: CGFloat) -> some View {
    Rectangle()
        .colorEffect(ShaderEffects.library.auroraField(
            .boundingRect, .float(time), .colorArray(palette.glows.map { $0.color(1) }),
            .float(energy), .float(level.intensity), .float(Glow.ambientAlphaCap(level))))
        .crannyDithered(scale: displayScale)
}
```

`Tests/CrannyEffectsTests/ShaderEffectsTests.swift`. The first test never needs a GPU. The second skips itself without a Metal device, as on VM runners. WP0 added `ShaderRenderTests.swift` (`auroraField` keeps the band black and stays under the cap; `crannyDither` keeps coverage) and `EffectsModuleTests.swift` (budget pause, shader/fallback switch, no shader sources in the bundle):

```swift
import Foundation
import Metal
import Testing
@testable import CrannyEffects

@Test func metallibIsBundled() {
    #expect(Bundle.module.url(forResource: "default", withExtension: "metallib") != nil)
}

@Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil)) func everyRequiredShaderLoads() {
    #expect(ShaderEffects.unavailabilityReason() == nil)
    #expect(ShaderEffects.isAvailable)
}
```

The remaining functions of §5.6. Each goes in its own file with the usual three includes; these signatures were compiled and rendered with stub bodies:

```metal
// Signatures of the remaining CrannyEffects shaders (DESIGN.md §5.6). Each lives in its own file; the bodies are WP11's.
[[ stitchable ]] half4  tideField(float2 position, half4 color, float4 bounds, float time,
                                  device const half4 *stops, int stopCount, float energy, float intensity, float cap);
[[ stitchable ]] half4  motesField(float2 position, half4 color, float4 bounds, float time,
                                   device const half4 *stops, int stopCount, float energy, float intensity, float cap);
[[ stitchable ]] half4  haloGlow(float2 position, half4 color, float4 bounds, float2 center, float radius,
                                 half4 glow, float cap);
[[ stitchable ]] float2 songRipple(float2 position, float2 center, float time, float amplitude, float wavelength,
                                   float speed);                                  // .distortionEffect
[[ stitchable ]] half4  liquidNeck(float2 position, SwiftUI::Layer layer, float reach, float progress,
                                   half4 fill);                                   // .layerEffect
[[ stitchable ]] half4  emberBurst(float2 position, half4 color, float4 bounds, float2 origin, float time,
                                   device const half4 *stops, int stopCount, float cap);
[[ stitchable ]] half4  chargeSweep(float2 position, half4 color, float4 bounds, float progress, half4 glow, float cap);
```

## Appendix C: Verification log

| Claim | How it was verified |
|---|---|
| All Swift in this document compiles | Scratch package `scratchpad/poc/design-final` (tools 6.2, macOS 14 platform, Swift 6 mode, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility`, `ExistentialAny`). Built the same files as `CrannyCore` (`defaultIsolation(nil)`) **and** `CrannyCoreMA` (`defaultIsolation(MainActor.self)`): **0 errors, 0 warnings**. Debug and release. |
| Contrast numbers (§2.1) | Harness `DSHarness` computes WCAG 2.x ratios from the same `CrannyPalette.Spec` values the colours use (`out/report.txt`). |
| Geometry tables (§3.3) | Harness prints every state for the 14″/16″/13″ MacBooks, a "Larger Text" scale, and external displays in floating and attached styles. |
| Spring physics (§4.1) | SDK `Spring(duration:bounce:)`: damping ratio, stiffness, damping, settling duration; overshoot sampled at 1 ms. |
| Path cost | 20,000 interpolated `NotchShape` paths, including `Path.union` ears: 0.64 µs each (release). |
| Palette extraction | 0.021 ms per artwork (release); an orange-on-navy test cover gives an accent with 8.5:1 on black. |
| Renders | `out/states-notch.png`, `states-floating.png`, `states-attached.png` (closed inside the red hardware outline; ears; shadows only when elevated), `corner-zoom.png` (ear + keyline starting below the band), `open-subtle.png` / `open-vivid.png` / `open-off.png` (full Nook composition with smoked cards, header in the band and the aurora). |
| Icon Composer | `actool --compile … --app-icon Cranny --minimum-deployment-target 14.0` on the 2-group `Cranny.icon` above → `Assets.car` + `Cranny.icns`, no errors. |
| SF Symbols | Every name in §14.1 checked against `name_availability.plist` (all ≤ macOS 14) and `symbol_restrictions.strings` (`video*` = FaceTime only; `airpods*`, `beats.*`, `accessibility` restricted to those products/features). |
| Window behaviour the design relies on | Research R1 (`docs/research/R1-notch-window.md`): per-pixel click-through, `.shadow` pass-through, the tri-state `ignoresMouseEvents`, nonactivating-at-init, key hand-back, fixed-canvas morph at 222–238 fps. |
| Review amendments (2026-10-14) | `DropZone.title: String`, `Text(verbatim: "Cranny")`, `NookGrid.paddingTune`, `CrannyTheme.panelPaddingTune`: rebuilt inside the full CrannyKit layout (`scratchpad/poc/review`), 0 warnings, Core tests pass incl. `NookGrid(paddingTune: 3)` → padding 15, panel r 35, card r 20. |
| Metal shaders (App. B.2, §5.6; 2026-10-14) | `CrannyShaders.h`, `Dither.metal`, `Aurora.metal`, `ShaderEffects.swift`, the aurora branch and the tests compiled inside a copy of the CrannyKit layout, with `CrannyEffects` built under **both** default isolations and 0 compiler warnings, and passed `swift test`. The universal Release app embeds `CrannyKit_CrannyEffects.bundle/Contents/Resources/default.metallib`, and `ShaderEffects.unavailabilityReason()` is nil inside the app. `ImageRenderer` renders of `auroraField` (+ dither) at 880 × 260 pt: top 40 % alpha 0; peak 0.36 / 0.64 against caps 0.45 / 0.80; curtains visibly tall and three-stop. The other seven signatures compile and render with stub bodies. A missing function or wrong argument count renders transparent, silently (hence `requiredFunctions` + per-function render tests). One comment line of B.1 was updated ("SwiftUI path…"); no code changed. |
| WP0 in the repo (2026-10-14) | The design-system files (`Color`, `Typography`, `Layout`, `Motion`, `Notch`, `Theme`, `Components`, `AmbientPalette`), `CrannyShaders.h`, `Dither.metal`, `Aurora.metal`, `ShaderEffects.swift` (+ `auroraField` in `requiredFunctions`) and the B.2 tests are byte-identical to this document; `AuroraField.swift` differs from B.1 only as described there. `make check`: 0 warnings; 67 tests pass, including the `auroraField` render test (top 40 % black, peak alpha under the cap). actool compiled the WP0 icon (`fill-specializations` + two rendered layers) into `Assets.car` and `AppIcon.icns`. Energy: the open panel with the aurora costs ≈ 5–10 % CPU on a 240-Hz display with `EffectClock` (11.4 % with `TimelineView` at 30 fps), so §4.7's ≤ 3 % is not met yet (ARCHITECTURE Appendix C). Screenshots were captured by window id with the screen locked, so the light shows its resting frame. |
| Phases B and C in the repo (2026-10-14) | The design-system listings of §2–§4 and App. A are still byte-identical to their files after phase C (checked file by file). The refinements recorded in this sync are each covered by the owning package's tests (ARCHITECTURE §10 "As built"): e.g. `SlotFitTests` (Bluetooth `medium` slot), `FeaturedRowTests` (Calendar Join layouts, en/ru, every text size and density), `MirrorResourceTests` (chip titles fit), `LightLayerTests` (Effect setting renders aurora, motes and tide), `TimerSoundNameTests`, `TerminologyTests` and `CopyGlossaryTests` (Russian terms), `SymbolTests` (§14.1 against `CrannySymbol` and the system catalogue). Visual checks used in-process snapshots only (the display was asleep); hardware, real input and VoiceOver are open (ARCHITECTURE §10.20). |
| Phase D in the repo (2026-10-14) | The §4.2 `Motion.swift` and App. A `Components.swift` listings were resynced after `b3beeac` (the unused delight curves `ripple`, `firstLight` and `fade` removed; `Delight` holds only the gulp) and `8920c06` (`CrannyIconButtonStyle` widens wells smaller than 28 × 24); every design-system listing is byte-identical to its file again (checked file by file). The rulings are covered by the owning packages' tests: R2 by `ActivityArbiterTests` and `ChoreographyTests` (reduced variants scheduled and drawn), R3 by `QuickAppsModelTests` (only user runs report; the Demo-mode sentences in English and Russian), R4 by `TimerModelTests` (the sound plays while paused, not in Demo mode), R5 by `PauseConfirmationTests` (the wing words fit the wing at notch units 0.8–1.25 in both languages; the open header) and `SceneAndHeaderTests` (header takeover, pixel test at the 632-pt and 481-pt headers); the swipe velocity by `OpenVelocityTests`. In-process snapshots (`--qa-pause`, `--qa-state`, `--qa-menu`, `-CrannyQASnapshot`) were checked by eye. Real input, hardware and VoiceOver remain open (ARCHITECTURE §10.20). |
| Phase E in the repo (2026-10-14) | The §4.2 `Motion.swift` listing was resynced after `c220418` / `67983d9` (the unused `release(velocity:remaining:)` removed); every other design-system listing of §2–§4 and App. A is still byte-identical to its file (checked block by block against the repo at `335b3ca`). Ruling E4's measured rule is covered by `FlashLabelFitTests` (every flash label in English and Russian at notch units 0.8–1.25) and `WingTextMetricsTests` (the measured wing equals `CompactSlots`' at every band unit; widths match what `crannyFont(.compact)` draws within 1 pt). The merge QA's offscreen snapshots showed «Привет» and the Tray's «Готово» with `doc.on.doc` in the medium wing and "Copied" in the wide wing. E3's region is covered by `DragAndMenuHoldTests`; real menus and a hardware notch were not available (ARCHITECTURE §10.20 #16). |
| Not verified here | Real notch radii and widths on each MacBook model (this Mac runs in clamshell mode with an external display). The closed radius 0.30·band and the 0.5-pt inset are starting values; calibrate on 13″/14″/15″/16″ hardware at every scaling mode with the Notch fit sheet and record per-model defaults. On-screen CPU/energy and the shaders' GPU frame time (Instruments on hardware). The look of the seven shaders WP11 still writes, and their parity with the fallbacks. Haptic delivery from a background agent. |

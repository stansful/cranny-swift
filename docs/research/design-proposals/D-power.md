# Cranny — Design-System Proposal, Direction C: "Calm power-user"

> Information-dense yet calm, keyboard-first, layout you can rearrange, a Settings window that previews every change live, and accessibility you can feel.
> Written 2026-10-14 for Cranny (MIT, clean-room). Nothing here copies NotchNook (or any GPL project) code, assets, names or UI text. Every API was checked against the macOS 27 SDK (Xcode 27.0, Swift 6.4) at **deployment target macOS 14.0**.

## 0. Status and verification

| What | How it was verified | Result |
|---|---|---|
| All Swift in this document (tokens, shape, motion, effects, components, live activities, widgets, settings, onboarding, menu bar extra, icon art) | `swiftc -swift-version 6 -target arm64-apple-macos14.0` on the PoC sources (`poc/design-power/v2/src/*.swift`, about 2,200 lines) | 0 errors, 0 warnings |
| Extra APIs cited, not used by the PoC (`NSPanel` non-activating, `sensoryFeedback`, `onKeyPress`, `focusable(interactions:)`, `focusSection`, `PhaseAnimator`, `ContentUnavailableView`, `scrollTargetBehavior`, `onGeometryChange`, `accessibilityRotor`, `AccessibilityNotification.Announcement`, `SMAppService`, Carbon `RegisterEventHotKey`, `glassEffect` / `GlassEffectContainer` / `glassEffectID` / `ConcentricRectangle` (26+), `symbolEffect(.wiggle)` (15+)) | `swiftc -typecheck` of `v2/apicheck/check.swift` at target 14.0, with the newer APIs behind `#available` | exit 0 |
| Visual output | `ImageRenderer` + offscreen `NSHostingController` snapshots → `v2/out/*.png` | `states.png`, `activities.png`, `a11y-hc-xl.png`, `aurora.png`, `filmstrip.png`, `settings.png`, `onboarding.png`, `icon-flat.png` |
| Contrast ratios | WCAG 2.x relative luminance, computed by the PoC (`numbers()` in `main.swift`) | numbers in §2.1 |
| Spring physics | `Spring(duration:bounce:)` → response, damping ratio, settling, measured overshoot (`v2/apicheck/springs.swift`) | numbers in §4.1 |
| `NotchShape.path(in:)` cost | 20,000 interpolated paths | **0.63 µs per path**, so animating it costs effectively nothing |
| SF Symbols | every name checked against `CoreGlyphs.bundle/name_availability.plist` (min OS) and `symbol_restrictions.strings` | all ≤ macOS 14, none misused (see §7.1) |
| Icon Composer `.icon` | wrote `Cranny.icon/icon.json` + 3 layers, compiled with `xcrun actool --app-icon Cranny --minimum-deployment-target 14.0` | `Assets.car` + fallback `Cranny.icns` produced, no errors |

Base path for all files mentioned: `<research-scratchpad>/poc/design-power/v2/` (scratch only, not in the repo).

Renders (open them next to this document):
- `out/states.png`: every notch state on a 14″ MacBook Pro geometry (185 × 32 pt cutout outlined in red), plus the no-notch handle and floating island.
- `out/activities.png`: the six compact live activities at 3×.
- `out/a11y-hc-xl.png`: Increase Contrast + XL text + rounded buttons (cells grow from 56 to 70 pt).
- `out/aurora.png`: the MeshGradient ambient effect behind the open Nook.
- `out/settings.png`, `out/onboarding.png`: the Settings window (the live preview stage is the real notch views) and onboarding step 2. The sidebar's vibrancy material doesn't show up in offscreen snapshots, so the sidebar appears blank. That's a limit of the capture method, not of the design.
- `out/icon-flat.png` (CoreGraphics fallback) and `out/icns.iconset/icon_128x128@2x.png` (rendered by actool from the layered `.icon`).

---

## 1. What we learned, what we fix, and the principles

### 1.1 Competitive look and feel (summary of research)

- **NotchNook (lo.cafe).** Closed, it looks like the hardware notch. While music plays it shows album art on the left of the notch and a waveform on the right. Hover expands it into the "Nook", a black panel with **Nook / Tray** tabs at the top and a row of widgets (media, calendar, Shortcuts, a Mirror camera toggle). Later versions added Notes, To-dos, Quick Apps and a Files tray with an AirDrop drop box. v1.2 added volume/brightness HUD replacement. Off the built-in display it renders a "half-size notch". Sources: MacStories, Macworld, iMore, Lowyat.
- **Dynamic Island (Apple HIG, Live Activities, Dec 2025 revision).** Background is pure black. The compact presentation is two elements, leading and trailing, "snug against the camera", balanced in width, reading as one piece of information. iPhone sizes: compact leading/trailing **52.33 × 36.67 pt**, island **230/250 pt** wide, expanded **371/408 × 84–160 pt**, **corner radius 44 pt**. Margins are concentric. Animations are capped at **2 s**. Dark mode adds a **key line** (a thin rim). At most one interactive element in compact. Use heavier text (medium or above). Show Live Activities only for things with a start and an end.
- **Alcove.** Paid, Swift, macOS 15+. Fluid transitions, HUDs, swipe gestures, notifications, lock-screen widgets. Users asked for **click or long-press instead of hover** to expand.
- **boring.notch (GPL, ideas only, no code read).** Hover-first, music-centric, with a visualizer.
- **Atoll (GPL, ideas only).** Media, live activities (focus, recording, privacy indicators, downloads), lock-screen widgets, system stats, shelf, notes.

### 1.2 Where users complain, and Cranny's concrete answer

| # | Complaint (source) | Cranny design answer |
|---|---|---|
| 1 | The most-upvoted boring.notch issues ask to **disable the "jiggly/wobbly" open/close animation** (#364: 26 reactions; #335: 21; #303: 16; #325, #424). The close animation **"doesn't fit the real notch" / "slides to the side revealing the actual notch"** (#350: 21; #316, #339). | Geometry springs are near-critically damped by default (bounce 0.08 open, **0 close**; measured overshoot 0.1 % and 0 %). Close lands exactly on the measured cutout. Width and height are symmetric about the notch centre, so it never slides sideways. A **Motion personality** setting offers Calm (default), Lively or Instant (§4). |
| 2 | **"Stuttering when opening"** (boring.notch #341). NotchNook **battery/CPU drain**; the developers advised rolling back to 1.4.6 (MacRumors thread, 2025). NotchNook "**hangs when hovering**" (Setapp reviews). | One fixed-size panel; the shape morphs via `animatableData` (0.63 µs per path). No layout animation and no window resizing. Every `TimelineView` is **paused** unless the Nook is open and effects are allowed. Idle budget: 0 timers when closed, ≤ 20 fps in compact, ≤ 30 fps open. Low Power Mode turns effects off. |
| 3 | **Accidental opens** from hover. The Alcove/App Store reviewer wanted click or long-press. boring.notch "doesn't open on hover sometimes" (#388). | **Hover intent**: dwell 220 ms (eager 100, deliberate 450), pointer speed < 900 pt/s, hold ⌥ to pass over. A visible **hover lift** (the shape grows 4 pt per side) acknowledges the dwell. Click, shortcut and pull-down gestures are first-class alternatives. |
| 4 | "**Fake notch on external displays feels jarring**". NotchNook's **Now Playing stays over fullscreen video** (MacStories). boring.notch "Disable in fullscreen / external displays" (#119: 14), "Hide in fullscreen for streaming" (#239), "Exclude apps" (#110). | On displays without a notch the default is a **floating island** (all corners round, detached 4 pt from the top), not a fake notch. A per-display style picker offers Floating island, Attached notch or Off. In fullscreen spaces compact activities hide by default and only alerts peek. There's an **Excluded apps** list. |
| 5 | **No keyboard shortcut to open** (boring.notch #135, "sneak peek shortcut"). The privacy question "**why does it need keyboard access?**" (#210). | Global **⌃⌥Space** opens the Nook with keyboard focus. It's a Carbon hot key, so no Accessibility permission is needed. Accessibility is requested **only** if the user turns on HUD replacement, which needs key interception, and the permission sheet explains exactly that. |
| 6 | **Repeated permission prompts** (Macworld). | Every permission is requested **just in time**, once, when its feature is switched on. Status lives on a **Permissions** pane with a one-line "why" for each. |
| 7 | **Tray has no multi-select** (Macworld). **"Clear all"** request (boring.notch #1248). | The Tray supports ⌘/⇧-click, ⌘A, multi-drag and Quick Look (Space). The selection drives a **pipelines bar** (Compress, Convert, Zip, Copy paths, AirDrop…) plus Clear All (⌘⌫). |
| 8 | **Inconsistent tab transition** ("fades one way, slides the other", boring.notch). | One symmetric, direction-aware transition: ±16 pt + opacity, spring 0.26 / 0. A matched-geometry selection pill. |
| 9 | **Duplicate HUDs**, system and app (Atoll #419). Brightness HUD not replaced for external keyboards (boring.notch #1055, #1441). Custom HUD steps (Atoll #171). | If key interception isn't authorised, Cranny **does not draw its HUD at all**, so there are never two. A Settings note explains how to enable it. Steps follow the system (16, or 64 with ⌥⇧), and fine steps show as tick marks. |
| 10 | Clean **screenshots and recordings** (boring.notch #161). | Closed = the exact cutout, drawn **under** the hardware, so nothing visible. **Demo mode** keeps a chosen state pinned and can redact calendar titles. |
| 11 | Multiple concurrent live activities (Atoll #245). | One primary activity in the slots plus a detached **satellite** (24 pt circle) for the second, like the HIG's "minimal" presentation. A priority queue is defined in §5.4. |
| 12 | "Trackpad **click sound** when hovering" and haptics tied to hover (boring.notch). | Haptics only fire on **gesture thresholds** (alignment) and **completions** (level change), never on hover. A single toggle controls them. |
| 13 | Calendar showed no events. Mirror only used the built-in camera (MacStories). | Calendar has an explicit empty state ("No events today · Calendars: 3 of 5 shown · Choose…"). Mirror has a camera picker in the widget's hover toolbar. |
| 14 | Liquid Glass request (boring.notch #922: 10). | On macOS 26+, controls can use `.glassEffect(.regular.interactive())` ("Glass controls", default on). The **notch body stays opaque black** because it has to merge with the hardware. |

### 1.3 Principles (7)

1. **Hardware-true.** Closed is the cutout, exactly. Every morph starts and ends on measured hardware geometry. No shadow until open, because a shadow would reveal the seam between software and hardware. The notch row is always solid black, even with the translucent Nook option.
2. **Calm by default; motion means information.** Near-critically damped springs. Nothing moves in peripheral vision unless something changed. Live activities only exist for things with a start and an end. Effects are opt-in, slow (under 0.2 Hz drift) and never shown while closed.
3. **Intent over proximity.** Opening requires intent (dwell + speed, click, shortcut or pull). Closing requires leaving plus a grace period (14 pt / 300 ms), and never happens while you're typing, dragging, pinned or inside a menu.
4. **Keyboard-first, pointer-complete.** Every action has a key path: ⌃⌥Space to open, ⌘1–5 for pages, ⌘K command palette, Tab between widgets, arrow keys inside them, type-to-capture. Holding ⌘ reveals every shortcut in place. Nothing is hover-only.
5. **Dense, not loud.** A strict cell grid (56 pt cells, 8 pt gutters). Hierarchy comes from weight and opacity, not colour. **Accent marks state and progress, never decoration.** Each card has at most one prominent (white) action. Sentences are ≥ 12 pt (body 13), metadata ≥ 11 pt, badges ≥ 10 pt, and even tertiary text is ≥ 6:1.
6. **One system, every surface.** The same tokens and views render the notch, the Settings live preview, onboarding and the tutorial. A setting change is visible before you commit to it.
7. **Respect the Mac.** Native controls in Settings (grouped `Form`), SF Symbols, the system accent, every accessibility display option honoured live, permissions only when needed, near-zero idle energy.

### 1.4 Improvements over NotchNook (summary)

Hardware-exact morph with no wobble and no sideways slide · hover intent + hover lift + ⌥ suppression · global shortcut, command palette and type-to-capture · hold-⌘ shortcut overlay · cell grid with per-widget width presets (min/max) and **multiple pages** · Settings with a **live preview stage** of the real views, search and per-setting reset · floating island on external displays · fullscreen and excluded-apps rules · satellite second activity · Tray multi-select + pipelines bar · contrast-clamped album accent (≥ 4.5:1) · own text-size setting that grows the grid (macOS has no Dynamic Type API for third parties, as confirmed by Apple DTS in Developer Forums thread 818858) · full VoiceOver model with actions and rotor · near-zero idle energy · just-in-time permissions.

---

## 2. Tokens (Swift)

**Module placement.** Put this in a `CrannyDesign` library target inside the `CrannyKit` package. It has no dependencies other than SwiftUI and AppKit. Every feature module depends on `CrannyDesign` and never hard-codes a colour, size, radius or animation.

**Access pattern.** Apply `.crannyThemeRoot(theme)` once at the root of each Cranny surface (notch panel, Settings preview, onboarding). Views read `@Environment(\.crannyTheme)`. The root merges the user's settings with the live system accessibility state (`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`), so a change in System Settings re-renders immediately.

**Why "single-appearance" colours.** The notch and the Nook always extend the black hardware notch, so their palette is a dark-only palette made of white alpha over black. Settings, onboarding and menus are ordinary windows and use **system semantic colours**, so they follow Light/Dark automatically.

```swift
// CrannyDesign — design tokens for direction C "Calm power-user".
// Pure Swift, no asset catalog. Deployment target macOS 14; newer APIs behind #available.
import SwiftUI
import AppKit

// MARK: - Traits: everything a token may depend on

public struct CrannyTraits: Equatable, Sendable {
    public enum Density: String, CaseIterable, Sendable { case compact, regular, comfortable }
    /// macOS has no public Dynamic Type / "Text size" API for third-party apps
    /// (DTS, Apple Developer Forums thread 818858), so Cranny ships its own setting.
    public enum TextSize: String, CaseIterable, Sendable {
        case small, standard, large, xLarge
        public var scale: CGFloat { switch self { case .small: 0.92; case .standard: 1; case .large: 1.12; case .xLarge: 1.24 } }
    }
    public enum ButtonShape: String, CaseIterable, Sendable { case capsule, rounded }
    public enum MotionPersonality: String, CaseIterable, Sendable { case calm, lively, instant }

    public var increaseContrast = false
    public var reduceTransparency = false
    public var reduceMotion = false
    public var differentiateWithoutColor = false
    public var density: Density = .regular
    public var textSize: TextSize = .standard
    public var buttonShape: ButtonShape = .capsule
    public var motion: MotionPersonality = .calm
    public var translucentNook = false          // Appearance ▸ "Translucent background"
    public var dividers = false                 // Appearance ▸ "Dividers between widgets" (instead of cards)
    public init() {}
}

// MARK: - Colors
// The notch/Nook is ALWAYS a dark surface (it extends the black hardware notch), so these
// are single-appearance tokens. Settings/onboarding windows use system semantic colors.

public struct CrannyColors: Sendable {
    public let hc: Bool        // Increase Contrast
    public let opaque: Bool    // Reduce Transparency (or translucency off)

    // Surfaces — "elevation" on black is expressed by white overlays.
    public var shell: Color { .black }                                   // never tinted, never translucent in the notch row
    public var shellTranslucent: Color { .black.opacity(opaque ? 1 : 0.78) }
    public var card: Color { .white.opacity(hc ? 0.12 : 0.06) }          // widget card (#0F0F0F on black)
    public var cardHover: Color { .white.opacity(hc ? 0.16 : 0.085) }
    public var control: Color { .white.opacity(hc ? 0.18 : 0.10) }       // button / chip / track
    public var controlHover: Color { .white.opacity(hc ? 0.24 : 0.14) }
    public var controlPressed: Color { .white.opacity(hc ? 0.30 : 0.18) }
    public var selection: Color { .white.opacity(hc ? 0.26 : 0.15) }     // selected tab / row (neutral, not accent)
    public var prominentFill: Color { .white }                           // the ONE primary action per card (play, Join)
    public var onProminent: Color { .black }

    // Strokes
    public var hairline: Color { .white.opacity(hc ? 0.32 : 0.08) }      // card edge, open-panel rim
    public var separator: Color { .white.opacity(hc ? 0.36 : 0.12) }     // "dividers" layout style
    public var dropTarget: Color { .white.opacity(hc ? 0.62 : 0.30) }    // dashed drop zones

    // Text (white alpha over black / card). Ratios measured by the PoC — see §2.1.
    public var textPrimary: Color { .white }                             // 21.0:1 on black
    public var textSecondary: Color { .white.opacity(hc ? 0.84 : 0.70) } // 9.96:1 on black, 9.55:1 on card (HC 14.5 / 12.0)
    public var textTertiary: Color { .white.opacity(hc ? 0.68 : 0.55) }  // 6.27:1 on black, 6.24:1 on card (HC 9.4 / 8.3)
    public var textQuaternary: Color { .white.opacity(hc ? 0.50 : 0.34) }// 2.9:1 → placeholders/decoration only (HC 5.3)

    // Semantic — system dynamic colors. The Nook forces .dark colorScheme, so these resolve
    // to their dark variants and switch to high-contrast variants automatically.
    public var success: Color { Color(nsColor: .systemGreen) }
    public var warning: Color { Color(nsColor: .systemOrange) }
    public var danger: Color { Color(nsColor: .systemRed) }
    public var info: Color { Color(nsColor: .systemBlue) }
    public var live: Color { Color(nsColor: .systemGreen) }             // "in progress" (meeting now, charging)

    public var syntax: Syntax { Syntax() }
    /// Notes "code mode" palette. Each ≥ 4.5:1 on the card fill (#0F0F0F); measured in the PoC.
    public struct Syntax: Sendable {
        public let keyword = Color(red: 1.00, green: 0.48, blue: 0.70)   // #FF7AB3
        public let string  = Color(red: 0.99, green: 0.62, blue: 0.40)   // #FC9E66
        public let number  = Color(red: 0.82, green: 0.75, blue: 1.00)   // #D1BFFF
        public let type    = Color(red: 0.42, green: 0.86, blue: 0.91)   // #6BDBE8
        public let comment = Color(white: 0.58)                          // #949494
        public let heading = Color.white                                 // Markdown #, **bold**
        public let link    = Color(red: 0.42, green: 0.70, blue: 1.00)   // #6BB3FF
    }
}

// MARK: - Accent strategy
// Rule: accent marks *state and progress* (fills, rings, focus, selection indicator in
// Settings) — never large backgrounds and never body text.

public enum AccentSource: Hashable, Sendable {
    case system                 // NSColor.controlAccentColor (follows System Settings)
    case albumArt               // contrast-clamped colour of current artwork → falls back to .system
    case swatch(AccentSwatch)   // user-picked
    case mono                   // white only ("disable colours" for HUD & visualizer)
}

public enum AccentSwatch: String, CaseIterable, Sendable {
    case blue, teal, green, yellow, orange, pink, purple, graphite
    /// All ≥ 7:1 on black (AAA for text), measured in the PoC.
    public var color: Color {
        switch self {
        case .blue:     Color(red: 0.36, green: 0.66, blue: 1.00)   // #5CA8FF
        case .teal:     Color(red: 0.31, green: 0.82, blue: 0.77)   // #4FD1C4
        case .green:    Color(red: 0.40, green: 0.83, blue: 0.53)   // #66D487
        case .yellow:   Color(red: 0.96, green: 0.77, blue: 0.32)   // #F5C452
        case .orange:   Color(red: 1.00, green: 0.62, blue: 0.36)   // #FF9E5C
        case .pink:     Color(red: 1.00, green: 0.50, blue: 0.71)   // #FF80B5
        case .purple:   Color(red: 0.72, green: 0.62, blue: 1.00)   // #B89EFF
        case .graphite: Color(red: 0.78, green: 0.78, blue: 0.80)   // #C7C7CC
        }
    }
}

public enum AccentResolver {
    @MainActor public static func resolve(_ source: AccentSource, artwork: NSColor?) -> Color {
        switch source {
        case .system:            Color(nsColor: .controlAccentColor)
        case .albumArt:          artwork.map { Color(nsColor: $0) } ?? Color(nsColor: .controlAccentColor)
        case .swatch(let s):     s.color
        case .mono:              .white
        }
    }
}

// MARK: - Typography (SF Pro / SF Pro Rounded / SF Mono via Font.Design)

public enum CrannyTextStyle: CaseIterable, Sendable {
    case display    // timer digits, HUD-in-peek percentage
    case title      // onboarding/peek primary line
    case headline   // track / event / note title
    case body       // note text, to-do text — the minimum size for sentences
    case callout    // artist, event title in lists
    case caption    // times, metadata (monospaced digits)
    case eyebrow    // small section label inside widgets
    case compact    // live-activity text in the notch row (fixed: the row is hardware height)
    case micro      // badges and counts only
    case code       // Notes code mode

    public struct Spec: Sendable {
        public let size: CGFloat, weight: Font.Weight, design: Font.Design
        public let lineHeight: CGFloat, tracking: CGFloat, monoDigits: Bool
    }

    public var spec: Spec {
        switch self {
        case .display:  Spec(size: 24, weight: .semibold, design: .rounded,    lineHeight: 28, tracking: -0.3, monoDigits: true)
        case .title:    Spec(size: 15, weight: .semibold, design: .default,    lineHeight: 20, tracking: -0.1, monoDigits: false)
        case .headline: Spec(size: 13, weight: .semibold, design: .default,    lineHeight: 16, tracking: 0,    monoDigits: false)
        case .body:     Spec(size: 13, weight: .regular,  design: .default,    lineHeight: 17, tracking: 0,    monoDigits: false)
        case .callout:  Spec(size: 12, weight: .regular,  design: .default,    lineHeight: 15, tracking: 0,    monoDigits: false)
        case .caption:  Spec(size: 11, weight: .medium,   design: .default,    lineHeight: 14, tracking: 0.1,  monoDigits: true)
        case .eyebrow:  Spec(size: 11, weight: .semibold, design: .default,    lineHeight: 13, tracking: 0.2,  monoDigits: false)
        case .compact:  Spec(size: 12, weight: .semibold, design: .rounded,    lineHeight: 14, tracking: 0,    monoDigits: true)
        case .micro:    Spec(size: 10, weight: .bold,     design: .rounded,    lineHeight: 12, tracking: 0.2,  monoDigits: true)
        case .code:     Spec(size: 12, weight: .regular,  design: .monospaced, lineHeight: 16, tracking: 0,    monoDigits: true)
        }
    }

    /// Text inside the notch row cannot grow — the row is the hardware notch height.
    public var scalesWithTextSize: Bool { self != .compact && self != .micro }
}

extension Font {
    public static func cranny(_ style: CrannyTextStyle, _ size: CrannyTraits.TextSize = .standard) -> Font {
        let s = style.spec
        let k = style.scalesWithTextSize ? size.scale : 1
        var f = Font.system(size: (s.size * k).rounded(), weight: s.weight, design: s.design)
        if s.monoDigits { f = f.monospacedDigit() }
        return f
    }
}

extension View {
    /// Font + tracking + line height for a Cranny text style (reads the theme's text size).
    public func crannyText(_ style: CrannyTextStyle) -> some View { modifier(CrannyTextModifier(style: style)) }
}

struct CrannyTextModifier: ViewModifier {
    @Environment(\.crannyTheme) private var theme
    let style: CrannyTextStyle
    func body(content: Content) -> some View {
        let s = style.spec
        let k = style.scalesWithTextSize ? theme.traits.textSize.scale : 1
        content
            .font(.cranny(style, theme.traits.textSize))
            .tracking(s.tracking)
            .lineSpacing(max(0, (s.lineHeight - s.size * 1.2) * k))
    }
}

// MARK: - Spacing (4-pt grid with a 2-pt micro step)

public enum Space {
    public static let xxxs: CGFloat = 2
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
}

// MARK: - Radii (always RoundedCornerStyle.continuous; nested radii are concentric)

public enum Radius {
    public static let chip: CGFloat = 6
    public static let control: CGFloat = 8          // "rounded" button shape
    public static let tile: CGFloat = 9             // 40-pt app/shortcut tile
    public static let artworkCompact: CGFloat = 5   // 20-pt artwork in the notch row
    public static let artwork: CGFloat = 8          // 52-pt artwork in a card corner (== NookMetrics.innerRadius, regular)
    public static func concentric(outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
        max(outer - inset, minimum)
    }
}

// MARK: - Nook grid metrics (density-dependent)

public struct NookMetrics: Equatable, Sendable {
    public let cell: CGFloat        // square grid unit
    public let gutter: CGFloat      // between cells and between widgets
    public let padding: CGFloat     // panel inner padding (sides + bottom)
    public let cardPadding: CGFloat // inside a widget card
    public let panelRadius: CGFloat // bottom corners of the open shape
    public let headerGap: CGFloat   // notch/header row → grid
    public let rows: Int            // grid height in cells (2 = standard)
    public var cardRadius: CGFloat { Radius.concentric(outer: panelRadius, inset: padding) }
    public var innerRadius: CGFloat { Radius.concentric(outer: cardRadius, inset: cardPadding) }

    /// Concentric by construction: cardRadius = panelRadius − padding, innerRadius = cardRadius − cardPadding.
    /// Larger text sizes grow the CELL (not just the font) so content never clips.
    public static func forDensity(_ d: CrannyTraits.Density, textSize: CrannyTraits.TextSize = .standard) -> NookMetrics {
        let k = textSize.scale
        func cell(_ c: CGFloat) -> CGFloat { (c * k / 2).rounded() * 2 }   // keep it even
        switch d {
        case .compact:     return NookMetrics(cell: cell(48), gutter: 6, padding: 8,  cardPadding: 8,  panelRadius: 22, headerGap: 6,  rows: 2)
        case .regular:     return NookMetrics(cell: cell(56), gutter: 8, padding: 10, cardPadding: 10, panelRadius: 28, headerGap: 8,  rows: 2)
        case .comfortable: return NookMetrics(cell: cell(64), gutter: 8, padding: 12, cardPadding: 12, panelRadius: 32, headerGap: 10, rows: 2)
        }
    }
    /// Width/height of a run of `n` cells including the gutters between them.
    public func span(_ n: Int) -> CGFloat { CGFloat(n) * cell + CGFloat(max(n - 1, 0)) * gutter }
    public static let maxColumns = 16
}

// MARK: - Strokes

public enum StrokeWidth {
    public static func hairline(_ displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) } // 1 device pixel
    public static let standard: CGFloat = 1
    public static let emphasis: CGFloat = 1.5       // dashed drop zone
    public static let focus: CGFloat = 2            // keyboard focus ring (accent)
    public static let scrubber: CGFloat = 3         // 6 while hovered/dragged
    public static let level: CGFloat = 4            // HUD level bar
    public static let ringCompact: CGFloat = 2.5    // timer/battery ring in the notch row
    public static let ring: CGFloat = 4             // timer ring in the widget
    public static let dash: [CGFloat] = [5, 4]
}

// MARK: - Shadows & glows

public struct ShadowToken: Sendable { public let color: Color; public let radius: CGFloat; public let y: CGFloat }

public enum Elevation {
    /// Closed / compact / peek: NO shadow — it would reveal the software↔hardware seam.
    public static let none = ShadowToken(color: .clear, radius: 0, y: 0)
    /// Open Nook over windows; multiplied by "openness" 0…1.
    public static let panel = ShadowToken(color: .black.opacity(0.45), radius: 24, y: 12)
    /// File tile being dragged in the Tray.
    public static let lifted = ShadowToken(color: .black.opacity(0.50), radius: 12, y: 6)
}

public enum Glow {
    /// Album-art glow: radial wash *inside* the shape (clipped), never outside.
    public static let artworkOpacity: Double = 0.22
    public static let artworkRadius: CGFloat = 260
    /// Ambient effect intensity range for the Settings slider (default 0.30).
    public static let ambientRange: ClosedRange<Double> = 0...0.5
}

extension View {
    public func crannyShadow(_ t: ShadowToken, amount: Double = 1) -> some View {
        shadow(color: t.color.opacity(amount), radius: t.radius * amount, x: 0, y: t.y * amount)
    }
}

// MARK: - Theme + environment

public struct CrannyTheme: Sendable {
    public var traits = CrannyTraits()
    public var accent: Color = Color(nsColor: .controlAccentColor)
    public var colors: CrannyColors { CrannyColors(hc: traits.increaseContrast, opaque: traits.reduceTransparency || !traits.translucentNook) }
    public var nook: NookMetrics { .forDensity(traits.density, textSize: traits.textSize) }
    public var buttonRadius: CGFloat? { traits.buttonShape == .capsule ? nil : Radius.control } // nil → Capsule
    public static let standard = CrannyTheme()
}

extension EnvironmentValues {
    @Entry public var crannyTheme: CrannyTheme = .standard
}

/// Root modifier: merges the user's Cranny settings with the system accessibility state.
/// Apply once at the root of every Cranny surface (notch panel, settings preview, onboarding).
public struct CrannyThemeRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor
    public var base: CrannyTheme
    public func body(content: Content) -> some View {
        var t = base
        t.traits.reduceMotion = t.traits.reduceMotion || reduceMotion
        t.traits.reduceTransparency = t.traits.reduceTransparency || reduceTransparency
        t.traits.increaseContrast = t.traits.increaseContrast || contrast == .increased
        t.traits.differentiateWithoutColor = t.traits.differentiateWithoutColor || noColor
        return content
            .environment(\.crannyTheme, t)
            .environment(\.colorScheme, .dark)   // system colours resolve to dark variants inside the Nook
    }
}
extension View {
    public func crannyThemeRoot(_ theme: CrannyTheme) -> some View { modifier(CrannyThemeRoot(base: theme)) }
}
```

### 2.1 Measured contrast (WCAG 2.x)

Card = white 6 % over black (#0F0F0F); with Increase Contrast, card = white 12 %.

| Token | alpha (std / HC) | on black | on card | HC on black | HC on card | Use |
|---|---|---|---|---|---|---|
| textPrimary | 1.00 | **21.0** | 19.1 | 21.0 | 16.6 | titles, values |
| textSecondary | 0.70 / 0.84 | **9.96** | 9.55 | 14.5 | 12.0 | artist, times |
| textTertiary | 0.55 / 0.68 | **6.27** | 6.24 | 9.4 | 8.3 | metadata, inactive tabs |
| textQuaternary | 0.34 / 0.50 | 2.89 | 3.08 | 5.3 | 5.1 | placeholders, line numbers **only** |
| hairline | 0.08 / 0.32 | 1.14 | – | 2.67 | – | card edge (decorative; HC raises it toward the 3:1 non-text level) |
| syntax keyword / string / number / type / comment / link | – | – | 7.9 / 9.3 / 11.5 / 11.8 / 6.3 / 8.6 | | | Notes code mode |
| accent swatches (8) | – | 8.5 – 12.9 | 7.8 – 11.8 | | | all AAA on black |

### 2.2 Accent strategy

- **Sources:** `system` (default: `NSColor.controlAccentColor`), `albumArt`, `swatch(…)` (8 curated, all ≥ 7:1), `mono` (white, the "disable colours" option for HUD and visualizer).
- **Album-art accent** (`AlbumAccent.extract`): sample the artwork at 24 × 24, then pick the hue bin with the highest weight, where weight = saturation² × closeness of brightness to 0.65. Return `nil` for near-greyscale art, which falls back to the system accent. Clamp the result for the dark surface: saturation 0.38–0.80, brightness ≥ 0.70, then raise until **≥ 4.5:1 on black**. Measured examples: navy #141966 → #6971EF (5.3:1), deep red #720C14 → #D1424D (4.6:1), brown #59381E → #B2703D (5.3:1). Cost is about 0.2 ms per track change; run it off the main actor and cross-fade the accent over 0.3 s.
- **Where accent appears:** progress fills (scrubber, timer ring, level bar), the visualizer, the focus ring, the selected checkbox, a drop target while armed, the code-mode toggle. **Never:** panel or card backgrounds, body text, large areas. The selected tab uses neutral `selection`, so the accent never fights album colours.
- **Semantic colours:** success/live = systemGreen, warning = systemOrange, danger = systemRed, info = systemBlue. They're resolved in the forced dark scheme and get high-contrast variants automatically. Semantic colour is always paired with a shape or text cue (§8).

```swift
import AppKit
import SwiftUI

/// Picks a legible accent from album art. Pure CoreGraphics, ~0.2 ms for a 24×24 sample.
/// Returns nil for near-greyscale art → caller falls back to the system accent.
public enum AlbumAccent {
    public static func extract(from image: CGImage) -> NSColor? {
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // 18 hue bins weighted by "vibrancy" (saturation × mid-brightness preference).
        var weight = [Double](repeating: 0, count: 18)
        var sum = [(Double, Double, Double)](repeating: (0, 0, 0), count: 18)
        var total = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let c = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let s = c.saturationComponent, v = c.brightnessComponent
            let w = s * s * (1 - abs(v - 0.65)) * (v > 0.12 ? 1 : 0)
            total += 1
            guard w > 0.02 else { continue }
            let bin = min(Int(c.hueComponent * 18), 17)
            weight[bin] += w; sum[bin].0 += r * w; sum[bin].1 += g * w; sum[bin].2 += b * w
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] / total > 0.035 else { return nil }          // greyscale art
        let w = weight[best]
        let raw = NSColor(srgbRed: sum[best].0 / w, green: sum[best].1 / w, blue: sum[best].2 / w, alpha: 1)
        return clampForDarkSurface(raw)
    }

    /// Ensures ≥ 4.5:1 against black (usable for text and 3:1 non-text on cards),
    /// caps saturation so neon art doesn't vibrate, never returns near-white.
    public static func clampForDarkSurface(_ c: NSColor, minContrast: Double = 4.5) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.sRGB)!.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        s = min(max(s, 0.38), 0.80)
        v = max(v, 0.70)
        var out = NSColor(hue: h, saturation: s, brightness: v, alpha: 1)
        var guardCount = 0
        while contrastOnBlack(out) < minContrast && guardCount < 12 {
            v = min(v + 0.04, 1); s = max(s - 0.04, 0.30)
            out = NSColor(hue: h, saturation: s, brightness: v, alpha: 1); guardCount += 1
        }
        return out
    }

    public static func relativeLuminance(_ c: NSColor) -> Double {
        let c = c.usingColorSpace(.sRGB)!
        func lin(_ x: CGFloat) -> Double { let x = Double(x); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
    public static func contrastOnBlack(_ c: NSColor) -> Double { (relativeLuminance(c) + 0.05) / 0.05 }
}
```

### 2.3 Typography

| Style | Size / weight / design | Line height | Digits | Notes |
|---|---|---|---|---|
| display | 24 semibold **SF Pro Rounded** | 28 | mono | timer, peek numbers; `contentTransition(.numericText(countsDown:))` |
| title | 15 semibold SF Pro | 20 | | onboarding, peek primary |
| headline | 13 semibold | 16 | | track/event/note title |
| body | 13 regular | 17 | | note text, to-dos |
| callout | 12 regular | 15 | | artist, event title in list |
| caption | 11 medium | 14 | mono | times, metadata, pipeline chips |
| eyebrow | 11 semibold, +0.2 tracking | 13 | | section labels (sentence case, no ALL CAPS) |
| compact | 12 semibold **Rounded** | 14 | mono | notch row; **does not scale** (hardware height) |
| micro | 10 bold Rounded | 12 | mono | badges and counts only |
| code | 12 **SF Mono** | 16 | mono | Notes code mode |

The Settings and onboarding windows use system text styles (`.body`, `.title2`, …), not these tokens.

### 2.4 Spacing, radii, strokes, elevation

- **Spacing:** 2 · 4 · 6 · 8 · 12 · 16 · 20 · 24 · 32 (a 4-pt grid with a 2-pt micro step).
- **Radii:** always `.continuous`, and always concentric: card = panel − padding, inner = card − card padding. At regular density: panel bottom **28**, card **18**, inner **8** (artwork, mirror inner preview, selected file tile). Fixed radii: chip 6, control (rounded-button mode) 8, app tile 9, compact artwork 5. The compact bottom radius is 0.42·h (13 at h = 32), peek 20, closed 0.30·h (10, user-tunable ±3).
- **Strokes:** hairline = 1 device pixel (`1/displayScale`), standard 1, emphasis 1.5 (dashed drop zones, dash 5/4), focus 2 (accent, offset 3 pt, concentric), scrubber 3 (6 while hovered or dragged), level bar 4, compact ring 2.5, widget ring 4.
- **Elevation:** closed, compact and peek have **no shadow**. Open uses black 45 %, blur 24, y 12, × openness. A dragged tray tile uses 50 %, blur 12, y 6. The open-panel **rim** is a hairline × openness, Cranny's version of the HIG "key line" that separates the Nook from dark windows.
- **Glows:** the album glow is a radial wash at 22 % of the accent, radius 260, **clipped inside the shape**. Ambient intensity 0–0.5 (default 0.30).

### 2.5 Components built on the tokens

```swift
import SwiftUI
import AppKit

// MARK: - Shape helper: capsule vs rounded per user setting

public struct CrannyButtonShape: Shape {
    public var radius: CGFloat?          // nil → capsule
    public func path(in r: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius ?? min(r.width, r.height) / 2, style: .continuous).path(in: r)
    }
}

// MARK: - Buttons

/// Icon button used everywhere inside the Nook (header actions, media transport, widget tools).
public struct CrannyIconButtonStyle: ButtonStyle {
    public enum Role { case plain, filled, prominent }
    public var role: Role = .filled
    public var size: CGFloat = 26                        // hit target ≥ 24 pt (macOS minimum 20)
    public func makeBody(configuration: Configuration) -> some View { IconBody(configuration: configuration, role: role, size: size) }

    struct IconBody: View {
        @Environment(\.crannyTheme) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration; let role: Role; let size: CGFloat
        var body: some View {
            let c = theme.colors
            let fill: Color = switch role {
            case .prominent: c.prominentFill
            case .filled: configuration.isPressed ? c.controlPressed : hovered ? c.controlHover : c.control
            case .plain: configuration.isPressed ? c.controlPressed : hovered ? c.control : .clear
            }
            configuration.label
                .font(.system(size: (size * 0.46).rounded(), weight: .semibold))
                .foregroundStyle(role == .prominent ? c.onProminent : c.textPrimary)
                .frame(width: size, height: size)
                .background(CrannyButtonShape(radius: theme.buttonRadius).fill(fill))
                .contentShape(CrannyButtonShape(radius: theme.buttonRadius))
                .scaleEffect(configuration.isPressed && !theme.traits.reduceMotion ? 0.94 : 1)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(Motion.hover.animation(theme.traits.motion, reduceMotion: theme.traits.reduceMotion), value: hovered)
                .animation(Motion.press.animation(theme.traits.motion, reduceMotion: theme.traits.reduceMotion), value: configuration.isPressed)
        }
    }
}

/// Small text action ("Join", "Start", "Undo"). `prominent` = the ONE primary action in a card.
public struct CrannyPillButtonStyle: ButtonStyle {
    public var prominent = false
    public func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, prominent: prominent) }
    struct PillBody: View {
        @Environment(\.crannyTheme) private var theme
        let configuration: Configuration; let prominent: Bool
        var body: some View {
            let c = theme.colors
            configuration.label
                .crannyText(.caption).fontWeight(.semibold)
                .foregroundStyle(prominent ? c.onProminent : c.textPrimary)
                .padding(.horizontal, 8).frame(minHeight: 20)
                .background(CrannyButtonShape(radius: theme.buttonRadius.map { _ in Radius.chip })
                    .fill(prominent ? c.prominentFill : configuration.isPressed ? c.controlPressed : c.control))
        }
    }
}

// MARK: - Key cap (shortcut hints; shown while ⌘ is held — "hold-⌘ cheat sheet")

public struct KeyCap: View {
    @Environment(\.crannyTheme) private var theme
    public var keys: String
    public init(_ keys: String) { self.keys = keys }
    public var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.colors.control))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.colors.hairline, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)    // shortcuts are exposed via accessibilityLabel/menus instead
    }
}

// MARK: - Widget card

public struct WidgetCard<Content: View>: View {
    @Environment(\.crannyTheme) private var theme
    public enum Style { case card, frameless }
    var cells: Int; var style: Style; var title: String; var content: Content
    public init(cells: Int, style: Style = .card, title: String, @ViewBuilder content: () -> Content) {
        self.cells = cells; self.style = style; self.title = title; self.content = content()
    }
    public var body: some View {
        let m = theme.nook, c = theme.colors
        let shape = RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
        content
            .padding(style == .card ? m.cardPadding : 0)
            .frame(width: m.span(cells), height: m.span(m.rows), alignment: .topLeading)
            .background {
                if style == .card && !theme.traits.dividers {
                    shape.fill(c.card).overlay(shape.strokeBorder(c.hairline, lineWidth: 1))
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(title))
    }
}

/// Keyboard focus ring for custom controls: accent, 2 pt, concentric with the element.
public struct FocusRing: ViewModifier {
    @Environment(\.crannyTheme) private var theme
    var focused: Bool; var radius: CGFloat
    public func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: StrokeWidth.focus)
                .padding(-3)
                .opacity(focused ? 1 : 0)
        }
    }
}

// MARK: - Level bar & progress ring

public struct LevelBar: View {
    @Environment(\.crannyTheme) private var theme
    var value: Double; var color: Color; var thickness: CGFloat = StrokeWidth.level
    public var body: some View {
        GeometryReader { g in
            Capsule(style: .continuous).fill(theme.colors.control)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous).fill(color)
                        .frame(width: value <= 0 ? 0 : max(thickness, g.size.width * min(value, 1)))
                }
        }
        .frame(height: thickness)
    }
}

public struct ProgressRing: View {
    @Environment(\.crannyTheme) private var theme
    var progress: Double; var color: Color; var lineWidth: CGFloat
    public var body: some View {
        ZStack {
            Circle().stroke(theme.colors.control, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Drop zone (Tray, AirDrop)

public struct DropZone: View {
    @Environment(\.crannyTheme) private var theme
    var symbol: String; var title: String; var targeted: Bool
    public var body: some View {
        let r = theme.nook.cardRadius
        VStack(spacing: Space.xs) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            Text(title).crannyText(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(targeted ? theme.colors.textPrimary : theme.colors.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(targeted ? theme.accent.opacity(0.16) : .clear))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
            .strokeBorder(targeted ? theme.accent : theme.colors.dropTarget,
                          style: StrokeStyle(lineWidth: StrokeWidth.emphasis, dash: StrokeWidth.dash)))
        .scaleEffect(targeted && !theme.traits.reduceMotion ? 1.02 : 1)
        .animation(Motion.commit.animation(theme.traits.motion, reduceMotion: theme.traits.reduceMotion), value: targeted)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Haptics (Force Touch trackpad). macOS plays only .generic / .alignment / .levelChange.

public enum Haptics {
    @MainActor public static var enabled = true      // Settings ▸ Gestures ▸ Haptic feedback
    @MainActor public static func tick()    { play(.alignment) }   // threshold crossed, snap to cell, swipe commit
    @MainActor public static func level()   { play(.levelChange) } // HUD hits 0/100, timer done, drop accepted
    @MainActor public static func generic() { play(.generic) }     // Nook opened by gesture
    @MainActor private static func play(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }
}
```

---

## 3. Geometry of the notch shape

### 3.1 One shape, six animatable parameters

`NotchShape` draws every state from `bodyWidth, bodyHeight, bottomRadius, earRadius, topRadius, topInset`.

- **Bottom corners:** `UnevenRoundedRectangle(style: .continuous)`.
- **Ears:** the concave flares where the top edge meets the menu bar are two quarter-circle cubics (control factor 0.4477). They overlap the body by 0.5 pt and are unioned (`Path.union`, macOS 14) into one clean outline, so stroking the rim never shows seams.
- **Floating island:** `topInset > 0` detaches the body; ears fade to 0 over the first 2 pt of detaching and the top corners round. That's how the no-notch island morphs.
- **Fixed canvas:** the panel window never resizes. It's sized for the largest open state plus a 24-pt shadow margin, and all motion is `animatableData` interpolation. Pointer events outside the current shape fall through (`contentShape(shape)` + window `ignoresMouseEvents` toggled by hit-testing the shape).

```swift
import SwiftUI
import AppKit

// MARK: - Shape

/// ONE shape for every state. It is drawn inside a FIXED-size canvas (the panel window never
/// resizes), and all six parameters are animatable, so closed → compact → peek → open (and the
/// floating island on no-notch displays) morph with a single spring — no layout animation.
public struct NotchShape: Shape {
    public var bodyWidth: CGFloat      // width of the black body, excluding ears
    public var bodyHeight: CGFloat     // height from the top of the body
    public var bottomRadius: CGFloat   // convex bottom corners (continuous)
    public var earRadius: CGFloat      // concave flare into the screen's top edge (attached mode)
    public var topRadius: CGFloat      // convex top corners (floating island only)
    public var topInset: CGFloat       // 0 = attached to the screen top; > 0 = floating island

    public typealias Pair = AnimatablePair
    public var animatableData: Pair<Pair<CGFloat, CGFloat>, Pair<Pair<CGFloat, CGFloat>, Pair<CGFloat, CGFloat>>> {
        get { Pair(Pair(bodyWidth, bodyHeight), Pair(Pair(bottomRadius, earRadius), Pair(topRadius, topInset))) }
        set {
            bodyWidth = newValue.first.first; bodyHeight = newValue.first.second
            bottomRadius = newValue.second.first.first; earRadius = newValue.second.first.second
            topRadius = newValue.second.second.first; topInset = newValue.second.second.second
        }
    }

    public init(_ g: NotchGeometry) {
        bodyWidth = g.bodyWidth; bodyHeight = g.bodyHeight; bottomRadius = g.bottomRadius
        earRadius = g.earRadius; topRadius = g.topRadius; topInset = g.topInset
    }

    public func path(in rect: CGRect) -> Path {
        let w = max(bodyWidth, 0), h = max(bodyHeight, 0)
        guard w > 0.5, h > 0.5 else { return Path() }
        let body = CGRect(x: rect.midX - w / 2, y: rect.minY + topInset, width: w, height: h)
        let rb = min(bottomRadius, h / 2, w / 2)
        let rt = min(topRadius, h - rb, w / 2)
        var path = UnevenRoundedRectangle(
            topLeadingRadius: rt, bottomLeadingRadius: rb,
            bottomTrailingRadius: rb, topTrailingRadius: rt,
            style: .continuous
        ).path(in: body)

        // Ears exist only while attached; they shrink to 0 over the first 2 pt of detaching.
        let attach = max(0, 1 - topInset / 2)
        let e = min(earRadius * attach, h - rb, body.minX - rect.minX)
        if e > 0.25 {
            let k: CGFloat = 0.4477                 // 1 − 0.5523: cubic ≈ quarter circle
            var ears = Path()
            for side in [-1.0, 1.0] as [CGFloat] {
                let x0 = side < 0 ? body.minX : body.maxX     // body edge
                let xo = x0 + side * e                        // ear tip on the top edge
                let lap = -side * 0.5                         // overlap into the body → no AA seam
                ears.move(to: CGPoint(x: xo, y: body.minY))
                ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY))
                ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY + e))
                ears.addLine(to: CGPoint(x: x0, y: body.minY + e))
                ears.addCurve(to: CGPoint(x: xo, y: body.minY),
                              control1: CGPoint(x: x0, y: body.minY + e * k),
                              control2: CGPoint(x: xo - side * e * (1 - k), y: body.minY))
                ears.closeSubpath()
            }
            path = path.union(ears)                  // macOS 14+: one clean outline (strokable)
        }
        return path
    }
}

// MARK: - Measured hardware metrics

public struct NotchHardware: Equatable, Sendable {
    public var hasNotch: Bool
    public var notchWidth: CGFloat      // cutout width (virtual width on no-notch screens)
    public var notchHeight: CGFloat     // cutout height == notch-row height
    public var screenWidth: CGFloat
    public var menuBarHeight: CGFloat

    /// Measure — never hard-code. Re-measure on NSApplication.didChangeScreenParametersNotification
    /// (scaled resolutions change the notch's size in points).
    @MainActor public static func measure(_ screen: NSScreen, widthTweak: CGFloat = 0, virtualWidth: CGFloat = 190) -> NotchHardware {
        let f = screen.frame
        let menuBar = max(f.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, !l.isEmpty, !r.isEmpty {
            return NotchHardware(hasNotch: true, notchWidth: f.width - l.width - r.width + widthTweak,
                                 notchHeight: top, screenWidth: f.width, menuBarHeight: menuBar)
        }
        return NotchHardware(hasNotch: false, notchWidth: virtualWidth + widthTweak, notchHeight: menuBar,
                             screenWidth: f.width, menuBarHeight: menuBar)
    }
}

// MARK: - Per-state geometry

public struct NotchGeometry: Equatable, Sendable {
    public var bodyWidth: CGFloat, bodyHeight: CGFloat
    public var bottomRadius: CGFloat, earRadius: CGFloat, topRadius: CGFloat, topInset: CGFloat
}

public enum NoNotchStyle: String, Sendable { case floatingIsland, attachedNotch }

public enum NotchState: Equatable, Sendable {
    case closed
    case compact(slot: CGFloat)                  // live activity flanking the notch; slot = ONE side
    case peek(width: CGFloat, extra: CGFloat)    // compact + detail row(s) below the notch row
    case open(width: CGFloat, height: CGFloat)   // the Nook
}

/// Symmetric slot widths, relative to the notch-row height `h` (32 pt on current MacBooks).
public enum SlotWidth {
    public static func glyph(_ h: CGFloat) -> CGFloat { (h + 8).rounded() }    // art / icon only       → 40
    public static func short(_ h: CGFloat) -> CGFloat { (h + 30).rounded() }   // icon + "12m" / "82%"  → 62
    public static func wide(_ h: CGFloat)  -> CGFloat { (h + 64).rounded() }   // HUD level bar         → 96
    /// Detached "satellite" circle for a second concurrent activity (iOS "minimal" analogue).
    public static func satellite(_ h: CGFloat) -> CGFloat { (h - 8).rounded() } // → 24
}

extension NotchGeometry {
    /// Hardware-true closed radius ≈ 0.30·h (≈10 pt at h = 32); user fine-tune ±3 pt.
    public static func closedBottomRadius(_ h: CGFloat, tweak: CGFloat = 0) -> CGFloat {
        min(max((h * 0.30).rounded(), 6), 12) + tweak
    }

    public static func make(_ state: NotchState, hw: NotchHardware, nook: NookMetrics,
                            noNotch: NoNotchStyle = .floatingIsland, radiusTweak: CGFloat = 0) -> NotchGeometry {
        let h = hw.notchHeight
        if !hw.hasNotch && noNotch == .floatingIsland {
            let pillH: CGFloat = 26
            switch state {
            case .closed:      // the handle (opacity is its own user token: 0 … 0.35)
                return .init(bodyWidth: 64, bodyHeight: 5, bottomRadius: 2.5, earRadius: 0, topRadius: 2.5, topInset: 4)
            case .compact(let slot):
                return .init(bodyWidth: 80 + 2 * slot, bodyHeight: pillH, bottomRadius: pillH / 2, earRadius: 0, topRadius: pillH / 2, topInset: 4)
            case .peek(let w, let extra):
                return .init(bodyWidth: max(w, 80 + 2 * SlotWidth.wide(pillH)), bodyHeight: pillH + extra,
                             bottomRadius: 20, earRadius: 0, topRadius: 20, topInset: 4)
            case .open(let w, let hh):
                return .init(bodyWidth: w, bodyHeight: hh, bottomRadius: nook.panelRadius, earRadius: 0, topRadius: nook.panelRadius, topInset: 6)
            }
        }
        switch state {
        case .closed:
            // Exactly the cutout, inset 0.5 pt so anti-aliasing never peeks out. No ears, no shadow.
            return .init(bodyWidth: hw.notchWidth - 1, bodyHeight: h - 0.5,
                         bottomRadius: closedBottomRadius(h, tweak: radiusTweak), earRadius: 0, topRadius: 0, topInset: 0)
        case .compact(let slot):
            return .init(bodyWidth: hw.notchWidth + 2 * slot, bodyHeight: h,
                         bottomRadius: (h * 0.42).rounded(), earRadius: 6, topRadius: 0, topInset: 0)
        case .peek(let w, let extra):
            return .init(bodyWidth: max(w, hw.notchWidth + 2 * SlotWidth.wide(h)), bodyHeight: h + extra,
                         bottomRadius: 20, earRadius: 8, topRadius: 0, topInset: 0)
        case .open(let w, let hh):
            return .init(bodyWidth: w, bodyHeight: hh, bottomRadius: nook.panelRadius, earRadius: 10, topRadius: 0, topInset: 0)
        }
    }
}

// MARK: - Open Nook size from the widget layout

public enum NookLayoutSize {
    /// `cells`: total width of the visible widgets in cells (widgets are separated by one gutter,
    /// so the grid is simply span(cells)).
    public static func size(cells: Int, hw: NotchHardware, nook m: NookMetrics, headerSideMin: CGFloat = 176) -> CGSize {
        let grid = m.span(min(cells, maxColumns(hw: hw, nook: m)))
        let headerNeeds = hw.notchWidth + 2 * headerSideMin           // tabs left of the cutout, actions right
        let w = min(max(grid + 2 * m.padding, headerNeeds), maxWidth(hw))
        let rowH = max(hw.notchHeight, 28)                             // header row == notch row
        let h = rowH + m.headerGap + m.span(m.rows) + m.padding
        return CGSize(width: w.rounded(), height: h.rounded())
    }
    public static func maxWidth(_ hw: NotchHardware) -> CGFloat { min(hw.screenWidth - 48, hw.screenWidth * 0.66) }
    public static func maxColumns(hw: NotchHardware, nook m: NookMetrics) -> Int {
        min(NookMetrics.maxColumns, Int(((maxWidth(hw) - 2 * m.padding + m.gutter) / (m.cell + m.gutter)).rounded(.down)))
    }
}
```

### 3.2 Sizes per state (14″ MacBook Pro, cutout 185 × 32 pt; `h` = notch height)

| State | Body width | Body height | Bottom r | Ear r | Shadow | Example (14″) |
|---|---|---|---|---|---|---|
| **closed** | notchW − 1 | h − 0.5 | 0.30·h clamped 6…12, ±3 user tweak | 0 | none | 184 × 31.5, r 10 |
| hover lift (anticipation while the dwell runs) | notchW + 8 | h + 3 | closed + 1 | 3 | none | 193 × 35 |
| **compact**, glyph slots | notchW + 2·(h + 8) | h | 0.42·h | 6 | none | 265 × 32, r 13 |
| compact, short slots (icon + "12m") | notchW + 2·(h + 30) | h | 0.42·h | 6 | none | 309 × 32 |
| compact, wide slots (HUD) | notchW + 2·(h + 64) | h | 0.42·h | 6 | none | 377 × 32 |
| satellite (2nd activity) | circle h − 8 | – | – | – | none | Ø 24, 6 pt right of the compact body |
| **peek** | max(content, notchW + 2·wide) | h + 58 (one detail row) | 20 | 8 | none | 377 × 90 |
| **open** (the Nook) | max(grid + 2·pad, notchW + 2·176), ≤ min(screen − 48, 0.66·screen) | h + gap + span(rows) + pad | 28 | 10 | panel × openness | 652 × 170 (10 cells) |

Measured by the PoC (`numbers()`):

| Display | Density | Cell / gutter | Open, 10 cells | Max columns | Card r / inner r | Slots g/s/w |
|---|---|---|---|---|---|---|
| 14″ MBP (1512 pt wide) | compact | 48 / 6 | 550 × 148 | 16 | 14 / 6 | 40 / 62 / 96 |
| | **regular** | **56 / 8** | **652 × 170** | 15 | **18 / 8** | 40 / 62 / 96 |
| | comfortable | 64 / 8 | 736 × 190 | 13 | 20 / 8 | 40 / 62 / 96 |
| 13″ Air (1470) | regular | 56 / 8 | 652 × 170 | 14 | 18 / 8 | 40 / 62 / 96 |
| "More Space" (notch ≈ 160 × 25) | regular | 56 / 8 | 652 × 166 | 16 | 18 / 8 | 33 / 55 / 89 |
| 27″ external, no notch (menu bar 25) | regular | 56 / 8 | 652 × 166 | 16 | 18 / 8 | 33 / 55 / 89 |
| 14″ MBP, **XL text** | regular | 70 / 8 | 792 × 198 | 12 | 18 / 8 | 40 / 62 / 96 |

### 3.3 Scaling rules

- **Measure, never hard-code.** `notchWidth = screen.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width` and `h = safeAreaInsets.top`. Re-measure on `didChangeScreenParametersNotification`, because scaled resolutions change the notch's size in points. Width fine-tune is ±20 pt and radius ±3 pt (Settings ▸ Appearance ▸ Notch fit, with a 2× magnified live outline over the real notch while you drag).
- **Slots** scale with `h` (glyph = h + 8, short = h + 30, wide = h + 64), so wider or taller notches keep the same proportions as the HIG's 52 × 37 compact elements.
- **Grid** cells don't depend on the notch. The header row (tabs left of the cutout, actions right) needs notchW + 2 × 176 pt, so a short layout still widens to fit the header.
- **No-notch displays:** default is the **floating island**. Closed = a **handle pill 64 × 5**, r 2.5, 4 pt below the top edge, opacity user-set from 0 (invisible) to 0.35, with a hot zone of 200 × menu-bar height. Compact = pill-height 26, capsule. Open = all corners `panelRadius`, `topInset` 6. The alternative **Attached notch** style uses the virtual width (190 pt default) with the same geometry as hardware.
- **Choose displays:** Built-in only (default) · All displays · Display with the menu bar · a custom list, with a style per display (Island / Attached / Off).

![states](<research-scratchpad>/poc/design-power/v2/out/states.png)
![filmstrip](<research-scratchpad>/poc/design-power/v2/out/filmstrip.png)

---

## 4. Motion

### 4.1 Spring table (Calm personality = default)

Specified as `.spring(duration:bounce:)`. Physics values come from `Spring(duration:bounce:)` in the SDK, and overshoot was measured on a 0 → 1 step.

| Token | duration / bounce | damping ratio | stiffness / damping | settles | overshoot | Used for |
|---|---|---|---|---|---|---|
| open | 0.40 / **0.08** | 0.92 | 246.7 / 28.9 | 0.67 s | 0.1 % (≈ 0.6 pt on a 652-pt panel) | closed/compact → open |
| open (Lively) | 0.40 / 0.22 | 0.78 | 246.7 / 24.5 | 0.78 s | 2.0 % (≈ 13 pt) | opt-in personality |
| close | 0.30 / **0** | 1.00 | 438.6 / 41.9 | 0.50 s | **0** (lands exactly on the cutout) | any → closed |
| peekIn | 0.34 / 0.08 | 0.92 | 341.5 / 34.0 | 0.58 s | 0.1 % | compact → peek |
| peekOut | 0.28 / 0 | 1.00 | 503.6 / 44.9 | 0.50 s | 0 | peek → compact |
| activitySwap | 0.30 / 0.04 | 0.96 | 438.6 / 40.2 | 0.50 s | 0 | slot width change (e.g. music → HUD) |
| hoverLift | 0.20 / 0 | 1.00 | 987 / 62.8 | 0.30 s | 0 | dwell anticipation |
| tab | 0.26 / 0 | 1.00 | 584 / 48.3 | 0.40 s | 0 | page content |
| tabIndicator | 0.30 / 0.10 | 0.90 | 438.6 / 37.7 | 0.53 s | 0.2 % | selection pill (matchedGeometry) |
| press | 0.18 / 0.20 | 0.80 | 1218 / 55.9 | 0.37 s | 1.5 % | button scale 0.94 |
| level | 0.16 / 0 | 1.00 | 1542 / 78.5 | 0.30 s | 0 | HUD bar following key repeat |
| snapBack | 0.36 / 0.12 | 0.88 | 304.6 / 30.7 | 0.63 s | 0.3 % | released gesture below threshold |
| commit | 0.30 / 0 | 1.00 | 438.6 / 41.9 | 0.50 s | 0 | drop accepted, checkbox, armed target |
| listReorder | 0.32 / 0.06 | 0.94 | 385.5 / 36.9 | 0.54 s | 0 | to-do completion moves, tray insert |
| hover (ease) | easeOut 0.12 | | | | | fills on hover |
| contentIn (ease) | easeOut 0.20, **delay 0.08** | | | | | content after the shape has passed about 60 % |
| contentOut (ease) | easeIn 0.10 | | | | | content gone before the shape shrinks over it |

Every animation stays under the HIG's 2-second cap. Springs **preserve velocity when interrupted**: hovering out mid-open reverses smoothly from the current shape, because `animatableData` is retargeted rather than restarted.

### 4.2 Choreography

**Open** (intent confirmed at t = 0):
1. t = 0: the shape springs `open`; compact slot content fades out (`contentOut`, 100 ms); the shadow and rim ramp with `openness`.
2. t = 80 ms: the header row fades in, then widgets follow (`contentIn` = opacity + blur 6 → 0 + scale 0.96 → 1 anchored at the top). **Stagger: 15 ms per widget, ordered outward from the notch centre**, capped at 90 ms.
3. About 400 ms in, the shape is visually there; it's settled by 670 ms. The keyboard focus ring appears only if the Nook was opened by keyboard.

**Close:** content out 100 ms with no stagger → shape `close` (no bounce) → on `.logicallyComplete` (`withAnimation(_:completionCriteria:_:completion:)`), set the window to `ignoresMouseEvents = true`, clear the shadow, and restore the previous key window.

**Peek in** (hover over compact, or an event such as a track change, a meeting in ≤ 5 min, or a timer finishing): the shape `peekIn` grows downward by one 58-pt detail row; the row content uses `contentIn`. Auto-collapse after 2.5 s for events; for hover it stays until the pointer leaves plus the grace period.

**Activity swap** (e.g. music → volume HUD): old slot content blur-replace out (`.transition(.blurReplace)`), slot width `activitySwap`, new content in. When the HUD ends, the reverse happens after 1.4 s of inactivity.

**Tab / page switch:** `AnyTransition.crannyTab(forward:)` (±16 pt + opacity, symmetric in both directions) with `tab`. The selection pill uses `matchedGeometryEffect` with `tabIndicator`. If pages have different heights, the shape uses `open`.

**Hover feedback:** control fills ease out over 0.12. The closed shape gets a **hover lift** (+4 pt per side, +3 pt down) while the dwell timer runs, and drops back if the pointer leaves first. Buttons scale to 0.94 on press.

**Numbers:** `contentTransition(.numericText(value:))` for HUD values and `.numericText(countsDown: true)` for timers. Symbols use `.contentTransition(.symbolEffect(.replace))` (e.g. mute ↔ speaker).

### 4.3 Gestures and rubber-banding

| Gesture (two-finger scroll over the notch/Nook) | Threshold | Feedback | Result |
|---|---|---|---|
| Pull **down** on closed/compact | 24 pt, or velocity ≥ 320 pt/s | The shape follows the fingers: `height += rubberBand(dy, limit: 28)`. Haptic `alignment` when the threshold is crossed. | Release past the threshold → `open`, carrying the gesture velocity. Release before it → `snapBack`. |
| Push **up** on open | 18 pt | Same, inverted. | `close` |
| Push **up** on compact/peek | 18 pt | The content lifts by the rubber-banded distance. | Dismiss this activity until it changes ("swipe to dismiss"). Auto-unhides on the next event. |
| **Horizontal** over media (compact, peek or open) | 44 pt | Artwork offset = `rubberBand(dx, 28)`; the next/previous glyph fades in on the leading side. Haptic `alignment` at the threshold. | Commit → artwork slides one slot out, the new artwork blur-replaces in, and the track changes. There's an **Invert direction** setting. |

Axis lock: the larger axis wins once |dx|/|dy| ≥ 1.6. A second gesture is ignored until the first settles.

### 4.4 Reduce Motion

- No spring, scale, blur or offset; durations ≤ 0.18 s.
- **Size changes become a cross-fade**: the closed (or compact) shape and the open shape cross-fade at their final sizes over 0.18 s instead of morphing.
- Tab switches are opacity-only (0.15 s). The HUD level jumps (no animation). The visualizer shows **static bars** (still conveys "playing"). The aurora freezes on a single static frame (or is hidden). The typewriter reveal is off. Peek auto-collapse still happens, but as a fade.
- The **Instant** personality turns animation off entirely for people who want it, even without Reduce Motion.

```swift
import SwiftUI
import AppKit

/// Motion tokens. Geometry springs are (near-)critically damped by default: users of comparable
/// apps filed the most-upvoted issues against a "jiggly/wobbly" open/close animation and a close
/// animation that did not land exactly on the hardware notch.
public enum Motion: CaseIterable, Sendable {
    case open, close, peekIn, peekOut, activitySwap, hoverLift
    case contentIn, contentOut, tab, tabIndicator
    case hover, press, level, snapBack, commit, listReorder

    public func animation(_ p: CrannyTraits.MotionPersonality = .calm, reduceMotion: Bool = false) -> Animation? {
        if p == .instant { return nil }
        if reduceMotion { return reduced }
        let lively = p == .lively
        switch self {
        case .open:         return .spring(duration: 0.40, bounce: lively ? 0.22 : 0.08)
        case .close:        return .spring(duration: 0.30, bounce: 0)      // must land exactly on the cutout
        case .peekIn:       return .spring(duration: 0.34, bounce: lively ? 0.20 : 0.08)
        case .peekOut:      return .spring(duration: 0.28, bounce: 0)
        case .activitySwap: return .spring(duration: 0.30, bounce: 0.04)
        case .hoverLift:    return .spring(duration: 0.20, bounce: 0)
        case .contentIn:    return .easeOut(duration: 0.20).delay(0.08)    // after the shape passes ~60 %
        case .contentOut:   return .easeIn(duration: 0.10)                 // gone before the shape shrinks over it
        case .tab:          return .spring(duration: 0.26, bounce: 0)
        case .tabIndicator: return .spring(duration: 0.30, bounce: lively ? 0.20 : 0.10)
        case .hover:        return .easeOut(duration: 0.12)
        case .press:        return .spring(duration: 0.18, bounce: 0.20)
        case .level:        return .spring(duration: 0.16, bounce: 0)      // HUD follows key repeat (~30 Hz)
        case .snapBack:     return .spring(duration: 0.36, bounce: lively ? 0.25 : 0.12)
        case .commit:       return .spring(duration: 0.30, bounce: 0)
        case .listReorder:  return .spring(duration: 0.32, bounce: 0.06)
        }
    }

    /// Reduce Motion: no bounce/scale/blur/offset. Size changes become a short cross-fade
    /// (see `NookPresence`) instead of a morph; continuous tracking (level) is instant.
    private var reduced: Animation? {
        switch self {
        case .open, .close, .peekIn, .peekOut, .activitySwap: return .easeInOut(duration: 0.18)
        case .contentIn:    return .easeOut(duration: 0.15)
        case .contentOut:   return .easeIn(duration: 0.08)
        case .hover, .press: return .linear(duration: 0.08)
        case .level, .hoverLift: return nil
        default:            return .easeInOut(duration: 0.15)
        }
    }

    /// Entrance stagger, ordered by distance from the notch centre outward.
    public static func stagger(index: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : min(Double(index) * 0.015, 0.09)
    }
}

/// iOS-style rubber band for gesture overscroll: small effort → movement, large effort → resistance.
@inline(__always)
public func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient c: CGFloat = 0.55) -> CGFloat {
    let sign: CGFloat = offset < 0 ? -1 : 1
    let x = abs(offset)
    return sign * (1 - 1 / (x * c / limit + 1)) * limit
}

/// Gesture thresholds (trackpad two-finger scroll deltas, in points).
public enum GestureSpec {
    public static let openPull: CGFloat = 24          // vertical pull-down to open
    public static let closePush: CGFloat = 18         // push-up to close / dismiss activity
    public static let trackSwipe: CGFloat = 44        // horizontal swipe to change track
    public static let commitVelocity: CGFloat = 320   // pt/s — a flick commits below the distance threshold
    public static let rubberLimit: CGFloat = 28       // max visual travel while dragging
    public static let axisLock: CGFloat = 1.6         // |dx| / |dy| ratio to lock the axis
}

/// Content cross-fade used for open/close: blur + scale anchored at the notch.
public struct NookContentTransition: ViewModifier {
    public var visible: Bool
    public var reduceMotion: Bool
    public func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: (visible || reduceMotion) ? 0 : 6)
            .scaleEffect(visible || reduceMotion ? 1 : 0.96, anchor: .top)
    }
}

/// Symmetric, direction-aware tab transition (fixes "fades one way, slides the other").
public extension AnyTransition {
    static func crannyTab(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: forward ? 16 : -16).combined(with: .opacity),
            removal: .offset(x: forward ? -16 : 16).combined(with: .opacity))
    }
}

// MARK: - Hover intent

/// Decides whether a pointer over the notch *means* "open", so travelling to the menu bar
/// does not open the Nook by accident.
public struct HoverIntent: Sendable {
    public enum Sensitivity: String, CaseIterable, Sendable {
        case eager, standard, deliberate
        public var dwell: Double { switch self { case .eager: 0.10; case .standard: 0.22; case .deliberate: 0.45 } }
    }
    public var sensitivity: Sensitivity = .standard
    public var maxPassThroughSpeed: CGFloat = 900                     // pt/s — faster = passing through
    public var suppressModifier: NSEvent.ModifierFlags = .option      // hold ⌥ to never open on hover

    public func shouldOpen(dwell: Double, speed: CGFloat, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard !modifiers.contains(suppressModifier) else { return false }
        return dwell >= sensitivity.dwell && speed < maxPassThroughSpeed
    }
    /// Close only after leaving the panel + margin for this long — never while pinned, typing,
    /// dragging, or while a menu/popover/sheet that belongs to the Nook is open.
    public static let leaveGraceDistance: CGFloat = 14
    public static let leaveGraceTime: Double = 0.30
    /// While dwelling (before intent completes) the closed shape grows by this much: anticipation.
    public static let hoverLift = CGSize(width: 8, height: 3)
}
```

---

## 5. Layouts

### 5.1 The open Nook

```
 ear╭────────────────────────────── 652 × 170 (regular, 10 cells) ─────────────────────────────╮ear
    │ pad 10                                                                                  │
    │ [▦ Nook ⌘1] [⌂ Tray 4] [≡ Notes]     ┌══════ hardware cutout 185 ══════┐   (⌕) (📌) (⚙)  │  header row = notch row (h = 32)
    │  tabs: pills 24 h, gap 2             └═════════════════════════════════┘   24-pt icon btns │
    │ ── headerGap 8 ──────────────────────────────────────────────────────────────────────── │
    │ ┌─ Media 4 ─────────────┐ ┌─ Calendar 3 ──────┐ ┌A┐ ┌─ Mirror 2 ──┐                     │
    │ │ 248 × 120, r 18       │ │ 184 × 120         │ │p│ │ 120 × 120   │   grid: 2 rows of   │
    │ │                       │ │                   │ │p│ │ frameless   │   56-pt cells,      │
    │ └───────────────────────┘ └───────────────────┘ └─┘ └─────────────┘   8-pt gutters       │
    ╰─ r 28 ────────────────────────────────────────────────────────────────────────── r 28 ─╯
```

- **Grid:** square cells (48 / **56** / 64 pt by density; × text-size scale), gutter 6 / **8** / 8, **2 rows**. Widgets are separated by one gutter, so a layout of *n* cells is `span(n)` wide. Max columns = floor((maxWidth − 2·pad + gutter) / (cell + gutter)), capped at **16** for calm (15 on a 14″ display at regular density).
- **Header row = notch row.** Tabs sit left of the cutout, actions right, so the dead space beside the camera is used (HIG: wrap content tightly around the camera). If the tabs don't fit their zone, labels collapse to icons, with tooltips and VoiceOver labels kept.
- **Pages:** **Nook** (widgets) and **Tray** are built in; up to **3 user pages** (the default third page is a "Notes" workspace: Notes 4 · To-dos 3 · Timer 2 · Shortcuts 1). Each page is its own grid. Switch with **⌘1–⌘5**, ⌃Tab / ⌃⇧Tab, or a click. There is deliberately no page-swipe gesture, because horizontal two-finger swipes belong to media (no gesture conflicts).
- **Dividers style** (Appearance): no card fills; instead, 1 pt `separator` lines between widgets, inset 10 pt top and bottom.
- **Padding** follows density presets, plus a "Panel padding" fine-tune of ±4 pt. Radii follow automatically and stay concentric.
- **Command palette (⌘K):** replaces the grid area at the same height. A 28-pt search field sits on a card, and up to 4 result rows of 22 pt each show icon 16, title (body), kind (caption, tertiary) and the shortcut as a `KeyCap`. It searches actions ("Start 25-minute timer", "New note", "Pause live activities for 1 hour", "Demo mode"), quick apps, Shortcuts, notes, to-dos and Settings panes. ↑ ↓ ↩ navigate; Esc returns to the grid.
- **Hold ⌘ for 0.5 s:** `KeyCap` hints appear beside every tab, action and quick-app tile, and in the focused widget (verified render: `out/states.png`, Notes page).
- **Edit layout (⌘E, or from Settings):** cards get a dashed outline and an 8 × 24 resize handle on the right edge. Drag to reorder (`listReorder`); resize in whole cells, with a haptic tick at each cell. ↩ finishes. ⌥←/→ moves the focused widget and ⌥⇧←/→ resizes it, all from the keyboard.

### 5.2 Widget widths (cells × 2 rows)

| Widget | Default | Min – max | What changes with width |
|---|---|---|---|
| Media | 4 | 3 – 6 | 3: art 40, no source row, transport only · 4: art 52 + source + AirPlay (`airplayaudio`) · 6: art 100 full height, + shuffle/repeat + mini visualizer + like |
| Calendar | 3 | 2 – 5 | 2: next 2 events, times only · 3: header + 3 rows + Join · 5: two columns (today / tomorrow) |
| Quick Apps | 1 per column | 1 – 4 | each column = 2 tiles of 40 pt in 56-pt cells |
| Shortcuts (Shortcuts.app) | 1 per column | 1 – 4 | same tile anatomy; glyph = the shortcut's SF Symbol, fill = the shortcut's colour |
| Mirror | 2 | 2 – 3 | 3: wider 4:3 preview |
| Notes | 4 | 3 – 8 | ≥ 6: note list sidebar (1 cell) + editor |
| To-dos | 3 | 2 – 5 | 2: no header counter |
| Timer | 2 | 2 – 3 | 3: presets column beside the ring |
| AirDrop | 2 | 1 – 2 | 1: icon-only target |
| Files (as a widget) | 4 | 3 – 8 | the Tray page is always full width |

### 5.3 Widget anatomies

All cards: `card` fill + 1-px `hairline`, radius 18, padding 10. Content is top-leading. One prominent (white) action at most. Every widget is an accessibility container named after itself and a `focusSection()` for keyboard traversal.

**Media (4 × 2, 248 × 120)**
```
┌──────────────────────────────────────────── r 18 ┐
│ ┌──────┐  Midnight Transit          (headline)  ◎ │  ◎ airplayaudio, 12 pt tertiary → output picker menu
│ │ art  │  Low Orbit Choir           (callout 2°)  │
│ │52 r8 │  ♪ Music                   (caption 3°)  │  source app (icon + name)
│ └──────┘                                          │
│ 1:24 ━━━━━━━━━━━━━━──────────────────── −2:13      │  scrubber 3 pt (6 on hover/drag), caption mono, remaining with "−"
│                ◀◀      ( ❚❚ )      ▶▶             │  26 plain · 28 prominent (white) · 26 plain
└───────────────────────────────────────────────────┘
```
States: **nothing playing** shows the last-played app icon + "Play" (prominent) + "Open Music" link, with no greyed transport. Artwork missing → a gradient from the album accent + `music.note`. Accent = album accent (if chosen), used for the scrubber and visualizer only. Keyboard: Space play/pause · ⌘← / ⌘→ previous/next · ← / → seek ±10 s while the scrubber is focused · ⌘L like. VoiceOver: container "Media, Midnight Transit by Low Orbit Choir"; the scrubber is adjustable (±10 s).

**Calendar (3 × 2, 184 × 120)**
```
┌──────────────────────────────── r 18 ┐
│ Wed 14  Oct                    ‹  ›  │  headline + callout 3°; ‹ › change day (← → when focused)
│ ▍ 9:00   Stand-up              (50%) │  past events dimmed to 50 % ("Show today's past events")
│ ▍ 10:30  Design review   [ Join ]    │  calendar colour bar 3 × 14 · caption-mono time · callout title
│   ━━━━━━━━━──────────────────────    │  in progress: 2-pt `live` (green) elapsed bar under the row
│ ▍ 13:00  Lunch with Ana              │  rows 20 pt; scrolls with a bottom fade mask when there are more
└──────────────────────────────────────┘
```
Join appears when a Zoom/Meet/Teams/Webex link is found in the URL, location or notes (prominent white pill). Days behind and ahead: 0–7 each. Empty state: "No events today" + "Calendars: 3 of 5 shown · Choose…". Keyboard: ↑ ↓ events · ↩ open in Calendar · ⌘J join.

**Quick Apps / Shortcuts (1 column × 2 rows)**: 40 × 40 tiles (real app icons via `NSWorkspace.icon(forFile:)`; Shortcuts tiles are rounded-square r 9 in the shortcut's colour with its glyph) centred in 56 × 56 cells. Hover shows a tooltip-style label pill under the Nook edge. Running apps get a 4-pt dot under the tile. ⌥1–⌥9 launch (shown with hold-⌘). Drag an app from Finder or the Dock onto the widget to add it.

**Mirror (2 × 2, frameless, r 18)**: the camera preview *is* the card. Off state: dark gradient + `web.camera` + "Click to preview" (caption). On: live preview, mirrored by default. A hover toolbar (top right, 22-pt circles on black 40 %) holds flip (`flip.horizontal`) and a camera picker menu (all `AVCaptureDevice`s, including external and Continuity cameras). The camera **never starts automatically**; it stops when the Nook closes. macOS shows its own green camera indicator, and Cranny adds nothing that competes with it.

**Notes (4 × 2) + code mode**
```
┌──────────────────────────────────────── r 18 ┐
│ deploy.md ⇕                        </>   +   │  title (rename: double-click or ⌘R) · ⇕ switcher (⌘[ ⌘]) · code toggle · new (⌘N)
│ 1  ## Release                                │  code mode: SF Mono 12, line numbers quaternary,
│ 2  let build = "1.4.2"                       │  syntax palette from tokens (≥ 6.3:1 on card)
│ 3  retry(3) // flaky CI                      │  plain mode: body 13 with the caret in accent
│ 4  [notes](https://…)                        │
└──────────────────────────────────────────────┘
```
The editor is an `NSTextView` (TextKit 2). Highlighting comes from a small tokenizer for Markdown + common languages, auto-detected by fence, file extension or content, and applied as attributes. **Typing effect ("ink settling"):** newly typed characters get a *rendering attribute* (`NSTextLayoutManager.addRenderingAttribute(_:value:for:)`, so the text storage and undo stack aren't touched). Their colour runs from accent to the final colour over 250 ms, driven by `NSView.displayLink(target:selector:)` (macOS 14), touching only the last ≤ 32 ranges. It's off under Reduce Motion. For SwiftUI `Text` (onboarding, peeks), a `TextRenderer` typewriter reveal is used on macOS 15+ (`Effects.swift`). **Type-to-capture:** if the Nook was opened by shortcut and nothing is focused, the first printable key starts the "quick capture" target (Notes or To-dos, configurable).

**To-dos (3 × 2)**: header "To-dos" + "2 left" (caption, tertiary). Rows 18–22 pt: 14-pt `circle` / `checkmark.circle.fill` (accent) + body text. Done items get a strikethrough, turn tertiary and move to the bottom (`listReorder`). A trailing "+ New to-do" row (quaternary placeholder). Keyboard: ↑ ↓ · Space toggle · ↩ new · ⌫ on an empty row deletes · ⌘↑/⌘↓ reorder. The focus ring is accent, 2 pt, concentric (verified render).

**Timer (2 × 2)**: a 4-pt ring (accent; `warning` in the last 10 s) around display digits (24 Rounded, mono, `.numericText(countsDown: true)`) and a caption label. Hover reveals preset chips (5 · 10 · 25 min). Keyboard: type digits then ↩ ("25" ↩ = 25 min, "90s" ↩ = 90 s) · Space pause/resume · ⌫ reset. When it finishes: the ring pulses once with `PhaseAnimator` (static under Reduce Motion), a `levelChange` haptic fires only if the finger is on the trackpad, an optional system sound plays, and a VoiceOver announcement is made. The timer continues as a compact live activity when the Nook closes.

**AirDrop target (2 × 2)**: a dashed `DropZone` (1.5 pt, dash 5/4, `dropTarget`) with `dot.radiowaves.up.forward` + "Drop to AirDrop". When armed (a drag hovers): accent stroke, accent fill at 16 %, scale 1.02, `symbolEffect(.bounce)`. On drop: `NSSharingService(named: .sendViaAirDrop)`.

**Files Tray page (full width)**
```
┌────────────────────────────────────────────────────────────┐ ┌ ─ ─ ─ ─ ─ ┐
│ ┌────┐  ┌────┐  ┌────┐  ┌────┐                             │   ((·))
│ │ QL │  │ QL │  │ QL │  │ ◔  │  tiles 64 × 72: 44-pt       │ │  Drop to   │
│ └────┘  └────┘  └────┘  └────┘  thumbnail r 6 + caption,   │    AirDrop
│ Brief.pdf hero…png notch.heic assets.zip  middle-truncated │ │ (2 cells)  │
│ 2 selected  [⤡ Compress] [⟳ Convert] [▤ Zip] [🔗 Copy paths] … │ └ ─ ─ ─ ─ ─ ┘
└────────────────────────────────────────────────────────────┘
```
Thumbnails come from QuickLookThumbnailing. Selected = `selection` fill + 1.5 pt accent ring. A running pipeline shows a progress ring over the tile. **Pipelines** are contextual to the selection's types: images → Compress, Convert ▸ (PNG, JPEG, HEIC, WebP), Resize ▸ (50 %, 1x/2x); any → Zip, Copy paths, AirDrop, Reveal in Finder, Remove; archives → Unzip. Results are added next to the source with an **Undo** chip (5 s). Keyboard: arrows · ⇧ extends · ⌘A · Space Quick Look · ⌘C copy · ⌘⌫ remove · ⌥⌘⌫ clear all. Dragging files onto the closed notch opens the Tray page with the AirDrop target armed. Retention: keep until removed / clear on quit / clear after 1 day.

### 5.4 Live activities (compact) and peeks

```
 ear╭──── leading slot ────┬════════ hardware cutout ════════┬──── trailing slot ────╮ear
    │  4 ·  [content]  · 6 │   (nothing is ever drawn here)    │ 6 ·  [content]  · 4  │      h = 32, bottom r 13
    ╰──────────────────────┴═══════════════════════════════════┴──────────────────────╯
     content is snug against the camera (6 pt) and balanced: both slots have the same width
```

| Activity | Slots | Leading | Trailing | Peek row (+58 pt) | Shows when |
|---|---|---|---|---|---|
| Now Playing | glyph 40 | artwork 20 × 20 r 5 | 4-bar visualizer 3 × (4–16) pt, accent | title + artist, ◀◀ ❚❚ ▶▶ (24/26 pt), 2-pt progress | playing; peek 2.5 s on track change |
| Meeting | short 62 | calendar-colour dot 7 + `person.2.wave.2.fill` (has link) or `calendar` | "in 5m" (`warning` at ≤ 1 min) / in progress: green dot + "12:04" elapsed | title, time range, attendee count, **Join** (prominent) | N min before (default 5), during the event |
| Timer | short 62 | ring 15 pt, 2.5 stroke | "4:59" mono (`warning` in the last minute) | when done: "Timer done" + Restart / Stop | running |
| Volume / brightness / keyboard light HUD | **wide 96** | symbol 13 pt (variable value for volume; device glyph such as `airpodspro` when audio goes to headphones) | level bar 44 × 4 + value "62" (mono; "–" when muted) | none | on key press; hides after 1.4 s |
| Battery | short 62 | code-drawn battery glyph 24 × 12, exact fill, bolt overlay when charging | "82 %" (green when charging) | time to full/empty, power source | plug/unplug (3 s); ≤ 20 % / ≤ 10 % (warning/danger peek) |
| Bluetooth device | short 62 | device glyph (`airpodspro`, `airpodsmax`, `headphones`, `beats.headphones`, `earbuds`) | battery ring 12 pt + "84 %" (or a ✓ if there's no battery info) | L / R / case batteries | connect (3 s) |

**Priority and concurrency.** One primary activity in the slots; the second-highest becomes the **satellite** (24-pt circle, 6 pt to the right of the compact body, same black, showing the minimal glyph: ring, artwork or dot). Clicking the satellite swaps it with the primary.

Priority order: HUD (transient, pre-empts everything) › alerts (timer done, meeting starting, battery ≤ 10 %) › connect events (Bluetooth, power, 3 s) › meeting in progress › timer running › Now Playing.

**Rules:**
- Only things with a start and an end.
- At most one interactive control in compact (the HIG says so); everything else goes in the peek.
- Hover over compact peeks; click opens the Nook focused on the related widget.
- Swipe up dismisses until the next change.
- In fullscreen spaces and excluded apps, only HUD and alerts appear.
- Inactivity timeout (0 = never) collapses compact to closed but keeps the satellite dot.

### 5.5 HUD replacement

```
 ╭────────── 96 ──────────┬═════════ 185 ═════════┬────────── 96 ──────────╮
 │              🔊 (13 pt)│                        │ ━━━━━━━━━━──────  62    │   h 32 · r 13 · ears 6
 ╰────────────────────────┴════════════════════════┴────────────────────────╯
```
- **Colour:** mono (white) by default; "Tint level with accent" is an option.
- **Steps:** 16 standard; with ⌥⇧ quarter steps, show 16 faint tick marks on the bar.
- **Muted:** `speaker.slash.fill` in tertiary, empty bar, value "–".
- **Brightness and keyboard light:** `sun.max.fill` and `light.max`.
- **Motion:** the level tracks key repeat with the `level` spring (instant under Reduce Motion). When audio is routed to AirPods or headphones, the leading symbol becomes the device glyph.
- **Never two HUDs:** if Accessibility permission (needed for the event tap that suppresses the system HUD) is missing, Cranny's HUD stays off, and Settings ▸ HUD explains how to enable it.

```swift
import SwiftUI

// MARK: - Root: one fixed-size panel, one morphing shape, content clipped to it

public struct NotchRoot<Content: View>: View {
    @Environment(\.crannyTheme) private var theme
    public var geometry: NotchGeometry
    public var notchHeight: CGFloat
    public var openness: Double                 // 0 closed … 1 open — drives shadow, rim, glow
    public var contentVisible: Bool
    public var content: Content
    public init(geometry: NotchGeometry, notchHeight: CGFloat, openness: Double, contentVisible: Bool, @ViewBuilder content: () -> Content) {
        self.geometry = geometry; self.notchHeight = notchHeight; self.openness = openness
        self.contentVisible = contentVisible; self.content = content()
    }

    public var body: some View {
        let shape = NotchShape(geometry)
        let c = theme.colors
        ZStack(alignment: .top) {
            // Translucent option: the notch row stays solid black so the hardware cutout never shows.
            shape.fill(theme.traits.translucentNook && !c.opaque
                       ? AnyShapeStyle(LinearGradient(stops: [.init(color: .black, location: 0),
                                                              .init(color: .black, location: notchHeight / max(geometry.bodyHeight, 1)),
                                                              .init(color: c.shellTranslucent, location: min(1, (notchHeight + 12) / max(geometry.bodyHeight, 1)))],
                                                      startPoint: .top, endPoint: .bottom))
                       : AnyShapeStyle(c.shell))
                .crannyShadow(Elevation.panel, amount: openness)     // 0 while closed/compact/peek
            content
                .modifier(NookContentTransition(visible: contentVisible, reduceMotion: theme.traits.reduceMotion))
                .frame(width: geometry.bodyWidth, height: geometry.bodyHeight + geometry.topInset, alignment: .top)
                .clipShape(shape)
            shape.stroke(c.hairline.opacity(openness), lineWidth: 1)  // rim only when open (separates from dark windows)
                .allowsHitTesting(false)
        }
        .contentShape(shape)     // clicks outside the shape fall through (window also toggles ignoresMouseEvents)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Cranny"))
    }
}

// MARK: - Compact row layout: leading slot | hardware cutout | trailing slot

/// Live-activity content sits *snug against the cutout* (6 pt gap), never under it.
public struct CompactRow<Leading: View, Trailing: View>: View {
    var slot: CGFloat; var notchWidth: CGFloat; var height: CGFloat
    var leading: Leading; var trailing: Trailing
    public init(slot: CGFloat, notchWidth: CGFloat, height: CGFloat,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.slot = slot; self.notchWidth = notchWidth; self.height = height
        self.leading = leading(); self.trailing = trailing()
    }
    public static var innerGap: CGFloat { 6 }
    public var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: slot - Self.innerGap - 4, alignment: .trailing).padding(.leading, 4)
            Color.clear.frame(width: notchWidth + 2 * Self.innerGap)     // the camera — never put content here
            trailing.frame(width: slot - Self.innerGap - 4, alignment: .leading).padding(.trailing, 4)
        }
        .frame(height: height)
    }
}

// MARK: - Now Playing (compact)

public struct NowPlayingCompact: View {
    @Environment(\.crannyTheme) private var theme
    var artwork: AnyView; var title: String; var artist: String
    var levels: [CGFloat]; var playing: Bool; var notchWidth: CGFloat; var h: CGFloat
    public var body: some View {
        CompactRow(slot: SlotWidth.glyph(h), notchWidth: notchWidth, height: h) {
            artwork.frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: Radius.artworkCompact, style: .continuous))
        } trailing: {
            MiniVisualizer(levels: levels, color: theme.accent, playing: playing && !theme.traits.reduceMotion)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now playing: \(title) by \(artist)"))
        .accessibilityValue(playing ? Text("Playing") : Text("Paused"))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: Text("Play or pause")) {}
        .accessibilityAction(named: Text("Next track")) {}
        .accessibilityAction(named: Text("Previous track")) {}
    }
}

/// Peek row under the notch row (hover on compact, or on track change for 2.5 s).
public struct NowPlayingPeek: View {
    @Environment(\.crannyTheme) private var theme
    var title: String; var artist: String; var progress: Double
    public var body: some View {
        let c = theme.colors
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).crannyText(.headline).lineLimit(1)
                    Text(artist).crannyText(.callout).foregroundStyle(c.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s)
                Button {} label: { Image(systemName: "backward.fill") }.buttonStyle(CrannyIconButtonStyle(role: .plain, size: 24))
                Button {} label: { Image(systemName: "pause.fill") }.buttonStyle(CrannyIconButtonStyle(role: .prominent, size: 26))
                Button {} label: { Image(systemName: "forward.fill") }.buttonStyle(CrannyIconButtonStyle(role: .plain, size: 24))
            }
            LevelBar(value: progress, color: theme.accent, thickness: 2)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .foregroundStyle(c.textPrimary)
    }
}

// MARK: - Meeting / calendar (compact)

public struct MeetingCompact: View {
    @Environment(\.crannyTheme) private var theme
    var calendarColor: Color; var minutesUntil: Int?; var elapsed: String?; var hasLink: Bool
    var notchWidth: CGFloat; var h: CGFloat
    public var body: some View {
        let c = theme.colors
        CompactRow(slot: SlotWidth.short(h), notchWidth: notchWidth, height: h) {
            HStack(spacing: 5) {
                Circle().fill(calendarColor).frame(width: 7, height: 7)
                Image(systemName: hasLink ? "person.2.wave.2.fill" : "calendar").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }
        } trailing: {
            if let m = minutesUntil {
                Text("in \(m)m").crannyText(.compact).foregroundStyle(m <= 1 ? c.warning : c.textPrimary)
            } else if let e = elapsed {
                HStack(spacing: 4) {
                    Circle().fill(c.live).frame(width: 6, height: 6)
                    Text(e).crannyText(.compact)
                }
            }
        }
        .foregroundStyle(c.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(minutesUntil.map { "Meeting in \($0) minutes" } ?? "Meeting in progress, \(elapsed ?? "")"))
    }
}

// MARK: - Timer (compact)

public struct TimerCompact: View {
    @Environment(\.crannyTheme) private var theme
    var remaining: Int; var total: Int; var notchWidth: CGFloat; var h: CGFloat
    public var body: some View {
        let c = theme.colors
        let urgent = remaining <= 60
        CompactRow(slot: SlotWidth.short(h), notchWidth: notchWidth, height: h) {
            ProgressRing(progress: Double(remaining) / Double(max(total, 1)), color: urgent ? c.warning : theme.accent,
                         lineWidth: StrokeWidth.ringCompact)
                .frame(width: 15, height: 15)
        } trailing: {
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                .crannyText(.compact)
                .foregroundStyle(urgent ? c.warning : c.textPrimary)
                .contentTransition(.numericText(countsDown: true))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer"))
        .accessibilityValue(Text("\(remaining / 60) minutes \(remaining % 60) seconds remaining"))
    }
}

// MARK: - Volume / brightness HUD (compact, wide slots)

public struct LevelHUDCompact: View {
    @Environment(\.crannyTheme) private var theme
    public enum Kind { case volume, brightness, keyboard }
    var kind: Kind; var level: Double; var muted: Bool; var colored: Bool
    var notchWidth: CGFloat; var h: CGFloat
    var symbol: String {
        switch kind {
        case .volume: muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: "sun.max.fill"
        case .keyboard: "light.max"
        }
    }
    public var body: some View {
        let c = theme.colors
        CompactRow(slot: SlotWidth.wide(h), notchWidth: notchWidth, height: h) {
            Image(systemName: symbol, variableValue: kind == .volume ? level : nil)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted ? c.textTertiary : c.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
        } trailing: {
            HStack(spacing: 6) {
                LevelBar(value: muted ? 0 : level, color: colored ? theme.accent : c.textPrimary)
                    .frame(width: 44)
                Text(muted ? "–" : "\(Int((level * 100).rounded()))")
                    .crannyText(.compact)
                    .contentTransition(.numericText(value: level))
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .animation(Motion.level.animation(theme.traits.motion, reduceMotion: theme.traits.reduceMotion), value: level)
        .foregroundStyle(c.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .volume ? Text("Volume") : Text("Brightness"))
        .accessibilityValue(muted ? Text("Muted") : Text("\(Int(level * 100)) percent"))
    }
}

// MARK: - Battery / charging (compact)

/// Code-drawn battery glyph so the fill is exact and can be tinted (SF battery symbols are stepped).
public struct BatteryGlyph: View {
    var percent: Int; var tint: Color; var charging: Bool
    @Environment(\.crannyTheme) private var theme
    public var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).strokeBorder(theme.colors.textTertiary, lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint)
                    .frame(width: max(2, 18 * CGFloat(percent) / 100)).padding(2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(theme.colors.textTertiary).frame(width: 1.5, height: 4)
        }
    }
}

public struct BatteryCompact: View {
    @Environment(\.crannyTheme) private var theme
    var percent: Int; var charging: Bool; var notchWidth: CGFloat; var h: CGFloat
    public var body: some View {
        let c = theme.colors
        let tint: Color = charging ? c.success : percent <= 10 ? c.danger : percent <= 20 ? c.warning : c.textPrimary
        CompactRow(slot: SlotWidth.short(h), notchWidth: notchWidth, height: h) {
            BatteryGlyph(percent: percent, tint: tint, charging: charging)
        } trailing: {
            Text("\(percent)%").crannyText(.compact).foregroundStyle(charging ? c.success : c.textPrimary)
        }
        .foregroundStyle(c.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(charging ? "Charging" : "Battery"))
        .accessibilityValue(Text("\(percent) percent"))
    }
}

// MARK: - Bluetooth device (compact)

public struct BluetoothCompact: View {
    @Environment(\.crannyTheme) private var theme
    var symbol: String; var name: String; var percent: Int?; var notchWidth: CGFloat; var h: CGFloat
    public var body: some View {
        let c = theme.colors
        CompactRow(slot: SlotWidth.short(h), notchWidth: notchWidth, height: h) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
        } trailing: {
            if let p = percent {
                HStack(spacing: 4) {
                    ProgressRing(progress: Double(p) / 100, color: p <= 20 ? c.warning : c.success, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    Text("\(p)%").crannyText(.compact)
                }
            } else {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(c.success)
            }
        }
        .foregroundStyle(c.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) connected"))
        .accessibilityValue(percent.map { Text("Battery \($0) percent") } ?? Text(""))
    }
}
```

### 5.6 Ambient effects (procedural, no Metal files, no videos)

- **Aurora:** a 3 × 3 `MeshGradient` (macOS 15+). The top row is pure black so it merges with the notch row; colour comes from [accent, accent rotated, neutral]. The mesh drifts slowly (< 0.2 Hz). On macOS 14 the fallback is a `Canvas` of blurred ellipses. A `TimelineView(.animation(minimumInterval: 1/30, paused:))` drives it and is **paused unless open**. Intensity is 0–0.5. It's off under Reduce Transparency and Low Power Mode, and frozen under Reduce Motion. Verified render: `out/aurora.png`.
- **Album glow:** a radial wash from the artwork side, inside the shape only.
- **Visualizer:** 4 bars, ≤ 20 fps. By default it's driven by a seeded pseudo-spectrum tied to the playback state, so no permission is needed. A "Real spectrum" option would need system-audio capture (a screen-recording-class permission), so it's opt-in and labelled as such.
- **Typing effects:** see Notes in §5.3.
- **Runtime Metal** (`MTLDevice.makeLibrary(source:)`) is held back as an advanced, opt-in option; nothing in this direction depends on it.

```swift
import SwiftUI

// MARK: - Ambient effect: "Aurora" (procedural, no Metal files, no videos)

/// Slow aurora behind the open Nook. MeshGradient (macOS 15+) with drifting control points,
/// Canvas + blurred ellipses on macOS 14. The TimelineView is PAUSED unless the Nook is open,
/// effects are enabled, Reduce Motion is off and Low Power Mode is off → zero idle cost.
public struct AuroraBackground: View {
    public var colors: [Color]          // [accent, accent-rotated, neutral]
    public var active: Bool
    public var intensity: Double = 0.30 // Glow.ambientRange
    public var fixedTime: Double? = nil // for previews / Reduce Motion (static frame)

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { tl in
            let t = fixedTime ?? tl.date.timeIntervalSinceReferenceDate
            Group {
                if #available(macOS 15.0, *) { mesh(t) } else { canvas(t) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @available(macOS 15.0, *)
    private func mesh(_ t: Double) -> some View {
        let c = colors + [Color.black, Color.black, Color.black]
        func drift(_ x: Float, _ y: Float, _ p: Double) -> SIMD2<Float> {
            [x + Float(0.06 * sin(t * 0.17 + p)), y + Float(0.05 * cos(t * 0.13 + p * 1.7))]
        }
        // 3×3 mesh: top row is pure black (merges with the notch row), colour lives low.
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.55], drift(0.5, 0.6, 1.1), [1, 0.5],
            [0, 1], drift(0.45, 1, 2.3), [1, 1],
        ]
        let k = intensity
        let colorsMesh: [Color] = [
            .black, .black, .black,
            c[0].opacity(k * 0.8), c[2].opacity(k * 0.5), c[1].opacity(k * 0.8),
            c[1].opacity(k), c[0].opacity(k * 1.2), c[2].opacity(k * 0.7),
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colorsMesh, smoothsColors: true)
    }

    private func canvas(_ t: Double) -> some View {
        Canvas(opaque: false, rendersAsynchronously: true) { ctx, size in
            ctx.addFilter(.blur(radius: min(size.height, 120) * 0.35))
            for (i, color) in colors.prefix(3).enumerated() {
                let p = Double(i) * 2.1
                let x = size.width * (0.5 + 0.38 * sin(t * 0.11 + p))
                let y = size.height * (0.80 + 0.15 * cos(t * 0.07 + p * 1.3))
                let r = size.height * (0.55 + 0.10 * sin(t * 0.05 + p))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 1.6, y: y - r * 0.6, width: r * 3.2, height: r * 1.2)),
                         with: .color(color.opacity(intensity)))
            }
        }
    }
}

// MARK: - Compact visualizer (notch row)

/// 4 bars, 3 pt wide, 2 pt gap, 4…16 pt tall. Driven by real levels when available, else a
/// seeded pseudo-spectrum tied to playback; ≤ 20 fps. Static bars under Reduce Motion.
public struct MiniVisualizer: View {
    public var levels: [CGFloat]        // 0…1, count 4
    public var color: Color
    public var playing: Bool
    public var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 3, height: playing ? 4 + 12 * (i < levels.count ? levels[i] : 0) : 3)
            }
        }
        .frame(width: 18, height: 16)
        .animation(.spring(duration: 0.14, bounce: 0), value: levels)
        .accessibilityHidden(true)      // the activity container carries the label/value
    }
}

// MARK: - Album-art glow (inside the shape only)

public struct ArtworkGlow: View {
    public var color: Color
    public var amount: Double           // follows openness 0…1
    public var body: some View {
        RadialGradient(colors: [color.opacity(Glow.artworkOpacity * amount), .clear],
                       center: UnitPoint(x: 0.18, y: 0.62), startRadius: 0, endRadius: Glow.artworkRadius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Typing effect for SwiftUI Text (onboarding, peeks): soft per-glyph reveal (macOS 15+)

@available(macOS 15.0, *)
public struct TypewriterRenderer: TextRenderer {
    public var revealed: Double             // number of glyphs revealed (animatable)
    public var animatableData: Double { get { revealed } set { revealed = newValue } }
    public func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var index = 0.0
        for line in layout { for run in line { for glyph in run {
            let a = max(0, min(1, revealed - index))       // 1-glyph soft edge
            var c = ctx
            c.opacity = a
            c.translateBy(x: 0, y: (1 - a) * 2)            // 2-pt settle
            c.draw(glyph)
            index += 1
        } } }
    }
}

extension View {
    /// Applies the typewriter reveal on macOS 15+, no-op on 14 or with Reduce Motion.
    @ViewBuilder public func typewriter(_ revealed: Double, enabled: Bool) -> some View {
        if #available(macOS 15.0, *), enabled { self.textRenderer(TypewriterRenderer(revealed: revealed)) } else { self }
    }
}
```

---

## 6. Settings window, onboarding and the tutorial, menu bar extra

### 6.1 Settings window

**Structure.**
- `Settings { SettingsRoot() }` with `NavigationSplitView`. Default size 840 × 600, minimum 780 × 560. The sidebar is 190–260 pt wide, with `.searchable(placement: .sidebar)`.
- Sidebar groups, in the order *configure → where it shows → what it shows → system*:
  - (General · Appearance · Keyboard & Shortcuts)
  - **Notch** (Nook & Widgets · Live Activities · HUD · Gestures)
  - **Features** (Media · Calendar · Tray)
  - (Permissions · About)
- "Shortcuts" from the brief became **Keyboard & Shortcuts**. It covers global and in-Nook key bindings plus which Shortcuts.app shortcuts appear in the widget.
- **Permissions** is a dedicated pane, which answers the "repeated prompts" complaint.

**Live preview stage (the signature element).**
- A 158-pt band at the top of every pane renders the **real notch views**, fed by the *draft* settings at 0.62 scale.
- Behind it are the user's own wallpaper (`NSWorkspace.shared.desktopImageURL(for:)`) and a fake menu bar.
- A segmented control picks Closed · Compact · Peek · Open · HUD. It auto-selects the state that's relevant to the pane (`SettingsPane.previewState`).
- **"Show on Notch"** plays the preview on the real notch for 5 s.
- Every slider and picker animates the preview with the real motion tokens, so the effect is visible before it's committed.
- Verified render: `out/settings.png`.

**Controls.**
- Native grouped `Form`, `LabeledContent`.
- Sliders always show their value (mono digits) with units: "220 ms", "±0 pt".
- Pickers for exclusive choices; switches for on/off.
- A custom **shortcut recorder**: a capsule showing ⌃⌥Space; click to record, Esc cancels, ⌫ clears, and conflicts with system shortcuts are flagged inline.
- A non-default value shows a 6-pt accent dot before its label. Every row has a context menu with **Reset to Default**; every section footer has **Reset Section**. General ▸ **Reset All Settings…** asks for confirmation and offers an undo for 10 s.

**Search.**
- Matches pane names, row labels and keywords (e.g. "dock" → Quick Apps, "volume" → HUD, "external monitor" → Displays).
- Selecting a result opens the pane, scrolls to the row and highlights it with an accent wash that fades over 1 s.

**Pane contents.**

| Pane | Key controls |
|---|---|
| General | Launch at login (`SMAppService.mainApp`) · Open the Nook: On hover / On click / Shortcut only · Hover delay (100–800 ms) · Hold ⌥ to pass over · Close when the pointer leaves (+ grace) · Inactivity timeout · Displays (list + style per display: Island / Attached / Off) · Hide handle when idle · Demo mode (+ redact calendar titles) · Check for updates automatically (GitHub Releases) · Reset All Settings… |
| Appearance | **Notch fit** (width ±20 pt, radius ±3 pt, with a 2× magnified live outline on the real notch) · Density · **Text size** (Small / Standard / Large / Extra Large) · Button shape (Capsule / Rounded) · Accent (System / Album art / 8 swatches / Mono) · Translucent background · Dividers between widgets · Glass controls (macOS 26+) · Ambient effect (Off / Glow / Aurora) + intensity · Motion (Calm / Lively / Instant) · Handle opacity (no-notch displays) |
| Keyboard & Shortcuts | Global shortcuts with recorders: Open Nook (⌃⌥Space, on), New note, Start timer, Show Tray, Toggle pin (off by default) · in-Nook reference table (same data as the hold-⌘ overlay) · Shortcuts.app: pick shortcuts for the widget |
| Nook & Widgets | Pages list (add, rename, reorder) · **layout editor on the preview stage** (drag to reorder, drag the right edge to resize in cells, snapping with haptic) · widget library ("+" with descriptions) · per-widget options (popover) |
| Live Activities | Per-activity toggles in a **draggable priority list** · peek on change · peek duration · minutes before meetings · satellite second activity · swipe up to dismiss · inactivity timeout · fullscreen behaviour (Hide / Alerts only / Show) · **Excluded apps** |
| HUD | Enable (requires Accessibility; explains why) · volume / brightness / keyboard light · tint with accent · show headphone glyph · duration (0.8–3 s) |
| Gestures | Pull down to open / push up to close · two-finger swipe for tracks + invert · sensitivity · **Haptic feedback** |
| Media | Source priority (Music, Spotify, browsers…) · album accent · visualizer (Off / Calm / Real spectrum (needs permission)) · peek on track change |
| Calendar | Calendars to include · days behind / ahead (0–7) · show today's past events · join-link providers · show while in an event + elapsed time |
| Tray | Retention · default pipeline settings (JPEG quality, max dimension, zip naming) · dropping on the notch opens the Tray · show AirDrop target |
| Permissions | Calendar · Camera · Accessibility · Automation (per media app) · Bluetooth: a status pill (Granted / Not yet / Denied), a one-line why, Grant… / Open System Settings |
| About | App icon (`CrannyIconArt`), version, Check for Updates, release notes, GitHub, MIT licence, acknowledgements, **Show Tutorial** |

### 6.2 Onboarding (first launch) and the interactive tutorial

**Window.** 640 × 460, titlebar hidden, not resizable, centred. Return = Continue, ⌘[ = Back, Esc = "Skip setup?" (confirm). The top half is the **live preview stage** and the bottom half is copy and controls. Verified render: `out/onboarding.png`.

| Step | Content | Interaction |
|---|---|---|
| 1 Meet Cranny | The preview cycles closed → compact (music) → open with the real springs. Headline (title2) and one sentence. | Continue |
| 2 Open it your way | Choose Hover (with sensitivity), Click or Shortcut Only. A **coach mark** (a 2-pt accent capsule around the real notch plus a material label: "Hover here, or press ⌃⌥Space") | Detects the actual open on the real notch. Each method gets ✓ (green) when done; Continue is enabled after one. |
| 3 Gestures | Shown only if a trackpad is present. A practice notch in the window. | Pull-down / swipe practice with live rubber-band feedback and the haptic |
| 4 Starting layout | 3 preset cards: **Listener** (Media 4 · Calendar 3 · Apps 1 · Mirror 2), **Maker** (Notes 4 · To-dos 3 · Timer 2 · Shortcuts 1), **Meetings** (Calendar 4 · Mirror 2 · Timer 2 · Apps 2) | Pick one → the preview updates |
| 5 Permissions, only when needed | A list of features that need permission, all **off**. Turning one on triggers its system prompt right then. | Optional; "Later" is fine |
| 6 You're set | Keyboard cheat sheet (the 8 most useful keys) · Launch at login (on) · Check for updates (on) | Done → the Nook opens once to show the result |

**Interactive tutorial** (Menu ▸ Show Tutorial, or About). It runs *in the notch itself*. A ghost peek row shows one instruction plus a `KeyCap`. Steps: open (hover or ⌃⌥Space) → ⌘2 Tray → drag any file onto the notch → swipe sideways on media → hold ⌘ → Esc to close. Each step detects completion (✓ + `alignment` haptic) and shows progress ("3 of 6", micro). Esc twice quits. All copy is original and localised (English and Russian).

### 6.3 Menu bar extra

- **Optional.** `MenuBarExtra(isInserted:)`, on by default. If it's hidden, launching the app again opens Settings.
- **Icon:** a code-drawn template image 18 × 12 pt: an outlined rounded screen rectangle with a filled `NotchShape` at the top centre. Fallback: `capsule.tophalf.filled`. Accessibility label "Cranny".
- **Menu** (`.menuBarExtraStyle(.menu)`): Open Nook ⌃⌥Space · Keep Open (toggle) · Pause Live Activities ▸ (1 Hour / Until Tomorrow / Until I Resume) · Demo Mode (toggle) · — · Settings… ⌘, · Check for Updates… · Show Tutorial · — · Quit Cranny ⌘Q.
- The app is an agent (`LSUIElement = YES`): no Dock icon.

```swift
import SwiftUI
import AppKit

// MARK: - Settings panes

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, keyboard
    case nook, activities, hud, gestures
    case media, calendar, tray
    case permissions, about
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: "General"; case .appearance: "Appearance"; case .keyboard: "Keyboard & Shortcuts"
        case .nook: "Nook & Widgets"; case .activities: "Live Activities"; case .hud: "HUD"; case .gestures: "Gestures"
        case .media: "Media"; case .calendar: "Calendar"; case .tray: "Tray"
        case .permissions: "Permissions"; case .about: "About"
        }
    }
    public var symbol: String {
        switch self {
        case .general: "gearshape"; case .appearance: "paintpalette"; case .keyboard: "command"
        case .nook: "square.grid.2x2"; case .activities: "capsule.tophalf.filled"; case .hud: "speaker.wave.2"
        case .gestures: "hand.draw"; case .media: "music.note"; case .calendar: "calendar"; case .tray: "tray.full"
        case .permissions: "hand.raised"; case .about: "info.circle"
        }
    }
    /// Sidebar groups: what you configure → where it shows → what it shows → system.
    public static let groups: [(String?, [SettingsPane])] = [
        (nil, [.general, .appearance, .keyboard]),
        ("Notch", [.nook, .activities, .hud, .gestures]),
        ("Features", [.media, .calendar, .tray]),
        (nil, [.permissions, .about]),
    ]
    /// Which preview state the live stage shows for this pane.
    public var previewState: PreviewStage.Mode {
        switch self {
        case .activities, .media, .calendar: .compact
        case .hud: .hud
        case .general, .appearance, .nook, .tray, .keyboard, .gestures: .open
        case .permissions, .about: .closed
        }
    }
}

// MARK: - Live preview stage: the REAL notch views, fed by draft settings, on a fake desktop

public struct PreviewStage: View {
    public enum Mode: String, CaseIterable, Identifiable { case closed, compact, peek, open, hud; public var id: String { rawValue } }
    var mode: Mode
    var theme: CrannyTheme
    var hw = NotchHardware(hasNotch: true, notchWidth: 185, notchHeight: 32, screenWidth: 1512, menuBarHeight: 32)
    public var body: some View {
        let m = theme.nook
        let open = NookLayoutSize.size(cells: 10, hw: hw, nook: m)
        let state: NotchState = switch mode {
        case .closed: .closed
        case .compact: .compact(slot: SlotWidth.glyph(32))
        case .peek: .peek(width: 0, extra: 52)
        case .open: .open(width: open.width, height: open.height)
        case .hud: .compact(slot: SlotWidth.wide(32))
        }
        let g = NotchGeometry.make(state, hw: hw, nook: m)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.30, green: 0.36, blue: 0.52), Color(red: 0.62, green: 0.48, blue: 0.50)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.white.opacity(0.22)).frame(height: 32)        // menu bar
            NotchRoot(geometry: g, notchHeight: 32, openness: mode == .open ? 1 : 0, contentVisible: true) {
                switch mode {
                case .open: OpenNook(hw: hw, size: CGSize(width: g.bodyWidth, height: g.bodyHeight))
                case .compact: NowPlayingCompact(artwork: AnyView(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)),
                                                 title: "Midnight Transit", artist: "Low Orbit Choir", levels: [0.4, 0.9, 0.6, 0.3],
                                                 playing: true, notchWidth: 185, h: 32)
                case .hud: LevelHUDCompact(kind: .volume, level: 0.62, muted: false, colored: true, notchWidth: 185, h: 32)
                default: EmptyView()
                }
            }
            .frame(width: 900, height: 240)
            .scaleEffect(0.62, anchor: .top)
            .frame(width: 900 * 0.62, height: 240 * 0.62, alignment: .top)   // layout size == visual size
        }
        .frame(height: 158)
        .clipped()
        .crannyThemeRoot(theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Live preview of the notch, \(mode.rawValue) state"))
    }
}

// MARK: - Settings window

public struct SettingsRoot: View {
    @State private var pane: SettingsPane? = .nook
    @State private var query = ""
    @State private var stage: PreviewStage.Mode = .open
    var theme = CrannyTheme.standard
    public var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.1) { p in Label(p.title, systemImage: p.symbol).tag(p) }
                    } header: { if let h = group.0 { Text(h) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .searchable(text: $query, placement: .sidebar, prompt: Text("Search settings"))
        } detail: {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    PreviewStage(mode: stage, theme: theme)
                    HStack {
                        Picker("Preview state", selection: $stage) {
                            ForEach(PreviewStage.Mode.allCases) { Text($0 == .hud ? "HUD" : $0.rawValue.capitalized).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        Spacer()
                        Button("Show on Notch") {}.help("Plays this preview on the real notch for 5 seconds")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .background(.background.secondary)
                Divider()
                Form {
                    Section("Layout") {
                        LabeledContent("Widgets") {
                            Text("Media 4 · Calendar 3 · Apps 1 · Mirror 2 = 10 cells").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Picker("Density", selection: .constant(CrannyTraits.Density.regular)) {
                            ForEach(CrannyTraits.Density.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Toggle("Dividers instead of cards", isOn: .constant(false))
                    }
                    Section("Opening") {
                        Picker("Open the Nook", selection: .constant(0)) {
                            Text("On hover").tag(0); Text("On click").tag(1); Text("Shortcut only").tag(2)
                        }
                        LabeledContent("Hover delay") {
                            HStack {
                                Slider(value: .constant(0.22), in: 0.05...0.8)
                                Text("220 ms").monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                            }
                        }
                        Toggle("Hold ⌥ to pass over without opening", isOn: .constant(true))
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle(pane?.title ?? "")
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}

// MARK: - Menu bar extra (agent app: LSUIElement = YES)

public struct CrannyMenuContent: View {
    public var body: some View {
        Button("Open Nook") {}.keyboardShortcut(.space, modifiers: [.control, .option])
        Toggle("Keep Open", isOn: .constant(false))
        Menu("Pause Live Activities") { Button("For 1 Hour") {}; Button("Until Tomorrow") {}; Button("Until I Resume") {} }
        Toggle("Demo Mode", isOn: .constant(false))
        Divider()
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Button("Check for Updates…") {}
        Button("Show Tutorial") {}
        Divider()
        Button("Quit Cranny") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

public struct CrannyScenes: Scene {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    public var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            CrannyMenuContent()
        } label: {
            Image(systemName: "capsule.tophalf.filled")     // replaced by a code-drawn template NSImage
                .accessibilityLabel(Text("Cranny"))
        }
        .menuBarExtraStyle(.menu)
        Settings { SettingsRoot() }
    }
}

// MARK: - Onboarding

public struct OnboardingStep: Identifiable, Sendable {
    public let id: Int; public let title: String; public let body: String; public let symbol: String
}

public struct OnboardingView: View {
    var step: Int = 1
    let steps: [OnboardingStep] = [
        .init(id: 0, title: "Meet Cranny", body: "Your notch becomes a calm little hub.", symbol: "sparkles"),
        .init(id: 1, title: "Open it your way", body: "Hover, click, or press a shortcut. Try it now.", symbol: "cursorarrow.motionlines"),
        .init(id: 2, title: "Gestures", body: "Pull down to open, swipe sideways to skip tracks.", symbol: "hand.draw"),
        .init(id: 3, title: "Pick a starting layout", body: "You can rearrange everything later.", symbol: "square.grid.2x2"),
        .init(id: 4, title: "Permissions, only when needed", body: "Each one is asked for when you turn its feature on.", symbol: "hand.raised"),
        .init(id: 5, title: "You're set", body: "Hold ⌘ in the Nook to see every shortcut.", symbol: "keyboard"),
    ]
    public var body: some View {
        let s = steps[step]
        VStack(spacing: 0) {
            PreviewStage(mode: step == 1 ? .closed : .open, theme: .standard)
                .overlay(alignment: .top) {
                    if step == 1 {   // coach mark: calm pulse ring around the notch
                        Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(width: 136, height: 30).offset(y: 2)
                            .overlay(alignment: .bottom) {
                                Text("Hover here, or press ⌃⌥Space").font(.callout.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.regularMaterial, in: Capsule()).fixedSize().offset(y: 36)
                            }
                    }
                }
            VStack(alignment: .leading, spacing: 10) {
                Label(s.title, systemImage: s.symbol).font(.title2.weight(.semibold))
                Text(s.body).font(.body).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Opened with hover").font(.callout)
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                    Text("Opened with the shortcut").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                Spacer()
                HStack {
                    HStack(spacing: 6) { ForEach(steps) { st in Circle().fill(st.id == step ? Color.primary : Color.secondary.opacity(0.35)).frame(width: 6, height: 6) } }
                        .accessibilityLabel(Text("Step \(step + 1) of \(steps.count)"))
                    Spacer()
                    Button("Back") {}.keyboardShortcut("[", modifiers: .command)
                    Button("Continue") {}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 640, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
```

---

## 7. Iconography, haptics, sounds, app icon

### 7.1 SF Symbols (all verified to exist at ≤ macOS 14 in `name_availability.plist`)

| Role | Symbol(s) |
|---|---|
| Pages / actions | `square.grid.2x2` (Nook), `tray.full` (Tray), `note.text` (Notes page), `magnifyingglass` (palette), `pin` / `pin.fill` (keep open), `gearshape`, `plus`, `ellipsis`, `xmark`, `chevron.left` / `chevron.right`, `chevron.up.chevron.down` (switchers) |
| Media | `play.fill`, `pause.fill`, `backward.fill`, `forward.fill`, `shuffle`, `repeat`, `repeat.1`, `heart` / `heart.fill`, `music.note`, `airplayaudio` (output picker, AirPlay only), `waveform` |
| Calendar | `calendar`, `person.2.wave.2.fill` (meeting with link), `clock` |
| Mirror | `web.camera`, `flip.horizontal`, `camera.fill` (picker) |
| Notes / to-dos | `chevron.left.forwardslash.chevron.right` (code mode), `text.alignleft`, `pencil`, `circle`, `checkmark.circle.fill`, `checklist`, `line.3.horizontal` (drag handle) |
| Timer | `timer`, `arrow.counterclockwise`, `bell`, `bell.slash` |
| Tray / pipelines | `doc`, `photo`, `doc.zipper`, `archivebox`, `arrow.down.right.and.arrow.up.left` (compress), `arrow.triangle.2.circlepath` (convert), `arrow.up.left.and.arrow.down.right` (resize), `link` / `doc.on.doc` (copy path), `square.and.arrow.up` (share), `folder` (reveal), `eye` (Quick Look), `trash`, `tray.and.arrow.down` (drop) |
| AirDrop target | `dot.radiowaves.up.forward` (there is **no** `airdrop` symbol) |
| Activities / HUD | `speaker.wave.3.fill` (variable value), `speaker.slash.fill`, `sun.max.fill`, `light.max`, `bolt.fill`, `airpodspro`, `airpodsmax`, `airpods` (AirPods only), `headphones`, `beats.headphones` (Beats only), `earbuds` |
| Settings sidebar | `gearshape`, `paintpalette`, `command`, `square.grid.2x2`, `capsule.tophalf.filled`, `speaker.wave.2`, `hand.draw`, `music.note`, `calendar`, `tray.full`, `hand.raised`, `info.circle` |
| Onboarding | `sparkles`, `cursorarrow.motionlines`, `hand.draw`, `keyboard`, `checkmark.circle.fill` |

**Restrictions** (from `symbol_restrictions.strings`):
- `video` and `video.fill` may only refer to **FaceTime**, so Cranny does *not* use them for meetings or the camera.
- `airplay.audio` is macOS 15+ and AirPlay-only; use `airplayaudio`.
- `safari` and `message.fill` are app-specific; Quick Apps shows real app icons instead.

**Style.**
- Monochrome rendering, weight semibold at 11–13 pt inside the Nook. Transport uses 13 (secondary) and 15 (prominent).
- Effects: `.contentTransition(.symbolEffect(.replace))` for toggles, `.symbolEffect(.bounce)` for armed drop targets, `variableValue` for volume. No looping symbol effects.

### 7.2 Haptics (`NSHapticFeedbackManager`; actuates only while a finger is on a Force Touch trackpad)

| Event | Pattern |
|---|---|
| Gesture threshold crossed (pull, push, track swipe) · layout edit snaps to a cell · tutorial step done | `.alignment` |
| Drop accepted (Tray, AirDrop) · HUD reaches 0 or 100 · timer done | `.levelChange` |
| Nook opened by a gesture commit | `.generic` |
| **Hover, peek, live-activity arrival** | **none, ever** (fixes the "click sound when hovering" complaint) |

There's one switch (Gestures ▸ Haptic feedback), independent of the hover settings.

### 7.3 Sounds

**None by default.** Opt-in only: "Timer finished" (a choice of **system** alert sounds via `NSSound(named:)`, e.g. "Glass"; Cranny ships no audio files) and "Pipeline finished" (off). Sounds are muted in Demo mode.

### 7.4 App icon: "Light from a cranny" (original)

**Concept.** A graphite squircle. At the top centre is Cranny's own notch silhouette (body + concave ears, built the same way as `NotchShape`). From it a cool fan of light (mint → blue → violet) spills down onto **three glass cells**, the Nook's widgets; the middle cell is brightest. It reads as "a small opening where useful things live" and is distinct from any existing product mark.

**Icon Composer (macOS 26+): `Cranny.icon`.** Verified: `actool` compiles it and also emits `Cranny.icns` for macOS 14/15.
- Background fill: linear gradient, Display P3, (0.17, 0.18, 0.22) → (0.05, 0.05, 0.07), top → bottom.
- Group **Notch** (front): `notch.png`, glass **off**, no shadow, no translucency, no specular. It stays a crisp black cut so the silhouette survives tinted and clear modes.
- Group **Cells**: `cells.png`, glass **on**, specular on, translucency 0.4, neutral shadow 0.5, lighting individual. This is where Liquid Glass shines.
- Group **Light** (back): `light.png`, glass off, blend mode `plus-lighter`.
- Appearance variants: Dark uses a deeper background (0.04 → 0.02); Tinted lets the system tint the cells and light with the notch kept black; Clear keeps the cells glass and light at 60 %.

```json
{
  "fill" : {
    "linear-gradient" : [
      "display-p3:0.17000,0.18000,0.22000,1.00000",
      "display-p3:0.05000,0.05000,0.07000,1.00000"
    ],
    "orientation" : { "start" : { "x" : 0.5, "y" : 0 }, "stop" : { "x" : 0.5, "y" : 1 } }
  },
  "groups" : [
    {
      "name" : "Notch",
      "layers" : [ { "name" : "notch", "image-name" : "notch.png", "glass" : false } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "translucency" : { "enabled" : false, "value" : 0 },
      "specular" : false
    },
    {
      "name" : "Cells",
      "layers" : [ { "name" : "cells", "image-name" : "cells.png", "glass" : true } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.4 },
      "specular" : true,
      "lighting" : "individual"
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

**Flat fallback (CoreGraphics).** `CrannyIconArt.draw(in:size:layers:masked:)` draws the same art into any `CGContext`. Uses: the onboarding/About artwork, a build-time 1024-pt PNG via `CrannyIconArt.png(size:masked:true)` → `iconutil`, if a build path ever skips actool, and producing the three Icon Composer layers (`masked:false`). It uses the macOS 824-pt body on a 1024 grid with a continuous r 185 squircle (`RoundedRectangle(style: .continuous).path(in:).cgPath`) and a drop shadow (black 35 %, blur 24, y 12). Renders: `out/icon-flat.png`, `out/icns.iconset/icon_128x128@2x.png`.

```swift
import CoreGraphics
import AppKit
import SwiftUI   // only for the continuous-corner squircle path

/// "Light from a cranny": a graphite squircle; a notch-shaped opening at the top lets a soft
/// fan of cool light spill down onto three glass cells (the Nook's widgets).
/// Pure CoreGraphics so it can (a) be the flat fallback icon rendered at build time,
/// (b) produce the PNG/SVG layers for the Icon Composer version, (c) draw onboarding art.
public enum CrannyIconArt {
    public enum Layer: CaseIterable { case background, light, cells, notch }

    /// Design space 1024 × 1024 (Icon Composer canvas). y grows DOWN (we flip the context).
    public static let notchRect = CGRect(x: 512 - 220, y: 0, width: 440, height: 200)
    public static let notchBottomRadius: CGFloat = 92
    public static let earRadius: CGFloat = 44
    public static let cell: CGFloat = 188, cellGap: CGFloat = 36, cellY: CGFloat = 560, cellRadius: CGFloat = 50

    /// Draw one layer (or all, if `layers` is nil) into a context of `size` points.
    /// `masked`: clip to the macOS squircle (flat fallback); Icon Composer applies its own mask.
    public static func draw(in ctx: CGContext, size: CGFloat, layers: Set<Layer>? = nil, masked: Bool) {
        let all = layers ?? Set(Layer.allCases)
        let s = size / 1024
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: s, y: -s)       // top-left origin, 1024 space

        // macOS (pre-26) icon grid: 824-pt body centred, continuous-ish corners (radius 185).
        let body = masked ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let k = body.width / 1024                                       // map art into the body
        if masked {
            let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: body).cgPath   // true continuous corners
            // drop shadow for the flat icon
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
            ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(squircle); ctx.clip()
        }
        ctx.translateBy(x: body.minX, y: body.minY); ctx.scaleBy(x: k, y: k)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!

        if all.contains(.background) {
            let g = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.17, green: 0.18, blue: 0.22, alpha: 1),
                                                           CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)] as CFArray,
                               locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])
        }
        if all.contains(.light) {
            // Fan of light from the notch opening: radial gradient, squashed vertically.
            let g = CGGradient(colorsSpace: space, colors: [
                CGColor(red: 0.62, green: 1.00, blue: 0.86, alpha: 0.95),
                CGColor(red: 0.38, green: 0.66, blue: 1.00, alpha: 0.55),
                CGColor(red: 0.55, green: 0.40, blue: 1.00, alpha: 0.00)] as CFArray, locations: [0, 0.45, 1])!
            ctx.saveGState()
            ctx.translateBy(x: 512, y: 180); ctx.scaleBy(x: 1.0, y: 1.25)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 520, options: [])
            ctx.restoreGState()
        }
        if all.contains(.cells) {
            let total = 3 * cell + 2 * cellGap
            for i in 0..<3 {
                let r = CGRect(x: 512 - total / 2 + CGFloat(i) * (cell + cellGap), y: cellY, width: cell, height: cell)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: cellRadius, cornerHeight: cellRadius, transform: nil))
                ctx.setFillColor(CGColor(gray: 1, alpha: i == 1 ? 0.34 : 0.18)); ctx.fillPath()
                ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), cornerWidth: cellRadius - 1.5, cornerHeight: cellRadius - 1.5, transform: nil))
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); ctx.setLineWidth(3); ctx.strokePath()
            }
        }
        if all.contains(.notch) {
            ctx.addPath(notchPath()); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// Notch silhouette with concave ears, in 1024 space (y down). Same construction as NotchShape.
    public static func notchPath() -> CGPath {
        let r = notchRect, rb = notchBottomRadius, e = earRadius, k: CGFloat = 0.4477
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX - e, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + e, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + e), control1: CGPoint(x: r.maxX + e * k, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + e * (1 - k)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rb))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rb, y: r.maxY), radius: rb)
        p.addLine(to: CGPoint(x: r.minX + rb, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - rb), radius: rb)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + e))
        p.addCurve(to: CGPoint(x: r.minX - e, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + e * (1 - k)), control2: CGPoint(x: r.minX - e * k, y: r.minY))
        p.closeSubpath()
        return p
    }

    public static func png(size: Int, layers: Set<Layer>? = nil, masked: Bool) -> Data? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(in: ctx, size: CGFloat(size), layers: layers, masked: masked)
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}
```

---

## 8. Accessibility

Inputs are read live through SwiftUI environment values (`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`). `CrannyThemeRoot` merges them with the user's Cranny overrides, and every token responds.

| Setting | What changes |
|---|---|
| **Reduce Motion** | Morphs become 0.18 s cross-fades at final sizes; no spring, scale, blur or offset; tab switches are opacity-only; HUD level is instant; the visualizer shows static bars; the aurora is frozen or hidden; no typewriter or ink effect; the timer-done pulse is replaced by a static ring colour; staggers are 0. The **Instant** personality is available to anyone. |
| **Reduce Transparency** | Translucent Nook → opaque black; Liquid Glass controls → flat `control` fills; ambient effects off; the onboarding label material → opaque. |
| **Increase Contrast** | Card 6 → 12 %, control 10 → 18 %, hairline 8 → 32 %, text 0.70 / 0.55 → 0.84 / 0.68 (tertiary 9.4:1); card strokes always drawn; quaternary rises to 5.3:1 so even placeholders are readable; semantic colours switch to their high-contrast system variants. Verified render: `out/a11y-hc-xl.png`. |
| **Differentiate Without Color** | Status never relies on colour alone: urgent timer adds `exclamationmark` before the digits; a live meeting shows "Now" text beside the green dot; low battery adds "Low"; calendar bars carry the calendar name in their VoiceOver label; an armed drop target changes its dash to solid as well as its colour; the selected file tile adds a checkmark badge. |
| **Text size** (Cranny setting; macOS has no third-party Dynamic Type API) | Small 0.92 · Standard 1.0 · Large 1.12 · XL 1.24 on every scalable style, **and the grid cell grows by the same factor** (56 → 70 at XL), so nothing clips (verified). The compact notch row cannot grow (hardware height). At Large and XL, compact text activities switch to their glyph form and the details move to the peek. |
| **VoiceOver** | Details below. |
| **Full Keyboard Access / keyboard only** | Details below. |
| **Pointer** | Hit targets ≥ 24 pt (macOS minimum 20); hover is never the only path (click, keyboard and the command palette reach everything); the close grace period is generous; "Close when the pointer leaves" can be turned off. |
| **Photosensitivity** | No flashing; the visualizer is capped at 20 fps with smoothed amplitude; ambient drift < 0.2 Hz; no full-panel brightness changes. |
| **Localisation (en, ru)** | Russian runs about 15–30 % longer: tab labels collapse to icons rather than truncating; titles truncate in the middle for files and at the tail for text; numbers, dates and durations use `FormatStyle` (12/24 h from the locale). The String Catalog (`.xcstrings`) carries comments for translators. |

**VoiceOver.**
- The panel is one container labelled "Cranny". Opening it posts a layout-changed notification and focus lands on the first widget (or the focused page when opened by keyboard).
- Each widget is a container named after itself.
- Live activities are single elements with label, value and named actions: "Play or pause", "Next track", "Join meeting", "Dismiss".
- A rotor "Widgets" jumps between widgets.
- Adjustable elements: scrubber ±10 s, timer ±1 min, HUD level.
- `AccessibilityNotification.Announcement` is posted for timer done, meeting starting in 1 min, and a pipeline finishing. It is *not* posted for HUD changes, because the system already speaks those.
- Key-cap hints are hidden from VoiceOver; shortcuts are exposed as hints ("Command-2").

**Keyboard.**
- The panel is a non-activating `NSPanel` that can become key (`canBecomeKey = true`), so the frontmost app stays frontmost. The sibling `notch-window` PoC verified `.nonactivatingPanel` must be set **at init**; setting it later activates the app.
- Tab / ⇧Tab move between widgets (`focusSection()`), arrows move inside a widget, ↩ activates, Esc closes.
- The focus ring is accent, 2 pt, concentric, and only shown after keyboard interaction.
- `onKeyPress` handles in-widget keys. The hold-⌘ overlay and the Keyboard pane document every binding.

---

## 9. Risks and tradeoffs of this direction

| Risk | Why it matters | Mitigation |
|---|---|---|
| **Density can tip into busy** | "Power-user" invites more widgets, more chips, more hints. | Neutral hierarchy (weight and opacity), accent scarcity, one prominent action per card, 2-row grid, hints only on hold-⌘, defaults ship with 10 cells. |
| **Keyboard focus in a non-activating panel** | Keystrokes go to the Nook while another app stays frontmost. Done wrong, this steals focus or loses the user's previous key window. | Become key only when opened by keyboard, by a click into a text field, or by type-to-capture. Restore the previous key window on close. `.nonactivatingPanel` set at init. Global hot key via Carbon (no Accessibility). QA matrix: fullscreen apps, Stage Manager, multiple Spaces. |
| **Covering menu-bar items** | Compact slots (up to 96 pt each side) widen the black shape over menu items and status icons. On macOS 27, status items are **not** individual windows in `CGWindowListCopyWindowInfo` (probed: only "Menubar"/MenuBarAgent windows at layer 24), so their positions can't be read without Accessibility. | Narrow slots by default (glyph/short); wide only for the transient HUD (1.4 s); a "Maximum activity width" setting; compact collapses while the pointer is in the menu bar outside the shape; optional AX-based measurement when Accessibility is granted anyway. |
| **Fixed-size transparent window** | A large invisible panel could swallow clicks meant for the menu bar or windows below. | `contentShape(shape)` + `ignoresMouseEvents` toggled by hit-testing the current shape; regression tests that click 4/12/24 pt outside the shape (the sibling PoC already measured that clicks below the shadow reach the app beneath). |
| **Hover intent tuning** | Too eager and it opens by accident; too deliberate and it feels laggy. | Three presets + ⌥ suppression + hover lift (feedback within 1 frame); click and shortcut alternatives; telemetry-free local A/B via the tutorial (time to open). |
| **Calm may underwhelm** | Users drawn to flashy notch apps expect bounce, glow and colour. | **Lively** personality (bounce 0.22), Aurora/Glow effects and album accent, all opt-in and previewable in Settings. |
| **No Dynamic Type on macOS** | The own text-size setting doubles the layout matrix (4 sizes × 3 densities). | Cells scale with text size (verified at XL); snapshot tests per size/density; compact row falls back to glyphs. |
| **OS-version visual drift** | MeshGradient only on 15+ (Canvas fallback on 14 looks softer); Liquid Glass only on 26+. | Effects are optional and subtle by design; glass is limited to controls; the notch body is identical on every OS. |
| **HUD needs Accessibility** | Suppressing the system HUD needs an event tap; without it you'd get duplicate HUDs (Atoll #419). | Off by default; never draw ours unless suppression works; clear explanation in the Permissions and HUD panes. |
| **Album-derived colour** | Muddy or neon artwork could produce ugly or illegible accents. | Hue-bin vibrancy weighting, saturation clamp 0.38–0.80, ≥ 4.5:1 guarantee, greyscale → system accent, used only for small fills. |
| **Real audio spectrum** | Needs a system-audio capture permission (screen-recording class), which is scary for a notch app. | Default pseudo-visualizer; "Real spectrum" opt-in with an honest label. |
| **Haptics are trackpad-only** | Mouse users get nothing. | Haptics are never the only feedback; every haptic has a visual counterpart. |
| **Energy** | A competitor's battery-drain reputation shows how sensitive users are. | Budget: 0 timers closed, ≤ 20 fps compact, ≤ 30 fps open, effects off in Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`). Verify with Instruments (Energy Log, Time Profiler) before each release. |
| **Grid rigidity** | A fixed 2-row grid limits tall content (long notes, busy calendars). | Pages + a Notes workspace page + width presets up to 8 cells; a possible future "3-row page" option (per page, not global). |
| **Pseudo-notch geometry** | The hardware bottom radius isn't published; ≈ 0.30·h is an estimate. | User fine-tune (±3 pt radius, ±20 pt width) with a magnified live outline; closed state inset by 0.5 pt so anti-aliasing never peeks out. |

---

## Appendix A — Widget anatomies in code (static PoC)

```swift
import SwiftUI

// Static anatomies of the open Nook (regular density) — used to verify the spec visually.

// MARK: - Header row (== notch row): tabs left of the cutout, actions right of it

public struct NookHeader: View {
    @Environment(\.crannyTheme) private var theme
    var notchWidth: CGFloat; var height: CGFloat
    var selected: Int; var trayCount: Int; var showKeyHints: Bool
    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                tab(0, "square.grid.2x2", "Nook", key: "⌘1")
                tab(1, "tray.full", "Tray", badge: trayCount, key: "⌘2")
                tab(2, "note.text", "Notes", key: "⌘3")
            }
            Spacer(minLength: notchWidth + 16)
            HStack(spacing: 6) {
                action("magnifyingglass", "Command palette", key: "⌘K")
                action("pin", "Keep open", key: "⌘P")
                action("gearshape", "Settings", key: "⌘,")
            }
        }
        .frame(height: height)
    }
    func tab(_ i: Int, _ symbol: String, _ title: String, badge: Int = 0, key: String) -> some View {
        let c = theme.colors, sel = i == selected
        return HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(title).crannyText(.caption).fontWeight(.semibold)
            if badge > 0 { Text("\(badge)").crannyText(.micro).padding(.horizontal, 4).frame(minHeight: 14).background(Capsule().fill(c.control)) }
            if showKeyHints { KeyCap(key) }
        }
        .foregroundStyle(sel ? c.textPrimary : c.textSecondary)
        .padding(.horizontal, 9).frame(height: 24)
        .background(CrannyButtonShape(radius: theme.buttonRadius).fill(sel ? c.selection : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(sel ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(Text("Command-\(i + 1)"))
    }
    func action(_ symbol: String, _ label: String, key: String) -> some View {
        Button {} label: { Image(systemName: symbol) }
            .buttonStyle(CrannyIconButtonStyle(role: .filled, size: 24))
            .overlay(alignment: .bottom) { if showKeyHints { KeyCap(key).offset(y: 14) } }
            .accessibilityLabel(Text(label))
    }
}

// MARK: - Media (4 × 2)

public struct MediaWidget: View {
    @Environment(\.crannyTheme) private var theme
    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.75, green: 0.25, blue: 0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Midnight Transit").crannyText(.headline).lineLimit(1)
                    Text("Low Orbit Choir").crannyText(.callout).foregroundStyle(c.textSecondary).lineLimit(1)
                    Label("Music", systemImage: "music.note").labelStyle(.titleAndIcon)
                        .crannyText(.caption).foregroundStyle(c.textTertiary).padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "airplayaudio").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.textTertiary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: 52)
            HStack(spacing: 6) {
                Text("1:24").crannyText(.caption).foregroundStyle(c.textTertiary)
                LevelBar(value: 0.38, color: theme.accent, thickness: StrokeWidth.scrubber)
                Text("−2:13").crannyText(.caption).foregroundStyle(c.textTertiary)
            }
            HStack(spacing: 10) {
                Spacer()
                Button {} label: { Image(systemName: "backward.fill") }.buttonStyle(CrannyIconButtonStyle(role: .plain, size: 26))
                Button {} label: { Image(systemName: "pause.fill") }.buttonStyle(CrannyIconButtonStyle(role: .prominent, size: 28))
                Button {} label: { Image(systemName: "forward.fill") }.buttonStyle(CrannyIconButtonStyle(role: .plain, size: 26))
                Spacer()
            }
        }
        .foregroundStyle(c.textPrimary)
    }
}

// MARK: - Calendar (3 × 2)

public struct CalendarWidget: View {
    @Environment(\.crannyTheme) private var theme
    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Wed 14").crannyText(.headline)
                Text("Oct").crannyText(.callout).foregroundStyle(c.textTertiary)
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundStyle(c.textTertiary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(c.textTertiary)
            }
            row(Color(red: 0.35, green: 0.75, blue: 0.85), "9:00", "Stand-up", past: true)
            VStack(spacing: 2) {
                row(Color(red: 0.35, green: 0.75, blue: 0.85), "10:30", "Design review", join: true)
                LevelBar(value: 0.35, color: c.live, thickness: 2).padding(.leading, 9)
            }
            row(Color(red: 0.95, green: 0.6, blue: 0.3), "13:00", "Lunch with Ana")
            Spacer(minLength: 0)
        }
        .foregroundStyle(c.textPrimary)
    }
    func row(_ color: Color, _ time: String, _ title: String, join: Bool = false, past: Bool = false) -> some View {
        let c = theme.colors
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 14)
            Text(time).crannyText(.caption).foregroundStyle(c.textSecondary).frame(width: 34, alignment: .leading)
            Text(title).crannyText(.callout).lineLimit(1)
            Spacer(minLength: 0)
            if join { Button("Join") {}.buttonStyle(CrannyPillButtonStyle(prominent: true)) }
        }
        .opacity(past ? 0.5 : 1)
        .frame(height: 20)
    }
}

// MARK: - Quick apps + Shortcuts (1 cell per column, 2 rows)

public struct QuickAppsWidget: View {
    @Environment(\.crannyTheme) private var theme
    var columns: Int; var showKeyHints: Bool
    let tiles: [(Color, String)] = [(.blue, "safari"), (.green, "message.fill"), (.orange, "terminal.fill"),
                                    (.purple, "wand.and.stars"), (.pink, "music.note"), (.gray, "folder.fill")]
    public var body: some View {
        let m = theme.nook
        Grid(horizontalSpacing: m.gutter, verticalSpacing: m.gutter) {
            ForEach(0..<2, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        let i = col * 2 + r
                        let t = tiles[i % tiles.count]
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(t.0.gradient)
                            .overlay(Image(systemName: t.1).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                            .frame(width: 40, height: 40)
                            .frame(width: m.cell, height: m.cell)
                            .overlay(alignment: .bottomTrailing) { if showKeyHints { KeyCap("⌥\(i + 1)").offset(x: -2, y: -2) } }
                    }
                }
            }
        }
    }
}

// MARK: - Mirror (2 × 2, frameless: the preview IS the card)

public struct MirrorWidget: View {
    @Environment(\.crannyTheme) private var theme
    public var body: some View {
        let c = theme.colors
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Image(systemName: "web.camera").font(.system(size: 20, weight: .medium))
                Text("Click to preview").crannyText(.caption)
            }
            .foregroundStyle(c.textSecondary)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "flip.horizontal")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(c.textSecondary)
                .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.4))).padding(6)
        }
    }
}

// MARK: - Notes (4 × 2) with code mode

public struct NotesWidget: View {
    @Environment(\.crannyTheme) private var theme
    var codeMode: Bool
    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(codeMode ? "deploy.md" : "Ideas").crannyText(.headline)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(c.textTertiary)
                Spacer()
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(codeMode ? theme.accent : c.textTertiary)
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(c.textTertiary)
            }
            if codeMode { code } else {
                (Text("Ship the notch morph spec, then draft onboarding copy. Ask Sam about the tray pipelines").foregroundStyle(c.textPrimary)
                 + Text("▍").foregroundStyle(theme.accent))
                    .crannyText(.body).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(c.textPrimary)
    }
    var code: some View {
        let s = theme.colors.syntax, t = theme.colors
        return VStack(alignment: .leading, spacing: 1) {
            line(1, Text("## Release").foregroundStyle(s.heading).bold())
            line(2, Text("let ").foregroundStyle(s.keyword) + Text("build").foregroundStyle(t.textPrimary) + Text(" = ").foregroundStyle(t.textSecondary) + Text("\"1.4.2\"").foregroundStyle(s.string))
            line(3, Text("retry").foregroundStyle(s.type) + Text("(").foregroundStyle(t.textSecondary) + Text("3").foregroundStyle(s.number) + Text(") ").foregroundStyle(t.textSecondary) + Text("// flaky CI").foregroundStyle(s.comment))
            line(4, Text("[notes](https://…)").foregroundStyle(s.link))
        }
        .font(.cranny(.code, theme.traits.textSize))
    }
    func line(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").foregroundStyle(theme.colors.textQuaternary).frame(width: 10, alignment: .trailing)
            text.lineLimit(1)
        }
    }
}

// MARK: - To-dos (3 × 2)

public struct TodosWidget: View {
    @Environment(\.crannyTheme) private var theme
    public var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("To-dos").crannyText(.headline); Spacer(); Text("2 left").crannyText(.caption).foregroundStyle(c.textTertiary) }
            row("Reply to Ana", done: false, focused: true)
            row("Export icons", done: false)
            row("Book flights", done: true)
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 14)
                Text("New to-do").crannyText(.body)
            }
            .foregroundStyle(c.textQuaternary).frame(height: 18)
        }
        .foregroundStyle(c.textPrimary)
    }
    func row(_ t: String, done: Bool, focused: Bool = false) -> some View {
        let c = theme.colors
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                .foregroundStyle(done ? theme.accent : c.textTertiary)
            Text(t).crannyText(.body).strikethrough(done, color: c.textTertiary)
                .foregroundStyle(done ? c.textTertiary : c.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(focused ? c.selection : .clear))
        .modifier(FocusRing(focused: focused, radius: 5))
    }
}

// MARK: - Timer (2 × 2)

public struct TimerWidget: View {
    @Environment(\.crannyTheme) private var theme
    var remaining: Int; var total: Int
    public var body: some View {
        let c = theme.colors
        ZStack {
            ProgressRing(progress: Double(remaining) / Double(total), color: theme.accent, lineWidth: StrokeWidth.ring)
            VStack(spacing: 0) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .crannyText(.display)
                    .contentTransition(.numericText(countsDown: true))
                Text("Focus").crannyText(.caption).foregroundStyle(c.textTertiary)
            }
        }
        .padding(4)
        .foregroundStyle(c.textPrimary)
    }
}

// MARK: - Tray tab (full width): files + pipelines + AirDrop

public struct TrayTab: View {
    @Environment(\.crannyTheme) private var theme
    var width: CGFloat
    public var body: some View {
        let m = theme.nook, c = theme.colors
        HStack(spacing: m.gutter) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    file("doc.richtext.fill", "Brief.pdf", .red, selected: true)
                    file("photo.fill", "hero@2x.png", .blue, selected: true)
                    file("photo.fill", "notch.heic", .teal)
                    file("doc.zipper", "assets.zip", .gray, progress: 0.6)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {         // pipelines for the current selection
                    Text("2 selected").crannyText(.caption).foregroundStyle(c.textTertiary)
                    chip("arrow.down.right.and.arrow.up.left", "Compress")
                    chip("arrow.triangle.2.circlepath", "Convert")
                    chip("doc.zipper", "Zip")
                    chip("link", "Copy paths")
                    Spacer(minLength: 0)
                }
            }
            .padding(m.cardPadding)
            .frame(width: width - m.span(2) - m.gutter - 2 * m.padding, height: m.span(m.rows), alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous).fill(c.card))
            DropZone(symbol: "dot.radiowaves.up.forward", title: "Drop to\nAirDrop", targeted: true)
                .frame(width: m.span(2), height: m.span(m.rows))
        }
        .foregroundStyle(c.textPrimary)
    }
    func file(_ symbol: String, _ name: String, _ tint: Color, selected: Bool = false, progress: Double? = nil) -> some View {
        let c = theme.colors
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.25))
                .overlay(Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint))
                .overlay { if let p = progress { ProgressRing(progress: p, color: theme.accent, lineWidth: 2.5).frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.6))) } }
                .frame(width: 44, height: 44)
            Text(name).crannyText(.caption).lineLimit(1).truncationMode(.middle).frame(width: 64)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? c.selection : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5))
    }
    func chip(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .crannyText(.caption).fontWeight(.semibold)
            .padding(.horizontal, 8).frame(height: 22)
            .background(CrannyButtonShape(radius: theme.buttonRadius.map { _ in Radius.chip }).fill(theme.colors.control))
    }
}

// MARK: - The open Nook

public struct OpenNook: View {
    @Environment(\.crannyTheme) private var theme
    var hw: NotchHardware; var size: CGSize; var tab: Int = 0; var showKeyHints = false
    public var body: some View {
        let m = theme.nook
        VStack(spacing: m.headerGap) {
            NookHeader(notchWidth: hw.notchWidth, height: hw.notchHeight, selected: tab, trayCount: 4, showKeyHints: showKeyHints)
            if tab == 0 {
                HStack(spacing: m.gutter) {
                    WidgetCard(cells: 4, title: "Media") { MediaWidget() }
                    WidgetCard(cells: 3, title: "Calendar") { CalendarWidget() }
                    WidgetCard(cells: 1, style: .frameless, title: "Quick apps") { QuickAppsWidget(columns: 1, showKeyHints: showKeyHints) }
                    WidgetCard(cells: 2, style: .frameless, title: "Mirror") { MirrorWidget() }
                }
            } else if tab == 1 {
                TrayTab(width: size.width)
            } else {
                HStack(spacing: m.gutter) {
                    WidgetCard(cells: 4, title: "Notes") { NotesWidget(codeMode: true) }
                    WidgetCard(cells: 3, title: "To-dos") { TodosWidget() }
                    WidgetCard(cells: 2, title: "Timer") { TimerWidget(remaining: 1124, total: 1500) }
                    WidgetCard(cells: 1, style: .frameless, title: "Shortcuts") { QuickAppsWidget(columns: 1, showKeyHints: false) }
                }
            }
        }
        .padding(.horizontal, m.padding)
        .padding(.bottom, m.padding)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}
```

## Appendix B — Render harness (how the numbers and images were produced)

Build and run (from `v2/`):
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -swift-version 6 -target arm64-apple-macos14.0 -O -o out/render src/*.swift
./out/render out
xcrun actool --compile out/actool-out --platform macosx --minimum-deployment-target 14.0 \
  --app-icon Cranny --output-partial-info-plist out/actool-out/partial.plist out/Cranny.icon
```

```swift
import SwiftUI
import AppKit

// Renders the spec to PNGs for visual verification + prints measured numbers.
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

@MainActor func save<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let img = r.cgImage else { print("render failed", name); return }
    let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
    print("wrote", name, img.width, "x", img.height)
}

/// Offscreen AppKit capture for views ImageRenderer can't draw (Form, List, NSControls).
@MainActor func snapshotWindow<V: View>(_ view: V, size: CGSize, _ name: String) {
    let vc = NSHostingController(rootView: view)
    let win = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                       styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .darkAqua)
    win.contentViewController = vc
    win.setContentSize(size)
    win.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    let target = win.contentView?.superview ?? vc.view          // theme frame: includes sidebar + toolbar
    target.layoutSubtreeIfNeeded()
    guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { print("snapshot failed", name); return }
    target.cacheDisplay(in: target.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote", name, rep.pixelsWide, "x", rep.pixelsHigh)
    win.orderOut(nil)
}

struct Desktop: View {
    var height: CGFloat; var menuBar: CGFloat = 32
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 0.75), Color(red: 0.85, green: 0.62, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.white.opacity(0.35)).frame(height: menuBar)
        }.frame(height: height)
    }
}

func contrast(_ fg: (Double, Double, Double), over bg: (Double, Double, Double), alpha: Double = 1) -> Double {
    func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    func L(_ c: (Double, Double, Double)) -> Double { 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2) }
    let mixed = (fg.0 * alpha + bg.0 * (1 - alpha), fg.1 * alpha + bg.1 * (1 - alpha), fg.2 * alpha + bg.2 * (1 - alpha))
    let a = L(mixed), b = L(bg)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@MainActor func numbers() {
    let black = (0.0, 0.0, 0.0)
    for (hc, label) in [(false, "standard"), (true, "increase contrast")] {
        let cardA = hc ? 0.12 : 0.06
        let card = (cardA, cardA, cardA)
        print("— text contrast (\(label)); card = white \(cardA)")
        for (n, a) in [("primary", 1.0), ("secondary", hc ? 0.84 : 0.70), ("tertiary", hc ? 0.68 : 0.55), ("quaternary", hc ? 0.50 : 0.34)] {
            // text over card: composite white@a over card colour
            print(String(format: "  %-10@ on black %5.2f:1   on card %5.2f:1", n as NSString,
                         contrast((1, 1, 1), over: black, alpha: a), contrast((1, 1, 1), over: card, alpha: a)))
        }
        print(String(format: "  hairline (white %.2f) vs black %.2f:1 ; control (white %.2f) vs card %.2f:1",
                     hc ? 0.32 : 0.08, contrast((1, 1, 1), over: black, alpha: hc ? 0.32 : 0.08),
                     hc ? 0.18 : 0.10, contrast((1, 1, 1), over: card, alpha: hc ? 0.18 : 0.10)))
    }
    let cardBg = (0.06, 0.06, 0.06)
    print("— syntax on card (#0F0F0F)")
    for (n, c) in [("keyword", (1.0, 0.48, 0.70)), ("string", (0.99, 0.62, 0.40)), ("number", (0.82, 0.75, 1.0)),
                   ("type", (0.42, 0.86, 0.91)), ("comment", (0.58, 0.58, 0.58)), ("link", (0.42, 0.70, 1.0))] {
        print(String(format: "  %-8@ %5.2f:1", n as NSString, contrast(c, over: cardBg)))
    }
    print("— accent swatches on black")
    for (n, c) in [("blue", (0.36, 0.66, 1.0)), ("teal", (0.31, 0.82, 0.77)), ("green", (0.40, 0.83, 0.53)), ("yellow", (0.96, 0.77, 0.32)),
                   ("orange", (1.0, 0.62, 0.36)), ("pink", (1.0, 0.50, 0.71)), ("purple", (0.72, 0.62, 1.0)), ("graphite", (0.78, 0.78, 0.80))] {
        print(String(format: "  %-8@ %5.2f:1  (on card %5.2f:1)", n as NSString, contrast(c, over: black), contrast(c, over: cardBg)))
    }
    print("— album-art accent clamp")
    func hex(_ c: NSColor) -> String { let c = c.usingColorSpace(.sRGB)!; return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255)) }
    for (name, c) in [("navy", NSColor(srgbRed: 0.08, green: 0.10, blue: 0.40, alpha: 1)), ("deep red", NSColor(srgbRed: 0.45, green: 0.05, blue: 0.08, alpha: 1)),
                      ("neon green", NSColor(srgbRed: 0.2, green: 1.0, blue: 0.1, alpha: 1)), ("brown", NSColor(srgbRed: 0.35, green: 0.22, blue: 0.12, alpha: 1))] {
        let out = AlbumAccent.clampForDarkSurface(c)
        print(String(format: "  %-10@ %@ → %@  %.2f:1 on black", name as NSString, hex(c), hex(out), AlbumAccent.contrastOnBlack(out)))
    }
    // geometry numbers
    for (label, hw) in [("14\" MBP", NotchHardware(hasNotch: true, notchWidth: 185, notchHeight: 32, screenWidth: 1512, menuBarHeight: 32)),
                        ("13\" Air", NotchHardware(hasNotch: true, notchWidth: 185, notchHeight: 32, screenWidth: 1470, menuBarHeight: 32)),
                        ("14\" More Space", NotchHardware(hasNotch: true, notchWidth: 160, notchHeight: 25, screenWidth: 1800, menuBarHeight: 25)),
                        ("27\" ext", NotchHardware(hasNotch: false, notchWidth: 190, notchHeight: 25, screenWidth: 2560, menuBarHeight: 25))] {
        for d in CrannyTraits.Density.allCases {
            let m = NookMetrics.forDensity(d)
            let s = NookLayoutSize.size(cells: 10, hw: hw, nook: m)
            print(String(format: "  %-15@ %-11@ cell %2.0f gutter %1.0f  open(10 cells) %4.0f×%3.0f  maxCols %2d  cardR %2.0f innerR %1.0f  slots g/s/w %2.0f/%2.0f/%2.0f",
                         label as NSString, d.rawValue as NSString, m.cell, m.gutter, s.width, s.height,
                         NookLayoutSize.maxColumns(hw: hw, nook: m), m.cardRadius, m.innerRadius,
                         SlotWidth.glyph(hw.notchHeight), SlotWidth.short(hw.notchHeight), SlotWidth.wide(hw.notchHeight)))
        }
    }
    // path performance
    let hw = NotchHardware(hasNotch: true, notchWidth: 185, notchHeight: 32, screenWidth: 1512, menuBarHeight: 32)
    let m = NookMetrics.forDensity(.regular)
    let a = NotchGeometry.make(.closed, hw: hw, nook: m), b = NotchGeometry.make(.open(width: 656, height: 172), hw: hw, nook: m)
    let rect = CGRect(x: 0, y: 0, width: 900, height: 260)
    let n = 20000; let t0 = Date(); var ok = 0
    for i in 0..<n {
        let t = CGFloat(i % 100) / 100
        var s = NotchShape(a); s.animatableData = NotchShape(a).animatableData
        var d = NotchShape(b).animatableData; d -= s.animatableData; d.scale(by: Double(t)); s.animatableData += d
        if !s.path(in: rect).isEmpty { ok += 1 }
    }
    print(String(format: "— NotchShape.path(in:) avg %.2f µs (%d/%d non-empty)", Date().timeIntervalSince(t0) / Double(n) * 1e6, ok, n))
}

@MainActor func renders() {
    let hw = NotchHardware(hasNotch: true, notchWidth: 185, notchHeight: 32, screenWidth: 1512, menuBarHeight: 32)
    let ext = NotchHardware(hasNotch: false, notchWidth: 190, notchHeight: 25, screenWidth: 2560, menuBarHeight: 25)
    let theme = CrannyTheme.standard
    let m = theme.nook
    let open = NookLayoutSize.size(cells: 10, hw: hw, nook: m)
    let art = AnyView(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.75, green: 0.25, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))

    struct Row { let title: String; let state: NotchState; let hw: NotchHardware; let content: AnyView; let openness: Double }
    let rows: [Row] = [
        Row(title: "closed — exactly the cutout (draws nothing visible)", state: .closed, hw: hw, content: AnyView(EmptyView()), openness: 0),
        Row(title: "compact · Now Playing (glyph slots 40)", state: .compact(slot: SlotWidth.glyph(32)), hw: hw,
            content: AnyView(NowPlayingCompact(artwork: art, title: "Midnight Transit", artist: "Low Orbit Choir", levels: [0.5, 1, 0.7, 0.35], playing: true, notchWidth: 185, h: 32)), openness: 0),
        Row(title: "compact · Volume HUD (wide slots 96)", state: .compact(slot: SlotWidth.wide(32)), hw: hw,
            content: AnyView(LevelHUDCompact(kind: .volume, level: 0.62, muted: false, colored: true, notchWidth: 185, h: 32)), openness: 0),
        Row(title: "peek · Now Playing (hover / track change)", state: .peek(width: 0, extra: 58), hw: hw,
            content: AnyView(VStack(spacing: 0) {
                NowPlayingCompact(artwork: art, title: "Midnight Transit", artist: "Low Orbit Choir", levels: [0.5, 1, 0.7, 0.35], playing: true, notchWidth: 185, h: 32)
                NowPlayingPeek(title: "Midnight Transit", artist: "Low Orbit Choir", progress: 0.38)
            }), openness: 0),
        Row(title: "open · Nook tab (10 cells: media 4 · calendar 3 · apps 1 · mirror 2)", state: .open(width: open.width, height: open.height), hw: hw,
            content: AnyView(OpenNook(hw: hw, size: open)), openness: 1),
        Row(title: "open · Tray tab (files, pipelines, AirDrop target armed)", state: .open(width: open.width, height: open.height), hw: hw,
            content: AnyView(OpenNook(hw: hw, size: open, tab: 1)), openness: 1),
        Row(title: "open · Notes tab, hold ⌘ → key hints", state: .open(width: open.width, height: open.height), hw: hw,
            content: AnyView(OpenNook(hw: hw, size: open, tab: 2, showKeyHints: true)), openness: 1),
        Row(title: "no notch · handle (opacity user-set 0…0.35)", state: .closed, hw: ext, content: AnyView(EmptyView()), openness: 0),
        Row(title: "no notch · floating compact island", state: .compact(slot: SlotWidth.glyph(25)), hw: ext,
            content: AnyView(NowPlayingCompact(artwork: art, title: "t", artist: "a", levels: [0.5, 1, 0.7, 0.35], playing: true, notchWidth: 80, h: 26).padding(.top, 4)), openness: 0),
    ]
    let sheet = VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
            let g = NotchGeometry.make(r.state, hw: r.hw, nook: m)
            let h = max(g.bodyHeight + g.topInset + 26, 50)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.title) — body \(Int(g.bodyWidth))×\(Int(g.bodyHeight)) rb \(Int(g.bottomRadius)) ear \(Int(g.earRadius))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.black)
                ZStack(alignment: .top) {
                    Desktop(height: h, menuBar: r.hw.menuBarHeight)
                    NotchRoot(geometry: g, notchHeight: r.hw.notchHeight, openness: r.openness, contentVisible: true) { r.content }
                        .opacity(r.hw.hasNotch ? 1 : 1)
                    if r.hw.hasNotch {
                        NotchShape(NotchGeometry(bodyWidth: 185, bodyHeight: 32, bottomRadius: 10, earRadius: 0, topRadius: 0, topInset: 0))
                            .stroke(Color.red.opacity(0.85), lineWidth: 0.75)
                    }
                }
                .frame(width: 900, height: h)
            }
        }
    }
    .padding(16).background(Color.white)
    .crannyThemeRoot(theme)
    save(sheet, "states.png")

    // Accessibility variant: Increase Contrast + XL text + rounded buttons
    var hc = CrannyTheme.standard
    hc.traits.increaseContrast = true; hc.traits.textSize = .xLarge; hc.traits.buttonShape = .rounded
    let mh = hc.nook
    let openH = NookLayoutSize.size(cells: 10, hw: hw, nook: mh)
    print("a11y metrics: cell", mh.cell, "open", openH)
    let a11y = ZStack(alignment: .top) {
        Desktop(height: openH.height + 20)
        NotchRoot(geometry: NotchGeometry.make(.open(width: openH.width, height: openH.height), hw: hw, nook: mh), notchHeight: 32, openness: 1, contentVisible: true) {
            OpenNook(hw: hw, size: openH, tab: 2)
        }
    }.frame(width: 1000).crannyThemeRoot(hc)
    save(a11y, "a11y-hc-xl.png")

    // Live activities gallery (zoomed)
    let gallery = VStack(alignment: .leading, spacing: 10) {
        ForEach(0..<6, id: \.self) { i in
            let slot: CGFloat = [SlotWidth.glyph(32), SlotWidth.short(32), SlotWidth.short(32), SlotWidth.wide(32), SlotWidth.short(32), SlotWidth.short(32)][i]
            ZStack(alignment: .top) {
                Desktop(height: 44)
                NotchRoot(geometry: NotchGeometry.make(.compact(slot: slot), hw: hw, nook: m), notchHeight: 32, openness: 0, contentVisible: true) {
                    switch i {
                    case 0: NowPlayingCompact(artwork: art, title: "t", artist: "a", levels: [0.5, 1, 0.7, 0.35], playing: true, notchWidth: 185, h: 32)
                    case 1: MeetingCompact(calendarColor: .teal, minutesUntil: 5, elapsed: nil, hasLink: true, notchWidth: 185, h: 32)
                    case 2: TimerCompact(remaining: 299, total: 1500, notchWidth: 185, h: 32)
                    case 3: LevelHUDCompact(kind: .brightness, level: 0.8, muted: false, colored: false, notchWidth: 185, h: 32)
                    case 4: BatteryCompact(percent: 82, charging: true, notchWidth: 185, h: 32)
                    default: BluetoothCompact(symbol: "airpodspro", name: "AirPods Pro", percent: 84, notchWidth: 185, h: 32)
                    }
                }
            }.frame(width: 520, height: 44)
        }
    }.padding(10).background(Color.white).crannyThemeRoot(theme)
    save(gallery, "activities.png", scale: 3)

    // Morph filmstrip (closed → open), sampled at spring progress
    let a = NotchGeometry.make(.closed, hw: hw, nook: m), b = NotchGeometry.make(.open(width: open.width, height: open.height), hw: hw, nook: m)
    func lerp(_ t: CGFloat) -> NotchGeometry {
        func l(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return NotchGeometry(bodyWidth: l(a.bodyWidth, b.bodyWidth), bodyHeight: l(a.bodyHeight, b.bodyHeight), bottomRadius: l(a.bottomRadius, b.bottomRadius),
                             earRadius: l(a.earRadius, b.earRadius), topRadius: 0, topInset: 0)
    }
    let film = HStack(spacing: 6) {
        ForEach([0, 0.25, 0.5, 0.75, 1.0] as [CGFloat], id: \.self) { t in
            ZStack(alignment: .top) { Desktop(height: 190); NotchShape(lerp(t)).fill(.black) }.frame(width: 700, height: 190).scaleEffect(0.5).frame(width: 350, height: 95)
        }
    }.padding(6).background(.white)
    save(film, "filmstrip.png")

    // Aurora (open, static frame) — MeshGradient on this OS
    let aurora = ZStack(alignment: .top) {
        Desktop(height: open.height + 20)
        NotchRoot(geometry: b, notchHeight: 32, openness: 1, contentVisible: true) {
            ZStack(alignment: .top) {
                AuroraBackground(colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.75, green: 0.25, blue: 0.65), Color(red: 0.3, green: 0.4, blue: 0.9)],
                                 active: false, intensity: 0.35, fixedTime: 12)
                OpenNook(hw: hw, size: open)
            }
        }
    }.frame(width: 900).crannyThemeRoot(theme)
    save(aurora, "aurora.png")
}

@MainActor func iconOutputs() {
    try? CrannyIconArt.png(size: 1024, masked: true)?.write(to: outDir.appendingPathComponent("icon-flat.png"))
    let iconDir = outDir.appendingPathComponent("Cranny.icon/Assets")
    try? FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
    try? CrannyIconArt.png(size: 1024, layers: [.light], masked: false)?.write(to: iconDir.appendingPathComponent("light.png"))
    try? CrannyIconArt.png(size: 1024, layers: [.cells], masked: false)?.write(to: iconDir.appendingPathComponent("cells.png"))
    try? CrannyIconArt.png(size: 1024, layers: [.notch], masked: false)?.write(to: iconDir.appendingPathComponent("notch.png"))
    print("wrote icon-flat.png + Cranny.icon/Assets layers")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    numbers()
    renders()
    iconOutputs()
    snapshotWindow(SettingsRoot(), size: CGSize(width: 900, height: 620), "settings.png")
    snapshotWindow(OnboardingView(step: 1), size: CGSize(width: 640, height: 460), "onboarding.png")
}
```

## Appendix C — Sources

- Apple HIG, Live Activities (Dec 16 2025 revision; compact/minimal/expanded anatomy, iPhone dimensions, 44-pt radius, key line, 2-s animation cap): https://developer.apple.com/design/human-interface-guidelines/live-activities
- Apple Developer Forums 818858, "Preferred Font Size / Dynamic Type on macOS" (DTS: Dynamic Type is not part of macOS): https://developer.apple.com/forums/thread/818858
- MacStories, "NotchNook and MediaMate": https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/
- Macworld, NotchNook review: https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html
- iMore, NotchNook review: https://www.imore.com/apps/mac-apps/this-dollar25-app-gives-my-macbook-pro-a-dynamic-island-and-it-was-worth-every-penny
- MacRumors forum thread on NotchNook battery/CPU: https://forums.macrumors.com/threads/notchnook.2463695/
- Setapp NotchNook customer reviews (hover hangs), via search summary: https://setapp.com/it/apps/notchnook/customer-reviews
- Alcove: https://tryalcove.com · App Store listing https://apps.apple.com/au/app/id6737410946 · AlternativeTo https://alternativeto.net/software/alcove
- boring.notch issues (titles and reaction counts only; no code read): #364, #335, #350, #303, #325, #316, #339, #341, #119, #239, #247, #110, #135, #210, #161, #1248, #1055, #1441, #922, #797 — https://github.com/TheBoredTeam/boring.notch/issues
- Atoll issues (titles only): #419, #245, #171, #487 — https://github.com/Ebullioscopic/Atoll/issues


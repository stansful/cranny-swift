# Cranny Architecture

> One thin Xcode app, one Swift package, seventeen modules that never import each other sideways. Feature teams build against contracts in `CrannyCore`; the shell owns windows, state and composition.

| | |
|---|---|
| Status | **v1.0, adopted** (2026-10-14), **reviewed** the same day (see "Changelog of review fixes" at the end). The definitive engineering reference. `docs/DESIGN.md` remains the single source of truth for pixels, colours, motion and copy; this document owns code structure, contracts, threading, build and the work plan. |
| Toolchain | Xcode 27.0 (27A266a), Swift 6.4, MacOSX27 SDK. Minimum supported toolchain: **Xcode 26 / Swift 6.2** (`swift-tools-version: 6.2`, `.defaultIsolation`, `@concurrent`, `.icon`, `#bundle`). |
| Platform | macOS 14.0 deployment target, universal (arm64 + x86_64). Newer APIs only behind `#available`. Not sandboxed, hardened runtime, agent app (`LSUIElement`). |
| Licence | MIT, clean room. No NotchNook code, assets, names or UI text; no GPL code (boring.notch); zero third-party dependencies. |
| Evidence | Research R1 (overlay window), R2 (media), R3 (system services), R4 (build) and their PoCs live in the research session's scratchpad, **not in the repo**; everything a work package needs from them is restated here. DESIGN.md. Every contract in §2–§3 and every file in the appendices was **compiled and run** for this document (Appendix C). |

Status tags: **[VERIFIED]** built or run on macOS 27.0.1 (this document or R1–R4) · **[SDK]** checked in the SDK · **[UNVERIFIED]** reasoned or documented only — the owning work package must confirm it.

**Contents.** 0 Decisions · 1 Repository · 2 Package · 3 CrannyCore API · 4 State machine · 5 Windows · 6 Media · 7 System services · 8 Build, packaging, localization · 9 Engineering rules · 10 Work breakdown · 11 Risks & hardware checklist · Appendix A Core sources · Appendix B Project & tooling files · Appendix C Verification log.

---

## 0. Decisions at a glance

| # | Decision | Why / evidence |
|---|---|---|
| D1 | **Repo layout:** `Cranny.xcodeproj` + synchronized folder `App/` (only `@main`, plists, entitlements, icon, assets) + local package `Packages/CrannyKit/` with **all** code. | R4's hand-written objectVersion-77 project, re-pathed and rebuilt: universal Release and hardened Debug builds, `codesign --verify --deep --strict` OK [VERIFIED, Appendix C]. New Swift files never touch the project. |
| D2 | **17 library targets in four layers** (§2.1). Feature modules depend on `CrannyCore` **only**. The shell is split into `CrannyNotchUI`, `CrannySettingsUI`, `CrannyOnboarding`, `CrannyAppShell` so that 10 engineers can work in parallel without sharing a target. | Each target builds alone with `swift build --target` in its own scratch dir; all 17 from clean in 45 s wall-clock with JOBS=6 (4.3 s warm), zero warnings [VERIFIED]. |
| D3 | **Isolation:** `CrannyCore` = nonisolated default; every other Swift target = `MainActor` default. All four Swift 7 upcoming features on. Values that cross threads are `nonisolated` + `Sendable`. | R4 §3.2. Core contracts compile under both [VERIFIED]. |
| D4 | **Cross-module communication only through Core "ports"** (`NotchControl`, `SystemEnvironment`, `AppControl`, `NowPlayingSource`, `TrayIntake`) reached via `CrannyServices`, plus registries (`ModuleRegistry`, `NotchZones`). | No sideways imports; shell and modules can be built and tested with the public test doubles in Core [VERIFIED]. |
| D5 | **Plug-in model:** each module exposes one `FeatureModule` type; `register(in:)` contributes widgets, live activities (+ samples, + Live Activities option rows), pages, settings panes, ⌘K commands, global shortcuts, capture targets, permission uses, launch/terminate hooks. The composition root lists modules once. | Reference `TimerModule` compiles and registers [VERIFIED]. |
| D6 | **One fixed-size, non-activating `NSPanel` per display at level 26**, morphing purely in SwiftUI; per-pixel click-through; never assign `ignoresMouseEvents`. | R1 (222–238 fps, 32/32 self-tests). |
| D7 | **AppKit owns drag-and-drop and scroll events**; SwiftUI views *declare* drop/scroll zones (`.crannyDropZone`, `.crannyScrollZone`) that the panel's root view routes to by geometry. | R1 §5: SwiftUI `.onDrag` hands out temporary copies; `.onDrop` registers `public.data`. Zone modifiers use back-deployed `onGeometryChange` (macOS 13) [SDK][VERIFIED compile]. |
| D8 | **Media:** our own perl-hosted ObjC bridge (R2 v3), built by an Xcode dylib target into `Contents/Frameworks`, never linked. Provider chain perl → ruby → AppleScript (opt-in). | R2 + R4; the Xcode-built bridge inside the new layout answered `hello/pong/state/artwork` under `/usr/bin/perl` [VERIFIED]. |
| D9 | **Artwork colour = DESIGN.md's `AmbientPalette.extract`** (moved into Core). R2's OKLab `ArtworkPalette`/`RGB(Float)` is **not** used: it would duplicate `RGB` and the palette contract. | DESIGN.md is the single source of truth for colour. |
| D10 | **HUD: "never two HUDs".** Cranny draws a HUD only when its Accessibility event tap replaces the system OSD; there is no passive tier. | DESIGN.md §10 overrides R3's passive mode; R3 verified OSD suppression. |
| D11 | **Settings and Welcome windows are AppKit-managed `NSWindow`s hosting SwiftUI**, not a SwiftUI `Settings` scene. The app's `App.body` contains only the `MenuBarExtra`. | We must open Settings at a specific pane from the Nook, Permissions flows and reopen events; programmatic opening of the `Settings` scene from an agent app is unreliable on macOS 14 [UNVERIFIED community reports] — AppKit windows avoid the question. |
| D12 | **No hidden Edit menu needed.** With the SwiftUI `App` lifecycle, `NSApp.mainMenu` already contains Edit with ⌘Z/X/C/V/A. `scripts/smoke.sh` asserts it on every CI run. | Diagnostics of the built app listed the menu [VERIFIED]; R1's gotcha applied to a pure-AppKit app. |
| D13 | **No `.metal` files in v1**, enforced: `scripts/check-modules.sh` fails on any `*.metal` under `Sources/` (B.12). Effects are SwiftUI (`MeshGradient` 15+, `Canvas`, `TimelineView`) exactly as DESIGN.md specifies; no `ShaderLibrary`/`.metallib`. Runtime `MTLDevice.makeLibrary(source:)` is reserved for a later version, behind a setting, always with the SwiftUI path as the fallback. | The Metal Toolchain is a separately downloaded Xcode component. The environment brief lists it as **not installed**; it was later installed on the research Mac (`xcrun metal` 32023.921, `research/X-metal-verified.md` — whose "Effects may ship Metal" conclusion is superseded by this decision). It is not guaranteed on CI runners or contributors' machines, and SwiftPM cannot build a target with `.metal` resources without it. R1 rejected Metal for the shape for the same reason. |
| D14 | **Settings apply instantly** (macOS convention). The Settings preview stage renders the real notch views with the live values plus sample activities; there is no draft store. "Reset All" is undoable for 10 s through `SettingsStore.snapshot()/restore(_:)` (A.1). | Simplest consistent model; DESIGN.md §11.2 was aligned to it. |
| D15 | **Launch at login = `SMAppService.mainApp` only** (no LaunchAgent fallback in v1). | R3 §9; fallback adds a second background item. Failure shows "Open Login Items…". |
| D16 | **Bundle id `app.cranny.Cranny`, log subsystem identical.** Never change it after the first public release: TCC grants and defaults are keyed by it. Before that release WP-Final confirms the project controls the `cranny.app` domain; if not, switch once to `io.github.<owner>.Cranny` (a foreign reverse-DNS id risks TCC/defaults collisions with a real app). | R4 verified; `tccutil reset All app.cranny.Cranny` for testing. |
| D17 | **Every Swift target has a test target, all declared up front.** `Package.swift`, `CrannyCore`, `App/`, the project, scripts and CI are owned by WP0/WP-Final; feature packages never edit them. | Avoids merge conflicts on shared files during the parallel phase. |
| D18 | **Low battery "Low Power Mode toggle" is a deep link** to Battery settings, not a toggle. | There is no public API to set Low Power Mode (`pmset` needs root). |
| D19 | **Zero dependencies.** `THIRD_PARTY_NOTICES.md` exists to record acknowledgements (technique credit for mediaremote-adapter, BSD-3; volumeHUD, MIT) and states that no third-party code is included. | R2 §3, R3 §1.2. |
| D20 | **"Nook" is an internal code name only; it never appears in UI text.** NotchNook's own UI labels its panel tabs "Nook" and "Tray", and "Nook" is part of its product name. User-visible copy: the open panel is "Cranny" ("Open Cranny", "Keep Cranny Open"), the built-in grid page is **Home**, the Settings pane is **Layout & Widgets**, onboarding says "layout". Types and persisted raw IDs (`NookWidget`, `PageID.nook = "nook"`, `nook.pages`) keep the code name. WP-Final checks every catalog against a competitor-term denylist (§8.7). | Clean-room rule: no competitor product names or UI text. |
| D21 | **Delight moments, previews and theme resolution are rendered in one place.** Feature modules *name* a delight (`LiveActivity.delight`), stages pass sample activities through `NotchSceneModel.sampleActivities`, and `ThemeResolver` (CrannyNotchUI) turns `CoreSettings` into theme/layout for the shell, the Settings stage and the onboarding stage alike. | Layer-1 modules cannot import `CrannyEffects`; SettingsUI/Onboarding cannot import the shell (§2.1). Added by the review (Changelog). |

---

## 1. Repository layout

```
Cranny/                                   ← repo root
├─ Cranny.xcodeproj/                      ← hand-written, objectVersion 77 (Appendix B.1); owner WP0
│  ├─ project.pbxproj                        targets: Cranny (app) + CrannyMediaBridge (dylib)
│  └─ xcshareddata/xcschemes/Cranny.xcscheme
├─ App/                                   ← buildable folder of target "Cranny"; owner WP0 → WP-Final
│  ├─ CrannyApp.swift                     ← the ONLY Swift file: @main → CrannyAppShell
│  ├─ Info.plist                          ← partial plist merged with generated keys (membership exception)
│  ├─ InfoPlist.xcstrings                 ← usage descriptions, en + ru
│  ├─ Cranny.entitlements                 ← hardened-runtime resource access, no sandbox
│  ├─ AppIcon.icon/                       ← Icon Composer document (macOS 26+; Xcode generates the 14/15 fallback)
│  └─ Assets.xcassets/                    ← AccentColor only (package code never reads Bundle.main assets, §8.8)
├─ Packages/
│  └─ CrannyKit/                          ← local Swift package with ALL code
│     ├─ Package.swift                    ← owner WP0 (§2.2); nobody else edits it
│     ├─ Sources/<Target>/…               ← one folder per target (§2.1), each with Resources/Localizable.xcstrings
│     └─ Tests/<Target>Tests/…            ← one test target per Swift target (Swift Testing)
├─ scripts/                               ← lib.sh build.sh run.sh smoke.sh dist.sh check-modules.sh sync-strings.sh
├─ docs/                                  ← DESIGN.md, ARCHITECTURE.md (+ CONTRIBUTING.md, PRIVACY.md from WP-Final)
├─ .github/workflows/                     ← ci.yml, release.yml
├─ VERSION                                ← marketing version, e.g. 0.1.0 (scripts/build.sh reads it; release tag must match)
├─ LICENSE                                ← MIT
├─ README.md                              ← install (Gatekeeper "Open Anyway" / xattr), build, permissions FAQ ("perl" helper)
├─ THIRD_PARTY_NOTICES.md                 ← "no third-party code included" + acknowledgements shown in About
├─ Makefile                               ← thin wrapper around scripts/
└─ .gitignore
```

Git-ignored outputs: `build/` (`Cranny.app`, dSYM, `DerivedData/`, `logs/`), `dist/` (zip, dmg, sha256), `Packages/CrannyKit/.build*/` (one SwiftPM scratch dir per target: 56–290 MB each, ≈ 2.8 GB for all 17 plus ≈ 0.5 GB for tests; `make distclean` removes them).

**Path changes from R4's PoC** (all applied and rebuilt, Appendix C): `Cranny/` → `App/`, `CrannyKit/` → `Packages/CrannyKit/`; in the project: the synchronized group path, `XCLocalSwiftPackageReference.relativePath`, `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_FILE`, the bridge group path and `USER_HEADER_SEARCH_PATHS`; plus `GCC_SYMBOLS_PRIVATE_EXTERN = YES` on the bridge target so it exports only `cranny_bridge_main` [VERIFIED with `nm -gU`].

---

## 2. Package layout

### 2.1 Layers and dependency rules

```
 L3  CrannyAppShell ─────────────────────────────────────────────── depends on everything below
       │ windows, per-display state machine, arbitration, input, ports, composition root, menu bar
 L2  CrannySettingsUI ──┐   CrannyOnboarding ──┐
       │ Core + NotchUI │     Core + NotchUI + Effects
       ▼                ▼
     CrannyNotchUI  (Core + Effects): render model + all notch/Nook views (shell, Settings stage, onboarding stage)
 L1  CrannyMedia  CrannyCalendar  CrannyQuickApps  CrannyMirror  CrannyNotes  CrannyTodos
     CrannyTimer  CrannyTray  CrannyHUD  CrannySystemActivities  CrannyEffects        ← each: Core ONLY
 L0  CrannyCore (design system, contracts, ports, settings, permissions, input, platform)
     CrannyMediaBridge (Objective-C; loaded by /usr/bin/perl at runtime; never imported by Swift)
```

Rules (enforced by `Package.swift`; a PR that adds an edge is rejected):
1. A layer-1 module imports `CrannyCore` and Apple frameworks only. It never imports another layer-1 module, `CrannyNotchUI` or the shell. `CrannyEffects` is layer 1 too (a view library with no `FeatureModule`).
2. Anything two layer-1 modules must share goes into `CrannyCore` as a value type or a port protocol, via a Core change request (§10.0).
3. The app target links only the static product `CrannyAppShell`. No `.dynamic` product is ever linked into the app (Release crash: "different Team IDs", R4 §7).
4. New targets are architecture changes. All 17 targets and 16 test targets exist from WP0 on, with placeholder sources, so nobody edits `Package.swift` during the parallel phase.

### 2.2 `Packages/CrannyKit/Package.swift` [VERIFIED: every target builds alone; `swift test` passes]

```swift
// swift-tools-version: 6.2
// CrannyKit — ALL Cranny code. The thin Xcode app target (Cranny.xcodeproj, folder App/)
// only contains @main, Info.plist, entitlements, the icon and the asset catalog.
//
// Layering (enforced by the dependency lists below — never add an edge that is not here):
//   L0  CrannyCore                      design system, contracts, settings, permissions, platform utils
//       CrannyMediaBridge (ObjC)        loaded by /usr/bin/perl at runtime, never imported by Swift
//   L1  feature modules + CrannyEffects depend on CrannyCore ONLY (never on each other)
//   L2  CrannyNotchUI                   notch/Nook composition views (Core + Effects)
//       CrannySettingsUI, CrannyOnboarding (Core + NotchUI [+ Effects])
//   L3  CrannyAppShell                  windows, state machine, composition root (depends on everything)
//
// This file is owned by Work Package 0. Feature packages never edit it.
import PackageDescription

/// Swift 7 defaults we opt into now (all verified to exist in Swift 6.2+).
let common: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"), // nonisolated async runs on the caller's actor; @concurrent hops off
    .enableUpcomingFeature("InferIsolatedConformances"),      // @MainActor types get @MainActor conformances
    .enableUpcomingFeature("MemberImportVisibility"),         // import what you use
    .enableUpcomingFeature("ExistentialAny"),                 // `any P` is spelled out
]
/// UI, feature and shell targets: everything is @MainActor unless marked `nonisolated`.
let mainActorByDefault: [SwiftSetting] = common + [.defaultIsolation(MainActor.self)]
/// CrannyCore: classic nonisolated default (models, value types, contracts).
let nonisolatedByDefault: [SwiftSetting] = common + [.defaultIsolation(nil)]

/// A layer-1 module: MainActor by default, depends on CrannyCore only, owns a String Catalog.
func feature(_ name: String) -> Target {
    .target(name: name, dependencies: ["CrannyCore"], resources: [.process("Resources")],
            swiftSettings: mainActorByDefault)
}
/// A layer-2/3 module.
func shellLayer(_ name: String, _ dependencies: [Target.Dependency]) -> Target {
    .target(name: name, dependencies: dependencies, resources: [.process("Resources")],
            swiftSettings: mainActorByDefault)
}
/// Every Swift target has exactly one test target, declared up front so nobody edits this file later.
func tests(_ module: String, isolation: [SwiftSetting] = mainActorByDefault) -> Target {
    let deps: [Target.Dependency] = module == "CrannyCore" ? ["CrannyCore"] : [.target(name: module), "CrannyCore"]
    return .testTarget(name: module + "Tests", dependencies: deps, swiftSettings: isolation)
}

let featureModules = [
    "CrannyMedia", "CrannyCalendar", "CrannyQuickApps", "CrannyMirror", "CrannyNotes",
    "CrannyTodos", "CrannyTimer", "CrannyTray", "CrannyHUD", "CrannySystemActivities", "CrannyEffects",
]

let package = Package(
    name: "CrannyKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        // The app links only this product (static). It pulls in the whole graph.
        .library(name: "CrannyAppShell", targets: ["CrannyAppShell"]),
        // CLI convenience only (`swift build --product CrannyMediaBridge`). The app never links it:
        // the Xcode target "CrannyMediaBridge" builds the same sources into Contents/Frameworks.
        .library(name: "CrannyMediaBridge", type: .dynamic, targets: ["CrannyMediaBridge"]),
    ],
    targets: [
        // L0
        .target(name: "CrannyCore", resources: [.process("Resources")], swiftSettings: nonisolatedByDefault),
        .target(name: "CrannyMediaBridge",                       // Objective-C, ARC (SwiftPM default)
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]),
        // L1
    ] + featureModules.map(feature) + [
        // L2
        shellLayer("CrannyNotchUI", ["CrannyCore", "CrannyEffects"]),
        shellLayer("CrannySettingsUI", ["CrannyCore", "CrannyNotchUI"]),
        shellLayer("CrannyOnboarding", ["CrannyCore", "CrannyNotchUI", "CrannyEffects"]),
        // L3
        shellLayer("CrannyAppShell", ["CrannyCore", "CrannyNotchUI", "CrannySettingsUI", "CrannyOnboarding"]
                   + featureModules.map { .target(name: $0) }),
        // Tests
        tests("CrannyCore", isolation: nonisolatedByDefault),
    ] + (featureModules + ["CrannyNotchUI", "CrannySettingsUI", "CrannyOnboarding", "CrannyAppShell"]).map { tests($0) }
)
```

### 2.3 Isolation per target

| Target(s) | Default isolation | Notes |
|---|---|---|
| `CrannyCore`, `CrannyCoreTests` | nonisolated | Value types are `nonisolated … Sendable`. UI-facing classes are explicitly `@MainActor` (`SettingsStore`, `PermissionsCenter`, `CrannyServices`, `ModuleRegistry`, `NotchZones`, `Haptics`). Views are main-actor through `View`. `JSONFileStore` is an `actor`. |
| Every other Swift target + its tests | `MainActor` | Models that are encoded/decoded or cross threads must be `nonisolated struct …: Codable, Sendable` — a plain `Codable` struct here gets a main-actor conformance that cannot be used in `@concurrent` code (R4 §3.2). Heavy work goes into `@concurrent` functions or actors. |
| `CrannyMediaBridge` | — (Objective-C, ARC on by SwiftPM default) | Built by SwiftPM only for `swift build --product CrannyMediaBridge`; the app uses the Xcode target. |

Every target also enables `NonisolatedNonsendingByDefault` (a `nonisolated async` function runs on the caller's actor — use `@concurrent` to leave it), `InferIsolatedConformances`, `MemberImportVisibility` and `ExistentialAny`. **`MemberImportVisibility` consequences seen while verifying:** a file that calls `String(localized:)` must `import Foundation`; a file that calls `Logger` methods must `import os`; `@Observable` needs `import Observation`.

### 2.4 Building one module

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer            # ALWAYS: xcode-select may point at the CLT
cd Packages/CrannyKit
swift build --target CrannyTimer --scratch-path .build-crannytimer        # your module + Core only
swift test --scratch-path .build-test --filter CrannyTimerTests             # builds all test targets (main is green)
../../scripts/check-modules.sh CrannyTimer                                  # same as CI, logs in build/logs/
```

**Toolchain selection.** `xcode-select` may point at `/Library/Developer/CommandLineTools`, and changing it needs `sudo`. Every manual `swift`/`xcodebuild`/`xcrun` command therefore starts with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the scripts do it themselves (`ensure_xcode`, B.7). The CLT ship Swift 6.4 too and can compile modules, but they lack `xcstringstool`, `actool`, `ictool` and the Xcode test frameworks, so mixing toolchains between scratch dirs is not allowed. Agents and anyone whose shell profile prints errors (for example `GVM_ROOT not set`) run important commands as separate invocations and check each exit status instead of chaining them with `&&`.

`swift build --target` on the Objective-C target only produces the object file; `swift build --product CrannyMediaBridge` produces `libCrannyMediaBridge.dylib` (arm64, ad-hoc signed by the linker) for CLI experiments (R4 §3.3). Everything also opens in Xcode (open `Packages/CrannyKit/Package.swift` for package-only work with `#Preview`, or `Cranny.xcodeproj` for the app).

---

## 3. CrannyCore public API

Everything in this section is the **contract** between work packages. The code blocks are the verified source files (built with zero warnings under the settings of §2.3; see Appendix C). WP0 copies them into the repo as they are; later changes are additive only (§10.0).

### 3.1 Directory map of `Sources/CrannyCore/`

| Folder / file | Contents | Section |
|---|---|---|
| `CrannyCore.swift` | Module overview, `PermissionKind.title` (Core's only localized strings) | A.9 |
| `DesignSystem/Color.swift`, `Typography.swift`, `Layout.swift`, `Motion.swift`, `Notch.swift`, `Theme.swift`, `Components.swift` | **Verbatim from DESIGN.md** §2.1–§4.2 and Appendix A, with two amendments (§3.2) | DESIGN.md |
| `DesignSystem/AmbientPalette.swift` | `AmbientPalette` (+ `extract(from:)`) and `EffectBudget`, moved out of DESIGN.md Appendix B so Media, Effects and the shell share them. `AuroraField` lives in `CrannyEffects`. | DESIGN.md App. B |
| `DesignSystem/SharedComponents.swift` | `WidgetStateView`, `CrannyChipButtonStyle`, `Scrubber`, `MarqueeText` | A.8 |
| `Contracts/Identifiers.swift` | `CrannyID<Tag>` and all well-known IDs | 3.3 |
| `Contracts/FeatureModule.swift` | `FeatureModule`, `ModuleRegistry` | 3.4 |
| `Contracts/Widget.swift` | `NookWidget`, `WidgetSizes`, `WidgetContext`, `AnyNookWidget`, `PageDescriptor` | 3.5 |
| `Contracts/LiveActivity.swift` | `LiveActivity`, `ActivityPriority`, `ActivityKind`, `ActivityAction`, `ActivityGesture`, `DelightMoment`, `RegisteredActivity` | 3.6 |
| `Contracts/Contributions.swift` | `SettingsPage`, `PaletteCommand(Provider)`, `KeyCombo`, `GlobalShortcut`, `CaptureTarget`, `PermissionUse` | 3.7 |
| `Contracts/NotchContext.swift` | `NotchPhase`, `OpenReason`, `NotchContext`, environment entries, `.notchMatched` | 3.8 |
| `Services/Ports.swift`, `Services/CrannyServices.swift` | Ports, media models, the service hub, public test doubles | 3.9 |
| `Input/NotchZones.swift`, `Input/SwipeTracker.swift` | Drop/scroll zone registry and modifiers; pure swipe state machine | 3.10, A.3–A.4 |
| `Settings/SettingsStore.swift`, `Settings/CoreSettings.swift` | Typed settings; shell-level keys and value types | 3.11, A.1–A.2 |
| `Permissions/PermissionsCenter.swift` | The only TCC query/request code | 3.12, A.5 |
| `Platform/Platform.swift`, `Platform/Concurrency.swift` | `Log`, `Haptics`, `AppPaths`, `JSONFileStore`, `AppInfo`, `SemanticVersion`, `observe(_:onChange:)`, `Debouncer`, `ProcessRunner` | 3.13, A.6–A.7 |
| `Resources/Localizable.xcstrings` | Core's catalog (en + ru) | 8.7 |

### 3.2 Design system placement and the two amendments

The DesignSystem files are DESIGN.md's code, copied verbatim. Three amendments were made for this architecture and are **already applied in DESIGN.md** (keep them):
1. `DropZone.title` is `String`, not `LocalizedStringKey` (a `LocalizedStringKey` passed into a package view is looked up in `Bundle.main` and stays English — R4 §3.4). **Rule for all Core components: they take already-localized `String`s or `Text`s.**
2. `NotchSurface` labels itself with `Text(verbatim: "Cranny")` (a name, not a translatable key).
3. `NookGrid.paddingTune` / `CrannyTheme.panelPaddingTune` implement Appearance ▸ Panel padding (±4 pt; `padding = density.padding + tune`, `panelRadius = Radius.card + padding`, so cards stay at r 20). Without them `CoreSettings.panelPaddingTune` had no effect.

DESIGN.md rules apply to every module: no literal colours/sizes/radii/animations; read `@Environment(\.cranny)`; `.crannyThemeRoot(_:)` exactly once per surface root (NotchUI canvas, Settings stage, onboarding stage); the hosting panel sets `appearance = .darkAqua`.

### 3.3 Identifiers

Typed string IDs with a phantom tag; they encode as plain strings and work as JSON dictionary keys (`CodingKeyRepresentable`, verified by a settings round-trip test). **Raw values are persisted — never rename one.** Well-known IDs live here so layers can name each other's things without importing them.

```swift
// CrannyCore/Contracts/Identifiers.swift
// Typed string identifiers. Raw values are stable and persisted (settings, layouts): never rename one.
import Foundation

/// A string identifier tagged with a phantom type so a `WidgetID` can never be passed as an `ActivityID`.
/// Encodes as a plain JSON string and can be a JSON dictionary key (`CodingKeyRepresentable`).
public nonisolated struct CrannyID<Tag>: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable,
                                         ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public nonisolated enum ModuleTag {}
public nonisolated enum WidgetTag {}
public nonisolated enum ActivityTag {}
public nonisolated enum PageTag {}
public nonisolated enum SettingsPageTag {}
public nonisolated enum CommandTag {}
public nonisolated enum ShortcutTag {}
public nonisolated enum DropZoneTag {}
public nonisolated enum ScrollZoneTag {}
public nonisolated enum DisplayTag {}

/// Namespace of a module or of a shell settings group: "timer", "appearance". Prefix of settings keys and log categories.
public typealias ModuleID = CrannyID<ModuleTag>
/// "<module>.<name>", e.g. "media.player".
public typealias WidgetID = CrannyID<WidgetTag>
/// "<module>.<name>", e.g. "timer.running".
public typealias ActivityID = CrannyID<ActivityTag>
/// A page in the Nook header ("nook", "tray", or a user page "page.<uuid>").
public typealias PageID = CrannyID<PageTag>
public typealias SettingsPageID = CrannyID<SettingsPageTag>
public typealias CommandID = CrannyID<CommandTag>
public typealias ShortcutID = CrannyID<ShortcutTag>
public typealias DropZoneID = CrannyID<DropZoneTag>
public typealias ScrollZoneID = CrannyID<ScrollZoneTag>
/// `CGDisplayCreateUUIDFromDisplayID` string: stable across reconnects and reboots (display IDs are not).
public typealias DisplayKey = CrannyID<DisplayTag>

// MARK: - Well-known identifiers (declared here so layers never import each other to name things)
// Static stored properties are not allowed in generic types, hence computed properties.

public extension CrannyID where Tag == ModuleTag {
    static var media: ModuleID { "media" }
    static var calendar: ModuleID { "calendar" }
    static var quickApps: ModuleID { "quickapps" }
    static var mirror: ModuleID { "mirror" }
    static var notes: ModuleID { "notes" }
    static var todos: ModuleID { "todos" }
    static var timer: ModuleID { "timer" }
    static var tray: ModuleID { "tray" }
    static var hud: ModuleID { "hud" }
    static var system: ModuleID { "system" }
    static var effects: ModuleID { "effects" }
    // Shell-owned settings namespaces (CoreSettings)
    static var general: ModuleID { "general" }
    static var appearance: ModuleID { "appearance" }
    static var displays: ModuleID { "displays" }
    static var nook: ModuleID { "nook" }
    static var activities: ModuleID { "activities" }
    static var gestures: ModuleID { "gestures" }
    static var keyboard: ModuleID { "keyboard" }
    static var onboarding: ModuleID { "onboarding" }
    static var updates: ModuleID { "updates" }
    static var shell: ModuleID { "shell" }
}

public extension CrannyID where Tag == WidgetTag {
    static var media: WidgetID { "media.player" }
    static var calendar: WidgetID { "calendar.agenda" }
    static var quickApps: WidgetID { "quickapps.launcher" }
    static var mirror: WidgetID { "mirror.camera" }
    static var notes: WidgetID { "notes.editor" }
    static var todos: WidgetID { "todos.list" }
    static var timer: WidgetID { "timer.clock" }
    static var airDrop: WidgetID { "tray.airdrop" }
    static var files: WidgetID { "tray.shelf" }
}

public extension CrannyID where Tag == ActivityTag {
    static var nowPlaying: ActivityID { "media.nowPlaying" }
    static var meetingSoon: ActivityID { "calendar.meetingSoon" }
    static var meetingNow: ActivityID { "calendar.meetingNow" }
    static var timerRunning: ActivityID { "timer.running" }
    static var timerDone: ActivityID { "timer.done" }
    static var charging: ActivityID { "system.charging" }
    static var lowBattery: ActivityID { "system.lowBattery" }
    static var bluetoothDevice: ActivityID { "system.bluetooth" }
    static var hud: ActivityID { "hud.level" }
    /// Shell-owned transient activity behind `NotchControl.flash(symbol:label:)` (onboarding "Hi", confirmations).
    static var flash: ActivityID { "shell.flash" }
}

public extension CrannyID where Tag == PageTag {
    static var nook: PageID { "nook" }
    static var tray: PageID { "tray" }
}

public extension CrannyID where Tag == DropZoneTag {
    /// Default target of any file drop that does not land on a specific zone.
    static var trayKeep: DropZoneID { "tray.keep" }
    static var airDrop: DropZoneID { "tray.airdrop" }
}

public extension CrannyID where Tag == SettingsPageTag {
    static var general: SettingsPageID { "general" }
    static var appearance: SettingsPageID { "appearance" }
    static var keyboard: SettingsPageID { "keyboard" }
    static var nookAndWidgets: SettingsPageID { "nook" }
    static var liveActivities: SettingsPageID { "activities" }
    static var hud: SettingsPageID { "hud" }
    static var gestures: SettingsPageID { "gestures" }
    static var media: SettingsPageID { "media" }
    static var calendar: SettingsPageID { "calendar" }
    static var shortcuts: SettingsPageID { "shortcuts" }
    static var tray: SettingsPageID { "tray" }
    static var permissions: SettingsPageID { "permissions" }
    static var about: SettingsPageID { "about" }
}

public extension CrannyID where Tag == ShortcutTag {
    static var openNook: ShortcutID { "shell.openNook" }
    static var openTray: ShortcutID { "tray.open" }
    static var newNote: ShortcutID { "notes.new" }
    static var startTimer: ShortcutID { "timer.start" }
    static var togglePin: ShortcutID { "shell.togglePin" }
    static var pauseActivities: ShortcutID { "shell.pauseActivities" }
}

/// Matched-geometry identifiers shared across layers (compact slot → peek row → widget).
public nonisolated enum MatchedID {
    public static let mediaArtwork = "media.artwork"
    public static let mediaVisualizer = "media.visualizer"
    public static let timerRing = "timer.ring"
}
```

### 3.4 Module plug-in: `FeatureModule` and `ModuleRegistry`

Lifecycle: the shell builds `CrannyServices`, creates the registry, calls `registry.register(M.self)` for every module in `CompositionRoot.modules`, registers its own contributions (`App/ShellContributions.swift`: Open Cranny/Toggle pin/Pause shortcuts, shell ⌘K commands, settings-pane commands), builds windows, then awaits `runLaunchHooks()` in registration order. `applicationWillTerminate` runs `runTerminateHooks()`.

Rules for `register(in:)`: create the module's models, contribute, set a port if the module provides one (`services.nowPlaying`, `services.tray`), and return. No file I/O, permission prompts, hardware, processes or network — do those in `onLaunch`. Read other modules' ports lazily (at use time), never in `register`.

```swift
// CrannyCore/Contracts/FeatureModule.swift
// How a module plugs into the app: one static entry point, contributions recorded in a registry.
import SwiftUI

/// Every layer-1 module exposes exactly one public type conforming to this (e.g. `TimerModule`).
/// The shell's composition root lists them; nothing else references module internals.
@MainActor public protocol FeatureModule {
    /// Namespace of the module's settings keys, storage directory and contributions.
    static var id: ModuleID { get }
    /// Called once at launch, before any window exists. Create the module's models, then contribute.
    /// Keep it cheap: no I/O, no permission prompts, no hardware. Start work in `registry.onLaunch`.
    static func register(in registry: ModuleRegistry)
}

/// Collects contributions. Owned by the shell; filled once at launch; read-only afterwards.
@MainActor public final class ModuleRegistry {
    public let services: CrannyServices

    public private(set) var widgets: [AnyNookWidget] = []
    public private(set) var pages: [PageDescriptor] = []
    public private(set) var activities: [RegisteredActivity] = []
    public private(set) var settingsPages: [SettingsPage] = []
    public private(set) var commandProviders: [any PaletteCommandProvider] = []
    public private(set) var shortcuts: [GlobalShortcut] = []
    public private(set) var captureTargets: [CaptureTarget] = []
    public private(set) var permissionUses: [PermissionUse] = []

    private var launchHooks: [@MainActor () async -> Void] = []
    private var terminateHooks: [@MainActor () -> Void] = []
    /// The module currently registering (set by `register(_:)`); used to attribute diagnostics.
    public private(set) var registeringModule: ModuleID?

    public init(services: CrannyServices) { self.services = services }

    /// Called by the composition root for each module, in order.
    public func register(_ module: any FeatureModule.Type) {
        registeringModule = module.id
        module.register(in: self)
        registeringModule = nil
    }

    // MARK: Contributions
    public func add<W: NookWidget>(widget: W) {
        precondition(self.widget(widget.id) == nil, "duplicate widget id \(widget.id)")
        widgets.append(AnyNookWidget(widget))
    }
    public func add(page: PageDescriptor) { pages.append(page) }
    public func add<A: LiveActivity>(activity: A, kind: ActivityKind,
                                     sample: (@MainActor () -> any LiveActivity)? = nil,
                                     options: (@MainActor () -> AnyView)? = nil) {
        precondition(activity.id == kind.id, "activity id must equal kind id")
        activities.append(RegisteredActivity(kind: kind, activity: activity, makeSample: sample, makeOptions: options))
    }
    /// Empty `namespaces` = the registering module (used by "Reset ‹Pane›…").
    public func add(settingsPage: SettingsPage) {
        var page = settingsPage
        if page.namespaces.isEmpty, let module = registeringModule { page.namespaces = [module] }
        settingsPages.append(page)
    }
    public func add(commands provider: any PaletteCommandProvider) { commandProviders.append(provider) }
    public func add(shortcut: GlobalShortcut) { shortcuts.append(shortcut) }
    public func add(captureTarget: CaptureTarget) { captureTargets.append(captureTarget) }
    public func declare(_ kind: PermissionKind, reason: String) {
        permissionUses.append(PermissionUse(kind: kind, module: registeringModule ?? .shell, reason: reason))
    }

    /// Runs after ALL modules registered and the services are wired (start observers, load files here).
    public func onLaunch(_ action: @escaping @MainActor () async -> Void) { launchHooks.append(action) }
    /// Runs from `applicationWillTerminate` (flush files, stop helpers). Must be fast and synchronous.
    public func onTerminate(_ action: @escaping @MainActor () -> Void) { terminateHooks.append(action) }

    // MARK: Shell side
    public func widget(_ id: WidgetID) -> AnyNookWidget? { widgets.first { $0.id == id } }
    public func activity(_ id: ActivityID) -> RegisteredActivity? { activities.first { $0.id == id } }
    public func runLaunchHooks() async { for hook in launchHooks { await hook() } }
    public func runTerminateHooks() { for hook in terminateHooks { hook() } }
}
```

### 3.5 Widgets

A widget renders **content only**; `CrannyNotchUI` wraps it in the card chrome (`.crannyCard(cells:)` or frameless, hover fill, ⋯ overflow menu with Options/Resize/Remove/Edit Layout, keyboard `focusSection`, VoiceOver container labelled `title`, the "Widgets" rotor). Every widget implements the five states of DESIGN.md §6.8 with `WidgetStateView`, adapts to `context.cells` per DESIGN.md §6.7 and honours `context.isPreview` (no hardware, no prompts, sample data allowed) and `context.redactsPersonalData`.

```swift
// CrannyCore/Contracts/Widget.swift
// A Nook widget: content for a card of N cells × 2 rows (DESIGN.md §6.3, §6.7, §6.8).
import SwiftUI

/// Allowed widths in grid cells (DESIGN.md §6.7). Height is always the grid height (2 rows; 3 in Notes focus).
public nonisolated struct WidgetSizes: Equatable, Sendable {
    public let minimum: Int
    public let preferred: Int
    public let maximum: Int
    public init(minimum: Int, preferred: Int, maximum: Int) {
        precondition(1 <= minimum && minimum <= preferred && preferred <= maximum, "invalid widget sizes")
        self.minimum = minimum; self.preferred = preferred; self.maximum = maximum
    }
    public func clamp(_ cells: Int) -> Int { min(max(cells, minimum), maximum) }
}

/// Everything a widget needs to lay itself out. Value type: cheap to diff, safe to pass around.
public nonisolated struct WidgetContext: Equatable, Sendable {
    /// Width in grid cells (already clamped to `sizes`).
    public var cells: Int
    /// 2, or 3 while the Nook is in a focus mode.
    public var rows: Int
    /// Size of the content area (card size minus card padding; the full card for frameless widgets).
    public var contentSize: CGSize
    /// The user is editing the layout (⌘E): show no live content that would fight the drag.
    public var isEditingLayout: Bool
    /// Keyboard focus is inside this widget, or it is the focused widget of a focus mode.
    public var isFocused: Bool
    /// Rendered on a Settings/onboarding stage or in `#Preview`: never start hardware (camera, audio tap),
    /// never prompt for permissions, never write user data. Sample data is allowed.
    public var isPreview: Bool
    /// Demo mode with redaction: replace personal text (event titles, note text) with neutral placeholders.
    public var redactsPersonalData: Bool

    public init(cells: Int, rows: Int = 2, contentSize: CGSize, isEditingLayout: Bool = false,
                isFocused: Bool = false, isPreview: Bool = false, redactsPersonalData: Bool = false) {
        self.cells = cells; self.rows = rows; self.contentSize = contentSize
        self.isEditingLayout = isEditingLayout; self.isFocused = isFocused
        self.isPreview = isPreview; self.redactsPersonalData = redactsPersonalData
    }
}

/// Implemented by feature modules (usually an `@Observable final class` holding its model).
/// The shell wraps `makeBody` in the card chrome (`crannyCard`, hover, overflow menu, focus section,
/// VoiceOver container labelled `title`) — widgets draw content only, never their own card.
@MainActor public protocol NookWidget: AnyObject {
    associatedtype Content: View
    associatedtype Options: View = EmptyView

    var id: WidgetID { get }
    /// Localized, sentence case ("To-dos"). Also the VoiceOver container label.
    var title: String { get }
    /// SF Symbol for the widget library and collapsed tabs (DESIGN.md §14.1 list only).
    var symbol: String { get }
    /// One localized line for the widget library.
    var summary: String { get }
    var sizes: WidgetSizes { get }
    /// `true` for widgets whose content IS the card (Mirror preview): no padding, no smoked fill.
    var isFrameless: Bool { get }

    @ViewBuilder func makeBody(context: WidgetContext) -> Content
    /// Per-widget options shown in a popover (Settings ▸ Layout & Widgets and the card's ⋯ menu).
    @ViewBuilder func makeOptions() -> Options
}

public extension NookWidget {
    var isFrameless: Bool { false }
}

public extension NookWidget where Options == EmptyView {
    func makeOptions() -> EmptyView { EmptyView() }
}

/// Type-erased widget stored by the registry.
@MainActor public final class AnyNookWidget: Identifiable {
    public let base: any NookWidget
    public var id: WidgetID { base.id }
    public var title: String { base.title }
    public var symbol: String { base.symbol }
    public var summary: String { base.summary }
    public var sizes: WidgetSizes { base.sizes }
    public var isFrameless: Bool { base.isFrameless }
    public let hasOptions: Bool
    private let body: @MainActor (WidgetContext) -> AnyView
    private let options: @MainActor () -> AnyView

    public init<W: NookWidget>(_ widget: W) {
        base = widget
        hasOptions = W.Options.self != EmptyView.self
        body = { AnyView(widget.makeBody(context: $0)) }
        options = { AnyView(widget.makeOptions()) }
    }
    public func makeBody(context: WidgetContext) -> AnyView { body(context) }
    public func makeOptions() -> AnyView { options() }
}

/// A full-width page in the Nook header provided by a module (the Tray page).
/// The Nook grid page and user pages are owned by the shell (`CoreSettings.pages`).
public struct PageDescriptor: Identifiable {
    public let id: PageID
    public let title: String
    public let symbol: String
    /// Sort key among module pages (the grid page "nook" always comes first).
    public let order: Int
    /// `micro` count badge in the header ("3"), nil = none. Read inside SwiftUI bodies (observable).
    public let badge: @MainActor () -> Int?
    public let makeView: @MainActor (WidgetContext) -> AnyView

    public init(id: PageID, title: String, symbol: String, order: Int,
                badge: @escaping @MainActor () -> Int? = { nil },
                makeView: @escaping @MainActor (WidgetContext) -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.order = order
        self.badge = badge; self.makeView = makeView
    }
}
```

### 3.6 Live activities

A module owns a **fixed set** of activity objects (each an `@Observable final class`) and flips `isActive`; the shell observes them and arbitrates (§4.6). `revision` is the "meaningful change" counter: it undoes a swipe-up dismissal and, if the kind peeks on change (or the priority is `.alert`), triggers one auto-peek. Transient activities set `expiresAt`. Each kind may provide a **sample** instance (sample data, independent of the real model) for the Settings "Simulate" chips and the onboarding stage, and an **options** view: extra rows shown under the activity in Settings ▸ Live Activities for keys the module owns (meeting lead time, low-battery thresholds…) — the shell-owned pane cannot import module settings enums. An activity names a **delight** (`.emberBurst`, `.chargeSweep`) instead of drawing it: feature modules cannot import `CrannyEffects`, so the shell schedules it (§4.6 step 7) and CrannyNotchUI draws it (§4.12).

```swift
// CrannyCore/Contracts/LiveActivity.swift
// Live activities: compact wings around the camera, the satellite, peek rows (DESIGN.md §9).
import SwiftUI

/// DESIGN.md §9.4. Lower raw value = more important. The user's order (Settings ▸ Live Activities)
/// only breaks ties *within* a class.
public nonisolated enum ActivityPriority: Int, Comparable, Codable, Sendable, CaseIterable {
    case hud = 0        // P0: transient, pre-empts everything for its lifetime
    case alert = 1      // P1: meeting soon, timer done, low battery, device connected, charging
    case ongoing = 2    // P2: meeting in progress, timer running, now playing
    case passive = 3    // P3: paused media
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Where the shell asks an activity to draw.
public nonisolated enum ActivityPlacement: Sendable, CaseIterable {
    case compactLeading     // left wing, content hugs the camera (trailing-aligned)
    case compactTrailing    // right wing, content hugs the camera (leading-aligned)
    case minimal            // 24u satellite circle: ONE glyph, ring or artwork
    case peekRow            // one 52-pt row: [visual 40] [title/subtitle] [≤ 3 controls]
}

/// Two-finger horizontal swipe over the compact/peek presentation of THIS activity (DESIGN.md §4.4).
public nonisolated enum ActivityGesture: Sendable, Equatable {
    case swipeLeft, swipeRight
}

/// Static description of an activity, shown in Settings ▸ Live Activities.
public nonisolated struct ActivityKind: Identifiable, Hashable, Sendable {
    public let id: ActivityID
    public let module: ModuleID
    public let title: String               // localized ("Now Playing")
    public let symbol: String
    public let defaultPriority: ActivityPriority
    public let isEnabledByDefault: Bool
    /// Whether "Peek on change" is offered for this kind, and its default.
    public let canPeekOnChange: Bool
    public let peeksOnChangeByDefault: Bool

    public init(id: ActivityID, module: ModuleID, title: String, symbol: String, defaultPriority: ActivityPriority,
                isEnabledByDefault: Bool = true, canPeekOnChange: Bool = false, peeksOnChangeByDefault: Bool = false) {
        self.id = id; self.module = module; self.title = title; self.symbol = symbol
        self.defaultPriority = defaultPriority; self.isEnabledByDefault = isEnabledByDefault
        self.canPeekOnChange = canPeekOnChange; self.peeksOnChangeByDefault = peeksOnChangeByDefault
    }
}

/// A one-shot visual played by CrannyNotchUI (CrannyEffects) on behalf of an activity (DESIGN.md §5.5).
/// Feature modules cannot import CrannyEffects, so they NAME the moment and the shell draws it.
public nonisolated enum DelightMoment: String, Sendable, Equatable, CaseIterable {
    case emberBurst     // timer done
    case chargeSweep    // charger connected: green sweep along the lower rim
    // Shell-driven (activities never return these):
    case songRipple     // track change while open: tide/aurora energy ripple
    case firstLight     // first open per session: light fills outward from the camera
    case gulp           // file caught: height −3 pt, spring back
}

/// A named action: VoiceOver custom action, keyboard/peek control, and the satellite/peek click targets.
public struct ActivityAction: Identifiable {
    public let id: String
    public let title: String               // localized ("Join meeting")
    public let symbol: String?
    public let perform: @MainActor () -> Void
    public init(id: String, title: String, symbol: String? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.symbol = symbol; self.perform = perform
    }
}

/// Implemented as an `@Observable final class` per activity (a module owns a FIXED set of them and
/// flips `isActive`). The shell observes the properties below; changing any of them re-arbitrates.
///
/// Rules (DESIGN.md §9.1–9.3): leading and trailing describe the SAME activity; one datum per side;
/// no free text in compact except tested `compactLabel` abbreviations; at most ONE interactive control
/// in compact (Join); peek rows have ≤ 3 controls with ≥ 28-pt hit targets.
@MainActor public protocol LiveActivity: AnyObject {
    associatedtype Leading: View
    associatedtype Trailing: View
    associatedtype Minimal: View
    associatedtype Row: View

    var id: ActivityID { get }
    /// Shown at all (still subject to user toggles, pause, dismissal and full-screen policy).
    var isActive: Bool { get }
    var priority: ActivityPriority { get }
    var slot: SlotWidth { get }
    /// Increment on every MEANINGFUL change (new track, last minute, meeting started, device connected).
    /// Undoes a swipe-up dismissal and, if the kind peeks on change (or priority is `.alert`), auto-peeks once.
    var revision: Int { get }
    /// Transient activities (charging 2.6 s, device connected, HUD 1.5 s) set this; the shell drops them after.
    var expiresAt: Date? { get }
    /// Light-layer palette while this is the top activity (`.timer`, `.charging`, album palette…).
    var palette: AmbientPalette? { get }
    /// Click on compact/peek opens the Nook focused on this widget.
    var opensWidget: WidgetID? { get }
    /// Floating-island displays only: optional label in the middle (`compactLabel`, ≤ 160 pt), e.g. track title.
    var middleLabel: String? { get }
    var accessibilityLabel: String { get }      // "Now playing: Midnight Window by The Example Band"
    var accessibilityValue: String? { get }     // "2 minutes 11 seconds left"
    var actions: [ActivityAction] { get }
    /// Played once by CrannyNotchUI when `revision` changes while this activity is visible (§5.5 caps apply).
    var delight: DelightMoment? { get }

    /// Return true if handled (Now Playing: next/previous track). Called on the main actor.
    func handle(_ gesture: ActivityGesture) -> Bool

    @ViewBuilder func compactLeading() -> Leading
    @ViewBuilder func compactTrailing() -> Trailing
    @ViewBuilder func minimal() -> Minimal
    @ViewBuilder func peekRow() -> Row
}

public extension LiveActivity {
    var expiresAt: Date? { nil }
    var palette: AmbientPalette? { nil }
    var opensWidget: WidgetID? { nil }
    var middleLabel: String? { nil }
    var accessibilityValue: String? { nil }
    var actions: [ActivityAction] { [] }
    var delight: DelightMoment? { nil }
    func handle(_ gesture: ActivityGesture) -> Bool { false }

    /// Type-erased view for a placement; callable on `any LiveActivity`.
    func view(for placement: ActivityPlacement) -> AnyView {
        switch placement {
        case .compactLeading: AnyView(compactLeading())
        case .compactTrailing: AnyView(compactTrailing())
        case .minimal: AnyView(minimal())
        case .peekRow: AnyView(peekRow())
        }
    }
}

/// What the registry stores for each activity.
public struct RegisteredActivity: Identifiable {
    public let kind: ActivityKind
    public let activity: any LiveActivity
    /// A self-contained instance with sample data (Settings "Simulate" chips, onboarding stage). Never
    /// touches the module's real model. nil = the kind cannot be simulated.
    public let makeSample: (@MainActor () -> any LiveActivity)?
    /// Extra rows under this activity in Settings ▸ Live Activities (module-owned keys, e.g. meeting lead time).
    public let makeOptions: (@MainActor () -> AnyView)?
    public var id: ActivityID { kind.id }
}
```

Calling `activity.view(for:)` on `any LiveActivity` from another module was verified in `CrannyNotchUI`'s skeleton.

### 3.7 Other contributions

```swift
// CrannyCore/Contracts/Contributions.swift
// Everything else a module can contribute: settings panes, ⌘K commands, global shortcuts,
// type-to-capture targets and the permissions it may ask for.
import SwiftUI

// MARK: - Settings pages

/// Sidebar group in the Settings window (DESIGN.md §11.1).
public nonisolated enum SettingsGroup: Int, Comparable, Sendable {
    case top = 0, notch = 1, features = 2, bottom = 3
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The system colour behind the white glyph of a sidebar icon (20 × 20, r 5).
public nonisolated enum SettingsIconTint: String, Sendable {
    case gray, purple, indigo, blue, pink, teal, orange, red, green
    public var color: Color {
        switch self {
        case .gray: .gray
        case .purple: .purple
        case .indigo: .indigo
        case .blue: .blue
        case .pink: .pink
        case .teal: .teal
        case .orange: .orange
        case .red: .red
        case .green: .green
        }
    }
}

/// Which notch state the Settings preview stage auto-selects for a pane (DESIGN.md §11.2).
public nonisolated enum PreviewStageState: String, Sendable, CaseIterable {
    case closed, activity, peek, open, hud
}

public struct SettingsPage: Identifiable {
    public let id: SettingsPageID
    public let title: String                 // localized
    public let symbol: String
    public let tint: SettingsIconTint
    public let group: SettingsGroup
    public let order: Int
    /// Localized search terms. Shell panes are indexed by their row labels; a MODULE pane is an opaque view,
    /// so it must list its row labels here too ("volume" → HUD, "lead time" → Calendar).
    public let keywords: [String]
    /// Settings namespaces reset by "Reset ‹Pane›…". Empty = the registering module (filled by the registry).
    public var namespaces: [ModuleID]
    /// nil = no preview stage (Permissions, About).
    public let previewState: PreviewStageState?
    public let makeView: @MainActor () -> AnyView

    public init(id: SettingsPageID, title: String, symbol: String, tint: SettingsIconTint, group: SettingsGroup,
                order: Int, keywords: [String] = [], namespaces: [ModuleID] = [], previewState: PreviewStageState? = .open,
                makeView: @escaping @MainActor () -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.tint = tint; self.group = group
        self.order = order; self.keywords = keywords; self.namespaces = namespaces
        self.previewState = previewState; self.makeView = makeView
    }
}

// MARK: - Command palette (⌘K)

public struct PaletteCommand: Identifiable {
    public let id: CommandID
    public let title: String                 // "Start 25-minute timer"
    public let kind: String                  // "Timer" (caption, tertiary)
    public let symbol: String
    public let keywords: [String]
    public let shortcut: KeyCombo?
    public let perform: @MainActor () -> Void
    public init(id: CommandID, title: String, kind: String, symbol: String, keywords: [String] = [],
                shortcut: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.kind = kind; self.symbol = symbol
        self.keywords = keywords; self.shortcut = shortcut; self.perform = perform
    }
}

/// Queried on every keystroke in the palette: must be fast (in-memory filtering only).
@MainActor public protocol PaletteCommandProvider: AnyObject {
    func commands(matching query: String) -> [PaletteCommand]
}

// MARK: - Keyboard

/// A key combination in Carbon terms (virtual key code + modifiers) so the shell can register it
/// with `RegisterEventHotKey` (no Accessibility permission needed; verified on macOS 27).
public nonisolated struct KeyCombo: Codable, Hashable, Sendable {
    public nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }
    public var keyCode: UInt16          // kVK_* (Carbon HIToolbox/Events.h)
    public var modifiers: Modifiers
    /// Display string for key caps ("⌃⌥N"), built by the caller from the current keyboard layout.
    public var display: String
    public init(keyCode: UInt16, modifiers: Modifiers, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
    }
    /// ⌃⌥N — DESIGN.md decision #11 (⌥⌘N is Finder's New Smart Folder; ⌃⌥Space switches input sources).
    public static let openNookDefault = KeyCombo(keyCode: 45 /* kVK_ANSI_N */, modifiers: [.control, .option], display: "⌃⌥N")
}

/// A system-wide shortcut contributed by a module ("New note"). The shell registers it and stores the
/// user's binding in `CoreSettings.shortcuts`; `defaultCombo == nil` means "off until the user sets one".
public struct GlobalShortcut: Identifiable {
    public let id: ShortcutID
    public let title: String
    public let defaultCombo: KeyCombo?
    public let perform: @MainActor () -> Void
    public init(id: ShortcutID, title: String, defaultCombo: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.defaultCombo = defaultCombo; self.perform = perform
    }
}

/// Type-to-capture (DESIGN.md §7.5): if the Nook was opened by the keyboard and nothing is focused, the
/// first printable keys go to the target the user chose (Notes or To-dos).
public struct CaptureTarget: Identifiable {
    public let id: String                   // "notes", "todos"
    public let title: String
    public let symbol: String
    /// Receives the first characters; must create the item, focus its editor and return the widget to focus.
    public let capture: @MainActor (String) -> WidgetID
    public init(id: String, title: String, symbol: String, capture: @escaping @MainActor (String) -> WidgetID) {
        self.id = id; self.title = title; self.symbol = symbol; self.capture = capture
    }
}

/// A permission a module may request, with its localized one-line reason (Permissions pane, onboarding).
public nonisolated struct PermissionUse: Hashable, Sendable {
    public let kind: PermissionKind
    public let module: ModuleID
    public let reason: String               // "Show your events in Cranny. Cranny never edits or uploads them."
    public init(kind: PermissionKind, module: ModuleID, reason: String) {
        self.kind = kind; self.module = module; self.reason = reason
    }
}
```

### 3.8 Notch context and environment

`CrannyNotchUI` sets these at the canvas root (and the Settings/onboarding stages set `isPreview`). Feature views read `@Environment(\.notchContext)` (phase, page, focused widget, hints, redaction) and use `.notchMatched(MatchedID.mediaArtwork)` for elements that travel between compact, peek and widget (DESIGN.md §4.3). Zones are found through `@Environment(\.notchZones)`.

```swift
// CrannyCore/Contracts/NotchContext.swift
// Read-only facts about the notch a view is rendered in. Set by CrannyNotchUI at the canvas root.
import SwiftUI

/// The visible presentation (DESIGN.md §3.3, ARCHITECTURE.md §4).
public nonisolated enum NotchPhase: String, Sendable, Codable {
    case hidden     // nothing drawn (full-screen policy, excluded app, locked, idle-hidden handle)
    case idle       // closed: exactly the hardware cutout, or the handle on displays without a notch
    case breath     // hover dwell acknowledged (+12u wide, +3u tall), nothing open yet
    case compact    // a live activity in the wings (+ optional satellite)
    case peek       // compact row + 52-pt rows below
    case open       // the Nook
}

public nonisolated enum OpenReason: String, Sendable, Codable {
    case hover, click, keyboard, swipe, drag, activity, programmatic, tutorial
}

public nonisolated struct NotchContext: Equatable, Sendable {
    public var phase: NotchPhase = .idle
    public var layout: NotchLayout = NotchLayout(metrics: .reference)
    public var display: DisplayKey?
    public var openReason: OpenReason?
    public var page: PageID?
    public var focusedWidget: WidgetID?
    /// Settings preview stage, onboarding stage or `#Preview`: no side effects.
    public var isPreview = false
    /// Demo mode with "Redact calendar titles".
    public var redactsPersonalData = false
    /// Hold-⌘ hints are visible: show `KeyCap`s next to commands.
    public var showsCommandHints = false
    /// The last interaction was the keyboard: draw `crannyFocusRing`s.
    public var keyboardNavigation = false
    public init() {}
}

/// Named coordinate space of the fixed canvas (top-left origin). Zones report frames in it.
public nonisolated enum NotchCoordinateSpace {
    public static let name = "cranny.canvas"
}

public extension EnvironmentValues {
    @Entry var notchContext = NotchContext()
    /// Namespace for matched geometry between compact, peek and widget presentations (`MatchedID`).
    @Entry var notchNamespace: Namespace.ID? = nil
    /// Drop / scroll zones of the canvas this view is in. nil on stages that do not take input.
    @Entry var notchZones: NotchZones? = nil
}

public extension View {
    /// `matchedGeometryEffect` in the canvas namespace; a no-op outside a notch canvas.
    func notchMatched(_ id: String, isSource: Bool = true) -> some View {
        modifier(NotchMatchedModifier(id: id, isSource: isSource))
    }
}

struct NotchMatchedModifier: ViewModifier {
    @Environment(\.notchNamespace) private var namespace
    let id: String
    let isSource: Bool
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}
```

### 3.9 Services hub and ports

`CrannyServices` is created by the shell and reaches every module through `registry.services`. Ports are protocols; their implementations live in the shell (`NotchControl`, `SystemEnvironment`, `AppControl`) or in a feature module (`NowPlayingSource` ← CrannyMedia, `TrayIntake` ← CrannyTray). The media value types (`NowPlaying`, `MediaCommand`, `ShuffleMode`, `RepeatMode`) are R2's verified models, moved into Core so the shell and other layers can use them. Public test doubles (`CrannyServices.preview()`, `PreviewNotchControl`, `PreviewSystemEnvironment`, `PreviewAppControl`) make every module testable and previewable alone.

```swift
// CrannyCore/Services/Ports.swift
// Cross-layer contracts. Implemented by the shell (NotchControl, SystemEnvironment, AppControl) or by a
// feature module (NowPlayingSource ← CrannyMedia, TrayIntake ← CrannyTray). Consumers never import the
// implementing module; they read `registry.services.*`.
import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NotchControl (implemented by CrannyAppShell)

public nonisolated enum NotchEvent: Sendable, Equatable {
    case opened(OpenReason)
    case closed
    case pinned(Bool)
    case pageChanged(PageID)
    case filesCaught(count: Int)
    case activityGesture(ActivityID, ActivityGesture)
    case commandHintsShown
    case paletteOpened
}

@MainActor public protocol NotchControl: AnyObject {
    /// Opens on the pointer's display. `focus` scrolls/highlights a widget and gives it keyboard focus.
    func open(page: PageID?, focus: WidgetID?, reason: OpenReason)
    func close()
    func togglePinned()
    /// Keeps the Nook open while `true` for `reason` (e.g. "notes.editing"). Every `true` needs a `false`.
    func setHoldOpen(_ hold: Bool, reason: String)
    /// Focus mode: the shape resizes to all columns × 3 rows around one widget (Notes). nil ends it.
    func setFocusMode(_ widget: WidgetID?)
    /// Asks for a one-off peek of an activity on the pointer's display (respects pause/full-screen policy).
    func requestPeek(_ activity: ActivityID)
    /// Makes the panel key without activating the app (typing). Released automatically on close.
    func requestKeyboardFocus()
    /// Appearance ▸ Notch fit is being dragged: freeze the real notch in hover and draw the 1-px outline.
    func setCalibrationOverlay(_ visible: Bool)
    /// The current shape in AppKit screen coordinates on the pointer's display (tutorial bubble anchor).
    func shapeFrameOnScreen() -> CGRect?
    /// AirDrop from an on-screen anchor window, re-activating the previous app afterwards (R3 §7).
    func presentAirDrop(_ urls: [URL]) async -> Bool
    /// Share picker (activates Cranny first, R3 §7).
    func presentSharePicker(_ urls: [URL])
    /// Shows a transient P1 compact activity (glyph + short label, 2.6 s) on the pointer display — onboarding
    /// "Hi", "Path copied". Ignored while paused or hidden. `label` is already localized; ≤ 12 characters.
    func flash(symbol: String, label: String)
    @discardableResult func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID
    func removeEventObserver(_ id: UUID)
}

// MARK: - SystemEnvironment (implemented by CrannyAppShell)

/// Observable facts about the machine. Read inside SwiftUI bodies or `observe(_:onChange:)`.
@MainActor public protocol SystemEnvironment: AnyObject, Observable {
    var isScreenLocked: Bool { get }
    var areDisplaysAsleep: Bool { get }
    var isLowPowerMode: Bool { get }
    var thermalState: ProcessInfo.ThermalState { get }
    var isOnBattery: Bool { get }
    var frontmostBundleID: String? { get }
    /// A full-screen app (or an excluded app) is in front on the pointer's display.
    var isFullScreenInFront: Bool { get }
    var isDemoMode: Bool { get }
    var areLiveActivitiesPaused: Bool { get }
    /// Built-in or Magic Trackpad present (onboarding gesture step, haptics copy).
    var hasTrackpad: Bool { get }
}

public extension SystemEnvironment {
    /// The energy budget for an effect drawn in an open Nook (DESIGN.md §4.7).
    func effectBudget(isOpen: Bool, isOnScreen: Bool, reduceMotion: Bool) -> EffectBudget {
        EffectBudget(isOpen: isOpen, onScreen: isOnScreen && !isScreenLocked && !areDisplaysAsleep,
                     lowPower: isLowPowerMode || thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue,
                     fullScreenFront: isFullScreenInFront, reduceMotion: reduceMotion, onBattery: isOnBattery)
    }
}

// MARK: - AppControl (implemented by CrannyAppShell; used by Settings, Onboarding, menu bar)

public nonisolated enum LoginItemState: Sendable, Equatable { case enabled, disabled, requiresApproval, unavailable(String) }
public nonisolated enum UpdateState: Sendable, Equatable {
    case idle, checking, upToDate
    case available(version: String, notesURL: URL)
    case failed(String)
}
public nonisolated enum ShortcutState: Sendable, Equatable { case off, registered, conflict }

@MainActor public protocol AppControl: AnyObject, Observable {
    var loginItem: LoginItemState { get }
    func setLaunchAtLogin(_ enabled: Bool)
    var update: UpdateState { get }
    func checkForUpdates()
    func shortcutState(_ id: ShortcutID) -> ShortcutState
    /// Stores the binding (nil = off) and re-registers it; returns the resulting state.
    @discardableResult func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState
    func openSettings(_ page: SettingsPageID?)
    func showWelcome()
    func startTutorial()
    /// Plays a preview stage state on the real notch for 5 s ("Show on Notch").
    func showOnNotch(_ state: PreviewStageState)
    func resetAllSettings()
    func quit()
}

// MARK: - Media (implemented by CrannyMedia)

/// Anchored position: `elapsed` is valid at `timestamp`; interpolate locally, never poll the provider.
public nonisolated struct NowPlaying: Equatable, Sendable {
    public var bundleID: String?
    public var parentBundleID: String?
    public var appName: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?        // nil = live stream
    public var elapsed: TimeInterval
    public var timestamp: Date
    public var rate: Double
    public var isPlaying: Bool
    public var itemID: String?
    public var artworkID: String?
    public var shuffle: ShuffleMode?
    public var repeatMode: RepeatMode?
    public var isMusicApp: Bool

    public init(bundleID: String?, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsed: TimeInterval = 0, timestamp: Date = Date(),
                rate: Double = 1, isPlaying: Bool, itemID: String? = nil) {
        self.bundleID = bundleID; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.elapsed = elapsed; self.timestamp = timestamp
        self.rate = rate; self.isPlaying = isPlaying; self.itemID = itemID; self.isMusicApp = false
    }
    public func position(at now: Date = Date()) -> TimeInterval {
        let speed = rate > 0 ? rate : 1
        let p = isPlaying ? elapsed + now.timeIntervalSince(timestamp) * speed : elapsed
        return max(0, duration.map { min(p, $0) } ?? p)
    }
    /// Identity for "track changed" and the artwork/palette cache.
    public var trackKey: String { itemID ?? [bundleID ?? "", title, artist ?? "", album ?? ""].joined(separator: "|") }
}

public nonisolated enum ShuffleMode: Int, Codable, Sendable { case off = 1, albums = 2, tracks = 3 }
public nonisolated enum RepeatMode: Int, Codable, Sendable { case off = 1, one = 2, all = 3 }

public nonisolated enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, skipForward15, skipBackward15
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

@MainActor public protocol NowPlayingSource: AnyObject, Observable {
    var nowPlaying: NowPlaying? { get }
    var artwork: CGImage? { get }
    /// `AmbientPalette.extract(from:)` of the artwork (cached per track); nil = no artwork yet.
    var palette: AmbientPalette? { get }
    /// Increments on every new track (debounced, playing only, not on the first snapshot after launch).
    var trackChangeCount: Int { get }
    /// 0…1 RMS (60 ms attack / 300 ms release) while the Live visualizer runs; otherwise 0.
    var audioEnergy: Double { get }
    @discardableResult func send(_ command: MediaCommand) async -> Bool
}

// MARK: - Tray (implemented by CrannyTray)

@MainActor public protocol TrayIntake: AnyObject, Observable {
    /// Header badge on the Tray page.
    var itemCount: Int { get }
    /// The drag "catch" state (DESIGN.md §8.3): Keep in Tray, AirDrop and up to 3 pinned pipelines that
    /// accept `types`, each declared with `.crannyDropZone`. Shown inside the open shape by CrannyNotchUI.
    func catchView(for types: [UTType]) -> AnyView
    /// Drop that no visible zone took (`NotchZones.performDrop` returned false, e.g. the catch view had not
    /// appeared yet): keep in the tray. The shell calls it; nothing else does.
    func accept(_ payload: DropPayload) async -> Bool
}
```

```swift
// CrannyCore/Services/CrannyServices.swift
// The service hub every module receives through `ModuleRegistry.services`.
import Foundation
import Observation

@MainActor @Observable public final class CrannyServices {
    public let settings: SettingsStore
    public let permissions: PermissionsCenter
    public let haptics: Haptics
    public let paths: AppPaths
    public let notch: any NotchControl
    public let environment: any SystemEnvironment
    public let app: any AppControl
    /// Set by CrannyMedia in `register(in:)`. Read lazily (at use time), never cache in `register`.
    public var nowPlaying: (any NowPlayingSource)?
    /// Set by CrannyTray in `register(in:)`.
    public var tray: (any TrayIntake)?

    public init(settings: SettingsStore, permissions: PermissionsCenter, haptics: Haptics, paths: AppPaths,
                notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl) {
        self.settings = settings; self.permissions = permissions; self.haptics = haptics; self.paths = paths
        self.notch = notch; self.environment = environment; self.app = app
    }

    /// In-memory settings, temporary paths and recording doubles: for `#Preview` and unit tests.
    public static func preview(environment: PreviewSystemEnvironment = PreviewSystemEnvironment()) -> CrannyServices {
        let defaults = UserDefaults(suiteName: "cranny.preview.\(UUID().uuidString)") ?? .standard
        let settings = SettingsStore(defaults: defaults)
        return CrannyServices(settings: settings, permissions: PermissionsCenter(),
                              haptics: Haptics(isEnabled: { false }), paths: .temporary(),
                              notch: PreviewNotchControl(), environment: environment, app: PreviewAppControl())
    }
}

// MARK: - Test doubles (public: used by every module's tests and #Previews)

@MainActor public final class PreviewNotchControl: NotchControl {
    /// Every call, in order ("open(nook,timer.clock,click)", "close", "hold(true,notes.editing)").
    public private(set) var calls: [String] = []
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]
    public init() {}
    public func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        calls.append("open(\(page?.rawValue ?? "-"),\(focus?.rawValue ?? "-"),\(reason.rawValue))")
    }
    public func close() { calls.append("close") }
    public func togglePinned() { calls.append("togglePinned") }
    public func setHoldOpen(_ hold: Bool, reason: String) { calls.append("hold(\(hold),\(reason))") }
    public func setFocusMode(_ widget: WidgetID?) { calls.append("focus(\(widget?.rawValue ?? "-"))") }
    public func requestPeek(_ activity: ActivityID) { calls.append("peek(\(activity))") }
    public func requestKeyboardFocus() { calls.append("key") }
    public func setCalibrationOverlay(_ visible: Bool) { calls.append("calibration(\(visible))") }
    public func shapeFrameOnScreen() -> CGRect? { nil }
    public func presentAirDrop(_ urls: [URL]) async -> Bool { calls.append("airdrop(\(urls.count))"); return true }
    public func presentSharePicker(_ urls: [URL]) { calls.append("share(\(urls.count))") }
    public func flash(symbol: String, label: String) { calls.append("flash(\(symbol))") }
    public func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    public func removeEventObserver(_ id: UUID) { observers[id] = nil }
    /// Tests: simulate the shell emitting an event.
    public func emit(_ event: NotchEvent) { for o in observers.values { o(event) } }
}

@MainActor @Observable public final class PreviewSystemEnvironment: SystemEnvironment {
    public var isScreenLocked = false
    public var areDisplaysAsleep = false
    public var isLowPowerMode = false
    public var thermalState = ProcessInfo.ThermalState.nominal
    public var isOnBattery = false
    public var frontmostBundleID: String? = nil
    public var isFullScreenInFront = false
    public var isDemoMode = false
    public var areLiveActivitiesPaused = false
    public var hasTrackpad = true
    public init() {}
}

@MainActor @Observable public final class PreviewAppControl: AppControl {
    public var loginItem: LoginItemState = .disabled
    public var update: UpdateState = .idle
    public var shortcuts: [ShortcutID: KeyCombo] = [:]
    public init() {}
    public func setLaunchAtLogin(_ enabled: Bool) { loginItem = enabled ? .enabled : .disabled }
    public func checkForUpdates() { update = .upToDate }
    public func shortcutState(_ id: ShortcutID) -> ShortcutState { shortcuts[id] == nil ? .off : .registered }
    public func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { shortcuts[id] = combo; return shortcutState(id) }
    public func openSettings(_ page: SettingsPageID?) {}
    public func showWelcome() {}
    public func startTutorial() {}
    public func showOnNotch(_ state: PreviewStageState) {}
    public func resetAllSettings() {}
    public func quit() {}
}
```

### 3.10 Input: zones and swipes (sources in A.3–A.4)

- `NotchZones` (`@MainActor @Observable`, one per canvas): views declare **drop zones** (`.crannyDropZone(id, accepts:, perform:)`) and **scroll zones** (`.crannyScrollZone(id, axis:, onUpdate:)`); each modifier reports its frame in the named coordinate space `NotchCoordinateSpace.name` via `onGeometryChange` (back-deployed to macOS 13 [SDK]) and unregisters on disappear. The shell's root `NSView` calls `dragUpdated(at:types:)`, `performDrop(_:fallback:)` (fallback `.trayKeep`), `dragEnded()` and `scroll(_:at:)`. Views highlight with `zones.armedDropZone == id`. The innermost accepting zone wins.
- `SwipeTracker` (pure `struct`): feed `ScrollSample`s (mirrors `NSEvent` phase/momentum/precise/natural-scrolling fields; the phase type is `SwipePhase` — it was `ScrollPhase`, which is ambiguous with `SwiftUI.ScrollPhase` in every file that imports both [VERIFIED compile error]); it locks to an axis at 1.6×, ignores momentum and phase-less wheels, emits `.tracking(axis, translation)` for rubber-banding, fires **one** `.committed(direction, velocity)` per touch sequence while the finger is down (so the `.alignment` haptic is felt) at `GestureSpec` distances (40 horizontal, 24 down, 18 up; ÷ sensitivity) or on release above the velocity threshold, and `.cancelled` when released short (snap back). Unit-tested [VERIFIED].

### 3.11 Settings (sources in A.1–A.2)

- `SettingKey<Value: Codable & Sendable & Equatable>(module, name, default:)`; id `"<module>.<name>"`; stored as JSON `Data` under **`cranny.<module>.<name>`** in `UserDefaults.standard` (domain `app.cranny.Cranny`). Writing the default removes the key.
- `SettingsStore` (`@MainActor`): `subscript(key)`, `binding(_:)`, `isDefault(_:)`, `reset(_:)`, `reset(module:)`, `resetAll()`, `snapshot()` / `restore(_:)` (the 10-s Undo of Reset All). One `@Observable` box per key, so a view is invalidated only by the keys it reads; reset and restore reload every live box from disk. Undecodable values fall back to the default and log. Tests inject `UserDefaults(suiteName:)`. Settings apply instantly (D14). Side effects of settings (hot keys, login item is *not* a setting, display panels) are driven by observing keys (`observe(_:onChange:)`), never by imperative calls from Settings, so Reset/Undo/Onboarding presets all just write keys.
- **Ownership:** shell-level keys are in `CoreSettings` (A.2). Each module declares its keys in `public enum <Module>Settings` in its own target (lists in §10); every value type used in a public key is `public` too (listed under "Public types"). A key a module owns but that DESIGN.md shows in a shell pane is surfaced through `registry.add(activity:…, options:)` (Live Activities) or `NookWidget.makeOptions()` (Layout & Widgets), never by importing the module. Namespaces = `ModuleID`s (`general`, `appearance`, `displays`, `nook`, `activities`, `gestures`, `keyboard`, `onboarding`, `updates`, plus one per module). **Never rename a key or change its type**; add a new key and migrate in `onLaunch`.
- Content is not settings: notes, to-dos, tray items and timer state are JSON files under `AppPaths` (§3.13). "Reset All Settings" keeps them.

### 3.12 Permissions (source in A.5)

`PermissionsCenter` (`@MainActor @Observable`) is the only code that queries or requests TCC. Kinds: `.accessibility`, `.calendar`, `.camera`, `.bluetooth`, `.systemAudioRecording`, `.automation(bundleID:)`. `status(_:)` never prompts; `request(_:)` shows the system prompt where one exists (Accessibility: prompt + 1.5-s polling for 2 min; Calendar: `requestFullAccessToEvents`; Camera: `requestAccess(for: .video)`; Bluetooth: a short-lived `CBCentralManager`; Automation: `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)` off the main thread; System Audio Recording: no API — CrannyMedia reports what it observed with `record(_:for:)`). `openSystemSettings(_:)` deep-links (scheme verified; anchors on 27 [UNVERIFIED]). Modules call `request` only from their widget's inline "needs permission" state or from onboarding/Settings rows, and declare every kind they may request with `registry.declare(_:reason:)`. The Automation probe and Carbon hot keys were run on this Mac: `AEDeterminePermissionToAutomateTarget` returns −600 when the target isn't running [VERIFIED].

### 3.13 Platform utilities (sources in A.6–A.7)

| API | Use |
|---|---|
| `Log.logger(.timer)` (`os.Logger`, subsystem `app.cranny.Cranny`, categories in `LogCategory`) | `private let log = Log.logger(.timer)` at file scope; user data with `privacy: .private`. |
| `Haptics.play(.alignment / .levelChange / .generic)` | Honors Settings ▸ Gestures ▸ Haptic feedback; never for hover, peek or arrivals. |
| `AppPaths.live.directory(for: .notes)` | `~/Library/Application Support/app.cranny.Cranny/<module>/` (created on demand); `cacheDirectory(for:)`; `AppPaths.temporary()` for tests. |
| `JSONFileStore<Value>` (actor) | Atomic JSON documents; corrupt files are moved aside and the default is used. |
| `observe(_:onChange:) -> ObservationToken` | Observation outside SwiftUI on macOS 14 (`Observations` is macOS 26+). Keep the token. |
| `Debouncer(delay:)` | Trailing debounce (note autosave, rebuild after settings changes). |
| `ProcessRunner.run(_:_:)` (`@concurrent`) | `/usr/bin/shortcuts`, `/usr/bin/ditto`… drains both pipes, explicit minimal environment, task cancellation terminates the process. |
| `AppInfo.current()`, `SemanticVersion` | Version display and the GitHub Releases comparison (pre-release suffix sorts before the release). |

### 3.14 Shared components catalogue

| Need | Component | From |
|---|---|---|
| Shape + clip + keyline + elevation + optional underglow/glass | `NotchSurface` | DESIGN App. A |
| Wings around the camera | `CompactSlots` | DESIGN App. A |
| Card | `.crannyCard(cells:hovered:frameless:)` (applied by NotchUI, not by widgets) | DESIGN App. A |
| Icon button (plain / filled / prominent) | `CrannyIconButtonStyle` | DESIGN App. A |
| Capsule / chip button (pipeline chips, Join, presets) | `CrannyChipButtonStyle(tint:prominent:)` | A.8 |
| Level / progress bar, HUD bar | `LevelBar` | DESIGN App. A |
| Interactive scrubber (drag, hover 4→6 pt, VoiceOver adjustable) | `Scrubber` | A.8 |
| Ring | `ProgressRing` | DESIGN App. A |
| Key caps (hold-⌘ hints, palette) | `KeyCap` | DESIGN App. A |
| Drop target visuals | `DropZone` (+ `.crannyDropZone` for behaviour) | DESIGN App. A + 3.10 |
| Empty / needs permission / loading / error | `WidgetStateView` | A.8 |
| The single permitted marquee (track title after 1.5 s hover) | `MarqueeText` | A.8 |
| Focus ring | `.crannyFocusRing(_:radius:)` | DESIGN App. A |
| Typography | `.crannyFont(_:)` | DESIGN §2.2 |
| Motion | `theme.animation(.open)`, `AnyTransition.crannyContent/crannySlot/crannyTab`, `CrannyMotion.rubberBand/release/stagger` | DESIGN §4 |

### 3.15 Isolation and Sendable map

| Kind | Types | Isolation |
|---|---|---|
| Values (thread-safe, persistable) | `CrannyID`, `WidgetSizes`, `WidgetContext`, `ActivityPriority`, `ActivityKind`, `ActivityPlacement`, `ActivityGesture`, `KeyCombo`, `PermissionUse`, `PermissionKind`, `PermissionStatus`, `NotchPhase`, `OpenReason`, `NotchContext`, `NotchEvent`, `NowPlaying`, `MediaCommand`, `ShuffleMode`, `RepeatMode`, `DropPayload`, `ScrollSample`, `SwipePhase`, `SwipeUpdate`, `SwipeTracker`, `DelightMoment`, `SettingKey`, `SettingsStore.Snapshot`, every `CoreSettings` value type, every DESIGN.md token type, `AmbientPalette`, `EffectBudget`, `AppPaths`, `AppInfo`, `SemanticVersion`, `ProcessOutput`, `LoginItemState`, `UpdateState`, `ShortcutState`, `HapticPattern`, `LogCategory` | `nonisolated`, `Sendable` |
| Main-actor services | `CrannyServices`, `ModuleRegistry`, `SettingsStore`, `PermissionsCenter`, `Haptics`, `NotchZones`, `AnyNookWidget`, `ObservationToken`, `Debouncer`, test doubles | `@MainActor` (Sendable by isolation) |
| Main-actor protocols | `FeatureModule`, `NookWidget`, `LiveActivity`, `PaletteCommandProvider`, `NotchControl`, `SystemEnvironment`, `AppControl`, `NowPlayingSource`, `TrayIntake` | `@MainActor`; the observable ones refine `Observable` |
| Closure-carrying descriptors | `PageDescriptor`, `SettingsPage`, `PaletteCommand`, `GlobalShortcut`, `CaptureTarget`, `ActivityAction`, `RegisteredActivity` | non-Sendable structs with `@MainActor` closures; created and read on the main actor only |
| Actors | `JSONFileStore` | own actor |
| Off-main entry points | `ProcessRunner.run` (`@concurrent`), `PermissionsCenter` Automation probe (`@concurrent`) | global executor |

### 3.16 Cross-module communication matrix

| Need | Provider → consumer | Mechanism |
|---|---|---|
| Album accent for the theme, album light, energy for effects | Media → Shell/NotchUI/Effects | `services.nowPlaying` (`palette.accent`, `palette`, `audioEnergy`) → `AccentResolver`, `AmbientPalette`, `EffectBudget` |
| Track swipe on compact/peek | Shell → Media | `activity.handle(.swipeLeft/.swipeRight)` on the primary `LiveActivity` |
| Track swipe / scrub / timer scroll inside the Nook | Shell → widget | `.crannyScrollZone` routed by `NotchZones.scroll` |
| File drops anywhere on the notch | Shell → Tray, AirDrop, Quick Apps, pipelines | `.crannyDropZone` + `NotchZones.performDrop(fallback: .trayKeep)` |
| Drag "catch" state content | Tray → NotchUI | `services.tray.catchView(for:)` |
| Open/close, holds, focus mode, peeks, key focus | Modules → Shell | `services.notch` (`NotchControl`) |
| AirDrop / share sheet anchored on screen | Tray, Notes → Shell | `NotchControl.presentAirDrop/presentSharePicker` |
| Tutorial detection (opened, file caught, swiped, hints) | Shell → Onboarding | `NotchControl.addEventObserver` |
| Locked, asleep, low power, battery, full screen, demo, paused | Shell → everyone | `services.environment` (`SystemEnvironment`, observable) |
| Launch at login, updates, shortcut registration, open Settings/Welcome/Tutorial, Show on Notch | Shell → Settings, Onboarding, menu | `services.app` (`AppControl`) |
| Permissions | Core → everyone | `services.permissions` |
| ⌘K actions, global shortcuts, type-to-capture | Modules → Shell/NotchUI | `registry.commandProviders`, `registry.shortcuts`, `registry.captureTargets` |
| Settings panes, widget options, activity toggles + per-activity options, simulate chips | Modules → SettingsUI | `registry.settingsPages` (`keywords`, `namespaces`), `AnyNookWidget.makeOptions()`, `registry.activities` (`kind`, `makeSample`, `makeOptions`) |
| Onboarding presets | Core → Onboarding | `NookPreset` (data; widget IDs from `Identifiers.swift`) |
| Render model of a notch | Shell/Settings/Onboarding → NotchUI | `NotchSceneModel` (§4.12); stages put samples in `sampleActivities` |
| Theme, per-display layout, notch-fit key, display key, light palette from `CoreSettings` | NotchUI → Shell/Settings/Onboarding | `ThemeResolver` (§4.12) — one implementation, three callers |
| Delight moments (ember burst, charge sweep, song ripple, first light, gulp) | Modules name / shell schedules → NotchUI draws | `LiveActivity.delight` → `NotchSceneModel.delight` + `delightSerial` (§4.6 step 7) |
| Short confirmation in the band ("Hi", "Path copied") | Onboarding, modules → Shell | `NotchControl.flash(symbol:label:)` (`ActivityID.flash`) |
| UI sounds ("Pop" on catch, "Tink" on to-do done) | Shell, Todos | `CoreSettings.uiSounds` ∧ ¬`environment.isDemoMode` → `NSSound(named:)` |

### 3.17 Reference module (verified)

`CrannyTimer`'s skeleton below compiles in the real package layout and exercises every contract: settings keys, a widget with a `#Preview`, an observable activity with a Live Activities option row, a command provider, a global shortcut and launch/terminate hooks. WP7 grows it into the full Timer (incl. `TimerDoneActivity` with `delight = .emberBurst`); other packages copy its shape.

```swift
// CrannyTimer/TimerModule.swift — reference skeleton showing every contract (ARCHITECTURE.md §3.17).
import CrannyCore
import Foundation
import Observation
import SwiftUI

public enum TimerModule: FeatureModule {
    public static var id: ModuleID { .timer }

    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let model = TimerModel(settings: services.settings, haptics: services.haptics)
        registry.add(widget: TimerWidget(model: model))
        registry.add(activity: TimerRunningActivity(model: model), kind: ActivityKind(
            id: .timerRunning, module: .timer,
            title: String(localized: "Timer", bundle: .module, comment: "Live activity name"),
            symbol: "timer", defaultPriority: .ongoing, canPeekOnChange: true, peeksOnChangeByDefault: true),
            options: { AnyView(Toggle(isOn: services.settings.binding(TimerSettings.peeksAtOneMinute)) {
                Text("Peek at one minute left", bundle: .module, comment: "Live Activities pane: timer option") }) })
        registry.add(commands: TimerCommands(model: model))
        registry.add(shortcut: GlobalShortcut(
            id: .startTimer, title: String(localized: "Start timer", bundle: .module, comment: "Global shortcut name")) {
                model.start(seconds: services.settings[TimerSettings.presets].first ?? 300)
                services.notch.open(page: .nook, focus: .timer, reason: .keyboard)
            })
        registry.onLaunch { await model.restore() }
        registry.onTerminate { model.persistNow() }
    }
}

public enum TimerSettings {
    public static let presets = SettingKey<[Int]>(.timer, "presets", default: [60, 300, 600, 1500])
    public static let sound = SettingKey<String?>(.timer, "sound", default: "Glass")
    public static let peeksAtOneMinute = SettingKey<Bool>(.timer, "peeksAtOneMinute", default: true)
}

@MainActor @Observable final class TimerModel {
    private(set) var endDate: Date?
    private(set) var total: TimeInterval = 0
    private(set) var revision = 0
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private var finish: Task<Void, Never>?

    init(settings: SettingsStore, haptics: Haptics) { self.settings = settings; self.haptics = haptics }

    var isRunning: Bool { endDate != nil }
    func remaining(at now: Date = .now) -> TimeInterval { max((endDate ?? now).timeIntervalSince(now), 0) }

    func start(seconds: Int) {
        total = TimeInterval(seconds)
        endDate = .now.addingTimeInterval(total)
        revision += 1
        scheduleFinish()
    }
    func stop() { endDate = nil; finish?.cancel(); revision += 1 }

    /// One sleep to the deadline — no ticking timer (energy rule: zero timers while closed).
    private func scheduleFinish() {
        finish?.cancel()
        guard let endDate else { return }
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
    func restore() async {}
    func persistNow() {}
}

final class TimerWidget: NookWidget {
    let model: TimerModel
    init(model: TimerModel) { self.model = model }
    let id: WidgetID = .timer
    var title: String { String(localized: "Timer", bundle: .module, comment: "Widget name") }
    let symbol = "timer"
    var summary: String { String(localized: "Countdowns with presets", bundle: .module, comment: "Widget library description") }
    let sizes = WidgetSizes(minimum: 2, preferred: 2, maximum: 3)

    func makeBody(context: WidgetContext) -> some View { TimerFace(model: model, context: context) }
}

struct TimerFace: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    let context: WidgetContext
    var body: some View {
        // Ticks only while visible AND running; paused it costs nothing (energy budget, DESIGN.md §4.7).
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            let left = model.remaining(at: tl.date)
            ZStack {
                ProgressRing(progress: model.total > 0 ? left / model.total : 0, color: theme.palette.warning, lineWidth: StrokeWidth.ring)
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                    .crannyFont(.numeral)
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 88, height: 88)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

@MainActor @Observable final class TimerRunningActivity: LiveActivity {
    @ObservationIgnored let model: TimerModel
    init(model: TimerModel) { self.model = model }
    let id: ActivityID = .timerRunning
    var isActive: Bool { model.isRunning }
    let priority: ActivityPriority = .ongoing
    let slot: SlotWidth = .medium
    var revision: Int { model.revision }
    var palette: AmbientPalette? { .timer }
    var opensWidget: WidgetID? { .timer }
    var accessibilityLabel: String { String(localized: "Timer running", bundle: .module, comment: "VoiceOver label") }
    var actions: [ActivityAction] {
        [ActivityAction(id: "stop", title: String(localized: "Stop timer", bundle: .module, comment: "VoiceOver action"),
                        symbol: "stop.fill") { [model] in model.stop() }]
    }

    func compactLeading() -> some View { TimerCompactRing(model: model) }
    func compactTrailing() -> some View { TimerCompactValue(model: model) }
    func minimal() -> some View { TimerCompactRing(model: model) }
    func peekRow() -> some View { TimerCompactValue(model: model) }   // WP7: ring 40 · label · ⏸ ⏹ · +1 min
}

/// Views read tokens from the environment — activities never hard-code colours.
struct TimerCompactRing: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            ProgressRing(progress: model.total > 0 ? model.remaining(at: tl.date) / model.total : 0,
                         color: theme.palette.warning, lineWidth: StrokeWidth.ringCompact)
        }
        .frame(width: 16 * theme.notchUnit, height: 16 * theme.notchUnit)
        .accessibilityHidden(true)
    }
}

struct TimerCompactValue: View {
    let model: TimerModel
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !model.isRunning)) { tl in
            Text(Duration.seconds(model.remaining(at: tl.date)).formatted(.time(pattern: .minuteSecond)))
                .crannyFont(.compact)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

final class TimerCommands: PaletteCommandProvider {
    let model: TimerModel
    init(model: TimerModel) { self.model = model }
    func commands(matching query: String) -> [PaletteCommand] {
        [PaletteCommand(id: "timer.start25", title: String(localized: "Start 25-minute timer", bundle: .module, comment: "Command palette"),
                        kind: String(localized: "Timer", bundle: .module, comment: "Command palette kind"),
                        symbol: "timer") { [model] in model.start(seconds: 1500) }]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
}

#Preview("Timer widget") {
    let services = CrannyServices.preview()
    let model = TimerModel(settings: services.settings, haptics: services.haptics)
    TimerWidget(model: model).makeBody(context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96)))
        .crannyCard(cells: 2)
        .crannyThemeRoot(CrannyTheme())
        .padding()
        .background(.black)
}
```

---

## 4. App state machine

The shell keeps **one state machine per display panel** (`NotchViewModel`, AppShell/State) and one global `ActivityArbiter`. Both are pure value-type reducers (`reduce(state, input, now) -> (state, [Effect])`) so they are unit-tested without windows; the view model executes the effects (timers, key focus, haptics, announcements, `NotchEvent`s) and writes the result into a `NotchSceneModel` (§4.12) that `CrannyNotchUI` renders. Timing constants come from DESIGN.md (`HoverIntent`, `GestureSpec`); where R1 and DESIGN differ (close delay 250 vs 300 ms), DESIGN wins.

### 4.1 State

```swift
// CrannyAppShell/State/NotchMachine.swift (WP13) — shape of the state; pure, Equatable.
struct NotchMachineState: Equatable {
    enum Surface: Equatable { case closed, peek(Peek), open(OpenState) }      // OpenState: §4.12
    enum Peek: Equatable { case hover, auto(ActivityID, until: TimeInterval) }
    enum Hover: Equatable { case outside, dwelling(since: TimeInterval), inside }
    enum Hidden: Equatable { case fullScreen, excludedApp, locked, displaysAsleep, idleHandle, notThisDisplay }

    var surface: Surface = .closed
    var hover: Hover = .outside
    var hidden: Hidden? = nil
    var pinned = false
    var holds: Set<String> = []          // NotchControl.setHoldOpen reasons + "menu", "drag", "typing"
    var graceDeadline: TimeInterval?     // pending close after leaving the exit zone
}
```

### 4.2 Phase derivation (what is drawn)

```
hidden != nil                         → .hidden   (content alpha 0 → automatically click-through)
surface == .open                      → .open     (geometry: open(columns) / focus: maxColumns × 3 rows)
surface == .peek                      → .peek     (rows: hover = all visible activities ≤ 4; auto = that activity)
arbiter.primary != nil                → .compact  (+ satellite if any)
hover == .dwelling, openMode ≠ .shortcutOnly → .breath
otherwise                             → .idle     (exact cutout; handle pill on displays without a notch)
```

### 4.3 Inputs and timings

| Input (from) | Constant |
|---|---|
| Pointer enters the **entry zone** = shape bounds + 4 pt, extended above the screen's top edge (pointer y can equal `frame.maxY`, R1 §2.5) — HoverTracker | `HoverIntent.entryInflation` 4 |
| Dwell elapsed — scheduled on entry | `CoreSettings.hoverDelay` (Instant 0 · **Short 0.12** · Standard 0.22 · Long 0.45 s); full-screen Space ≥ `fullScreenDwell` 0.40 s |
| Dwell over compact → quick peek | `HoverIntent.peekDwell` 0.18 s (setting `quickPeekOnHover`) |
| Pointer leaves the **exit zone** = shape bounds + 14 pt (while open/peek) | `exitInflation` 14; grace `closeGrace` 0.30 s |
| Pointer speed > 1200 pt/s, mouse button down, ⌥ held (setting) | blocks hover-open (`HoverIntent.shouldOpen`) |
| Click on shape / activity / satellite — SwiftUI tap in NotchUI | — |
| Swipe (two fingers) — `SwipeTracker` in `NotchPanel.sendEvent` | `GestureSpec` |
| File drag near = closed shape + 80 pt wide, 40 pt below the band — DragDetector | `dragProximity`; no dwell |
| Hot key `.openNook` (Carbon, default ⌃⌥N) | toggles |
| Esc, ⌘P (pin), ⌘K (palette), ⌘E (edit), ⌘1–⌘5 / ⌃Tab (pages) — NotchUI key handling while key | — |
| `setHoldOpen`, NSMenu/NSPopover tracking, panel key status, drag in progress | holds |
| Activity changes, peek requests — ActivityArbiter | peek `CoreSettings.peekDuration` 2.6 s |
| Inactivity | `openInactivityTimeout` (0 = off, 5–60 s); compact: `compactInactivityTimeout` |
| Idle handle (displays without a notch, `hideHandleWhenIdle`) | one `Task.sleep` of `handleIdleDelay` (default 10 s) after the last activity/hover; no polling |
| Environment (full screen, excluded app, lock, sleep, demo, pause) — ShellEnvironment | re-evaluated 0.6 s after space changes |

### 4.4 Transition table

| From | Input | Guard | To | Effects |
|---|---|---|---|---|
| idle / compact | pointer enters entry zone | not hidden; `openMode ≠ .shortcutOnly` | hover = dwelling | schedule dwell (idle: hover delay; compact: peek dwell if quick peek is on) |
| dwelling | dwell elapsed | `HoverIntent.shouldOpen(…)`; `openMode == .hover`; VoiceOver off | idle → **open**(page: `lastPage`, reason `.hover`); compact → **peek(.hover)** | emit `.opened(.hover)` |
| dwelling (breath) | pointer leaves | — | idle | cancel dwell |
| idle / breath / compact / peek | click on shape | — | **open**(focus: primary's `opensWidget`, reason `.click`) | — |
| peek | click on a row | — | **open**(focus: that activity's widget) | — |
| compact | click on satellite | — | compact (primary ⇄ satellite swapped) | — |
| compact | swipe **up** committed over the satellite | `swipeToDismiss` | satellite dismissed until its `revision` changes | haptic |
| any visible | hot key Open Cranny (`.openNook`) | — | open ⇄ closed (toggle); opening makes the panel key | `.makeKey` |
| idle / compact | swipe **down** committed | `swipeOpenClose` | **open**(reason `.swipe`) carrying velocity | haptic `.alignment` at threshold |
| open | swipe **up** committed over the header row | `swipeOpenClose` | closed | haptic |
| compact / peek | swipe **up** committed | `swipeToDismiss` | primary dismissed until its `revision` changes | haptic |
| compact / peek | swipe **left/right** committed | `trackSwipe` | unchanged; `primary.handle(.swipeLeft/Right)` | haptic, emit `.activityGesture` |
| idle (no-notch handle) | swipe **up** | — | hidden(.idleHandle) until the next activity revision | — |
| idle (no-notch handle) | `handleIdleDelay` elapsed | `hideHandleWhenIdle`; no primary; pointer outside | hidden(.idleHandle) (fade) | — |
| hidden(.idleHandle) | next activity revision, or pointer enters the entry zone (geometric, works while invisible) | — | idle / compact | — |
| closed / compact / peek | file drag enters proximity | `services.tray != nil` | **open**(mode `.catchFiles(types)`, reason `.drag`) | add the `opacity(0.001)` enlarged hit zone (R1 §4.1) |
| open(.grid) | file drag starts or enters the shape | — | unchanged: the grid stays so widget zones (Quick Apps "add app", AirDrop widget, Files shelf) can take the drop; unmatched drops fall back to `.trayKeep` → `services.tray.accept` | `zones.dragUpdated` arms widget zones |
| open(.catchFiles) / open(.grid) | drop performed | — | catch: previous surface after the 0.25 s gulp; grid: unchanged | `zones.performDrop(fallback: .trayKeep)`, if false `await services.tray?.accept(payload)`; emit `.filesCaught(n)`, haptic `.generic`, delight `.gulp`, UI sound "Pop" if `uiSounds`; remove hit zone |
| open(.catchFiles) | drag ends without drop / leaves zones | — | grace 0.30 s → previous surface | remove hit zone |
| open / peek(.hover) | pointer leaves exit zone | `closeOnLeave`; not pinned; holds empty; panel not key; no drag; no menu | grace → **closed** | schedule grace |
| grace | pointer re-enters | — | cancel grace | — |
| open | inactivity timeout | timeout > 0; not pinned; holds empty; pointer outside | closed | — |
| open | Esc | palette → grid, edit → grid, focus → grid, else close | as described | close: `.relinquishKey` |
| open | ⌘P / pin button / `togglePinned()` | — | pinned toggled | emit `.pinned` |
| closed / compact | arbiter requests auto-peek | pointer display; not paused; policy allows peeks | **peek(.auto(id, until: now + peekDuration))** | VoiceOver announcement for P1 |
| peek(.auto) | `until` reached | pointer not inside | closed (compact) | — |
| any | environment: full screen / excluded app | policy `.hideAll` | hidden(.fullScreen / .excludedApp) | — |
| any | environment: full screen | policy `.alertsAndHUD` | not hidden; arbiter restricted to P0/P1; dwell ≥ 0.40 s | — |
| any | screen locked / displays asleep | — | hidden(.locked / .displaysAsleep) | close; stop hardware (modules observe `SystemEnvironment`) |
| hidden | condition clears | — | previous surface = closed | — |
| any | demo mode on | — | never auto-closes or hides (acts as pinned + policy `.showAll`) | — |
| open → closed | (any close) | — | closed | `.relinquishKey` if key (R1 §3.5), end focus mode, emit `.closed` |

Every geometry change animates with DESIGN.md §4.1 springs (`open` grows with bounce 0.14; `close`, `activityOut`, `peekOut`, `hoverOut`, `hudOut` land with bounce 0). Under Reduce Motion, open/close/resize cross-fade at final size (`CrannyMotion.morphsShape`).

### 4.5 What holds the Nook open

Pinned · Demo mode · panel is key (typing) · an `NSMenu` is tracking or an `NSPopover` is shown inside the panel (shell observes `NSMenu.didBeginTrackingNotification` / `didEndTrackingNotification` and `NSPopover.willShow/didClose` for windows owned by the panel) · a file drag is in progress · ⌘K palette or edit mode is active · any `setHoldOpen(true, reason:)` (Notes editing/focus, Mirror running a permission prompt, Tray pipeline progress sheet) · a share or AirDrop sheet presented by `NotchControl`.

### 4.6 Activity arbitration (global, one per app)

```
input  registry.activities, CoreSettings.activityPreferences / activityOrder / pausedUntil / satellite,
       dismissed[id] = revision at swipe-up, lastSeen[id] = last revision observed, now,
       environment (full-screen restricted?), per-display DisplayPreferences

1  candidates = activities where
       activity.isActive
     ∧ (prefs[id]?.isEnabled ?? kind.isEnabledByDefault)
     ∧ (activity.expiresAt == nil ∨ expiresAt > now)
     ∧ dismissed[id] ≠ activity.revision
     ∧ (¬paused ∨ priority == .hud)
     ∧ (¬fullScreenRestricted ∨ priority ≤ .alert)
2  order by (priority.rawValue, index in activityOrder ?? registration index)
3  primary = first; satellite = second (if the satellite setting is on); overflow = rest (hover peek lists ≤ 4 rows)
4  for each candidate with revision > lastSeen[id]:
       if priority == .alert ∨ (prefs[id]?.peeksOnChange ?? kind.peeksOnChangeByDefault):
           request auto-peek(id) on the pointer display
       lastSeen[id] = revision
   (at launch lastSeen is initialised to the current revisions: no peeks on launch)
5  per display: hide compact if ¬showsActivities (keep HUD if showsHUD); no peeks if ¬showsPeeks
6  schedule ONE wake-up at the earliest expiresAt (no polling)
7  delight: for each visible candidate whose revision changed and whose `delight` ≠ nil, plus shell sources
       (.songRipple on nowPlaying.trackChangeCount while open, .firstLight on the first open per session,
        .gulp on filesCaught): if none is playing ∧ ¬paused ∧ ¬fullScreenInFront ∧ motion ∉ {calm, instant}
       ∧ ¬reduceMotion (DESIGN §5.5 caps; Reduce Motion variants are drawn by NotchUI)
       → scene.delight = moment; scene.delightSerial += 1 on the pointer's display only
```

Transient P0/P1 activities therefore take the wings and hand them back automatically when they expire (DESIGN.md §9.4). VoiceOver announcements (P1 only, ≤ 1 per 10 s) use `AccessibilityNotification.Announcement`.

### 4.7 Peeks, dismissal, pause and timeouts

- **Auto-peek** only on the pointer's display, never while open, never while paused or in full screen under `.hideAll`; duration `peekDuration`; a hover keeps it.
- **Swipe-up dismissal** stores the revision; it is undone by the activity's next revision (auto-unhide, setting `autoUnhide`).
- **Pause Live Activities** (menu bar): `CoreSettings.pausedUntil` = +1 h / tomorrow 00:00 / `.distantFuture`; silences activities, peeks and delight moments; the HUD still works.
- **Compact inactivity timeout** collapses compact to idle until the next revision (the satellite stays). Media's "hide paused after N s" is the module's own `isActive` logic.
- **Menu-bar courtesy:** pointer in the band within 24 pt beside the wings → wings retract (`activityOut`) and return 1.5 s after the pointer leaves the band.

### 4.8 Full screen, excluded apps, lock

`ShellEnvironment.isFullScreenInFront` is true for the pointer's display when a full-screen or excluded app is in front (§5.7). Policy (`CoreSettings.fullScreenPolicy`): `.hideAll` → hidden; **`.alertsAndHUD`** (default) → only P0/P1, hover dwell 0.40 s; `.showAll` → normal. Lock and display sleep hide everything and stop hardware work.

### 4.9 Multi-display policy

- **Panels:** one `NotchPanelController` per eligible display, keyed by `DisplayKey` (display UUID). Eligible = selected by `CoreSettings.displaySelection` and style ≠ `.off`: `.builtIn` → the built-in display if online, else the primary display (`NSScreen.screens[0]`; clamshell removes the built-in screen, R1 §2.6) · `.pointer` → panels on all displays, only the pointer's one is visible (others `hidden(.notThisDisplay)`), switching when the pointer changes display · `.all` · `.custom([DisplayKey])`.
- **Style per display:** hardware notch → attached notch; otherwise `DisplayPreferences.style ?? CoreSettings.noNotchStyle` (Floating island default). `NotchLayout` per display from `NotchMetrics.measure(screen)` + `notchFit[model]` + density/text size.
- **Content per display:** compact activities on every visible display (per-display toggle); **peeks, alerts and the HUD only on the pointer's display**; at most **one open Nook** — opening on display A closes any other.
- **Reconfiguration:** `didChangeScreenParametersNotification` + `CGDisplayRegisterReconfigurationCallback`, debounced 250 ms (R1 §2.6): update existing controllers (geometry applied only while closed; pending otherwise), create new ones, close removed ones. Also re-validate on wake and `activeSpaceDidChange`.

### 4.10 Keyboard and focus

- The panel becomes key only when a text view is clicked (`becomesKeyOnlyIfNeeded`), when opened by the hot key, or via `requestKeyboardFocus()`. Programmatic `makeKey()` on the non-activating panel without activating the app is expected to work like a clicked text field [UNVERIFIED — WP13 confirms with the R1 interaction harness].
- On every close the shell calls `orderOut` + `orderFrontRegardless` if the panel is key, which returns key status to the previous app's window [VERIFIED R1].
- Never use `NSApp.isActive` to decide who is frontmost (true while our panel is key); use `NSWorkspace.frontmostApplication` [VERIFIED R1].
- In-Nook keys (DESIGN.md §16 keyboard map) are handled in NotchUI with `.onKeyPress`/`.keyboardShortcut` while the panel is key. Hold-⌘ hints: a local `flagsChanged` monitor (0.5 s) sets `NotchContext.showsCommandHints`. Type-to-capture: when opened by keyboard and nothing is focused, the first printable `keyDown` goes to `CaptureTarget.capture(_:)` of `CoreSettings.typeToCapture`, then focus moves to the returned widget.
- Global shortcuts: Carbon `RegisterEventHotKey` on `GetApplicationEventTarget()` — no Accessibility needed; compiled and registered ⌃⌥N on macOS 27 in Swift 6 mode [VERIFIED, Appendix C; key delivery inside the running app is confirmed by WP13]. Registration failure = conflict → `ShortcutState.conflict` shown in Settings ▸ Keyboard.

### 4.11 The HUD while the Nook is open

If a HUD activity becomes primary while the Nook is open, NotchUI renders its leading/trailing views **inside the header row** (left and right of the camera, replacing tabs and actions with `contentSwap` for the HUD's lifetime). The open geometry never changes. Adopted in DESIGN.md §10 ("While the panel is open").

### 4.12 Render contract: `NotchSceneModel` (CrannyNotchUI) [VERIFIED compile]

The shell (one per display), the Settings preview stage and the onboarding stage each own a `NotchSceneModel` and render it with `NotchCanvasView(model:registry:actions:)`. Only the owner writes it. WP12 implements the views behind this API; WP13–WP15 code against it from day one.

```swift
// CrannyNotchUI/NotchScene.swift — the render model of one notch (one per display panel, one per stage).
import CrannyCore
import CrannyEffects
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// What the open Nook is showing.
public nonisolated enum NookMode: Equatable, Sendable {
    case grid
    case palette                       // ⌘K
    case editLayout                    // ⌘E
    case focus(WidgetID)               // Notes focus: all columns × 3 rows
    case catchFiles([UTType])          // file drag in progress (DESIGN.md §8.3)
}

public nonisolated struct OpenState: Equatable, Sendable {
    public var page: PageID
    public var focus: WidgetID?
    public var mode: NookMode
    public var reason: OpenReason
    public init(page: PageID, focus: WidgetID? = nil, mode: NookMode = .grid, reason: OpenReason) {
        self.page = page; self.focus = focus; self.mode = mode; self.reason = reason
    }
}

/// Written ONLY by its owner (the shell's per-display view model, or a preview stage). Views read it.
@MainActor @Observable public final class NotchSceneModel {
    public var phase: NotchPhase = .idle
    public var layout: NotchLayout
    public var theme: CrannyTheme
    public var primary: ActivityID?
    public var satellite: ActivityID?
    public var peekRows: [ActivityID] = []
    /// Stages (Settings preview, onboarding) put `RegisteredActivity.makeSample()` instances here; the canvas
    /// prefers them over the registry's live objects. The shell leaves it empty.
    public var sampleActivities: [ActivityID: any LiveActivity] = [:]
    public var open: OpenState?
    public var pinned = false
    public var ambient: AmbientPalette = .afterglow
    /// One-shot delight to play (DESIGN.md §5.5). The owner applies the caps (one at a time, not paused,
    /// not in full screen, not under Calm/Instant/Reduce Motion) and bumps `delightSerial`; NotchUI plays
    /// each serial once. Sources: activities' `delight`, track change (`.songRipple`), first open (`.firstLight`),
    /// file caught (`.gulp`).
    public var delight: DelightMoment?
    public var delightSerial = 0
    /// Live rubber-band offset from a gesture in progress (pt; +y = down).
    public var gestureTranslation: CGSize = .zero
    public var context = NotchContext()
    public let zones: NotchZones

    public init(layout: NotchLayout, theme: CrannyTheme, zones: NotchZones = NotchZones()) {
        self.layout = layout; self.theme = theme; self.zones = zones
    }

    /// The shape for the current state (pure function of the model + layout, DESIGN.md §3.3).
    public var geometry: NotchGeometry {
        switch phase {
        case .hidden: .zero
        case .idle: layout.closed
        case .breath: layout.hover
        case .compact: layout.compact(primarySlot)
        case .peek: layout.peek(rows: max(peekRows.count, 1))
        case .open:
            if case .focus? = open?.mode { layout.open(columns: layout.maxColumns, rows: 3) }
            else { layout.open(columns: openColumns) }
        }
    }
    /// Set by the owner from the registry (slot of the primary activity).
    public var primarySlot: SlotWidth = .short
    /// Sum of visible widget widths on the current page (set by the owner).
    public var openColumns: Int = 10
}

/// Callbacks from the views to the owner. Stages pass no-ops.
public struct NotchUIActions {
    public var selectPage: @MainActor (PageID) -> Void = { _ in }
    public var togglePin: @MainActor () -> Void = {}
    public var showPalette: @MainActor () -> Void = {}
    public var openSettings: @MainActor () -> Void = {}
    public var close: @MainActor () -> Void = {}
    public var activityTapped: @MainActor (ActivityID) -> Void = { _ in }
    public var satelliteTapped: @MainActor () -> Void = {}
    public var commitLayout: @MainActor ([NookPage]) -> Void = { _ in }
    /// ⌘K / ⌘E / Esc chain / focus mode: NotchUI asks, the owner writes `open.mode`.
    public var setMode: @MainActor (NookMode) -> Void = { _ in }
    /// Keyboard focus moved to a widget (nil = none); the owner mirrors it into `context.focusedWidget`.
    public var focusWidget: @MainActor (WidgetID?) -> Void = { _ in }
    /// VoiceOver "Dismiss" action and swipe-up on the satellite.
    public var dismissActivity: @MainActor (ActivityID) -> Void = { _ in }
    /// VoiceOver "Open" on the collapsed notch.
    public var open: @MainActor () -> Void = {}
    public init() {}
}
```

`ThemeResolver` lives next to it so the shell (WP13), the Settings stage (WP14) and the onboarding stage (WP15) resolve `CoreSettings` identically — they cannot import each other (§2.1). Owner WP12; the API below is final and was compiled in the package layout with zero warnings:

```swift
// CrannyNotchUI/ThemeResolver.swift — CoreSettings → theme, layout and light palette.
// Shared by the shell (one per display), the Settings preview stage and the onboarding stage,
// so all three render identically. Pure functions of their inputs.
import AppKit
import CrannyCore
import SwiftUI

public enum ThemeResolver {
    /// The theme of one surface. `albumAccent` = `services.nowPlaying?.palette?.accent` while media plays.
    public static func theme(settings: SettingsStore, albumAccent: RGB?, notchUnit: CGFloat,
                             isFloatingDisplay: Bool) -> CrannyTheme {
        var t = CrannyTheme()
        t.textSize = settings[CoreSettings.textSize]
        t.density = settings[CoreSettings.density]
        t.widgetStyle = settings[CoreSettings.widgetStyle]
        t.buttonShape = settings[CoreSettings.buttonShape]
        t.motion = settings[CoreSettings.motion]
        t.ambience = settings[CoreSettings.ambience]
        t.effect = settings[CoreSettings.effect]
        t.translucentBackground = settings[CoreSettings.translucentBackground]
        t.panelPaddingTune = CGFloat(settings[CoreSettings.panelPaddingTune])
        t.glassIsland = isFloatingDisplay && settings[CoreSettings.glassIsland]
        t.hapticsEnabled = settings[CoreSettings.haptics]
        t.notchUnit = notchUnit
        t.accent = AccentResolver.resolve(settings[CoreSettings.accent], albumAccent: albumAccent,
                                          systemAccent: AccentResolver.systemAccent(),
                                          palette: t.palette.spec, increaseContrast: false)
        return t
    }

    /// Per-display layout. `metrics` come from `NotchMetrics.measure(screen)` (or `.reference` on a stage).
    public static func layout(metrics: NotchMetrics, displayModel: String?, style: NoNotchStyle,
                              settings: SettingsStore, textSize: CrannyTextSize, density: NookDensity,
                              widgetStyle: WidgetStyle) -> NotchLayout {
        let fit = displayModel.flatMap { settings[CoreSettings.notchFit][$0] } ?? NotchFit()
        return NotchLayout(metrics: metrics, noNotchStyle: style, widthTune: fit.widthTune, radiusTune: fit.radiusTune,
                           grid: NookGrid(density: density, textSize: textSize, style: widgetStyle,
                                          paddingTune: CGFloat(settings[CoreSettings.panelPaddingTune])))
    }

    /// `CGDisplayCreateUUIDFromDisplayID` string — the per-display settings key (stable across reconnects).
    public static func displayKey(_ screen: NSScreen) -> DisplayKey? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return DisplayKey(string)
    }

    /// "<vendor>-<model>" key of `CoreSettings.notchFit` (stable per display model, not per unit).
    public static func displayModelKey(_ screen: NSScreen) -> String? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(n.uint32Value)
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))"
    }

    /// The light-layer palette (DESIGN.md §5.2): the top activity's palette, else by accent source.
    public static func ambientPalette(topActivity: AmbientPalette?, accent: AccentSource, systemAccent: RGB) -> AmbientPalette {
        if let topActivity { return topActivity }
        switch accent {
        case .automatic, .system: return .tinted(systemAccent)
        case .swatch: return .afterglow
        case .monochrome: return .mono
        }
    }
}
```

---

## 5. Window strategy (from R1)

### 5.1 Decision

One borderless, **non-activating `NSPanel` per display at level 26** (`.statusBar + 1`), on all Spaces, sized **once** to the largest open shape plus margins (`NotchLayout.canvasSize`, e.g. 900 × 282 on a 14″), glued to the top edge and centred on the notch (screen centre without one), clamped inside the screen. Every closed → breath → compact → peek → open morph is a SwiftUI `NotchShape` animation inside that fixed canvas (222–238 fps on 240 Hz, window frame constant [VERIFIED R1]). The canvas is resized only while closed (when density, text size, notch fit or screen geometry change).

Click-through is the window server's per-pixel pass-through: alpha-0 pixels and SwiftUI `.shadow`s pass clicks, moves and drags to the windows below; any drawn pixel (even alpha 0.001) captures. **Never assign `ignoresMouseEvents`** (an explicit `false` makes the whole rectangle capture, with no way back). Hiding = content alpha 0.

Rejected: resizing the window per frame (frame/content desync), toggling `ignoresMouseEvents` from a mouse monitor (tri-state pitfall, one-event lag), levels < 24 (pushed out of the menu-bar strip in full screen), `.screenSaver` (covers menus, tooltips and drag images), private CGS space APIs.

### 5.2 The panel [VERIFIED: R1 configuration, built in the new layout]

```swift
// CrannyAppShell/Overlay/NotchPanel.swift — R1 §3.1 configuration (verified on macOS 27).
import AppKit
import SwiftUI

extension NSWindow.Level {
    /// Above the menu bar (24) and status items (25); below menus (101), tooltips (200), drag images (500).
    static let notchOverlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
}

final class NotchPanel: NSPanel {
    /// Every scroll event delivered to this window passes through here first (gestures, scroll zones).
    var scrollInterceptor: ((NSEvent) -> Bool)?

    init(frame: CGRect) {
        // .nonactivatingPanel MUST be in the init style mask (R1 gotcha 4).
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true            // resets level to 3 -> set level AFTER (R1 gotcha 1)
        level = .notchOverlay
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        // NEVER assign ignoresMouseEvents (tri-state; R1 §4.1).
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let intercept = scrollInterceptor, intercept(event) { return }
        super.sendEvent(event)
    }
}

/// Root content view: hit-testing limited to the shape, AppKit drop destination for the Tray.
final class NotchRootView: NSView {
    var interactiveRect: () -> CGRect = { .zero }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // R1 gotcha 6
}
```

### 5.3 One controller per display (outline for WP13)

```swift
@MainActor final class NotchPanelController {
    let key: DisplayKey
    let panel: NotchPanel                       // §5.2
    let root: NotchRootView                     // hitTest + NSDraggingDestination (+ file promises)
    let scene: NotchSceneModel                  // §4.12, rendered by NotchCanvasView
    let viewModel: NotchViewModel               // §4 reducer + effects
    init(screen: NSScreen, registry: ModuleRegistry) {
        // layout = ThemeResolver.layout(metrics: .measure(screen), displayModel: ThemeResolver.displayModelKey(screen), …)
        // theme  = ThemeResolver.theme(settings:albumAccent:notchUnit:isFloatingDisplay:)   (re-run on observed key changes)
        // frame  = top-centred canvasSize, backingAlignedRect(.alignAllEdgesNearest), clamped to screen.frame
        // host   = NotchHostingView(rootView: NotchCanvasView(model: scene, registry: registry, actions: viewModel.actions))
        //          host.sizingOptions = []; host.safeAreaRegions = []   (no 32–38 pt jump on notched displays)
        // root.interactiveRect = shape bounds (+ satellite, + 0.001-alpha drag zone) converted to bottom-left coords
        // panel.scrollInterceptor = viewModel.handleScroll(_:)         (§5.6)
        // panel.orderFrontRegardless()                                 (never activates the app)
    }
    func update(screen: NSScreen)   // geometry changes applied only while closed
    func close()                    // orderOut + close on display removal
}
```

### 5.4 Coordinator and displays

`OverlayCoordinator` owns `[DisplayKey: NotchPanelController]`, rebuilds on screen changes (debounced 250 ms; keys from `ThemeResolver.displayKey(_:)` = `CGDisplayCreateUUIDFromDisplayID` of `NSScreenNumber` [VERIFIED R1, compiled in this review] — the same helper the Settings ▸ General display table uses), applies the display selection policy (§4.9), routes pointer events to controllers, and enforces "one open Nook". Menu-bar height for no-notch displays: `frame.maxY − visibleFrame.maxY` > 0, else the Window Server layer-24 window height, else 30 (never `NSStatusBar.thickness`, which says 22 on macOS 27 [VERIFIED R1]); `NotchMetrics.measure` implements the first and last; WP13 adds the layer-24 fallback for auto-hidden menu bars.

### 5.5 Pointer, hover and file-drag detection

- **PointerMonitor:** global **and** local `NSEvent` monitors for `.mouseMoved`, `*.MouseDragged`, `.leftMouseUp` (no permission for mouse events; global monitors miss our own windows' events) reading `NSEvent.mouseLocation` [VERIFIED R1]. Handler is O(displays) with no allocation. Speed for the pass-through rule = distance / Δtimestamp of consecutive events.
- **Zones** (screen coordinates, recomputed from the current shape): entry = shape + 4 pt and extended above `frame.maxY`; exit = shape + 14 pt; drag proximity = closed shape + 80 pt wide and 40 pt below the band. `NSTrackingArea` only as a secondary signal (it fires over opaque pixels only).
- **File drags from other apps:** on `leftMouseDragged`, read `NSPasteboard(name: .drag).changeCount`; when it changes, inspect `types` for `public.file-url` or promise types (`NSFilePromiseReceiver.readableDraggedTypes`) [VERIFIED R1]. The drag pasteboard is not subject to the macOS 15.4+ paste alert [SDK].

### 5.6 Drop and scroll routing

- **Drops:** `NotchRootView` registers `.fileURL`, `.URL` and the file-promise types. `draggingEntered/Updated` → convert the location to canvas top-left coordinates → `scene.zones.dragUpdated(at:types:)` (returns `.copy`). `performDragOperation` → read `NSURL`s (`urlReadingFileURLsOnly`); resolve promises with `NSFilePromiseReceiver.receivePromisedFiles(atDestination:options:operationQueue:reader:)` into `paths.cacheDirectory(for: .tray)/Incoming/<uuid>/` [UNVERIFIED R1 §5.1] → `zones.performDrop(DropPayload, fallback: .trayKeep)`; if that returns false (no zone registered yet), `await services.tray?.accept(payload)` so a file is never lost. A drag that starts while the grid is open keeps the grid (widget zones receive it); only a drag arriving at a closed/compact/peek notch opens the catch state (§4.4).
- **Drag out** (tray tiles): AppKit `NSDraggingSource` with `NSURL` pasteboard writers so receivers get the original file, not a SwiftUI temporary copy [VERIFIED R1 §5.3] — implemented inside CrannyTray as an `NSViewRepresentable`.
- **Scrolls** (`NotchPanel.sendEvent`, delivered even when the panel is not key [VERIFIED R1]): closed/compact/peek → the shell's own `SwipeTracker(axis: .any)` drives open (down), dismiss (up) and track swipes (left/right on the primary activity) with live rubber-band offsets in `scene.gestureTranslation`; open → `scene.zones.scroll(sample, at:)` (consumed if a scroll zone is under the pointer), else a vertical swipe-up over the header row closes, else the event goes to SwiftUI (`ScrollView`s in widgets). Phase-less wheel events never form gestures.

### 5.7 Full-screen detection [VERIFIED heuristics R1 §3.4, R3 §10]

For each display, with `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` (bounds, layer, owner PID need no Screen Recording permission):
`fullScreen(display) = ∃ window: layer 0 ∧ owner ∉ {Cranny, Dock, Finder-desktop} ∧ bounds ≈ CGDisplayBounds(display) (tolerance: height may be shorter by safeAreaInsets.top on notched displays [UNVERIFIED]) ∧ (owner is frontmost ∨ the Window Server layer-24 menu-bar window is absent on that display)`.
Evaluate 0.6 s after `activeSpaceDidChange`, `didActivateApplication`, screen-parameter changes, and lazily right before a hover-open or auto-peek — no timers. `NSApp.currentSystemPresentationOptions` and `visibleFrame` do not reflect other apps' full screen [VERIFIED]. Excluded apps (`CoreSettings.excludedBundleIDs`) count as full screen when frontmost.

### 5.8 Focus hand-back and menus

`relinquishKeyIfNeeded`: `if panel.isKeyWindow { panel.orderOut(nil); panel.orderFrontRegardless() }` on every close [VERIFIED R1]. The SwiftUI `App` lifecycle already installs a main menu with Edit ⌘Z/X/C/V/A (D12, verified by `scripts/smoke.sh`); if a future SDK drops it, install R1's hidden Edit menu (`EditMenu.make()`) in `applicationDidFinishLaunching`.

### 5.9 Other windows (all owned by CrannyAppShell)

| Window | Kind | Notes |
|---|---|---|
| Settings | `NSWindow` (titled, closable, miniaturizable, resizable) hosting `SettingsRootView` (CrannySettingsUI) in an `NSHostingController` | 860 × 620 default, 780 × 560 min, frame autosave name, restores the last pane. Opening = `NSApp.activate()` (in response to a user action) + `makeKeyAndOrderFront`. On close, give activation back to the app that was frontmost before (`NSApp.yieldActivation(to:)` + `activate(from:options:)` [UNVERIFIED R1 §3.5]). |
| Welcome | `NSWindow` 640 × 480, `.fullSizeContentView`, hidden title bar, not resizable, centred, hosting `WelcomeView` | First launch (`onboardingCompletedVersion == nil`) and "Show welcome". |
| Tutorial bubble | small non-activating `NSPanel` at level 26 positioned 10 pt under `NotchControl.shapeFrameOnScreen()` | Owned by CrannyOnboarding's `TutorialController` (it may create AppKit windows), positioned via the port. |
| AirDrop anchor | transparent, normal-level, on-screen window centred under the notch (or the open Nook panel if ≥ 400 × 300) passed as `sourceWindowForShareItems` | R3 §7: the AirDrop sheet centres on its source window and inherits its level. |
| Calibration outline | drawn inside the panel (1-px accent outline of the closed shape + 2× loupe) while `setCalibrationOverlay(true)` | Appearance ▸ Notch fit. |
| Menu bar extra | SwiftUI `MenuBarExtra(isInserted:)` `.menuBarExtraStyle(.menu)` — the only scene in `App.body` | DESIGN.md §13. "Settings…" is a `Button` calling `AppControl.openSettings(nil)` with `.keyboardShortcut(",")` — never `SettingsLink`/`openSettings` (there is no `Settings` scene, D11). The template icon is drawn in code (`NSImage(size:flipped:drawingHandler:)` with `NotchShape`, `isTemplate = true`), so no asset is read from `Bundle.main`. If the icon is hidden, `applicationShouldHandleReopen` opens Settings. |

---

## 6. Media architecture (from R2)

### 6.1 Why a bridge

Since macOS 15.4, `mediaremoted` gives unentitled clients an empty entitlement mask: a direct `MRMediaRemoteGetNowPlayingInfo` from Cranny returns `nil`/`0`/`false` ("Operation not permitted"). Apple's platform interpreters `/usr/bin/perl` and `/usr/bin/ruby` are admitted (`com.apple.perl`, mask ≠ 0) and have no library validation, so they can load our ad-hoc- or Developer-ID-signed dylib, which calls MediaRemote and speaks JSON over pipes [VERIFIED R2 tests a, b, d]. We never spoof a `com.apple.*` identity.

### 6.2 Components

```
Cranny.app (hardened, never loads the dylib itself)
 └─ CrannyMedia.MediaService (@MainActor @Observable, implements NowPlayingSource)
      ├─ providers, in order:  MediaRemoteBridgeProvider(.perl) → (.ruby) → AppleScriptProvider (opt-in) → none
      │    └─ BridgeConnection ── Process(/usr/bin/perl -e '<DynaLoader loader>' <dylib>) ── stdin: commands
      │                                                                             └── stdout: NDJSON events
      ├─ ArtworkDecoder (@concurrent): ImageIO thumbnail 512 px → CGImage; AmbientPalette.extract(from:) (Core)
      ├─ Visualizer: SyntheticSpectrum (default) | SystemAudioTap + SpectrumAnalyzer (opt-in, 14.2+)
      └─ BridgeHealthMonitor: CoreAudio "process is running output" vs bridge "nothing playing" → degraded
Contents/Frameworks/libCrannyMediaBridge.dylib   (universal; signed with the app; exports only cranny_bridge_main)
```

### 6.3 Bridge packaging [VERIFIED in the new layout]

- Sources: `Packages/CrannyKit/Sources/CrannyMediaBridge/CrannyMediaBridge.m` + `include/CrannyMediaBridge.h` (`void cranny_bridge_main(void);`) — R2's v3 bridge verbatim (≈ 230 lines, MIT, original). Protocol out: `hello`, `state` (full de-duplicated snapshot), `artwork` (only when item/artwork/length changes), `ack`, `error`, `pong`; in: `cmd 0..13 [guardPID]`, `seek <s> [guardPID]`, `shuffle|repeat 1..3`, `refresh`, `ping`, `quit`. Exits on stdin EOF, SIGPIPE, or re-parenting to launchd. Event-driven (50 ms trailing debounce), ~23 MB RSS, ~0 CPU idle.
- Built by the **Xcode target `CrannyMediaBridge`** (`library.dynamic`, buildable folder → the package directory, `EXECUTABLE_PREFIX = lib`, `SKIP_INSTALL = YES`, `GCC_SYMBOLS_PRIVATE_EXTERN = YES`), embedded by the app's "Embed Media Bridge" Copy Files phase into `Contents/Frameworks` with `CodeSignOnCopy`. The app **does not link it**. The universal Release build produced `x86_64 arm64`, `flags=0x10002(adhoc,runtime)`, only `_cranny_bridge_main` exported, and `/usr/bin/perl` returned `hello`, `pong`, `state`, `artwork` [VERIFIED, Appendix C].
- **Locator** (`BridgeLocator`): `CRANNY_MEDIA_BRIDGE` env override → `Bundle.main.privateFrameworksURL/libCrannyMediaBridge.dylib` → next to the executable (SwiftPM tools/tests).
- **Quarantine:** a quarantined, non-notarized dylib makes perl block on a Gatekeeper prompt or refuse it [VERIFIED R2/R4]. Before spawning, `getxattr(path, "com.apple.quarantine")`; if present, copy the dylib to `AppPaths.directory(for: .media)/libCrannyMediaBridge.dylib` (files Cranny writes are not quarantined) and use the copy; log it.
- Loader programs (R2, verified): perl `-e 'use strict; use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die …; my $s = DynaLoader::dl_find_symbol($h, "cranny_bridge_main") or die …; DynaLoader::dl_install_xsub("main::bridge", $s); bridge();'`; ruby `-e 'require "fiddle"; h = Fiddle.dlopen(ARGV[0]); Fiddle::Function.new(h["cranny_bridge_main"], [], Fiddle::TYPE_VOID).call'`. Environment `["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]` only.
- The helper shows as "perl" (child of Cranny) in Activity Monitor; README FAQ explains it.

### 6.4 Provider contract (module-internal, `nonisolated`)

R2's verified `MediaProvider` protocol and `ProviderEvent` (`.nowPlaying(NowPlaying?)`, `.artwork(trackKey:data:)`, `.unavailable(reason:)`), `BridgeConnection` (process + pipes + buffer confined to a private serial queue; 4-s handshake watchdog; 8-MB corrupt-stream guard), `MediaRemoteBridgeProvider` and `AppleScriptProvider` are adopted with these changes: models come from Core (`NowPlaying`, `MediaCommand`, `ShuffleMode`, `RepeatMode`); R2's `ArtworkPalette` and `RGB` are dropped (D9); force unwraps in R2's code (`Bundle.main.executableURL!`, `CGColorSpace(...)!`, vDSP setup `!`) are rewritten with `guard`.

### 6.5 `MediaService` behaviour (implements `NowPlayingSource`)

- **Failover:** on `.unavailable`, restart the same provider after 0.5 s, 2 s, 8 s; 3 failures within 60 s → next provider [VERIFIED R2 demo]. AppleScript is used only if `MediaSettings.allowAppleEvents` (default **off**: it needs per-app Automation prompts); it never launches a player (checks `runningApplications` first), wraps scripts in `with timeout of 2 seconds`, treats −1743 as "denied" and reports it to `PermissionsCenter`.
- **Commands:** play/pause/toggle/seek update `nowPlaying` optimistically; the next provider state (60–75 ms) is authoritative. Commands are acknowledged in ≈ 12 ms.
- **Progress:** `NowPlaying.position(at:)` interpolation; a `TimelineView` ticks only in visible views; MediaRemote is never polled.
- **Track change → peek:** `trackChangeCount` increments when `trackKey` changes, debounced 300 ms, only while playing, never for the first snapshot after launch. The Now Playing activity bumps its `revision` on it (the shell peeks if "Peek on change" is on).
- **Artwork:** decode off the main actor with `CGImageSourceCreateThumbnailAtIndex` (max 512 px, transform applied); palette with Core's `AmbientPalette.extract(from:)` (0.021 ms per artwork in release, DESIGN App. C); LRU of 16 by `trackKey`; late artwork for the current track is applied, never cleared for the same track key (seek glitch).
- **Filters:** `MediaSettings.ignoredBundleIDs`, `showsBrowserMedia` (browser bundle IDs filtered when off). Sessions without a title count as nothing playing.
- **Blocked-bridge detection** (R2 §5.4): if any Core Audio process has `kAudioProcessPropertyIsRunningOutput == 1` for > 10 s while the bridge reports nothing playing, mark the provider "degraded", show it in Settings ▸ Media with an "Allow Apple Events fallback" suggestion, and include it in diagnostics. "Test media detection" button: checks that the helper answers `ping` and, while Core Audio reports output, that `state` carries a PID and title. (R2's fake `MPNowPlayingInfoCenter` publisher is a test tool only; Cranny itself must never publish now-playing info, or it becomes the elected player.)

### 6.6 Visualizer (DESIGN.md §9.2 visual spec, R2 §8 costs)

| Mode (`MediaSettings.visualizer`) | Source | Rendering |
|---|---|---|
| **Ambient** (default) | `SyntheticSpectrum` (pure): incommensurate sines × a 100–120 BPM pulse seeded by `trackKey`, eased to rest on pause | Compact/peek: **Core Animation layers** in an `NSViewRepresentable` (`CAKeyframeAnimation` or 30 Hz data-driven transforms inside `CATransaction.setDisableActions(true)`) — 0.06–0.34 % CPU. **Never** SwiftUI `TimelineView`+`Canvas` for the always-on bars (4.6–4.8 % CPU) [VERIFIED R2]. Open widget: `Canvas` ≤ 30 fps only while open. |
| **Live** (opt-in) | `SystemAudioTap` (macOS 14.2+): `CATapDescription(stereoGlobalTapButExcludeProcesses: [Cranny])` + private aggregate device + IO proc pushing mono into a try-lock ring; `SpectrumAnalyzer` FFT 1024 → 24 log bands at display rate (≈ 1.5 µs per frame) | Same renderers; RMS → `audioEnergy` (60 ms attack / 300 ms release) for the aurora. Runs only while playing, a viz is visible, not Low Power/locked/asleep; stops after 10 s paused. Permission state is inferred (silence / `kAudioDevicePermissionsError`) and reported with `permissions.record(_:for: .systemAudioRecording)`. Tap global-excluding-self, not per-PID (browser audio comes from helper processes [VERIFIED R2 test i]). [UNVERIFIED at runtime: never started, to avoid the prompt] |
| Static / Off | — | Static dots / nothing |

Energy (DESIGN.md §4.7): ≤ 30 fps on AC, ≤ 20 fps on battery, only while audio plays; paused → static. Reduce Motion → static bars.

### 6.7 Surfaces

- **Media widget** (DESIGN.md §7.1): artwork (`.notchMatched(MatchedID.mediaArtwork)`, album glow), title (`MarqueeText`), artist, `Scrubber` (+ `.crannyScrollZone` horizontal seek, `.levelChange` haptic at 10 %), transport (prominent ⏯), 6 cells: shuffle/repeat/output. Track swipe over artwork/title via `.crannyScrollZone`. Click artwork → open the source app (`urlForApplication(withBundleIdentifier:)` + `openApplication(at:configuration:)`).
- **Now Playing activity:** slot `.short`; leading artwork 20u (matched), trailing 5-bar visualizer; peek row artwork 40 + title/artist + ⏮⏯⏭ + 2-pt progress; `palette` = album palette; `opensWidget = .media`; `handle(.swipeLeft/.swipeRight)` → previous/next; P2 while playing, P3 while paused, inactive after `hidePausedAfterSeconds`; sample instance with a fictional track for Settings/onboarding.
- **Settings ▸ Media** page (registry): provider status (perl/ruby/AppleScript/none + last error), visualizer mode (Live asks for System Audio Recording with a why-sheet), ignore apps, show browser media, Apple Events fallback, artwork in compact, peek on track change (writes `CoreSettings.activityPreferences[.nowPlaying]`), test media detection. There is **no "source priority"**: MediaRemote exposes only the system-elected player (R2 §9.6), so ordering sources is impossible; the ignore list is the only control. "Hide paused media after N s" is the Now Playing activity's options row (Live Activities pane).

---

## 7. System services (from R3)

### 7.1 HUD — volume, brightness, keyboard backlight (CrannyHUD)

- **Mechanism [VERIFIED R3 §1.2]:** a session-level active `CGEventTap` (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`) on `NX_SYSDEFINED` (subtype 8, aux control buttons). Consuming a volume key suppresses **both** the system change and the macOS 27 OSD (a 352 × 149 MenuBarAgent window); Cranny then applies the change itself. Changing volume through CoreAudio never shows the OSD. Decode `NSEvent(cgEvent:).data1`: key code = bits 31–16, `0x0A` down / `0x0B` up, bit 0 repeat; ⌥⇧ = fine steps.
- **Thread:** the tap runs on its own `Thread` + `CFRunLoop` (`MediaKeyInterceptor`, R3 reference code) so a busy main thread never trips `tapDisabledByTimeout`; the callback re-enables a disabled tap. The handler must return within microseconds: it reads an immutable configuration snapshot (`OSAllocatedUnfairLock<HUDTapConfig>`, written by the main actor when settings/permission change), applies volume through CoreAudio on the tap thread (thread-safe), and posts UI updates with `Task { @MainActor in … }`.
- **Consume vs pass through** (return `false` = the system handles it): feature off or Accessibility missing (then no tap at all) · output device has no settable `VirtualMainVolume` (HDMI/DisplayPort; macOS shows "not adjustable") · no controllable display for brightness (external non-Apple display, lid closed) · ⌥ alone (system opens Sound/Displays settings) · any key we don't own. Key-ups are consumed symmetrically with their key-downs.
- **Volume:** `AudioToolbox`'s `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (needs `import AudioToolbox`), output scope, main element; 16 steps (1/16), ⌥⇧ quarter steps, snap to grid, volume-up unmutes [VERIFIED R3]. `VolumeObserver` (CoreAudio listener, coalesced 15 ms, re-attached on default-device change) keeps the level current and drives the "output device changed" glyph bounce.
- **Brightness** (private, `Private/DisplayBrightness.swift`): `DisplayServices` `GetBrightness/SetBrightness/CanChangeBrightness` via `dlopen`/`dlsym` (loads under hardened runtime without `disable-library-validation` [VERIFIED]); target = built-in display when online and awake. Built-in get/set and real brightness keys on Apple Silicon are [UNVERIFIED] (lid closed during research) — WP9 runs `keylog` (R3 §1.2) on a MacBook with the lid open before enabling it by default.
- **Keyboard backlight** (private `CoreBrightness.KeyboardBrightnessClient`): read verified, write [UNVERIFIED]; low priority (Apple Silicon keyboards have no backlight keys).
- **Feedback sound:** when the global default `com.apple.sound.beep.feedback` is 1 (⇧ inverts), play `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff` (exists on 27.0.1 [VERIFIED]) with `NSSound`; muted in Demo mode.
- **UI:** one `HUDActivity` (`.hud`, priority `.hud`, slot `.wide`, `expiresAt = now + HUDSettings.duration` refreshed per press, `revision` per press). Only the bar (`LevelBar`, `hudLevel`) and digits animate after the first press; 2-pt bump at 0/100 % with `.levelChange`. Colours Mono (default white) / Accent / Semantic; ticks under Differentiate Without Color or fine steps; VoiceOver "Volume, 62 percent" on settle.
- **Never two HUDs (D10):** without Accessibility, or with `HUDSettings.replaceSystemHUD` off, there is no tap and no HUD; Settings ▸ HUD shows a status pill and "Open System Settings". Other HUD apps with their own taps compete (head insert wins); detect known bundle IDs (MonitorControl, volumeHUD, SoundSource) and warn [UNVERIFIED list].

### 7.2 Battery and charging (CrannySystemActivities) [VERIFIED R3 §2]

`IOPSCopyPowerSourcesInfo`/`List`/`GetPowerSourceDescription`, `IOPSGetProvidingPowerSourceType`, `IOPSCopyExternalPowerAdapterDetails`; `IOPSNotificationCreateRunLoopSource` (C callback without captures — route through a static/context) + `NSProcessInfoPowerStateDidChange`. Model has **three** charge states: charging · discharging · **plugged in, not charging** (charge limit / optimized charging). Desktop Macs have no internal battery → activities never activate. Activities: **Charging** (P1 transient 2.6 s on plug/unplug, `.charging` palette, `delight = .chargeSweep` on plug-in), **Low battery** (P1 at 20 % and 10 %, persists ≤ 10 %; peek row "Low Power Mode…" opens `x-apple.systempreferences:com.apple.Battery-Settings.extension` [UNVERIFIED anchor] — D18). Thresholds are the Low battery activity's options row in Settings ▸ Live Activities (there is no System pane).

### 7.3 Bluetooth accessories (CrannySystemActivities) [VERIFIED R3 §3]

Permission-free by default: (1) CoreAudio device list + default-output listener, transport `'blue'`/`'blea'`, for "headphones connected"; (2) IOKit HID matching on `AppleDeviceManagementHIDEventService` (`BatteryPercent`, `Product`, `ProductID`, add/terminate notifications) for Magic devices; (3) private `IOPSCopyPowerSourcesByType(4)` via `dlsym` for AirPods Left/Right/Case/Combined. Refresh on those notifications and every 60 s only while the Bluetooth activity is visible. Opt-in `SystemSettings.showsAllBluetoothDevices` (the Bluetooth activity's options row) uses IOBluetooth (needs the Bluetooth prompt via `PermissionsCenter.request(.bluetooth)`; private `batteryPercent*` selectors guarded with `responds(to:)`). Symbols mapped from vendor 76 product IDs (data table) with category fallbacks; restricted symbols (`airpods*`, `beats.*`) only for those products; `trackpad` and `airdrop` symbols don't exist [VERIFIED].

### 7.4 Calendar (CrannyCalendar) [VERIFIED R3 §4]

- One long-lived `EKEventStore`, recreated after the permission becomes granted (observe `services.permissions`). `requestFullAccessToEvents` only from the widget's "Show your events" button or onboarding.
- Fetch `predicateForEvents(start: startOfDay − daysBehind, end: startOfDay + daysAhead + 1)`, sorted by start; filter cancelled, declined-by-me (`attendees.first { $0.isCurrentUser }?.participantStatus == .declined`), optional all-day/birthdays, hidden calendars (`CalendarSettings.hiddenCalendarIDs`). Refresh on `.EKEventStoreChanged`, wake, `.NSSystemTimeZoneDidChange`, `.NSCalendarDayChanged`.
- **No polling:** one `Task.sleep` to the next boundary (lead time before start, 1 minute before, start, end); while a meeting runs, a once-per-minute tick only while its activity is visible.
- `MeetingLinkDetector` = R3's v2 (Zoom incl. zoomgov/zoommtg, Meet, Teams incl. `/meet/` and SafeLinks unwrapping, Webex, FaceTime, Slack huddle, Whereby, GoTo, Jitsi, Chime; search order URL → location → notes; earliest match wins; 12/12 tests) rewritten without `try!` (patterns validated by unit tests). Join opens the native client when `urlForApplication(toOpen:)` resolves (Zoom `zoommtg://` conversion), else the browser (`CalendarSettings.joinInApp`).
- Activities: **Meeting soon** (P1 at lead time and again at 1 min — two revisions; Join capsule if a link) and **Meeting in progress** (P2, elapsed ring/remaining). Their options rows carry `leadMinutes` and `inEventDisplay` (DESIGN.md shows them in the Live Activities pane). Demo-mode redaction replaces titles. Denied → deep link `Privacy_Calendars`.

### 7.5 Camera mirror (CrannyMirror) [VERIFIED R3 §5 compile/enumeration]

`AVCaptureDevice.DiscoverySession([.builtInWideAngleCamera, .external, .continuityCamera], .video, .unspecified)` (Continuity needs `NSCameraUseContinuityCameraDeviceType`, set in Info.plist); filter Desk View; KVO `systemPreferredCamera`, hot-plug notifications; `isSuspended` (lid closed) → "Camera unavailable" state. `AVCaptureSession` confined to a private serial queue; preview layer in a layer-hosting `NSView`; mirrored via `isVideoMirrored` (or a flipped layer). **Runs only while the Mirror widget is visible in an open Nook** and stops on close, page change, sleep, lock and `isPreview`. Never starts by itself; the first click requests Camera access. Entitlement `com.apple.security.device.camera` (hardened runtime).

### 7.6 Quick Apps and Shortcuts (CrannyQuickApps) [VERIFIED R3 §6]

Apps: `NSWorkspace.openApplication(at:configuration:)` (`activates = true`, `addsToRecentItems = false`), icons via `icon(forFile:)`, bundle IDs resolved with `urlForApplication(withBundleIdentifier:)`, running dots from `didLaunch/didTerminateApplication` notifications, add by `NSOpenPanel` (`.application`) or by dropping an app (`.crannyDropZone(accepts: [.application])`). Shortcuts: `ProcessRunner.run("/usr/bin/shortcuts", ["list", "--show-identifiers"])` → `Name (UUID)`; run by UUID (`["run", uuid]`) off the main actor with cancellation; progress ring, success/failure badges. No glyph API: user-chosen symbol + hue. ⌥1–⌥9 launch while the Nook is key.

### 7.7 AirDrop and sharing (CrannyAppShell `SharingPresenter`) [VERIFIED R3 §7]

`NSSharingService(named: .sendViaAirDrop).perform(withItems:)` activates Cranny itself and centres its sheet on the delegate's `sourceWindowForShareItems` (inheriting its level) — so the shell provides an on-screen anchor (§5.9). `NSSharingServicePicker` shows nothing unless the app is active → `NSApp.activate()` first. Capture `frontmostApplication` before and re-activate it in `didShareItems`/`didFailToShareItems`. Exposed to modules only as `NotchControl.presentAirDrop(_:)` / `presentSharePicker(_:)`.

### 7.8 Tray storage and pipelines (CrannyTray) [VERIFIED R3 §8]

- **Storage:** copy dropped files into `AppPaths.directory(for: .tray)/<uuid>/<name>` by default (originals may be temporary — screenshots, promises — and re-reading Desktop/Documents/Downloads later can prompt); index in `tray/index.json` (`JSONFileStore`) with UUID, original bookmark (non-sandboxed bookmarks survive moves, `isStale` → re-save; fail after delete), size, date. "Link to original" is an option. Retention: until removed (default) / clear on quit / after 1 day; size and item caps.
- **Thumbnails:** `QLThumbnailGenerator` (`iconMode`), fallback `NSWorkspace.icon(forFile:)`; cached.
- **Drag out:** AppKit `NSDraggingSource` + `NSURL` writers (original file), `.move` removes the item; generated files via `NSFilePromiseProvider` [UNVERIFIED].
- **Pipelines** (`@concurrent`, cancellable, progress reported to the tile): ImageIO compress/convert/resize (write types queried at runtime with `CGImageDestinationCopyTypeIdentifiers()` — AVIF encodes on 27, WebP/JPEG-XL are decode-only), `kCGImageDestinationLossyCompressionQuality`, thumbnails with transform, optional metadata strip; zip `ditto -c -k --sequesterRsrc --keepParent`, unzip `ditto -x -k`; copy paths; reveal; Vision remove background / OCR; PDFKit images → PDF; `AVAssetExportSession` video compress (`export(to:as:)` on 15+, `export()` fallback). User pipelines are chains of these steps stored in `TraySettings.userPipelines`; up to 3 pinned pipelines appear as catch-state drop zones. Results go next to the source (or to Downloads for tray-owned files), slide in with an Undo chip for 5 s.
- **Quick Look** with Space from a non-activating panel is [UNVERIFIED]: WP8 tests `QLPreviewPanel`; fallback opens Quick Look after `NSApp.activate()`.

### 7.9 Launch at login (CrannyAppShell `LoginItemController`)

`SMAppService.mainApp` `register()`/`unregister()`, status read every time Settings/onboarding shows it (never cached): `.enabled`, `.requiresApproval` (→ `SMAppService.openSystemSettingsLoginItems()`), `.notRegistered`/`.notFound` = off [VERIFIED status API; `register()` UNVERIFIED for ad-hoc builds — R3 test plan]. Prompt users to move the app to /Applications (App Translocation breaks login items).

### 7.10 Environment (CrannyAppShell `ShellEnvironment`, implements `SystemEnvironment`)

Lock: distributed `com.apple.screenIsLocked/Unlocked` + `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` (undocumented, long-standing). Sleep: `NSWorkspace.screensDidSleep/Wake`, `willSleep/didWake`, `sessionDidResignActive/BecomeActive`. Power: `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`, `thermalState` + notification, AC vs battery via `IOPSGetProvidingPowerSourceType`. Frontmost: `didActivateApplicationNotification`. Full screen: §5.7. Trackpad presence: IOKit HID (built-in or Magic Trackpad). All event-driven; `activeSpaceDidChange` needs the real `NSApp.run()` loop [VERIFIED R3 §10]. Screen-sharing detection has no public API → not shipped in v1; Demo mode covers recordings.

### 7.11 Update check (CrannyAppShell `UpdateChecker`)

Daily (and on demand) `GET https://api.github.com/repos/<CrannyGitHubRepository>/releases` (`/latest` unless pre-releases are included), ephemeral `URLSession`, `If-None-Match` with the stored ETag, no cookies, no identifiers. Compare tag with `SemanticVersion`; show "Update available" in the menu bar extra and About with a link to the release page; never downloads or installs. Empty `CrannyGitHubRepository` (Info.plist) disables the check. This is Cranny's only network access.

### 7.12 Private API register

All private symbols are resolved at runtime with `dlopen`/`dlsym` or `responds(to:)` (never linked), live in a `Private/` folder of the **one** module that uses them, have a capability probe and a graceful fallback, and are listed here. Hardened runtime loads them without `disable-library-validation` [VERIFIED R3].

| Symbol / key | Module | Fallback |
|---|---|---|
| MediaRemote `MRMediaRemote*` | CrannyMediaBridge (in perl) | ruby host → AppleScript (opt-in) → nothing |
| DisplayServices `Get/Set/CanChangeBrightness` | CrannyHUD | pass brightness keys through |
| CoreBrightness `KeyboardBrightnessClient` | CrannyHUD | pass keys through |
| IOKit `IOPSCopyPowerSourcesByType(4)` | CrannySystemActivities | CoreAudio + HID sources only |
| IOBluetooth `batteryPercent*` selectors (opt-in path) | CrannySystemActivities | connection without battery |
| `CGSSessionScreenIsLocked` session key, `com.apple.screenIsLocked` notifications | CrannyAppShell | sleep/session notifications |

### 7.13 Permission matrix

| Feature | API | TCC service | Info.plist key | Hardened-runtime entitlement | Asked when | Without it |
|---|---|---|---|---|---|---|
| HUD replacement | CGEventTap on `NX_SYSDEFINED` | Accessibility | — (fixed system text) | — | Settings ▸ HUD "Replace the system HUD" or onboarding step 5 | no HUD at all (D10) |
| Calendar widget & meetings | EventKit | Calendars | `NSCalendarsFullAccessUsageDescription` (+ legacy `NSCalendarsUsageDescription`) | `com.apple.security.personal-information.calendars` | widget "Show your events" / onboarding | "Show your events" state |
| Mirror | AVFoundation | Camera | `NSCameraUsageDescription`, `NSCameraUseContinuityCameraDeviceType` | `com.apple.security.device.camera` | first click on Mirror (never in onboarding) | placeholder |
| Media fallback | Apple Events to Music/Spotify | Automation (per app) | `NSAppleEventsUsageDescription` | `com.apple.security.automation.apple-events` | enabling "Apple Events fallback" | MediaRemote bridge only |
| Live visualizer | Core Audio process tap (14.2+) | System Audio Recording | `NSAudioCaptureUsageDescription` (hand-written plist; no `INFOPLIST_KEY_`) | `com.apple.security.device.audio-input` (kept; need [UNVERIFIED]) | choosing Live in Settings ▸ Media (why-sheet first) | Ambient visualizer |
| All Bluetooth devices (opt-in) | IOBluetooth | Bluetooth | `NSBluetoothAlwaysUsageDescription` | — (sandbox-only entitlement) | enabling the option | permission-free sources |
| Tray file references | FileManager | Files & Folders | Desktop/Documents/Downloads/Removable/Network folder strings | — | only with "Link to original" | copies (default) |
| Global shortcuts, gestures, hover | Carbon hot keys, NSEvent mouse monitors, panel scroll events | none [VERIFIED] | — | — | — | — |
| Launch at login | SMAppService | Login Items | — | — | Settings / onboarding toggle | — |

`NSMicrophoneUsageDescription` and the `device.audio-input` entitlement are present only as a safety net for the audio tap; WP1 verifies whether the tap needs them and **reports** the result — WP-Final edits `App/Info.plist`, `InfoPlist.xcstrings` and the entitlements (WP0/WP-Final-owned files, §10.0). `tccutil reset All app.cranny.Cranny` resets everything during development (service names `Accessibility`, `AppleEvents`, `Calendar`, `Camera`, `AudioCapture`, `BluetoothAlways` [VERIFIED R4 §8]).

---

## 8. Build, packaging and localization (from R4)

### 8.1 Xcode project facts [VERIFIED]

- Hand-written `project.pbxproj`, **objectVersion 77** (Xcode 16+ buildable folders), full text in Appendix B.1. Objects: `PBXFileSystemSynchronizedRootGroup` "App" (`path = App`) with a `PBXFileSystemSynchronizedBuildFileExceptionSet` excluding `Info.plist` from Copy Bundle Resources; a second synchronized group pointing **into the package** at `Packages/CrannyKit/Sources/CrannyMediaBridge` for the dylib target; `XCLocalSwiftPackageReference` (`relativePath = Packages/CrannyKit`) and `XCSwiftPackageProductDependency` `CrannyAppShell` (no `package =` key needed for local packages).
- Targets: **Cranny** (application; phases Sources, Frameworks, Resources, "Embed Media Bridge" Copy Files → Frameworks with `CodeSignOnCopy`; target dependency on the bridge) and **CrannyMediaBridge** (`library.dynamic`). Every product in `packageProductDependencies` is linked automatically; dynamic products are not embedded automatically — another reason to link only the static `CrannyAppShell`.
- Schemes: shared `Cranny` (Appendix B.2) + auto-generated package schemes. `xcodebuild -list` shows targets Cranny and CrannyMediaBridge.
- **Universal builds need `-destination 'generic/platform=macOS'`**; without it xcodebuild silently builds arm64 only [VERIFIED R4 §5]. `scripts/build.sh` passes it.
- New Swift files, resources and catalogs never touch the project. Adding a *target* to the project (not expected) means editing it by hand or in Xcode (Xcode may reformat the file on first open — harmless).

### 8.2 Build settings (target "Cranny"; shared ones at project level)

| Setting | Value | Why |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `app.cranny.Cranny` | D16 |
| `MACOSX_DEPLOYMENT_TARGET` | 14.0 | project level |
| `SWIFT_VERSION` / `SWIFT_DEFAULT_ACTOR_ISOLATION` / `SWIFT_APPROACHABLE_CONCURRENCY` / `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | 6.0 / MainActor / YES / YES | same flags as the package's shell targets |
| `ENABLE_HARDENED_RUNTIME` | YES | notarization; resource-access entitlements |
| `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE` / `DEVELOPMENT_TEAM` | `-` / Manual / "" | builds for anyone without an Apple account |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | NO (Release) | else ad-hoc Release ships `get-task-allow` [VERIFIED R4] |
| `CODE_SIGN_ENTITLEMENTS` | `App/Cranny.entitlements` | |
| `GENERATE_INFOPLIST_FILE` + `INFOPLIST_FILE` | YES + `App/Info.plist` | file keys merged with generated ones [VERIFIED] |
| `INFOPLIST_KEY_CFBundleDisplayName` / `INFOPLIST_KEY_NSPrincipalClass` | Cranny / NSApplication | |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | 0.1.0 / 1 in the project; **overridden** by `scripts/build.sh` from `VERSION` / `BUILD_NUMBER` | single source of truth = `VERSION` |
| `LOCALIZATION_PREFERS_STRING_CATALOGS`, `SWIFT_EMIT_LOC_STRINGS`, `STRING_CATALOG_GENERATE_SYMBOLS` | YES | |
| `ASSETCATALOG_COMPILER_APPICON_NAME` / `…GLOBAL_ACCENT_COLOR_NAME` | AppIcon / AccentColor | `AppIcon.icon` wins over an `.appiconset` of the same name |
| `LD_RUNPATH_SEARCH_PATHS` | `$(inherited) @executable_path/../Frameworks` | |
| `ONLY_ACTIVE_ARCH` | YES Debug / NO Release (+ `-destination generic`) | |
| Bridge target: `EXECUTABLE_PREFIX`, `SKIP_INSTALL`, `DYLIB_INSTALL_NAME_BASE`, `GCC_SYMBOLS_PRIVATE_EXTERN`, `USER_HEADER_SEARCH_PATHS` | lib / YES / @rpath / **YES** / `$(SRCROOT)/Packages/CrannyKit/Sources/CrannyMediaBridge/include` | exports only `cranny_bridge_main` [VERIFIED] |

**Debug vs Release hardening:** with ad-hoc signing and `ENABLE_XOJIT_PREVIEWS = YES` (the Debug default), Xcode disables hardened runtime for Debug, so library-validation and missing-entitlement bugs only reproduce in Release. `scripts/run.sh` builds Debug with `ENABLE_XOJIT_PREVIEWS=NO` → `flags=0x10002(adhoc,runtime)` [VERIFIED in the new layout]. Xcode IDE runs keep previews working.

### 8.3 Info.plist, entitlements, usage strings

`App/Info.plist` (Appendix B.3) adds: `LSUIElement`, `LSApplicationCategoryType`, copyright, **`CFBundleLocalizations` [en, ru]** (without it package bundles fall back to English [VERIFIED R4]), `CrannyGitHubRepository` (empty = no update check), every usage description of §7.13 and `NSCameraUseContinuityCameraDeviceType`. `App/InfoPlist.xcstrings` (Appendix B.4) localizes all of them into Russian; the merged plist and `ru.lproj/InfoPlist.strings` were checked with `plutil` [VERIFIED]. `App/Cranny.entitlements` (Appendix B.5): `automation.apple-events`, `device.camera`, `device.audio-input`, `personal-information.calendars`; **no App Sandbox** (the perl child, event taps and Apple Events need it unsandboxed), **no `cs.disable-library-validation`**.

### 8.4 Icon and assets

`App/AppIcon.icon` (Icon Composer) is the single icon source; actool generates `AppIcon.icns` (16–256 px) and `Assets.car` renditions for macOS 14/15 [VERIFIED R4 §6]. The final artwork follows DESIGN.md §15 ("Light from the nook"); WP-Final authors it in Icon Composer (`ictool` renders previews: `/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool`). `Assets.xcassets` holds `AccentColor` only. Module images, if any, go in the module's `Resources/` (prefer SF Symbols and code-drawn shapes; no videos, GIFs or Lottie). About and onboarding show the real icon with `NSApp.applicationIconImage` (no second renderer); the menu-bar template icon is drawn in code (§5.9). DESIGN.md §15's CoreGraphics `CrannyIconRenderer` is optional tooling, not part of v1. Never bundle SF Pro/SF Mono or any Apple font (system fonts are used at runtime only).

### 8.5 Scripts and Makefile (Appendix B.7–B.14)

| Command | Script | Does |
|---|---|---|
| `make build` | `scripts/build.sh` | Universal Release → `build/Cranny.app` + dSYM; version from `VERSION`; verifies the signature; ≈ 21 s clean on M4 Max |
| `make debug` | `CONFIGURATION=Debug ARCHS=$(uname -m) scripts/build.sh` | Debug build |
| `make run` | `scripts/run.sh` | Debug (hardened), quits the previous dev instance, launches with `open -n` so TCC attributes prompts to Cranny, not the terminal [VERIFIED R4 §8]; `DEV_SIGN_IDENTITY="Cranny Dev"` signs with a stable identity |
| `make smoke` | `scripts/smoke.sh` | Runs `Cranny --diagnostics` (no UI), checks all 16 resource bundles, the bridge dylib and the Edit menu [VERIFIED] |
| `make check` | `scripts/check-modules.sh [Target…]` | `swift build --target` per target in its own scratch dir; `JOBS=N`, `TEST=1` |
| `make test` | `swift test` | Swift Testing |
| `make strings` / `make strings-check` | `scripts/sync-strings.sh` | Adds new keys from the compiler's `.stringsdata` to each catalog with `xcstringstool sync`; `CHECK=1` fails CI when stale (≈ 25 s for all targets) |
| `make dist` | `scripts/dist.sh` | zip (`ditto --norsrc --keepParent`) + APFS DMG + sha256; notarizes and staples when `SIGN_IDENTITY`, `TEAM_ID`, `NOTARY_PROFILE` are set |
| `make list`, `make clean`, `make distclean` | | |

Scripts target `/bin/bash` 3.2, source `scripts/lib.sh`, find Xcode even when `xcode-select` points at the Command Line Tools (`DEVELOPER_DIR`), and require Xcode ≥ 26. **Exception:** `make strings`/`strings-check` read the swift-build backend's `out/Intermediates.noindex` layout; the script now passes `--build-system swiftbuild` explicitly (VERIFIED on Swift 6.4), which Xcode 26's SwiftPM 6.2 may not support [UNVERIFIED] — treat Xcode 27 as the minimum for the strings steps (CI pins it, §8.9). Bash scripts are not affected by zsh profile noise (`#!/usr/bin/env bash` is non-interactive).

### 8.6 Signing, distribution and TCC during development

- **Default:** ad-hoc signing with hardened runtime; anyone can build. Ad-hoc designated requirement = `cdhash`, so **every rebuild loses Accessibility, Camera, Calendar and Automation grants** [VERIFIED R3/R4]. Contributors who test permission features create a self-signed "Cranny Dev" code-signing certificate (Keychain Access ▸ Certificate Assistant) and run `DEV_SIGN_IDENTITY="Cranny Dev" make run` [UNVERIFIED: no identity on this Mac]. Reset with `tccutil reset All app.cranny.Cranny`.
- **Releases:** Developer ID Application + hardened runtime + secure timestamp + notarization + staple (`release.yml` imports the certificate and notary key when the secrets exist) so the embedded bridge is covered by the ticket [UNVERIFIED end-to-end]. Without a Developer ID, releases are ad-hoc and the README documents System Settings ▸ Privacy & Security ▸ "Open Anyway" or `xattr -dr com.apple.quarantine /Applications/Cranny.app`, plus the media module's quarantine copy (§6.3).
- **Launch from Finder/`open`, not by exec'ing the binary**, when testing permissions (responsible process). `scripts/smoke.sh` execs the binary on purpose (CI; no TCC involved).

### 8.7 Localization strategy [VERIFIED R4 §3.4 + this document]

1. **One String Catalog per target**: `Sources/<Target>/Resources/Localizable.xcstrings`, compiled into `Contents/Resources/CrannyKit_<Target>.bundle`. No shared localization file; nobody edits another target's catalog. App-level strings (usage descriptions, display name) live in `App/InfoPlist.xcstrings`.
2. **Always pass the module bundle:** `Text("Nothing playing", bundle: .module, comment: "…")`, `String(localized: "…", bundle: .module, comment: "…")`, `Label { Text(…, bundle: .module) } icon: { … }`, `Toggle(isOn:) { Text(…, bundle: .module) }`, `.accessibilityLabel(Text(…, bundle: .module))`, `.help(String(localized: …))`. Never use initializers that take a bare `LocalizedStringKey` (`Text("…")`, `Button("…")`, `Toggle("…", isOn:)`, `LabeledContent("…")`) inside the package — they read `Bundle.main` and stay English [VERIFIED R4]. `#bundle` is an equivalent alternative to `.module`.
3. **Keys are the English source text in sentence case**, every key has a translator comment, interpolations use format specifiers through `String(localized: "\(count) minutes left", …)` with plural variations in the catalog (ru: one/few/many/other). If the same English text needs different translations, use distinct keys with `defaultValue:`; one comment per key otherwise (`sync` warns about conflicting comments).
4. **Workflow:** write code → `make strings` (adds keys with comments, never deletes) → add Russian translations (state `translated`) in Xcode's catalog editor or JSON → `make strings-check` must pass in CI. `xcstringstool extract` is not used (it turns interpolations into `%arg`).
5. **Formatting** through `FormatStyle` only (`Duration.formatted`, `Date.formatted`, `.percent`); 12/24-hour from the locale; no string concatenation of translatable fragments.
6. **Length:** Russian runs 15–35 % longer; compact slots never hold free text except tested `compactLabel` abbreviations; tabs collapse to icons; pseudo-localisation at 1.4× in snapshot checks (WP-Final).
7. **Glossary** (keep it consistent across 17 catalogs; WP-Final reviews):

| English | Russian | Note |
|---|---|---|
| Cranny | Cranny | never translated; also the name of the open panel in UI copy ("Open Cranny" / «Открыть Cranny») |
| notch | вырез (экрана) | |
| Home (the built-in grid page) | Главная | code id `nook`; the word "Nook" never appears in UI text (D20) |
| Layout & Widgets (Settings pane) | Раскладка и виджеты | |
| layout (a page of widgets, onboarding presets) | раскладка | |
| Tray | Лоток | |
| live activity / Live Activities | активность / Активности | |
| peek | мини-просмотр | not «Быстрый просмотр» (= Quick Look) |
| pipeline | конвейер | |
| widget | виджет | |
| Mirror | Зеркало | |
| Notes · To-dos · Timer · Calendar | Заметки · Задачи · Таймер · Календарь | |
| Quick Apps · Shortcuts (app) | Быстрые приложения · Быстрые команды | Apple's Russian name for Shortcuts |
| Pin / Keep open | Закрепить | |
| Demo mode | Демо-режим | |
| Settings | Настройки | |
| Join (meeting) | Подключиться | |

8. **Competitor-term denylist** (clean room, D20): no UI string may contain "Nook", "NotchNook", "Notch Nook", "boring.notch", "Alcove", "Atoll" or text copied from their UIs. WP-Final greps every `.xcstrings` and `App/InfoPlist.xcstrings` for the list before each release; generic words that competitors also use ("Tray", "Mirror", "Live Activities") are allowed but never in the same pairing/ordering as a competitor's UI.

### 8.8 Resource strategy

Each target declares `resources: [.process("Resources")]` and must keep that folder (with at least the catalog). Access resources only through `Bundle.module` (the generated accessor is `nonisolated` and finds `CrannyKit_<Target>.bundle` in `Contents/Resources` [VERIFIED]). No `Bundle.main` lookups for package resources; no absolute paths. Sounds are system sounds only (DESIGN.md §14.3); Cranny ships no audio, video or Lottie files.

### 8.9 CI (Appendix B.15–B.16)

`ci.yml` (push to main, PRs, manual) on the GitHub `xcode-27` image (arm64, macOS 27.0.1, Xcode 27.0; public preview; fallback `macos-26` with Xcode 26.6): toolchain info → `JOBS=3 TEST=1 scripts/check-modules.sh` → `CHECK=1 scripts/sync-strings.sh` → universal `scripts/build.sh` → **`scripts/smoke.sh`** → `scripts/dist.sh` → upload zip/dmg/sha256 (logs on failure). `release.yml` (tags `v*`): checks the tag equals `VERSION`, optionally imports Developer ID + notary key, builds, smoke-tests, packages/notarizes and publishes a GitHub Release with generated notes. Both YAML files parse [VERIFIED]; neither has run on GitHub yet [UNVERIFIED], including the runner label and the `actions/*@v7` major versions — WP0 pins whatever exists on its first green run. The `macos-26` fallback job runs everything **except** `strings-check` (Xcode 27 only, §8.5). The Metal Toolchain is not required anywhere (D13). x86_64 slices are built but never executed (no Rosetta here): WP-Final adds an Intel smoke job (`--diagnostics`) if an Intel runner label is available [UNVERIFIED]. `hdiutil create` prints a deprecation warning on macOS 27 (still works); move `dist.sh` to `diskutil image create` when it breaks.

---

## 9. Engineering rules

### 9.1 Concurrency

1. **UI and façades are `@MainActor`** (module default). Models that are persisted or cross threads are `nonisolated struct …: Codable, Sendable`.
2. **Leave the main actor explicitly:** `@concurrent` functions for CPU/IO (image pipelines, artwork decode, file copies, JSON of large documents, `ProcessRunner`); `actor`s for shared mutable stores (`JSONFileStore`). With `NonisolatedNonsendingByDefault`, a plain `nonisolated async` function still runs on the caller's actor.
3. **Dedicated threads/queues only where an OS API demands them:** the event-tap thread (HUD), CoreAudio listener/IO queues, the camera session queue, the bridge's pipe queue. Each is confined, documented at the top of its file, and talks to the main actor with `Task { @MainActor in … }`.
4. **`MainActor.assumeIsolated`** only inside callbacks documented to run on the main thread (NSEvent monitors, `NotificationCenter` with `queue: .main`, Carbon handlers dispatched to main) — with a comment. No `DispatchQueue.main.sync`, no semaphores waiting on the main thread.
5. **`@unchecked Sendable`** only for small wrappers whose thread-safety is argued in a comment (R2's `BridgeConnection`, lock-protected boxes). Prefer `OSAllocatedUnfairLock` (macOS 13+) over `NSLock` in new code; `Synchronization.Mutex` needs macOS 15 and is only usable behind `#available`.
6. Observation: views read `@Observable` models directly; non-view code uses `observe(_:onChange:)` (Core). No Combine.
7. Cancellation: every long task is a `Task` stored by its owner and cancelled on stop/deinit; `Task.sleep` to deadlines instead of repeating timers.

### 9.2 Performance and energy (release gate, DESIGN.md §4.7)

- **Closed with nothing playing = zero work:** no timers, no `TimelineView`, no Canvas, no polling. Everything is event-driven (notifications, KVO, CoreAudio/IOKit callbacks, MR notifications through the bridge).
- **Timers only while visible:** `TimelineView(.animation(minimumInterval:paused:))` with `paused` bound to visibility/need; compact visualizer on Core Animation; open-Nook effects ≤ 30 fps on AC, ≤ 20 fps on battery, static halo in Low Power Mode or `thermalState ≥ .serious`, paused when occluded (`NSWindow.occlusionState`) or a full-screen app is in front; Reduce Motion freezes a resting frame.
- **Allowed polling (exhaustive):** Accessibility grant check every 1.5 s for ≤ 2 min after a request; accessory batteries every 60 s only while the Bluetooth activity is visible; passive brightness at 2 Hz only while a brightness HUD is visible.
- **Hardware only while visible:** camera, audio tap; stop on close, lock, sleep, page change.
- **No I/O on the main actor** except tiny settings reads (UserDefaults). Decode images off-main; cache thumbnails and artwork (LRU).
- Targets: Activity Monitor Energy Impact < 1.0 idle; open + aurora ≤ 3 % CPU; no hitches at 120 Hz; measured with Instruments before each release (WP-Final).

### 9.3 Errors and logging

- Each module defines `enum <Module>Error: Error, LocalizedError` with localized one-line `errorDescription`s for anything a user can see; widgets show `WidgetStateView(.error, …)` with a retry action. Never show raw `NSError` text in the UI.
- Expected absences are not errors (no battery, nothing playing, permission not granted → empty/needs-permission state).
- Log with `Log.logger(<category>)` (`import os`): `.error` for failures with context, `.info` for state transitions, `.debug` for chatty details. User content (titles, names, paths) with `privacy: .private`; codes and states `.public`. No `print`.
- **No `fatalError`, `try!`, `as!` or force unwraps (`!`) in production code.** `precondition` only for programmer errors at registration time (duplicate IDs). Regexes are `Regex` literals or built in `do/catch` with a test.
- Private API calls are guarded (`dlsym != nil`, `responds(to:)`) and degrade silently with one `.info` log line.

### 9.4 Code style

- Swift API Design Guidelines; clarity at the call site; no abbreviations except standard ones (URL, ID, HUD).
- Small focused files (≈ ≤ 300 lines), one primary type per file, `// MARK:` sections, doc comments on every `public` declaration.
- Imports are explicit (MemberImportVisibility): `Foundation` for `String(localized:)`, `os` for `Logger` calls, `Observation` for `@Observable`, `SwiftUI`/`AppKit` as used.
- Views: tokens only (`@Environment(\.cranny)`, `crannyFont`, `Space`, `Radius`, `theme.animation(…)`), never literal colours/sizes/animations; SF Symbols only from DESIGN.md §14.1 (no `video*`, restricted symbols only for their products).
- Every view file ends with `#Preview` blocks on black with `.crannyThemeRoot(CrannyTheme())` and `CrannyServices.preview()` data (they compile in `swift build --target` [VERIFIED R4]).
- Access control: module internals `internal`; only the `FeatureModule` type, settings enums and what tests need are `public` (tests use `@testable import`).
- No third-party dependencies; no new targets; no edits outside your package (§10.0).
- Never give a `public` type a name that an Apple framework also exports (Core's `ScrollPhase` collided with `SwiftUI.ScrollPhase` and broke every file importing both; it is `SwipePhase` now). A Core change request lists new public names; the reviewer compiles a probe file that imports `AppKit`, `SwiftUI`, `AVFoundation`, `EventKit`, `CoreAudio`, `IOKit` and `CrannyCore` and aliases each new name (the review's probe found no other collision).
- No `.metal` files and no `ShaderLibrary` (D13); no bundled fonts, sounds, videos, GIFs or Lottie (§8.8).

### 9.5 Accessibility (DESIGN.md §16 is normative)

Every control has an accessibility label (localized), every widget is a VoiceOver container named after itself, every live activity is one element with label, value and named actions (`ActivityAction`), adjustable elements implement `accessibilityAdjustableAction`, decorative layers are `accessibilityHidden`. Nothing is hover-only: each action has click, keyboard and VoiceOver paths. Honour Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color through the theme (never read raw flags in modules). Hit targets ≥ 28 × 24 in the Nook, ≥ 32 × 24 in the band.

### 9.6 Testing

- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) in `Tests/<Target>Tests`. Test pure logic exhaustively: state machine and arbitration (shell), `SwipeTracker`, `HoverIntent`, geometry, `SettingsStore`, `SemanticVersion`, meeting-link detection, calendar windowing, `NowPlaying` interpolation, bridge JSON parsing, synthetic spectrum, tray pipelines on temp files, note/to-do stores, timer deadlines, palette determinism, key-event decoding, pass-through rules.
- Modules are tested alone with `CrannyServices.preview()` and the public doubles (`PreviewNotchControl.calls` records interactions; `emit` simulates shell events).
- Integration tests that need hardware or prompts are opt-in (`CRANNY_INTEGRATION=1`) and never run in CI.
- Manual checklists: §11 (hardware notch, keys, permissions, full screen, multi-display) per release.

### 9.7 Definition of done (every work package)

1. `scripts/check-modules.sh <YourTarget>` passes with **zero warnings**; `swift test --filter <YourTarget>Tests` passes; `make strings-check` passes with Russian translations for every new key.
2. `make build && make smoke` pass; the feature works in `make run` on macOS 14 behaviour paths (`#available` fallbacks exercised by code review) and on 27.
3. Every view has previews, accessibility labels, Reduce Motion/Transparency/Contrast behaviour; energy rules respected (no timers while hidden).
4. Settings keys documented in the module's `<Module>Settings` enum with defaults matching §10; permissions declared; no edits outside the package's folders.
5. Acceptance criteria of the package (§10) demonstrated in the PR description (screen recording for UI).

---

## 10. Work breakdown

### 10.0 Process

**Phases.** **A — WP0 Foundation** (serial, 2 engineers) must be merged before anything else starts. **B — WP1…WP16** run in parallel (10 engineers, staffing in §10.19). **C — WP-Final** integration, QA and release.

**Ownership is by folder.** Each package edits only the folders listed under it (its `Sources/<Target>/…` and `Tests/<Target>Tests/…`, plus named files in `CrannyAppShell`). Shared files — `Package.swift`, `Sources/CrannyCore/**`, `Sources/CrannyNotchUI/{NotchScene, ThemeResolver}.swift`, `App/**` (incl. `Info.plist`, `InfoPlist.xcstrings`, entitlements), `Cranny.xcodeproj/**`, `scripts/**`, `.github/**`, `docs/**`, `THIRD_PARTY_NOTICES.md`, `CompositionRoot.swift`, `AppDelegate.swift`, `CrannyScenes.swift` — belong to WP0 during phase B (WP12 owns `NotchScene.swift` and `ThemeResolver.swift`; WP16 owns `App/ShellContributions.swift`). A package that needs a change in an `App/**` file (usage string, entitlement) files it with WP0; nobody else edits those files.

**Intra-shell interfaces.** `CrannyAppShell` hosts four packages (WP13–WP16). WP0's skeleton fixes these internal signatures (stub bodies) so they can code against each other from day one; changing one is a change request to WP0:
- `OverlayCoordinator` (WP13): `init(registry:environment:)`, `start()`, `let notchControl: ShellNotchControl`, `play(_ state: PreviewStageState, for: Duration)` (backs `AppControl.showOnNotch`), `toggleOpen()`, `setPinned(_:)`.
- `HotKeyCenter` (WP13, `Input/HotKeyCenter.swift`): `apply(_ shortcuts: [GlobalShortcut], bindings: [ShortcutID: KeyCombo?]) -> [ShortcutID: ShortcutState]`, `state(_:) -> ShortcutState`. It re-applies itself when `CoreSettings.shortcuts` changes (observed), so WP16's `setShortcut` only writes the key and returns `state(_:)`.
- `ShellEnvironment` (WP13) derives `isDemoMode`/`areLiveActivitiesPaused` from `CoreSettings.demoMode`/`pausedUntil` by observation; `PauseController`/`DemoMode` (WP16) are the only writers of those keys.
- `SettingsWindowController.show(page:)` (WP14), `WelcomeWindowController.show()` (WP15), `TutorialController.start()` (public in CrannyOnboarding, WP15), `ShellAppServices.start()` (WP16, owns `ShellAppControl`, `LoginItemController`, `UpdateChecker`, `PauseController`, `DemoMode`).
- `App/ShellContributions.swift` (WP16 after WP0 creates it): the shell's `GlobalShortcut`s (Open Cranny, Toggle pin → `OverlayCoordinator`; Pause → `PauseController`), the shell ⌘K provider (Pause for 1 hour, Demo mode, Keep open, Show tutorial, every Settings pane) and nothing else.

**Contract changes during phase B** go through a *Core change request*: a small PR to the owner that is **additive only** (new type, new case with a default, new protocol requirement with a default implementation in an extension, new well-known ID). No renames, no removals, no signature changes. The owner reviews within one working day. Because `CompositionRoot` already registers every module, a module's contributions appear in the app as soon as its PR merges; there is no big-bang integration.

**Branches and CI.** One branch per package (`wp/07-timer`); PRs into `main`; `main` is always green (CI: `check-modules` + tests + strings-check + universal build + smoke + dist). Rebase daily.

**Strings scheme (all packages).** Catalog `Sources/<Target>/Resources/Localizable.xcstrings`; keys are the English text in sentence case; every key has a comment of the form `"<Surface>: <purpose>"` (e.g. `"Timer widget: preset chip, minutes"`); Russian per the §8.7 glossary, state `translated`; `make strings` then `make strings-check`.

**Acceptance (all packages)** = §9.7 Definition of done + the package's own list below.

### 10.1 WP0 — Foundation (serial; first)

- **Targets/folders:** everything listed as shared above; placeholders for all others.
- **Create:** the repository of §1 with the verified files of Appendix B (project, scheme, `App/*`, scripts incl. `smoke.sh`, Makefile, workflows, `.gitignore`, `VERSION` = 0.1.0), `LICENSE` (MIT), `README.md` (build/run, Gatekeeper, permissions FAQ), `THIRD_PARTY_NOTICES.md`, `docs/CONTRIBUTING.md` (§10.0 + §9 summary).
- **CrannyKit:** `Package.swift` (§2.2); **CrannyCore complete**: DesignSystem from DESIGN.md (+ §3.2 amendments, `AmbientPalette.swift`, `SharedComponents.swift`), `Contracts/*`, `Services/*`, `Input/*`, `Settings/*`, `Permissions/*`, `Platform/*` exactly as §3 and Appendix A; Core catalog with Russian; Core tests (settings round-trip incl. dictionary keys, snapshot/restore, `SwipeTracker`, `SemanticVersion`, `HoverIntent.shouldOpen`, `NotchLayout` sizes against DESIGN.md §3.3 incl. panel padding tune, zone hit-testing, `JSONFileStore` corrupt-file handling, `ProcessRunner` with `/bin/echo` and cancellation, registry fills `SettingsPage.namespaces`); the SDK name-collision probe of §9.4.
- **Placeholders:** every layer-1 target gets `<Name>Module.swift` (`FeatureModule` with empty `register`), an empty catalog and one registration test; `CrannyEffects` gets `AuroraField.swift` (DESIGN.md App. B, verbatim); `CrannyMediaBridge` gets R2's v3 bridge (Appendix C verified it).
- **NotchUI skeleton:** `NotchScene.swift` and `ThemeResolver.swift` (§4.12, final API) + a minimal `NotchCanvasView` (idle, compact via `CompactSlots` + `view(for:)` resolving `sampleActivities[id] ?? registry.activity(id)`, open grid of cards from `CoreSettings.pages`) — the verified skeleton is the starting point.
- **AppShell skeleton** (verified skeleton is the starting point): `App/AppDelegate.swift` as a thin orchestrator that owns and starts four components with **final initializers and stub bodies** — `OverlayCoordinator` (WP13), `SettingsWindowController` (WP14), `WelcomeWindowController` (WP15), `ShellAppServices` (WP16); `App/CrannyScenes.swift` (`MenuBarExtra` whose content is `MenuBarContent`, WP16); `App/CompositionRoot.swift` (all modules, §3.4 order); `App/ShellContributions.swift` (§10.0); `App/Diagnostics.swift` (Appendix B.18); `Overlay/NotchPanel.swift` (§5.2); minimal port implementations, **one file per type** so later owners never share a file: `Services/ShellNotchControl.swift` (open/close/hold/focus/flash), `Services/ShellEnvironment.swift` (lock/sleep/low power/AC/frontmost), `Services/ShellAppControl.swift` (open Settings/quit), plus stubs with the final signatures of §10.0 "Intra-shell interfaces": `Windows/SettingsWindowController.swift`, `Windows/WelcomeWindowController.swift`, `Services/ShellAppServices.swift`, `MenuBar/MenuBarContent.swift`, `Overlay/OverlayCoordinator.swift`, `Input/HotKeyCenter.swift`.
- **Behaviour at the end of WP0:** a panel on the built-in (or primary) display shows the closed cutout (or island handle); hovering ≥ 120 ms opens the panel with the configured page (placeholder cards are fine); leaving + 300 ms closes; Esc closes and hands focus back; the menu bar extra opens Settings (sidebar skeleton) and quits.
- **Acceptance:** `make check` (17 targets, zero warnings), `make test`, `make strings-check`, `make build` (universal), `make smoke`, `make dist` locally and on GitHub CI; Appendix C's verification steps reproduce; R1's key panel checks (click delivered without activating the app, per-pixel pass-through, level 26 over a full-screen Space) re-checked on the skeleton — manually or by porting R1's self-test into `CrannyAppShellTests`.

### 10.2 WP1 — Media · `CrannyMedia` (+ `CrannyMediaBridge`)

- **Files:** `MediaModule.swift` · `MediaSettings.swift` · `Service/MediaService.swift` · `Providers/{MediaProvider, BridgeConnection, BridgeLocator, MediaRemoteBridgeProvider, AppleScriptProvider}.swift` · `Artwork/ArtworkDecoder.swift` · `Health/BridgeHealthMonitor.swift` · `Visualizer/{SyntheticSpectrum, SpectrumAnalyzer, SystemAudioTap, VisualizerBarsView}.swift` · `UI/{MediaWidget, NowPlayingActivity, MediaSettingsPane}.swift` · bridge `.m`/`.h` (owned from now on).
- **Responsibilities:** §6 in full: `NowPlayingSource` implementation published as `services.nowPlaying`; provider chain with backoff/failover; quarantine copy; artwork + palette; visualizer modes (CA layers in compact); Media widget (4–6 cells); Now Playing activity (+ sample, + options row "Hide paused media after N s"); Settings ▸ Media page (`.media`, group `.features`, tint red; keywords = its row labels; no "source priority", §6.7); ⌘K commands (Play/Pause, Next, Previous); permissions declared: `.automation(com.apple.Music)`, `.automation(com.spotify.client)`, `.systemAudioRecording`; reports (does not edit) whether the tap needs `NSMicrophoneUsageDescription`/`audio-input` (§7.13).
- **Public types:** `MediaModule`, `MediaSettings`, `MediaVisualizerMode`.
- **Settings (`media.`):** `visualizer: MediaVisualizerMode = .ambient` (`live/ambient/static/off`) · `allowAppleEvents: Bool = false` · `ignoredBundleIDs: [String] = []` · `showsBrowserMedia: Bool = true` · `artworkInCompact: Bool = true` · `hidePausedAfterSeconds: Double = 30` · `showsVisualizerInWidget: Bool = true`.
- **Acceptance:** tests — bridge NDJSON fixtures → `NowPlaying` (incl. missing title, `+inf` duration dropped, artwork keyed by item), backoff 0.5/2/8 s and failover after 3 failures in 60 s (fake provider + injected clock), optimistic commands, track-change debounce rules, synthetic spectrum determinism and rest, locator order and quarantine copy (temp file + `setxattr`). App — Music, Spotify and a browser tab appear in compact within 0.5 s of playback; transport from widget, peek and swipe; artwork, accent and light update on track change; `kill -9` of the helper → restart in ≈ 0.5 s; quitting Cranny leaves no `perl` process; idle CPU ≈ 0; compact bars cost < 0.5 % CPU (Instruments).

### 10.3 WP2 — Calendar · `CrannyCalendar`

- **Files:** `CalendarModule.swift` · `CalendarSettings.swift` · `Store/{CalendarStore, EventSnapshot, EventSource}.swift` · `Scheduling/MeetingScheduler.swift` · `Links/{MeetingLinkDetector, JoinLauncher}.swift` · `UI/{CalendarWidget, MeetingSoonActivity, MeetingNowActivity, CalendarSettingsPane}.swift`.
- **Responsibilities:** §7.4; widget per DESIGN.md §7.2 (2–5 cells, day strip, states incl. "Show your events"); activities Meeting soon (P1) and Meeting in progress (P2) with samples and options rows (lead time 1–30 min; in-event elapsed/remaining); Settings ▸ Calendar page; ⌘K "Join next meeting"; `registry.declare(.calendar, …)`; demo redaction.
- **Public types:** `CalendarModule`, `CalendarSettings`, `MeetingService`, `InEventDisplay` (enums used by public keys).
- **Settings (`calendar.`):** `daysBehind: Int = 0` · `daysAhead: Int = 1` · `showsPastEventsToday: Bool = true` · `hiddenCalendarIDs: [String] = []` · `includesAllDay: Bool = true` · `includesBirthdays: Bool = false` · `leadMinutes: Int = 5` · `inEventDisplay: InEventDisplay = .remaining` · `joinProviders: [MeetingService] = MeetingService.allCases` · `joinsInApp: Bool = true`.
- **Acceptance:** detector tests (R3's 12 cases + more Teams/Webex/SafeLinks/Google redirect variants); windowing and filtering against an injected `EventSource` (no EventKit in tests); scheduler boundaries incl. DST and time-zone change; no timer while no event is upcoming; Join launches Zoom natively when installed else the browser; permission denied → deep link.

### 10.4 WP3 — Quick Apps & Shortcuts · `CrannyQuickApps`

- **Files:** `QuickAppsModule.swift` · `QuickAppsSettings.swift` · `Apps/{AppCatalog, RunningAppsObserver}.swift` · `Shortcuts/{ShortcutsCLI, ShortcutListParser}.swift` · `UI/{LauncherWidget, AppTile, ShortcutTile, ShortcutsSettingsPane}.swift` · `QuickAppsCommands.swift`.
- **Responsibilities:** §7.6; widget per DESIGN.md §7.3 (columns of 2 tiles, 1–6 columns; edit mode "+"; drop an app to add); Settings ▸ Shortcuts page (`.shortcuts`): pick Shortcuts.app shortcuts (search, symbol, colour), Quick Apps list, labels; ⌘K launch app / run shortcut; ⌥1–⌥9 while the Nook is key.
- **Public types:** `QuickAppsModule`, `QuickAppsSettings`, `AppEntry`, `ShortcutEntry`.
- **Settings (`quickapps.`):** `apps: [AppEntry] = [Finder, Safari, Mail, Music]` (bundle IDs; unresolved ones hidden) · `shortcuts: [ShortcutEntry] = []` · `showsLabels: Bool = false`.
- **Acceptance:** parser tests on captured `shortcuts list --show-identifiers` output (names with parentheses, Cyrillic, emoji); run by UUID with cancellation and failure badges; running-app dots update without polling; drag from Finder/Dock adds an app.

### 10.5 WP4 — Mirror · `CrannyMirror`

- **Files:** `MirrorModule.swift` · `MirrorSettings.swift` · `Camera/{CameraController, CameraCatalog}.swift` · `UI/{CameraPreviewView, MirrorWidget}.swift`.
- **Responsibilities:** §7.5; widget per DESIGN.md §7.4 (frameless, 2–3 cells, hover toolbar: flip, camera menu); `registry.declare(.camera, …)`.
- **Public types:** `MirrorModule`, `MirrorSettings`.
- **Settings (`mirror.`):** `cameraID: String? = nil` (nil = system preferred) · `isMirrored: Bool = true`.
- **Acceptance:** never starts without a click; stops ≤ 1 s after close, page change, lock, sleep and in previews (tests drive a `CameraControlling` fake through `PreviewSystemEnvironment`); Desk View hidden; suspended (lid closed) state; hot-plug of a USB/Continuity camera updates the menu.

### 10.6 WP5 — Notes · `CrannyNotes`

- **Files:** `NotesModule.swift` · `NotesSettings.swift` · `Store/{Note, NotesStore}.swift` · `Editor/{NoteTextView, SyntaxHighlighter, LanguageDetector, TypingEffect}.swift` · `UI/{NotesWidget, NoteListMenu}.swift` · `NotesCommands.swift`.
- **Responsibilities:** DESIGN.md §7.5: multiple notes (create, rename ⌘R, delete with confirmation, list menu), `NSTextView` (TextKit 2) in an `NSViewRepresentable`, code mode with syntax highlighting (Markdown + common languages; pure tokenizer), typing effect via TextKit 2 rendering attributes (off under Reduce Motion/Instant or `CoreSettings.typingEffect` off), focus mode via `notch.setFocusMode(.notes)`, `setHoldOpen(true, "notes.editing")` while the editor is first responder, capture target "notes", shortcut `.newNote`, ⌘K "New note"/"Open ‹title›". Storage: `AppPaths/notes/index.json` + `<uuid>.md`, autosave debounced 0.5 s and on terminate.
- **Public types:** `NotesModule`, `NotesSettings`, `NoteMode`.
- **Settings (`notes.`):** `defaultMode: NoteMode = .plain` · `lastNoteID: String? = nil`. The typing effect reads `CoreSettings.typingEffect` and `theme.reduceMotion`/`motion == .instant`; it is implemented inside Notes (TextKit 2), not with `CrannyEffects.TypewriterText` (layer rule).
- **Acceptance:** typing with another app frontmost; ⌘A/C/V/X/Z work in the panel; no data loss across `kill -9` (≤ 0.5 s of typing) and relaunch; highlighter tests per language; typing effect never touches the text storage/undo stack; Esc leaves focus mode before closing.

### 10.7 WP6 — To-dos · `CrannyTodos`

- **Files:** `TodosModule.swift` · `TodosSettings.swift` · `Store/{Todo, TodoStore}.swift` · `UI/{TodosWidget, TodoRow}.swift` · `TodosCommands.swift`.
- **Responsibilities:** DESIGN.md §7.6 (2–6 cells, header count, check animation, collapse after 1.2 s, keyboard: ↩ new, Space toggle, ⌫ on empty deletes, ⌘↑/⌘↓ reorder); "To-do done" delight drawn inside the widget (self-drawn check; Lively: six stateless motes in a local `Canvas`, no `CrannyEffects`); "Tink" when `CoreSettings.uiSounds` ∧ ¬demo; `.generic` haptic; capture target "todos"; storage `AppPaths/todos/todos.json`.
- **Public types:** `TodosModule`, `TodosSettings`.
- **Settings (`todos.`):** `hidesCompleted: Bool = true`.
- **Acceptance:** store tests (ordering, persistence, corrupt file); keyboard map; VoiceOver: each row is a toggle with its text.

### 10.8 WP7 — Timer · `CrannyTimer`

- **Files:** grow §3.17 into `TimerModule.swift` · `TimerSettings.swift` · `Model/{TimerModel, TimerState}.swift` · `UI/{TimerWidget, TimerRunningActivity, TimerDoneActivity, DurationParser}.swift` · `TimerCommands.swift`.
- **Responsibilities:** DESIGN.md §7.7 and §9.2: deadline-based model persisted in `AppPaths/timer/state.json` (restored on launch), presets, scroll ±1 min (`.crannyScrollZone`, `.levelChange` per minute), typed durations ("25", "90s"), running (P2, options row "Peek at one minute left") and done (P1, Stop/+1 min, sound `NSSound(named:)` muted in Demo mode, `delight = .emberBurst`) activities with samples, peek at 1 minute left, ⌘K "Start N-minute timer", shortcut `.startTimer`.
- **Public types:** `TimerModule`, `TimerSettings`.
- **Settings (`timer.`):** `presets: [Int] = [60, 300, 600, 1500]` (seconds) · `sound: String? = "Glass"` · `peeksAtOneMinute: Bool = true`.
- **Acceptance:** no work while hidden (no ticking timers; `TimelineView` paused); survives relaunch; 10-s digit pulse (colour only under Reduce Motion); `DurationParser` tests.

### 10.9 WP8 — Tray, AirDrop, Files · `CrannyTray`

- **Files:** `TrayModule.swift` · `TraySettings.swift` · `Store/{TrayItem, TrayStore, TrayStorage, Retention}.swift` · `Thumbnails/ThumbnailCache.swift` · `Pipelines/{Pipeline, PipelineRunner, ImageSteps, ArchiveSteps, VisionSteps, PDFSteps, VideoSteps, BuiltinPipelines}.swift` · `UI/{TrayPage, TrayTile, FileDragSource, CatchView, PipelineChips, AirDropWidget, FilesShelfWidget, TraySettingsPane, PipelineEditor}.swift`.
- **Responsibilities:** §7.8 and DESIGN.md §8: `TrayIntake` published as `services.tray`; Tray page (`PageID.tray`, badge); catch view with Keep/AirDrop/≤ 3 pinned pipeline zones (`.crannyDropZone`); multi-select, Quick Look, context menu, AppKit drag out; contextual pipeline chips with progress, Undo (5 s), errors; user pipeline editor (Settings ▸ Tray page); AirDrop widget (`notch.presentAirDrop`); Files mini shelf widget (3–8 cells, recent 6; also a drop zone); `TrayIntake.accept` for drops no zone took (§5.6); "Copy paths" confirms with `notch.flash`; shortcut `.openTray`; ⌘K "Clear tray"; retention.
- **Public types:** `TrayModule`, `TraySettings`, `PipelineDefinition`, `PipelineStep`, `TrayRetention`, `TrayStorageMode`, `TrayOutputLocation`, `TrayZipNaming`.
- **Settings (`tray.`):** `retention: TrayRetention = .untilRemoved` · `maxItems: Int = 50` · `storageMode: TrayStorageMode = .copy` · `opensTrayOnDrop: Bool = true` · `showsAirDropZone: Bool = true` · `pinnedPipelines: [String] = ["builtin.compress", "builtin.zip"]` · `userPipelines: [PipelineDefinition] = []` · `jpegQuality: Double = 0.8` · `maxDimension: Int = 1600` · `outputLocation: TrayOutputLocation = .nextToSource` · `zipNaming: TrayZipNaming = .firstItem` (`firstItem` "Brief.zip" / `dated` "Archive 2026-10-14.zip"; DESIGN.md §11.1 "zip naming").
- **Acceptance:** pipeline tests on temp files (formats from `CGImageDestinationCopyTypeIdentifiers()`, zip/unzip round trip, resize keeps orientation, cancellation); drops from Finder, Safari image and Photos (promise) land as copies; drag-out to Finder delivers the stored file (not a SwiftUI cache copy); AirDrop sheet fully on screen and focus returns to the previous app; Quick Look decision documented (§7.8).

### 10.10 WP9 — HUD · `CrannyHUD`

- **Files:** `HUDModule.swift` · `HUDSettings.swift` · `Keys/{MediaKeyEvent, MediaKeyInterceptor, HUDTapConfig, PassThroughPolicy}.swift` · `Audio/{SystemVolume, VolumeObserver}.swift` · `Private/{DisplayBrightness, KeyboardBacklight}.swift` · `Feedback/FeedbackSound.swift` · `UI/{HUDActivity, HUDViews, HUDSettingsPane}.swift`.
- **Responsibilities:** §7.1 and DESIGN.md §10: HUD activity (+ sample) and Settings ▸ HUD page (`.hud`, group `.notch`, teal) with the Accessibility status pill; `registry.declare(.accessibility, …)`.
- **Public types:** `HUDModule`, `HUDSettings`, `HUDColors`.
- **Settings (`hud.`):** `replaceSystemHUD: Bool = false` · `volume: Bool = true` · `brightness: Bool = true` · `keyboardBacklight: Bool = true` · `colors: HUDColors = .mono` · `showsValue: Bool = false` · `showsOutputDevice: Bool = true` · `duration: Double = 1.5`.
- **Acceptance:** tests for `data1` decoding (key, down/up, repeat, ⌥, ⌥⇧) and the pass-through policy table; with Accessibility + setting on: 1/16 and 1/64 steps, mute, no MenuBarAgent OSD window appears (window-list check as in R3 `osdtest`), HUD bar animates without shape motion after the first press; HDMI/non-settable output passes through; tap survives `tapDisabledByTimeout`; turning the setting off removes the tap; without Accessibility there is no HUD; evidence from a lid-open MacBook (a small listen-only key logger as described in R3 §1.2: log `NX_SYSDEFINED` subtype-8 key codes and `keyDown` 144/145) attached to the PR before brightness is enabled by default.

### 10.11 WP10 — System activities · `CrannySystemActivities`

- **Files:** `SystemActivitiesModule.swift` · `SystemSettings.swift` · `Power/{BatteryState, PowerSources, PowerObserver}.swift` · `Accessories/{AudioDeviceWatcher, HIDPeripheralWatcher, BluetoothDeviceWatcher, DeviceSymbols, Accessory}.swift` · `Private/AccessoryBatteries.swift` · `UI/{ChargingActivity, LowBatteryActivity, BluetoothActivity, BatteryGlyph}.swift`.
- **Responsibilities:** §7.2–§7.3 and DESIGN.md §9.2 rows Charging (`delight = .chargeSweep`), Low battery, Bluetooth device (with samples); no settings page — thresholds and "Show all Bluetooth devices" are options rows of the Low battery / Bluetooth activities; optional IOBluetooth path behind that setting and `PermissionsCenter.request(.bluetooth)`; `registry.declare(.bluetooth, …)`.
- **Public types:** `SystemActivitiesModule`, `SystemSettings`.
- **Settings (`system.`):** `lowBatteryThresholds: [Int] = [20, 10]` · `showsAllBluetoothDevices: Bool = false`.
- **Acceptance:** state tests from captured IOPS dictionaries (charging, discharging, plugged-not-charging, desktop); plug/unplug produces one transient 2.6-s activity; AirPods connect shows L/R/Case without any TCC prompt; refresh only on notifications (+ 60 s while visible).

### 10.12 WP11 — Effects · `CrannyEffects`

- **Files:** `AuroraField.swift` (from WP0) · `MotesField.swift` · `TideField.swift` · `HaloField.swift` · `AmbientLayer.swift` · `EmberBurst.swift` · `ChargeSweep.swift` · `FirstLight.swift` · `LiquidNeck.swift` · `TypewriterText.swift` · `RippleModifier.swift`.
- **Responsibilities:** DESIGN.md §5 and Appendix B: stateless effects (pure functions of time, palette, energy, intensity), `AmbientLayer(palette:level:effect:energy:budget:)` choosing the effect (Halo under Low Power), framed to the current shape, `ambientIn/Out` fill/drain; one view per `DelightMoment` (ember burst, charge sweep along a given outline path, song-change ripple, first light; the gulp is a geometry offset NotchUI applies) plus the satellite liquid neck; `TypewriterText` (`TextRenderer` on 15+, fade on 14) for NotchUI/Onboarding text only. No `.metal` (D13).
- **Public types:** `AmbientLayer`, `AuroraField`, `MotesField`, `TideField`, `HaloField`, `EmberBurst`, `ChargeSweep`, `FirstLight`, `LiquidNeck`, `TypewriterText`, `View.songChangeRipple(_:)`.
- **Settings:** none (reads values passed by the caller from `CoreSettings`).
- **Acceptance:** alpha never exceeds `Glow.ambientAlphaCap` (test over sampled frames); `TimelineView` paused when `EffectBudget.minimumInterval == nil`; Reduce Motion shows a resting frame; macOS 14 Canvas path renders; open Nook + aurora ≤ 3 % CPU (Instruments, 120 Hz).

### 10.13 WP12 — Notch UI · `CrannyNotchUI`

- **Files:** `NotchScene.swift` and `ThemeResolver.swift` (contract owner) · `NotchCanvasView.swift` · `Compact/{CompactView, SatelliteView, MiddleLabel, ProgressRim}.swift` · `Peek/PeekView.swift` · `Nook/{NookView, NookHeader, NookGrid, WidgetCard, CardOverflowMenu, CommandPaletteView, EditLayoutView, CatchHost, CommandHintsOverlay, HUDHeaderOverlay}.swift` · `Choreography/{Stagger, ContentTransitions, DelightPlayer}.swift` · `Keyboard/NookKeyHandling.swift`.
- **Responsibilities:** every presentation of DESIGN.md §3.3, §4.3, §6 and §9.1–§9.3 rendered from `NotchSceneModel`: activities resolved as `sampleActivities[id] ?? registry.activity(id)`; geometry from `NotchLayout`; `NotchSurface` with keyline/elevation/underglow; `AmbientLayer` behind the open grid; compact wings + satellite (+ neck) + floating-island middle label; progress rim (`CoreSettings.progressRim`, progress read from `services.nowPlaying` while the primary is `.nowPlaying`); `DelightPlayer` plays `scene.delight` once per `delightSerial` with its Reduce Motion variant; peek rows (30-ms stagger); header (tabs "Home"/"Tray"/user pages with badges, actions, time/date on displays without a notch, HUD-in-header §4.11); grid with card chrome (hover, ⋯ menu, focus sections, VoiceOver containers, "Widgets" rotor); ⌘K palette (providers from the registry, ↑↓↩ Esc); edit layout (drag reorder/resize in cells with `.alignment` haptics via `registry.services.haptics`, ⌥←/→, ⌥⇧←/→, writes through `actions.commitLayout`); mode changes, focus moves, VoiceOver Open/Dismiss through `actions.setMode/focusWidget/open/dismissActivity` (the scene is written only by its owner); catch host (`services.tray.catchView`); hold-⌘ hints; Esc chain; matched geometry; choreography and Reduce Motion cross-fades.
- **Public types:** `NotchSceneModel`, `OpenState`, `NookMode`, `NotchUIActions`, `NotchCanvasView`, `ThemeResolver`.
- **Settings:** reads `CoreSettings` (pages, density, styles); writes nothing directly.
- **Acceptance:** `#Preview`s for every state × {notch, floating island, attached} × {standard, lit, highContrast, opaque}; ImageRenderer tests assert shape sizes equal DESIGN.md §3.3 within 0.5 pt; no text reflow during morphs (content laid out at final size); keyboard map of DESIGN.md §16; VoiceOver reads activities with label/value/actions.

### 10.14 WP13 — Shell: overlay, state, input · `CrannyAppShell` (`Overlay/`, `State/`, `Input/`, `Services/{ShellNotchControl, ShellEnvironment, SharingPresenter, FlashActivity}.swift`)

- **Files:** `Overlay/NotchPanel.swift` (from WP0) · `Overlay/{NotchRootView, NotchHostingView, NotchPanelController, OverlayCoordinator, DisplayCatalog, PointerMonitor, HoverTracker, DragDetector, FilePromiseResolver, FullScreenDetector, FocusManager, CalibrationOverlay}.swift` · `State/{NotchMachine, NotchViewModel, ActivityArbiter, PeekScheduler, DelightScheduler}.swift` · `Input/{GestureRouter, HotKeyCenter, KeyboardRouter}.swift` · the four service files.
- **Responsibilities:** §4 and §5 completely: per-display controllers and display policy (keys via `ThemeResolver.displayKey`); hover intent, close grace, holds (incl. menu/popover tracking); click/hot-key/swipe/drag triggers incl. satellite swipe-up and the idle-handle timer; drop and scroll routing into `NotchZones` with the `TrayIntake.accept` fallback; full-screen/excluded/lock policy; arbitration, peeks, dismissal, pause, timeouts, menu-bar courtesy; delight scheduling (§4.6 step 7); the `ActivityID.flash` activity behind `NotchControl.flash`; key focus and hand-back; type-to-capture; hold-⌘ hints; `NotchControl` (incl. focus mode, calibration overlay, event observers) and `SystemEnvironment` implementations; theme/layout/ambient palette via `ThemeResolver` (WP12) re-run on observed key changes; "Pop" UI sound on catch; AirDrop/share presenter (§7.7).
- **Public types:** none beyond `AppDelegate`/`CrannyScenes` (WP0).
- **Settings:** reads `CoreSettings`; writes `nook.lastPage` only (`pausedUntil`/`demoMode` belong to WP16).
- **Acceptance:** reducer tests for every row of §4.4 and arbiter tests for §4.6–§4.7 (injected clock); R1 harness re-run (non-activating click delivery, focus hand-back, per-pixel pass-through, level 26 over full-screen Spaces, drag-in from another app); multi-display: built-in/pointer/all/custom, hot-plug and clamshell; ⌃⌥N toggles without Accessibility; full-screen detection on a notched display (R1 §10 checklist).

### 10.15 WP14 — Settings UI · `CrannySettingsUI` (+ `CrannyAppShell/Windows/SettingsWindowController.swift`)

- **Files:** `SettingsRootView.swift` · `Sidebar/{SettingsSidebar, SettingsSearchIndex}.swift` · `Stage/{PreviewStage, WallpaperMiniature, MenuBarMiniature, SimulateChips}.swift` · `Panes/{GeneralPane, DisplayTable, AppearancePane, NotchFitControls, KeyboardPane, ShortcutRecorder, NookWidgetsPane, WidgetLibrary, LiveActivitiesPane, GesturesPane, PermissionsPane, AboutPane}.swift` · `Components/{SettingRow, PaneFooter, ResetAllController}.swift` · the window controller.
- **Responsibilities:** DESIGN.md §11 in full: sidebar with groups, icons and search (localized keywords); live preview stage (real `NotchCanvasView` with a preview `NotchSceneModel` built by `ThemeResolver`, sample activities from `RegisteredActivity.makeSample` placed in `sampleActivities`, state picker, Simulate chips, `app.showOnNotch`); wallpaper miniature from `NSWorkspace.desktopImageURL(for:)` **only** when that file is outside Desktop/Documents/Downloads/removable volumes (reading those would raise a Files & Folders prompt from Settings), else a neutral gradient; shell-owned panes (General with per-display table keyed by `ThemeResolver.displayKey` + `NSScreen.localizedName`, UI sounds, idle-handle delay; Appearance incl. Notch fit → `notch.setCalibrationOverlay`, panel padding; Keyboard via `app.setShortcut`/`shortcutState`, plus a best-effort system-conflict warning read from the `com.apple.symbolichotkeys` `AppleSymbolicHotKeys` domain [VERIFIED readable on 27; format UNVERIFIED] since `RegisterEventHotKey` does not fail on system combos; Layout & Widgets grid editor + pages + library + `makeOptions()` popovers; Live Activities draggable priority list with each kind's `makeOptions` rows; Gestures with "Feel it"; Permissions from `registry.permissionUses` + `PermissionsCenter`; About with `NSApp.applicationIconImage`); module panes from `registry.settingsPages` (search uses their `keywords`; "Reset ‹Pane›…" resets `namespaces`); conventions (changed-value dot, per-row Reset to Default, pane reset, Reset All = `settings.snapshot()` → `app.resetAllSettings()` → 10-s Undo with `settings.restore(_:)`); window 860 × 620, min 780 × 560, autosave, deep-link to a pane.
- **Public types:** `SettingsRootView(registry:initialPage:)`.
- **Settings:** writes `CoreSettings` keys through bindings.
- **Acceptance:** every pane renders in en/ru light/dark; search finds "volume" → HUD and Russian equivalents; Reset All restores defaults and undo restores the snapshot; stage animates with the real motion tokens; no permission requested except from explicit buttons.

### 10.16 WP15 — Onboarding & tutorial · `CrannyOnboarding` (+ `CrannyAppShell/Windows/WelcomeWindowController.swift`)

- **Files:** `WelcomeView.swift` · `Steps/{HelloStep, OpenItStep, GesturesStep, PresetStep, PermissionsStep, DoneStep}.swift` · `Stage/OnboardingStage.swift` · `Tutorial/{TutorialController, TutorialBubblePanel, TutorialSteps}.swift` · the window controller.
- **Responsibilities:** DESIGN.md §12: six steps with real detection through `notch.addEventObserver` (opened by hover/click/shortcut, file caught, track swiped, hints shown, pinned), step 1's "Hi" on the real notch via `notch.flash(symbol: "hand.wave.fill", label:)`, stage built with `ThemeResolver` + `sampleActivities`, presets writing `CoreSettings.pages` (`NookPreset`), permission rows only for the chosen features (from `registry.permissionUses`), launch at login and updates via `AppControl`, completion stored in `CoreSettings.onboardingCompletedVersion`; the 5-step interactive tutorial with a bubble panel under `notch.shapeFrameOnScreen()`, skip and replay.
- **Public types:** `WelcomeView(registry:onFinish:)`, `TutorialController`.
- **Settings:** writes `onboarding.completedVersion`, `onboarding.tutorialCompleted`, `nook.pages`.
- **Acceptance:** shown once on first launch and from "Show welcome"; every step skippable; gesture step skipped without a trackpad; VoiceOver "Step 2 of 6"; Reduce Motion still frames.

### 10.17 WP16 — App services & menu bar · `CrannyAppShell` (`Services/{ShellAppControl, ShellAppServices, LoginItemController, UpdateChecker, PauseController, DemoMode}.swift`, `App/ShellContributions.swift`, `MenuBar/`)

- **Responsibilities:** `AppControl` implementation (login item §7.9, updates §7.11, shortcut bindings written to `CoreSettings.shortcuts` and state read from WP13's `HotKeyCenter`, open Settings/Welcome/Tutorial through the window controllers, `showOnNotch` via `OverlayCoordinator.play`, Reset All, quit); shell contributions and ⌘K commands (§10.0); menu bar extra exactly as DESIGN.md §13 (Open Cranny, Keep Cranny Open, Pause Live Activities ▸, Show On ▸, Demo Mode, Settings… as a `Button` with ⌘,, Check for Updates…, Show Tutorial, About, Quit; template icon drawn in code; hide-icon setting with reopen → Settings); Demo mode and Pause as the only writers of `general.demoMode`/`activities.pausedUntil` (WP13's `ShellEnvironment` observes them).
- **Settings:** writes `general.demoMode`, `activities.pausedUntil`, `updates.*`, `general.showsMenuBarIcon`.
- **Acceptance:** login item toggling with `.requiresApproval` handling (tested on an ad-hoc and a stable-identity build in /Applications, R3 §9 plan); update check against a test repository with ETag; menu items have keyboard equivalents and VoiceOver labels.

### 10.18 WP-Final — Integration, QA, release

Icon (`App/AppIcon.icon` per DESIGN.md §15 in Icon Composer); `CrannyGitHubRepository`; the bundle-id/domain check (D16); `App/**` edits requested by packages (usage strings, entitlements — e.g. WP1's audio-tap finding); README, CONTRIBUTING, PRIVACY ("no network except the update check; nothing leaves the Mac"), THIRD_PARTY_NOTICES; localization review against the glossary, the competitor-term denylist (§8.7 rule 8) and 1.4× pseudo-localisation; design QA of every DESIGN.md §3.3 geometry and §4.1 motion on 13″/14″/16″ notched MacBooks and an external display; energy gates (§9.2) with Instruments; the hardware checklist (§11); CI green on the GitHub runner incl. smoke; signed + notarized release dry run (or the documented ad-hoc path); a v0.1.0 tag.

### 10.19 Staffing for ten engineers

| Engineer | Phase A | Phase B | Phase C |
|---|---|---|---|
| E1 | WP0 (shell skeleton, project, CI) | WP13 Shell | Integration lead |
| E2 | WP0 (Core) | WP12 Notch UI (+ Core change requests) | Design QA |
| E3 | — | WP1 Media | Media hardening |
| E4 | — | WP8 Tray | Tray QA |
| E5 | — | WP9 HUD, then WP10 System activities | Hardware checklist |
| E6 | — | WP2 Calendar, then WP4 Mirror | |
| E7 | — | WP5 Notes, then WP6 To-dos | Localization review |
| E8 | — | WP7 Timer, WP3 Quick Apps, then WP16 App services | Release |
| E9 | — | WP14 Settings UI | |
| E10 | — | WP11 Effects, then WP15 Onboarding | Energy measurements |

---

## 11. Risks and the hardware checklist

### 11.1 Open risks

| # | Risk | Impact | Mitigation / owner |
|---|---|---|---|
| 1 | Apple closes the perl/ruby MediaRemote route or removes the interpreters | Now Playing stops | Ruby host, AppleScript fallback, blocked-bridge detection (§6.5); watch the mediaremote-adapter issue tracker each beta — WP1 |
| 2 | Private APIs change (DisplayServices, CoreBrightness, `IOPSCopyPowerSourcesByType`, lock key) | Brightness HUD, AirPods batteries, lock detection degrade | Register §7.12, `dlsym`/`responds(to:)` probes, silent fallbacks — WP9, WP10, WP13 |
| 3 | Real notch geometry (radius 0.30·band, 0.5-pt inset, aux-area coordinate space) never measured on hardware | Visible seams around the camera | Notch fit calibration; R1 §10 checklist on 13″/14″/16″ — WP13, WP-Final |
| 4 | Brightness keys on Apple Silicon not observed; `SMAppService.register()`, IOBluetooth runtime, live audio tap, camera runtime, Quick Look from a non-activating panel, programmatic `makeKey()` all UNVERIFIED | Feature gaps | Each owning WP verifies before enabling by default (§10) |
| 5 | Ad-hoc signing resets TCC grants on every build/update; Gatekeeper on downloads; quarantined bridge | Users re-grant permissions; media blocked | Stable dev identity, Developer ID + notarization for releases, quarantine copy (§6.3, §8.6) |
| 6 | Other HUD apps' event taps compete; Secure Event Input may block taps | HUD inconsistent | Pass-through rules, warning for known apps (§7.1) |
| 7 | `xcode-27` CI image is a preview; Xcode 26 only declared, not tested | CI breaks | `macos-26` fallback job; WP0 runs CI once on both |
| 8 | 17 targets × per-target scratch dirs ≈ 3.3 GB with tests | Disk | `make distclean` locally; CI starts from a clean checkout |
| 9 | `hdiutil create` deprecated on macOS 27 | DMG step breaks in future | Switch to `diskutil image create` when needed — WP-Final |
| 10 | Full-screen detection heuristic (bounds + layer + menu-bar absence) on notched displays | Notch over full-screen video | `.alertsAndHUD` default, excluded apps, lazy re-check before showing — WP13 |
| 11 | Russian copy length in compact slots and tabs | Truncation | Glossary, `compactLabel` tests, 1.4× pseudo-loc — all WPs, WP-Final |
| 12 | x86_64 slices never executed (no Rosetta on the research Mac) | Intel users crash at launch unnoticed | Intel smoke job if a runner exists; otherwise a manual run on an Intel Mac before release — WP-Final |
| 13 | Strings tooling depends on the swift-build backend layout (SwiftPM 6.4) | `strings-check` breaks on Xcode 26 or a future layout change | Explicit `--build-system swiftbuild`; strings steps pinned to Xcode 27 (§8.5) — WP0 |
| 14 | Competitor naming/UI text leaks into copy ("Nook" + "Tray" tab pair) | Clean-room/trademark complaint | D20, denylist grep before release (§8.7) — WP-Final |
| 15 | Metal Toolchain present on some machines tempts `.metal` effects | Builds fail on CI/contributors without the component | D13 guard in `check-modules.sh` — all WPs |

### 11.2 Hardware checklist (each release; R1 §10, R3 §12)

On a notched MacBook with the lid open, with a stable-identity or release build launched from Finder:
1. `NotchMetrics.measure` per screen: `safeAreaInsets.top`, aux-area widths, notch rect; compare the closed shape with the camera housing at every scaling mode (Notch fit at 0).
2. Hover/click/hot-key open; typing in Notes with another app frontmost; Esc returns focus.
3. Full screen: Safari video, Keynote, a game; policy `.alertsAndHUD`; menu bar revealed by hovering the top edge.
4. Drag a file from Finder, an image from Safari, a photo from Photos (promise) into the notch; drag a tray item back to Finder.
5. Two-finger swipes on the built-in trackpad: track change, open, close, dismiss; haptics felt.
6. Volume and brightness keys (and the key-logger output, §7.1), ⌥ and ⌥⇧ variants, HDMI output.
7. AirPods connect/disconnect; charger plug/unplug; Low Power Mode.
8. Mission Control, Stage Manager, Spaces switching, external display hot-plug, lid close/open (clamshell).
9. 120 Hz ProMotion: open/close morph smooth; Energy Impact < 1.0 idle.
10. VoiceOver run and keyboard-only run through every feature.

---

## Appendix A — CrannyCore implementation sources (verbatim, compiled)

These complete §3. WP0 copies them unchanged; the DesignSystem files (`Color`, `Typography`, `Layout`, `Motion`, `Notch`, `Theme`, `Components`, `AmbientPalette`) are DESIGN.md's code with the §3.2 amendments and are not repeated here. `CrannyEffects/AuroraField.swift` is DESIGN.md Appendix B's `AuroraField` with `import SwiftUI` and `import CrannyCore`.

### A.1 `Settings/SettingsStore.swift`

```swift
// CrannyCore/Settings/SettingsStore.swift
// Typed, module-namespaced, observable settings persisted in UserDefaults.
import Foundation
import Observation
import os
import SwiftUI

/// A typed settings key. Declare keys as `static let` in the owning module's `<Module>Settings` enum.
/// Stored under "cranny.<module>.<name>" as JSON data. Never rename a key; add a new one and migrate.
public nonisolated struct SettingKey<Value: Codable & Sendable & Equatable>: Sendable, Hashable {
    public let module: ModuleID
    public let name: String
    public let defaultValue: Value
    public init(_ module: ModuleID, _ name: String, default defaultValue: Value) {
        self.module = module; self.name = name; self.defaultValue = defaultValue
    }
    /// "timer.presets"
    public var id: String { "\(module.rawValue).\(name)" }
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// One observable box per key, so a view reading `settings[TimerSettings.presets]` is invalidated
/// only by that key (fine-grained Observation; no global "settings changed" storms).
@MainActor @Observable final class SettingBox<Value: Codable & Sendable & Equatable> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor public final class SettingsStore {
    public static let keyPrefix = "cranny."
    private let defaults: UserDefaults
    private var boxes: [String: AnyObject] = [:]
    private var reloadHandlers: [String: @MainActor () -> Void] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The app uses `.standard` (domain = bundle id). Tests and previews pass `UserDefaults(suiteName:)`.
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public subscript<V>(key: SettingKey<V>) -> V {
        get { box(key).value }
        set {
            let b = box(key)
            guard b.value != newValue else { return }
            b.value = newValue
            if newValue == key.defaultValue {
                defaults.removeObject(forKey: Self.keyPrefix + key.id)
            } else if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Self.keyPrefix + key.id)
            }
        }
    }

    /// For SwiftUI controls: `Toggle(isOn: settings.binding(HUDSettings.showValue)) { … }`.
    public func binding<V>(_ key: SettingKey<V>) -> Binding<V> {
        Binding(get: { self[key] }, set: { self[key] = $0 })
    }

    /// Drives the "changed from default" dot and per-row "Reset to Default" (DESIGN.md §11.3).
    public func isDefault<V>(_ key: SettingKey<V>) -> Bool { self[key] == key.defaultValue }
    public func reset<V>(_ key: SettingKey<V>) { self[key] = key.defaultValue }

    /// "Reset ‹Pane›…": every key of a namespace (only keys already read in this session are live-updated;
    /// the others are removed from disk and read back as defaults).
    public func reset(module: ModuleID) { reset(prefix: Self.keyPrefix + module.rawValue + ".") }
    /// "Reset All Settings…". Content (notes, to-dos, tray files) is NOT settings and is kept.
    public func resetAll() { reset(prefix: Self.keyPrefix) }

    /// Opaque copy of every persisted Cranny key: take one before "Reset All" so the 10-s Undo can restore it.
    public nonisolated struct Snapshot: Sendable { fileprivate let values: [String: Data] }
    public func snapshot() -> Snapshot {
        var values: [String: Data] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.keyPrefix) {
            if let data = value as? Data { values[key] = data }
        }
        return Snapshot(values: values)
    }
    /// Replaces every Cranny key with `snapshot` and updates the live values (Undo of "Reset All").
    public func restore(_ snapshot: Snapshot) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        for (key, data) in snapshot.values { defaults.set(data, forKey: key) }
        for handler in reloadHandlers.values { handler() }
    }

    private func reset(prefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        for (id, handler) in reloadHandlers where (Self.keyPrefix + id).hasPrefix(prefix) { handler() }
    }

    private func box<V>(_ key: SettingKey<V>) -> SettingBox<V> {
        if let b = boxes[key.id] as? SettingBox<V> { return b }
        let b = SettingBox(load(key))
        boxes[key.id] = b
        reloadHandlers[key.id] = { [weak self, weak b] in
            guard let self, let b else { return }
            let v = self.load(key)
            if b.value != v { b.value = v }
        }
        return b
    }

    /// The persisted value, or the default (undecodable data is logged and ignored).
    private func load<V>(_ key: SettingKey<V>) -> V {
        guard let data = defaults.data(forKey: Self.keyPrefix + key.id) else { return key.defaultValue }
        if let v = try? decoder.decode(V.self, from: data) { return v }
        Log.logger(.settings).error("undecodable value for \(key.id, privacy: .public); using default")
        return key.defaultValue
    }
}
```

### A.2 `Settings/CoreSettings.swift`

```swift
// CrannyCore/Settings/CoreSettings.swift
// Shell-level settings shared by CrannyNotchUI, CrannySettingsUI, CrannyOnboarding and CrannyAppShell.
// Feature modules declare their own keys in their own targets (e.g. TimerSettings).
import Foundation

// MARK: - Value types

/// Settings ▸ General ▸ Open the Nook.
public nonisolated enum OpenMode: String, Codable, CaseIterable, Sendable { case hover, click, shortcutOnly }

/// Settings ▸ General ▸ In full-screen apps (DESIGN.md §3.7).
public nonisolated enum FullScreenPolicy: String, Codable, CaseIterable, Sendable { case hideAll, alertsAndHUD, showAll }

/// Settings ▸ General ▸ Show on.
public nonisolated enum DisplaySelection: Codable, Hashable, Sendable {
    case builtIn            // default when a built-in display is online; falls back to the primary display
    case pointer            // the display with the pointer
    case all
    case custom([DisplayKey])
}

/// Handle on displays without a notch (Appearance).
public nonisolated enum HandleVisibility: String, Codable, CaseIterable, Sendable { case visible, hiddenUntilHover }

/// Per-display row of the General ▸ Show on table, keyed by `DisplayKey`.
public nonisolated struct DisplayPreferences: Codable, Hashable, Sendable {
    /// nil = automatic (hardware notch if present, else `CoreSettings.noNotchStyle`).
    public var style: NoNotchStyle?
    public var showsActivities = true
    public var showsPeeks = true
    public var showsHUD = true
    public init(style: NoNotchStyle? = nil) { self.style = style }
}

/// Appearance ▸ Notch fit, stored per display MODEL ("<vendor>-<model>" from CGDisplayVendorNumber/ModelNumber).
public nonisolated struct NotchFit: Codable, Hashable, Sendable {
    public var widthTune: CGFloat = 0      // −10…+10 pt, 0.5 steps
    public var radiusTune: CGFloat = 0     // −3…+3 pt
    public init(widthTune: CGFloat = 0, radiusTune: CGFloat = 0) { self.widthTune = widthTune; self.radiusTune = radiusTune }
}

/// One card in a Nook page: a widget and its width in cells.
public nonisolated struct NookItem: Codable, Hashable, Sendable {
    public var widget: WidgetID
    public var cells: Int
    public init(_ widget: WidgetID, cells: Int) { self.widget = widget; self.cells = cells }
}

/// A grid page. The built-in grid page has id `.nook`; user pages (≤ 3) get "page.<uuid>".
public nonisolated struct NookPage: Codable, Hashable, Sendable, Identifiable {
    public var id: PageID
    public var title: String?            // nil = built-in localized title ("Home"; code id stays `nook`, D20)
    public var symbol: String
    public var items: [NookItem]
    public init(id: PageID, title: String? = nil, symbol: String, items: [NookItem]) {
        self.id = id; self.title = title; self.symbol = symbol; self.items = items
    }
}

/// Onboarding step 4 presets (DESIGN.md §12.1). Data only, so no layer imports a feature module.
public nonisolated enum NookPreset: String, CaseIterable, Codable, Sendable {
    case listener, maker, meetings, minimal
    public var items: [NookItem] {
        switch self {
        case .listener: [.init(.media, cells: 5), .init(.calendar, cells: 3), .init(.quickApps, cells: 2)]
        case .maker:    [.init(.notes, cells: 4), .init(.todos, cells: 3), .init(.timer, cells: 2), .init(.quickApps, cells: 1)]
        case .meetings: [.init(.calendar, cells: 4), .init(.mirror, cells: 2), .init(.timer, cells: 2), .init(.quickApps, cells: 2)]
        case .minimal:  [.init(.media, cells: 4)]
        }
    }
    public var page: NookPage { NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: items) }
}

/// Per live-activity user preferences (Settings ▸ Live Activities). Missing entry = kind defaults.
public nonisolated struct ActivityPreference: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var peeksOnChange: Bool
    public init(isEnabled: Bool, peeksOnChange: Bool) { self.isEnabled = isEnabled; self.peeksOnChange = peeksOnChange }
}

// MARK: - Keys

public nonisolated enum CoreSettings {
    // General
    public static let openMode = SettingKey<OpenMode>(.general, "openMode", default: .hover)
    public static let hoverDelay = SettingKey<HoverIntent.Delay>(.general, "hoverDelay", default: HoverIntent.defaultDelay)
    public static let holdOptionToPass = SettingKey<Bool>(.general, "holdOptionToPass", default: true)
    public static let closeOnLeave = SettingKey<Bool>(.general, "closeOnLeave", default: true)
    /// Seconds; 0 = off (5–60).
    public static let openInactivityTimeout = SettingKey<Double>(.general, "openInactivityTimeout", default: 0)
    /// No-notch displays: fade the handle out after `handleIdleDelay` s without activity or hover (DESIGN.md §3.5).
    public static let hideHandleWhenIdle = SettingKey<Bool>(.general, "hideHandleWhenIdle", default: false)
    public static let handleIdleDelay = SettingKey<Double>(.general, "handleIdleDelay", default: 10)
    public static let fullScreenPolicy = SettingKey<FullScreenPolicy>(.general, "fullScreenPolicy", default: .alertsAndHUD)
    public static let excludedBundleIDs = SettingKey<[String]>(.general, "excludedBundleIDs", default: [])
    public static let demoMode = SettingKey<Bool>(.general, "demoMode", default: false)
    public static let demoRedactsCalendar = SettingKey<Bool>(.general, "demoRedactsCalendar", default: true)
    public static let showsMenuBarIcon = SettingKey<Bool>(.general, "showsMenuBarIcon", default: true)
    /// System UI sounds: "Pop" on file caught, "Tink" on to-do done (DESIGN.md §14.3). Muted in Demo mode.
    public static let uiSounds = SettingKey<Bool>(.general, "uiSounds", default: false)

    // Displays
    public static let displaySelection = SettingKey<DisplaySelection>(.displays, "selection", default: .builtIn)
    public static let perDisplay = SettingKey<[DisplayKey: DisplayPreferences]>(.displays, "perDisplay", default: [:])
    public static let notchFit = SettingKey<[String: NotchFit]>(.displays, "notchFit", default: [:])

    // Appearance
    public static let accent = SettingKey<AccentSource>(.appearance, "accent", default: .automatic)
    public static let textSize = SettingKey<CrannyTextSize>(.appearance, "textSize", default: .standard)
    public static let motion = SettingKey<MotionPersonality>(.appearance, "motion", default: .standard)
    public static let ambience = SettingKey<AmbienceLevel>(.appearance, "ambience", default: .subtle)
    public static let effect = SettingKey<AmbientEffect>(.appearance, "effect", default: .aurora)
    public static let albumGlow = SettingKey<Bool>(.appearance, "albumGlow", default: true)
    public static let underglow = SettingKey<Bool>(.appearance, "underglow", default: true)       // Vivid only
    public static let progressRim = SettingKey<Bool>(.appearance, "progressRim", default: false)
    public static let translucentBackground = SettingKey<Bool>(.appearance, "translucentBackground", default: false)
    public static let glassIsland = SettingKey<Bool>(.appearance, "glassIsland", default: false)
    public static let buttonShape = SettingKey<ButtonShapeStyle>(.appearance, "buttonShape", default: .capsule)
    public static let widgetStyle = SettingKey<WidgetStyle>(.appearance, "widgetStyle", default: .cards)
    public static let density = SettingKey<NookDensity>(.appearance, "density", default: .standard)
    public static let panelPaddingTune = SettingKey<Double>(.appearance, "panelPaddingTune", default: 0)  // ±4 pt
    public static let noNotchStyle = SettingKey<NoNotchStyle>(.appearance, "noNotchStyle", default: .floatingIsland)
    public static let handleVisibility = SettingKey<HandleVisibility>(.appearance, "handleVisibility", default: .visible)
    public static let typingEffect = SettingKey<Bool>(.appearance, "typingEffect", default: true)

    // Layout & Widgets (code namespace `nook`)
    public static let pages = SettingKey<[NookPage]>(.nook, "pages", default: [NookPreset.listener.page])
    public static let lastPage = SettingKey<PageID>(.nook, "lastPage", default: .nook)

    // Live Activities
    public static let activityPreferences = SettingKey<[ActivityID: ActivityPreference]>(.activities, "preferences", default: [:])
    /// The user's order (ties within a priority class).
    public static let activityOrder = SettingKey<[ActivityID]>(.activities, "order", default: [])
    public static let peekDuration = SettingKey<Double>(.activities, "peekDuration", default: HoverIntent.peekAutoDismiss)
    public static let quickPeekOnHover = SettingKey<Bool>(.activities, "quickPeekOnHover", default: true)
    public static let satellite = SettingKey<Bool>(.activities, "satellite", default: true)
    /// Seconds; 0 = never. Collapses compact to closed (keeps the satellite).
    public static let compactInactivityTimeout = SettingKey<Double>(.activities, "compactInactivityTimeout", default: 0)
    public static let swipeToDismiss = SettingKey<Bool>(.activities, "swipeToDismiss", default: true)
    public static let autoUnhide = SettingKey<Bool>(.activities, "autoUnhide", default: true)
    public static let menuBarCourtesy = SettingKey<Bool>(.activities, "menuBarCourtesy", default: true)
    /// Menu bar extra ▸ Pause Live Activities. nil = not paused; `.distantFuture` = until resumed.
    public static let pausedUntil = SettingKey<Date?>(.activities, "pausedUntil", default: nil)

    // Gestures
    public static let trackSwipe = SettingKey<Bool>(.gestures, "trackSwipe", default: true)
    public static let invertTrackSwipe = SettingKey<Bool>(.gestures, "invertTrackSwipe", default: false)
    public static let swipeOpenClose = SettingKey<Bool>(.gestures, "swipeOpenClose", default: true)
    public static let gestureSensitivity = SettingKey<Double>(.gestures, "sensitivity", default: 1)   // 0.5…1.5
    public static let haptics = SettingKey<Bool>(.gestures, "haptics", default: true)

    // Keyboard
    /// User overrides; a missing entry means the shortcut's `defaultCombo`; an explicit nil means "off".
    public static let shortcuts = SettingKey<[ShortcutID: KeyCombo?]>(.keyboard, "shortcuts", default: [:])
    /// `CaptureTarget.id` ("notes", "todos") or nil = off.
    public static let typeToCapture = SettingKey<String?>(.keyboard, "typeToCapture", default: "notes")

    // Onboarding & updates
    public static let onboardingCompletedVersion = SettingKey<String?>(.onboarding, "completedVersion", default: nil)
    public static let tutorialCompleted = SettingKey<Bool>(.onboarding, "tutorialCompleted", default: false)
    public static let checksForUpdates = SettingKey<Bool>(.updates, "automatic", default: true)
    public static let includesPrereleases = SettingKey<Bool>(.updates, "prereleases", default: false)
    public static let lastUpdateCheck = SettingKey<Date?>(.updates, "lastCheck", default: nil)
}
```

### A.3 `Input/NotchZones.swift`

```swift
// CrannyCore/Input/NotchZones.swift
// AppKit owns drag-and-drop and scroll events for the panel (R1 §5–6: SwiftUI .onDrop registers
// public.data/public.item and .onDrag hands out temporary copies). Views DECLARE zones; the shell's
// root NSView routes events to them by geometry. One registry per canvas (per display panel).
import SwiftUI
import UniformTypeIdentifiers

/// Files dropped on the notch. File promises (Photos, Mail, Safari) are already resolved to URLs
/// by the shell (in a temporary directory) before a handler is called.
public nonisolated struct DropPayload: Sendable {
    public var fileURLs: [URL]
    public var contentTypes: [UTType]
    public init(fileURLs: [URL], contentTypes: [UTType]) { self.fileURLs = fileURLs; self.contentTypes = contentTypes }
}

@MainActor @Observable public final class NotchZones {
    public struct DropZone {
        public let id: DropZoneID
        public var frame: CGRect                         // in NotchCoordinateSpace.name
        public let accepts: [UTType]
        public let perform: @MainActor (DropPayload) async -> Bool
    }
    public struct ScrollZone {
        public let id: ScrollZoneID
        public var frame: CGRect
        public let axis: SwipeAxis
        public let onUpdate: @MainActor (SwipeUpdate) -> Void
    }

    /// The drop zone under the pointer during a file drag (views highlight when `armedDropZone == id`).
    public private(set) var armedDropZone: DropZoneID?
    /// Types on the drag pasteboard while a file drag is in progress, else empty.
    public private(set) var draggedTypes: [UTType] = []
    @ObservationIgnored private var dropZones: [DropZoneID: DropZone] = [:]
    @ObservationIgnored private var scrollZones: [ScrollZoneID: ScrollZone] = [:]
    @ObservationIgnored private var trackers: [ScrollZoneID: SwipeTracker] = [:]
    @ObservationIgnored private var activeScrollZone: ScrollZoneID?

    public init() {}

    // MARK: View side (via modifiers)
    public func setDropZone(_ zone: DropZone) { dropZones[zone.id] = zone }
    public func removeDropZone(_ id: DropZoneID) { dropZones[id] = nil; if armedDropZone == id { armedDropZone = nil } }
    public func setScrollZone(_ zone: ScrollZone) { scrollZones[zone.id] = zone }
    public func removeScrollZone(_ id: ScrollZoneID) { scrollZones[id] = nil; trackers[id] = nil }

    // MARK: Shell side (NotchRootView: NSDraggingDestination + NotchPanel.sendEvent)
    public func dragUpdated(at point: CGPoint, types: [UTType]) {
        draggedTypes = types
        armedDropZone = dropZones.values
            .filter { $0.frame.contains(point) && $0.accepts.contains { a in types.contains { $0.conforms(to: a) } } }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id   // innermost wins
    }
    public func dragEnded() { draggedTypes = []; armedDropZone = nil }
    /// Delivers to the armed zone, else to `fallback` (normally `.trayKeep`). Returns false if nobody took it.
    public func performDrop(_ payload: DropPayload, fallback: DropZoneID? = .trayKeep) async -> Bool {
        let target = armedDropZone.flatMap { dropZones[$0] } ?? fallback.flatMap { dropZones[$0] }
        dragEnded()
        guard let target else { return false }
        return await target.perform(payload)
    }
    /// Feeds a scroll event to the zone under the pointer. Returns true if consumed.
    public func scroll(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) || activeScrollZone == nil {
            activeScrollZone = scrollZones.values.first { $0.frame.contains(point) }?.id
        }
        guard let id = activeScrollZone, let zone = scrollZones[id] else { return false }
        var tracker = trackers[id] ?? SwipeTracker(axis: zone.axis)
        let update = tracker.handle(sample)
        trackers[id] = tracker
        if let update { zone.onUpdate(update) }
        if sample.phase.contains(.ended) || sample.phase.contains(.cancelled) { activeScrollZone = nil }
        return true
    }
}

public extension View {
    /// Declares a file drop target (Tray keep zone, AirDrop widget, pipeline zones, Quick Apps).
    func crannyDropZone(_ id: DropZoneID, accepts: [UTType],
                        perform: @escaping @MainActor (DropPayload) async -> Bool) -> some View {
        modifier(DropZoneModifier(id: id, accepts: accepts, perform: perform))
    }
    /// Declares a two-finger scroll target (track swipe over artwork, timer ±1 min, scrubber seek).
    func crannyScrollZone(_ id: ScrollZoneID, axis: SwipeAxis,
                          onUpdate: @escaping @MainActor (SwipeUpdate) -> Void) -> some View {
        modifier(ScrollZoneModifier(id: id, axis: axis, onUpdate: onUpdate))
    }
}

struct DropZoneModifier: ViewModifier {
    @Environment(\.notchZones) private var zones
    let id: DropZoneID
    let accepts: [UTType]
    let perform: @MainActor (DropPayload) async -> Bool
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(NotchCoordinateSpace.name)) }) { frame in
                zones?.setDropZone(.init(id: id, frame: frame, accepts: accepts, perform: perform))
            }
            .onDisappear { zones?.removeDropZone(id) }
    }
}

struct ScrollZoneModifier: ViewModifier {
    @Environment(\.notchZones) private var zones
    let id: ScrollZoneID
    let axis: SwipeAxis
    let onUpdate: @MainActor (SwipeUpdate) -> Void
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(NotchCoordinateSpace.name)) }) { frame in
                zones?.setScrollZone(.init(id: id, frame: frame, axis: axis, onUpdate: onUpdate))
            }
            .onDisappear { zones?.removeScrollZone(id) }
    }
}
```

### A.4 `Input/SwipeTracker.swift`

```swift
// CrannyCore/Input/SwipeTracker.swift
// Pure two-finger swipe state machine (extends R1 §6's verified recognizer with live tracking for
// rubber-banding, DESIGN.md §4.4). No AppKit state: unit-test it with synthetic samples.
import CoreGraphics
import Foundation

public nonisolated enum SwipeAxis: Sendable, Equatable { case horizontal, vertical, any }
public nonisolated enum SwipeDirection: Sendable, Equatable { case left, right, up, down }

/// Scroll phases (mirrors NSEvent.Phase without importing AppKit).
public nonisolated struct SwipePhase: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let began = SwipePhase(rawValue: 1 << 0)
    public static let stationary = SwipePhase(rawValue: 1 << 1)
    public static let changed = SwipePhase(rawValue: 1 << 2)
    public static let ended = SwipePhase(rawValue: 1 << 3)
    public static let cancelled = SwipePhase(rawValue: 1 << 4)
    public static let mayBegin = SwipePhase(rawValue: 1 << 5)
}

public nonisolated struct ScrollSample: Sendable, Equatable {
    public var phase: SwipePhase
    public var isMomentum: Bool            // momentumPhase non-empty: fingers already lifted → ignored
    public var deltaX: CGFloat             // scrollingDeltaX
    public var deltaY: CGFloat             // scrollingDeltaY
    public var isPrecise: Bool             // hasPreciseScrollingDeltas (trackpad, Magic Mouse)
    public var isInvertedFromDevice: Bool  // "natural scrolling": deltas already follow the fingers
    public var timestamp: TimeInterval
    public init(phase: SwipePhase, isMomentum: Bool, deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool,
                isInvertedFromDevice: Bool, timestamp: TimeInterval) {
        self.phase = phase; self.isMomentum = isMomentum; self.deltaX = deltaX; self.deltaY = deltaY
        self.isPrecise = isPrecise; self.isInvertedFromDevice = isInvertedFromDevice; self.timestamp = timestamp
    }
}

public nonisolated enum SwipeUpdate: Sendable, Equatable {
    /// Live finger travel along the locked axis (pt, +x = right, +y = down). Drive rubber-banding with it.
    case tracking(SwipeAxis, translation: CGFloat)
    /// Threshold crossed (fires ONCE per touch sequence, while the finger is still down → haptic now).
    case committed(SwipeDirection, velocity: CGFloat)
    /// Released below the threshold: snap back (`CrannyMotion.Kind.snapBack`).
    case cancelled
}

public nonisolated struct SwipeTracker: Sendable {
    public var axis: SwipeAxis
    /// Commit distances per direction (DESIGN.md `GestureSpec`).
    public var horizontalCommit: CGFloat = GestureSpec.trackSwipeCommit
    public var downCommit: CGFloat = GestureSpec.pullOpen
    public var upCommit: CGFloat = GestureSpec.pushClose
    public var horizontalVelocity: CGFloat = GestureSpec.trackSwipeVelocity
    public var verticalVelocity: CGFloat = GestureSpec.verticalVelocity
    /// Settings ▸ Gestures ▸ Sensitivity (0.5…1.5): divides the distances.
    public var sensitivity: CGFloat = 1
    public var invertHorizontal = false

    private var x: CGFloat = 0, y: CGFloat = 0
    private var locked: SwipeAxis?
    private var fired = false
    private var lastFire: TimeInterval = -.infinity
    private var lastSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?
    private var previousSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?

    public init(axis: SwipeAxis) { self.axis = axis }

    public mutating func handle(_ s: ScrollSample) -> SwipeUpdate? {
        guard !s.isMomentum, s.isPrecise, !s.phase.isEmpty else { return nil }
        if s.phase.contains(.began) || s.phase.contains(.mayBegin) { reset() }
        if s.phase.contains(.ended) || s.phase.contains(.cancelled) {
            defer { reset() }
            guard !fired, let locked else { return nil }   // already committed, or never locked to an axis
            let v = velocity(at: s.timestamp)
            if let dir = direction(for: locked, distance: locked == .horizontal ? x : y),
               abs(locked == .horizontal ? v.x : v.y) >= (locked == .horizontal ? horizontalVelocity : verticalVelocity),
               s.timestamp - lastFire >= GestureSpec.cooldown {
                lastFire = s.timestamp
                return .committed(dir, velocity: locked == .horizontal ? v.x : v.y)
            }
            return .cancelled
        }
        guard s.phase.contains(.changed) || s.phase.contains(.began) else { return nil }
        let sign: CGFloat = s.isInvertedFromDevice ? 1 : -1      // normalise to physical finger motion
        x += s.deltaX * sign; y += s.deltaY * sign
        previousSample = lastSample
        lastSample = (s.timestamp, x, y)
        if locked == nil {
            if abs(x) >= 4, abs(x) >= abs(y) * GestureSpec.axisLock, axis != .vertical { locked = .horizontal }
            else if abs(y) >= 4, abs(y) >= abs(x) * GestureSpec.axisLock, axis != .horizontal { locked = .vertical }
        }
        guard let locked else { return nil }
        let d = locked == .horizontal ? x : y
        if !fired, s.timestamp - lastFire >= GestureSpec.cooldown, let dir = direction(for: locked, distance: d),
           abs(d) >= commitDistance(dir) / max(sensitivity, 0.1) {
            fired = true; lastFire = s.timestamp
            let v = velocity(at: s.timestamp)
            return .committed(dir, velocity: locked == .horizontal ? v.x : v.y)
        }
        return fired ? nil : .tracking(locked, translation: d)
    }

    private func direction(for axis: SwipeAxis, distance d: CGFloat) -> SwipeDirection? {
        guard d != 0 else { return nil }
        switch axis {
        case .horizontal:
            var right = d > 0
            if invertHorizontal { right.toggle() }
            return right ? .right : .left
        case .vertical: return d > 0 ? .down : .up
        case .any: return nil
        }
    }
    private func commitDistance(_ dir: SwipeDirection) -> CGFloat {
        switch dir {
        case .left, .right: horizontalCommit
        case .down: downCommit
        case .up: upCommit
        }
    }
    /// pt/s between the two most recent samples (precise deltas arrive at display rate).
    private func velocity(at t: TimeInterval) -> (x: CGFloat, y: CGFloat) {
        guard let last = lastSample, let prev = previousSample else { return (0, 0) }
        let dt = max(last.t - prev.t, 0.001)
        return ((last.x - prev.x) / dt, (last.y - prev.y) / dt)
    }
    private mutating func reset() {
        x = 0; y = 0; locked = nil; fired = false; lastSample = nil; previousSample = nil
    }
}
```

### A.5 `Permissions/PermissionsCenter.swift`

```swift
// CrannyCore/Permissions/PermissionsCenter.swift
// The ONLY place that queries or requests TCC permissions (R3 §11). Modules call `request` from the
// inline "needs permission" state of their widget — never at launch, never in bulk.
import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreServices
import EventKit
import Observation

public nonisolated enum PermissionKind: Hashable, Codable, Sendable {
    case accessibility                  // HUD key interception (CGEventTap on NX_SYSDEFINED)
    case calendar                       // EventKit full access
    case camera                         // Mirror
    case bluetooth                      // optional "Show all Bluetooth devices" (IOBluetooth)
    case systemAudioRecording           // optional Live visualizer (Core Audio process tap, macOS 14.2+)
    case automation(bundleID: String)   // Apple Events to Music / Spotify (media fallback)

    /// System Settings deep link (scheme verified on macOS 27; anchors UNVERIFIED there).
    public var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: URL(string: base + "Privacy_Accessibility")
        case .calendar: URL(string: base + "Privacy_Calendars")
        case .camera: URL(string: base + "Privacy_Camera")
        case .bluetooth: URL(string: base + "Privacy_Bluetooth")
        case .systemAudioRecording: URL(string: base + "Privacy_ScreenCapture")
        case .automation: URL(string: base + "Privacy_Automation")
        }
    }
}

public nonisolated enum PermissionStatus: String, Codable, Sendable {
    case notDetermined, granted, denied, restricted
    /// No query API (system audio recording) or the automation target is not running.
    case unknown
}

@MainActor @Observable public final class PermissionsCenter {
    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private var accessibilityWatch: Task<Void, Never>?
    @ObservationIgnored private var recorded: [PermissionKind: PermissionStatus] = [:]

    public init() { refresh() }

    public func status(_ kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? query(kind)
    }

    /// Re-query everything (call on app activation and when Settings ▸ Permissions appears).
    public func refresh() {
        var next: [PermissionKind: PermissionStatus] = [:]
        for kind in [PermissionKind.accessibility, .calendar, .camera, .bluetooth, .systemAudioRecording] {
            next[kind] = query(kind)
        }
        for (kind, _) in statuses { if case .automation = kind { next[kind] = query(kind) } }
        statuses = next
    }

    /// Shows the system prompt when one exists; otherwise opens System Settings. Returns the new status.
    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt is a mutable C global (Swift 6 error) — use its literal value.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            watchAccessibility()
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .bluetooth:
            await BluetoothPrompt.trigger()
        case .systemAudioRecording:
            break   // prompted by AudioDeviceStart in CrannyMedia; it reports back via `record`
        case .automation(let bundleID):
            _ = await Self.automationStatus(bundleID, ask: true)
        }
        let s = query(kind)
        statuses[kind] = s
        return s
    }

    public func openSystemSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// For kinds without a query API: the feature reports what it observed (tap delivered audio → granted).
    public func record(_ status: PermissionStatus, for kind: PermissionKind) {
        recorded[kind] = status
        statuses[kind] = status
    }

    // MARK: Queries (cheap, never prompt)
    private func query(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .calendar:
            return switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .denied, .writeOnly: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .camera:
            return switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .bluetooth:
            return switch CBManager.authorization {
            case .allowedAlways: .granted
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .systemAudioRecording:
            return recorded[kind] ?? .unknown
        case .automation(let bundleID):
            return Self.automationStatusSync(bundleID)
        }
    }

    /// Accessibility changes do not notify: poll every 1.5 s for up to 2 minutes after a request.
    private func watchAccessibility() {
        accessibilityWatch?.cancel()
        accessibilityWatch = Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self, !Task.isCancelled else { return }
                if AXIsProcessTrusted() { self.statuses[.accessibility] = .granted; return }
            }
        }
    }

    private static func automationStatusSync(_ bundleID: String) -> PermissionStatus {
        map(automationOSStatus(bundleID, ask: false))
    }
    /// `AEDeterminePermissionToAutomateTarget` blocks while its prompt is up: never on the main thread.
    @concurrent private static func automationStatus(_ bundleID: String, ask: Bool) async -> PermissionStatus {
        map(automationOSStatus(bundleID, ask: ask))
    }
    nonisolated private static func automationOSStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }
    nonisolated private static func map(_ status: OSStatus) -> PermissionStatus {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
        default: .unknown          // procNotFound (-600): the player is not running
        }
    }
}

/// Creating a CBCentralManager is what shows the Bluetooth prompt.
@MainActor private enum BluetoothPrompt {
    static var manager: CBCentralManager?
    static func trigger() async {
        guard CBManager.authorization == .notDetermined else { return }
        manager = CBCentralManager(delegate: nil, queue: nil)
        for _ in 0..<60 where CBManager.authorization == .notDetermined {
            try? await Task.sleep(for: .milliseconds(500))
        }
        manager = nil
    }
}
```

### A.6 `Platform/Platform.swift`

```swift
// CrannyCore/Platform/Platform.swift
// Logging, haptics, file locations, version info.
import AppKit
import Foundation
import os

// MARK: - Logging

public nonisolated enum LogCategory: String, Sendable, CaseIterable {
    case app, overlay, state, input, activities, settings, permissions, storage, updates, onboarding
    case media, mediaBridge, calendar, quickApps, mirror, notes, todos, timer, tray, pipelines
    case hud, eventTap, system, bluetooth, effects
}

/// `private let log = Log.logger(.timer)` at file scope. Interpolate user data with `privacy: .private`
/// (titles, file names, paths); states, counts and error codes with `privacy: .public`.
public nonisolated enum Log {
    public static let subsystem = "app.cranny.Cranny"
    public static func logger(_ category: LogCategory) -> Logger { Logger(subsystem: subsystem, category: category.rawValue) }
}

// MARK: - Haptics (DESIGN.md §14.2)

public nonisolated enum HapticPattern: Sendable {
    case alignment      // threshold crossed, drop zone armed, snap, tutorial step
    case levelChange    // detents: scrubber 10 %, timer minute, HUD at 0/100 %
    case generic        // drop accepted, pipeline done, to-do completed, opened by gesture
}

/// Never for hover, peek or an activity arriving. Every haptic has a visual counterpart.
@MainActor public final class Haptics {
    private let isEnabled: @MainActor () -> Bool
    public init(isEnabled: @escaping @MainActor () -> Bool) { self.isEnabled = isEnabled }
    public func play(_ pattern: HapticPattern) {
        guard isEnabled() else { return }
        let p: NSHapticFeedbackManager.FeedbackPattern = switch pattern {
        case .alignment: .alignment
        case .levelChange: .levelChange
        case .generic: .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }
}

// MARK: - Files

/// ~/Library/Application Support/app.cranny.Cranny/<module>/ — the only place modules write files.
public nonisolated struct AppPaths: Sendable {
    public let root: URL
    public let caches: URL
    public init(root: URL, caches: URL) { self.root = root; self.caches = caches }

    public static let live: AppPaths = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return AppPaths(root: support.appending(path: Log.subsystem, directoryHint: .isDirectory),
                        caches: caches.appending(path: Log.subsystem, directoryHint: .isDirectory))
    }()

    /// A fresh throw-away root for tests and previews.
    public static func temporary() -> AppPaths {
        let base = FileManager.default.temporaryDirectory.appending(path: "cranny-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppPaths(root: base.appending(path: "Support"), caches: base.appending(path: "Caches"))
    }

    /// Creates the directory on first use.
    public func directory(for module: ModuleID) throws -> URL {
        let url = root.appending(path: module.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public func cacheDirectory(for module: ModuleID) throws -> URL {
        let url = caches.appending(path: module.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Codable document on disk with atomic writes. Corrupt files are renamed aside and the default is used.
public actor JSONFileStore<Value: Codable & Sendable> {
    public let url: URL
    private let defaultValue: Value
    public init(url: URL, defaultValue: Value) { self.url = url; self.defaultValue = defaultValue }

    public func load() -> Value {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        do { return try JSONDecoder().decode(Value.self, from: data) } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.logger(.storage).error("corrupt \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }
    }

    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

// MARK: - App info and versions

public nonisolated struct AppInfo: Sendable, Codable {
    public let bundleIdentifier: String
    public let version: String
    public let build: String
    public static func current(_ bundle: Bundle = .main) -> AppInfo {
        AppInfo(bundleIdentifier: bundle.bundleIdentifier ?? "(none)",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
    }
}

/// "v1.2" / "1.10.0" / "1.2.0-beta.1" (pre-release suffix sorts before the release).
public nonisolated struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    public let prerelease: String?
    public init?(_ string: String) {
        var s = Substring(string)
        if s.hasPrefix("v") { s = s.dropFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        let nums = parts.first.map { $0.split(separator: ".").map { Int($0) } } ?? []
        guard (1...3).contains(nums.count), nums.allSatisfy({ $0 != nil }) else { return nil }
        let n = nums.compactMap { $0 } + [0, 0]
        (major, minor, patch) = (n[0], n[1], n[2])
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }
    public static func < (a: Self, b: Self) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) { return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch) }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
    public var description: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
}
```

### A.7 `Platform/Concurrency.swift`

```swift
// CrannyCore/Platform/Concurrency.swift
// Small, verified building blocks so modules never hand-roll threading.
import Foundation
import Observation

// MARK: - Observation outside SwiftUI (macOS 14-safe; `Observations` is macOS 26+)

/// Calls `onChange` with the new value whenever something `value()` reads changes.
/// Keep the returned token alive; `cancel()` (or releasing it) stops observing.
@MainActor public final class ObservationToken {
    fileprivate var observer: AnyObject?
    public func cancel() { observer = nil }
}

@MainActor @discardableResult
public func observe<T: Equatable>(_ value: @escaping @MainActor () -> T,
                                  onChange: @escaping @MainActor (T) -> Void) -> ObservationToken {
    let token = ObservationToken()
    let observer = Observer(value: value, onChange: onChange)
    token.observer = observer
    observer.arm()
    return token
}

@MainActor private final class Observer<T: Equatable> {
    let value: @MainActor () -> T
    let onChange: @MainActor (T) -> Void
    var last: T
    init(value: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
        self.value = value; self.onChange = onChange; self.last = value()
    }
    func arm() {
        withObservationTracking { _ = value() } onChange: { [weak self] in
            Task { @MainActor in self?.fire() }
        }
    }
    private func fire() {
        let now = value()
        if now != last { last = now; onChange(now) }
        arm()
    }
}

// MARK: - Debounce

/// Trailing debounce on the main actor (note autosave, settings-driven rebuilds).
@MainActor public final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?
    public init(delay: Duration) { self.delay = delay }
    public func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    public func cancel() { task?.cancel(); task = nil }
}

// MARK: - Subprocesses

public nonisolated struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var succeeded: Bool { status == 0 }
}

public nonisolated enum ProcessRunError: Error, Sendable { case launchFailed(String) }

/// Runs a command-line tool off the main actor (`/usr/bin/shortcuts`, `/usr/bin/ditto`).
/// Both pipes are drained while the process runs (no pipe-buffer deadlock). Cancelling the calling task
/// terminates the process. Environment is minimal and explicit (never inherits PERL5LIB, DYLD_*).
public nonisolated enum ProcessRunner {
    @concurrent
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"],
                           currentDirectory: URL? = nil) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessOutput, any Error>) in
                let collector = OutputCollector()
                out.fileHandleForReading.readabilityHandler = { collector.append($0.availableData, error: false) }
                err.fileHandleForReading.readabilityHandler = { collector.append($0.availableData, error: true) }
                process.terminationHandler = { p in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    collector.append(out.fileHandleForReading.readDataToEndOfFile(), error: false)
                    collector.append(err.fileHandleForReading.readDataToEndOfFile(), error: true)
                    let (o, e) = collector.result
                    cont.resume(returning: ProcessOutput(status: p.terminationStatus, stdout: o, stderr: e))
                }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: ProcessRunError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

private nonisolated final class ProcessBox: @unchecked Sendable {   // Process is thread-safe for terminate()
    private let process: Process
    init(_ p: Process) { process = p }
    func terminate() { if process.isRunning { process.terminate() } }
}

private nonisolated final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    func append(_ d: Data, error: Bool) {
        guard !d.isEmpty else { return }
        lock.withLock { if error { err.append(d) } else { out.append(d) } }
    }
    var result: (Data, Data) { lock.withLock { (out, err) } }
}
```

### A.8 `DesignSystem/SharedComponents.swift`

```swift
// CrannyCore/DesignSystem/SharedComponents.swift
// Components added by ARCHITECTURE.md on top of DESIGN.md Appendix A. They read tokens only and take
// ALREADY-LOCALIZED Strings (a LocalizedStringKey passed into Core would be looked up in Bundle.main).
import SwiftUI

// MARK: - Widget states (DESIGN.md §6.8: empty · needs permission · loading · error)

public struct WidgetStateView: View {
    public enum Kind: Sendable { case empty, needsPermission, loading, error }
    @Environment(\.cranny) private var theme
    private let kind: Kind, symbol: String, message: String, actionTitle: String?
    private let action: (@MainActor () -> Void)?

    public init(_ kind: Kind, symbol: String, message: String, actionTitle: String? = nil,
                action: (@MainActor () -> Void)? = nil) {
        self.kind = kind; self.symbol = symbol; self.message = message
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        let p = theme.palette
        VStack(spacing: Space.s) {
            if kind == .loading {
                ProgressRing(progress: 0.25, color: p.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                    .foregroundStyle(kind == .error ? p.danger : p.secondaryLabel)
            }
            Text(message).crannyFont(.callout).foregroundStyle(p.secondaryLabel)
                .multilineTextAlignment(.center).lineLimit(2)
            if let actionTitle, let action {
                Button(action: action) { Text(actionTitle) }
                    .buttonStyle(CrannyChipButtonStyle(prominent: kind == .needsPermission))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chip / capsule button (pipeline chips, Join capsule, presets)

public struct CrannyChipButtonStyle: ButtonStyle {
    public var tint: Color?
    public var prominent: Bool
    public init(tint: Color? = nil, prominent: Bool = false) { self.tint = tint; self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, tint: tint, prominent: prominent) }

    struct ChipBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration, tint: Color?, prominent: Bool
        var body: some View {
            let p = theme.palette
            let fill: Color = prominent ? (tint ?? .white) : (configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control)
            configuration.label
                .crannyFont(.caption).fontWeight(.semibold)
                .foregroundStyle(prominent ? Color.black : (tint ?? p.label))
                .padding(.horizontal, Space.m).frame(minHeight: 22)
                .background(Capsule(style: .continuous).fill(fill))
                .contentShape(Capsule(style: .continuous))
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
        }
    }
}

// MARK: - Scrubber (interactive LevelBar: media seek, HUD-style sliders)

public struct Scrubber: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    @State private var dragValue: Double?
    private let value: Double
    private let step: Double
    private let label: String
    private let valueDescription: String
    private let onCommit: @MainActor (Double) -> Void

    /// `value` 0…1. `step` is the VoiceOver/arrow-key increment (e.g. 10 s / duration).
    public init(value: Double, step: Double, label: String, valueDescription: String,
                onCommit: @escaping @MainActor (Double) -> Void) {
        self.value = value; self.step = step; self.label = label
        self.valueDescription = valueDescription; self.onCommit = onCommit
    }

    public var body: some View {
        let active = hovered || dragValue != nil
        GeometryReader { g in
            LevelBar(value: dragValue ?? value, tint: theme.accentColor,
                     thickness: active ? StrokeWidth.scrubberActive : StrokeWidth.scrubber)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(max($0.location.x / max(g.size.width, 1), 0), 1) }
                    .onEnded { _ in if let v = dragValue { onCommit(v) }; dragValue = nil })
        }
        .frame(height: HitTarget.nook.height)
        .onHover { hovered = $0 }
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueDescription))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(value + step, 1))
            case .decrement: onCommit(max(value - step, 0))
            @unknown default: break
            }
        }
    }
}

// MARK: - Marquee (the ONLY marquee: overflowing track title after a 1.5 s hover, DESIGN.md §2.2)

public struct MarqueeText: View {
    @Environment(\.cranny) private var theme
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    private let text: String, style: CrannyTextStyle, isActive: Bool

    /// `isActive` = hovered for ≥ 1.5 s (the caller owns the timer). Reduce Motion: never scrolls; tooltip instead.
    public init(_ text: String, style: CrannyTextStyle, isActive: Bool) {
        self.text = text; self.style = style; self.isActive = isActive
    }

    public var body: some View {
        let overflow = max(textWidth - boxWidth, 0)
        Text(text).crannyFont(style).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            .offset(x: offset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .clipped()
            .help(text)
            .onChange(of: isActive && overflow > 0 && !theme.reduceMotion) { _, run in
                if run {
                    withAnimation(.linear(duration: Double(overflow) / 30).delay(0.3).repeatForever(autoreverses: true)) { offset = -overflow }
                } else {
                    withAnimation(theme.animation(.contentSwap)) { offset = 0 }
                }
            }
            .accessibilityLabel(Text(text))
    }
}
```

### A.9 `CrannyCore.swift`

```swift
// CrannyCore/CrannyCore.swift
// Module overview: DesignSystem/ (DESIGN.md tokens + components), Contracts/ (module plug-in API),
// Services/ (ports + hub), Settings/, Permissions/, Input/, Platform/.
import Foundation

public extension PermissionKind {
    /// Localized name for Settings ▸ Permissions and onboarding rows.
    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility", bundle: .module, comment: "Permission name (System Settings ▸ Privacy)")
        case .calendar: String(localized: "Calendars", bundle: .module, comment: "Permission name")
        case .camera: String(localized: "Camera", bundle: .module, comment: "Permission name")
        case .bluetooth: String(localized: "Bluetooth", bundle: .module, comment: "Permission name")
        case .systemAudioRecording: String(localized: "System Audio Recording", bundle: .module, comment: "Permission name")
        case .automation(let bundleID):
            String(localized: "Automation (\(bundleID))", bundle: .module, comment: "Permission name; argument is an app bundle identifier")
        }
    }
}
```

### A.10 `Tests/CrannyCoreTests/CrannyCoreTests.swift` (starting point)

```swift
import Foundation
import SwiftUI
import Testing
@testable import CrannyCore

@MainActor @Test func settingsPersistResetAndNamespace() throws {
    let suite = "cranny.test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let key = SettingKey<[Int]>(.timer, "presets", default: [1, 5])
    let a = SettingsStore(defaults: defaults)
    #expect(a[key] == [1, 5] && a.isDefault(key))
    a[key] = [25]
    #expect(SettingsStore(defaults: defaults)[key] == [25])          // persisted (JSON under cranny.timer.presets)
    #expect(defaults.data(forKey: "cranny.timer.presets") != nil)
    a.reset(module: .timer)
    #expect(a[key] == [1, 5])                                          // live box reset
    #expect(defaults.data(forKey: "cranny.timer.presets") == nil)
    a[CoreSettings.activityPreferences] = [.nowPlaying: ActivityPreference(isEnabled: false, peeksOnChange: true)]
    let json = try #require(defaults.data(forKey: "cranny.activities.preferences"))
    #expect(String(decoding: json, as: UTF8.self).contains("\"media.nowPlaying\""))  // dictionary keyed by raw id
    a.resetAll()
    #expect(a[CoreSettings.activityPreferences].isEmpty)
}

@Test func swipeCommitsOncePerSequence() {
    var t = SwipeTracker(axis: .horizontal)
    func s(_ p: SwipePhase, _ dx: CGFloat, _ ts: TimeInterval) -> ScrollSample {
        ScrollSample(phase: p, isMomentum: false, deltaX: dx, deltaY: 0, isPrecise: true, isInvertedFromDevice: true, timestamp: ts)
    }
    #expect(t.handle(s(.began, 0, 0)) == nil)
    var updates: [SwipeUpdate] = []
    for i in 1...10 { if let u = t.handle(s(.changed, 6, Double(i) * 0.016)) { updates.append(u) } }
    #expect(updates.contains { if case .committed(.right, _) = $0 { true } else { false } })
    #expect(updates.filter { if case .committed = $0 { true } else { false } }.count == 1)
    #expect(t.handle(s(.ended, 0, 0.2)) == nil)
}

@Test func versions() throws {
    #expect(try #require(SemanticVersion("v1.2")) < #require(SemanticVersion("1.10.0")))
    #expect(try #require(SemanticVersion("1.0.0-beta.2")) < #require(SemanticVersion("1.0.0")))
}

@MainActor @Test func registryFillsPageNamespacesAndActivityOptions() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(settingsPage: SettingsPage(id: "x", title: "X", symbol: "gearshape.fill", tint: .gray, group: .features, order: 0) { AnyView(EmptyView()) })
    #expect(registry.settingsPages.first?.namespaces == [])           // registered outside a module: stays empty (shell)
    let notch = PreviewNotchControl()
    notch.flash(symbol: "hand.wave.fill", label: "Hi")
    #expect(notch.calls == ["flash(hand.wave.fill)"])
    #expect(DelightMoment.allCases.count == 5)
}

@MainActor @Test func resetAllCanBeUndone() throws {
    let defaults = try #require(UserDefaults(suiteName: "cranny.test.\(UUID().uuidString)"))
    let s = SettingsStore(defaults: defaults)
    s[CoreSettings.openMode] = .click
    s[CoreSettings.panelPaddingTune] = 3
    let snap = s.snapshot()
    s.resetAll()
    #expect(s[CoreSettings.openMode] == .hover)
    s.restore(snap)
    #expect(s[CoreSettings.openMode] == .click && s[CoreSettings.panelPaddingTune] == 3)
    #expect(SettingsStore(defaults: defaults)[CoreSettings.openMode] == .click)
    let g = NookGrid(paddingTune: 3)
    #expect(g.padding == 15 && g.cardRadius == Radius.card && g.panelRadius == 35)
}
```

---

## Appendix B — App target, project and tooling files (verbatim, built)

### B.1 `Cranny.xcodeproj/project.pbxproj`

```text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		C0A11E000000000000000020 /* CrannyAppShell in Frameworks */ = {isa = PBXBuildFile; productRef = C0A11E000000000000000030 /* CrannyAppShell */; };
		C0A11E000000000000000078 /* libCrannyMediaBridge.dylib in Embed Media Bridge */ = {isa = PBXBuildFile; fileRef = C0A11E000000000000000074 /* libCrannyMediaBridge.dylib */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		C0A11E000000000000000076 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = C0A11E000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = C0A11E000000000000000070;
			remoteInfo = CrannyMediaBridge;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		C0A11E000000000000000014 /* Embed Media Bridge */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
				C0A11E000000000000000078 /* libCrannyMediaBridge.dylib in Embed Media Bridge */,
			);
			name = "Embed Media Bridge";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		C0A11E000000000000000004 /* Cranny.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Cranny.app; sourceTree = BUILT_PRODUCTS_DIR; };
		C0A11E000000000000000074 /* libCrannyMediaBridge.dylib */ = {isa = PBXFileReference; explicitFileType = "compiled.mach-o.dylib"; includeInIndex = 0; path = libCrannyMediaBridge.dylib; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		C0A11E000000000000000006 /* Exceptions for "App" folder in "Cranny" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = C0A11E000000000000000010 /* Cranny */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		C0A11E000000000000000005 /* App */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				C0A11E000000000000000006 /* Exceptions for "App" folder in "Cranny" target */,
			);
			path = App;
			sourceTree = "<group>";
		};
		C0A11E000000000000000075 /* CrannyMediaBridge */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			name = CrannyMediaBridge;
			path = Packages/CrannyKit/Sources/CrannyMediaBridge;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		C0A11E000000000000000012 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				C0A11E000000000000000020 /* CrannyAppShell in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		C0A11E000000000000000072 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		C0A11E000000000000000002 = {
			isa = PBXGroup;
			children = (
				C0A11E000000000000000005 /* App */,
				C0A11E000000000000000075 /* CrannyMediaBridge */,
				C0A11E000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		C0A11E000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				C0A11E000000000000000004 /* Cranny.app */,
				C0A11E000000000000000074 /* libCrannyMediaBridge.dylib */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		C0A11E000000000000000010 /* Cranny */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = C0A11E000000000000000060 /* Build configuration list for PBXNativeTarget "Cranny" */;
			buildPhases = (
				C0A11E000000000000000011 /* Sources */,
				C0A11E000000000000000012 /* Frameworks */,
				C0A11E000000000000000013 /* Resources */,
				C0A11E000000000000000014 /* Embed Media Bridge */,
			);
			buildRules = (
			);
			dependencies = (
				C0A11E000000000000000077 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				C0A11E000000000000000005 /* App */,
			);
			name = Cranny;
			packageProductDependencies = (
				C0A11E000000000000000030 /* CrannyAppShell */,
			);
			productName = Cranny;
			productReference = C0A11E000000000000000004 /* Cranny.app */;
			productType = "com.apple.product-type.application";
		};
		C0A11E000000000000000070 /* CrannyMediaBridge */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = C0A11E000000000000000080 /* Build configuration list for PBXNativeTarget "CrannyMediaBridge" */;
			buildPhases = (
				C0A11E000000000000000071 /* Sources */,
				C0A11E000000000000000072 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				C0A11E000000000000000075 /* CrannyMediaBridge */,
			);
			name = CrannyMediaBridge;
			packageProductDependencies = (
			);
			productName = CrannyMediaBridge;
			productReference = C0A11E000000000000000074 /* libCrannyMediaBridge.dylib */;
			productType = "com.apple.product-type.library.dynamic";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		C0A11E000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {
					C0A11E000000000000000010 = {
						CreatedOnToolsVersion = 27.0;
					};
					C0A11E000000000000000070 = {
						CreatedOnToolsVersion = 27.0;
					};
				};
			};
			buildConfigurationList = C0A11E000000000000000050 /* Build configuration list for PBXProject "Cranny" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				ru,
			);
			mainGroup = C0A11E000000000000000002;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				C0A11E000000000000000040 /* XCLocalSwiftPackageReference "CrannyKit" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = C0A11E000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				C0A11E000000000000000010 /* Cranny */,
				C0A11E000000000000000070 /* CrannyMediaBridge */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		C0A11E000000000000000013 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		C0A11E000000000000000011 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		C0A11E000000000000000071 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		C0A11E000000000000000077 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = C0A11E000000000000000070 /* CrannyMediaBridge */;
			targetProxy = C0A11E000000000000000076 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		C0A11E000000000000000051 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				DEVELOPMENT_TEAM = "";
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 0.1.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		C0A11E000000000000000052 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;
				CODE_SIGN_STYLE = Manual;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				DEVELOPMENT_TEAM = "";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 0.1.0;
				ONLY_ACTIVE_ARCH = NO;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
			};
			name = Release;
		};
		C0A11E000000000000000061 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = App/Cranny.entitlements;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = App/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Cranny;
				INFOPLIST_KEY_NSPrincipalClass = NSApplication;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = app.cranny.Cranny;
				PRODUCT_NAME = "$(TARGET_NAME)";
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		C0A11E000000000000000062 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = App/Cranny.entitlements;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = App/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Cranny;
				INFOPLIST_KEY_NSPrincipalClass = NSApplication;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = app.cranny.Cranny;
				PRODUCT_NAME = "$(TARGET_NAME)";
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
		C0A11E000000000000000081 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				EXECUTABLE_PREFIX = lib;
				GCC_SYMBOLS_PRIVATE_EXTERN = YES;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				USER_HEADER_SEARCH_PATHS = "$(SRCROOT)/Packages/CrannyKit/Sources/CrannyMediaBridge/include";
			};
			name = Debug;
		};
		C0A11E000000000000000082 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				EXECUTABLE_PREFIX = lib;
				GCC_SYMBOLS_PRIVATE_EXTERN = YES;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				USER_HEADER_SEARCH_PATHS = "$(SRCROOT)/Packages/CrannyKit/Sources/CrannyMediaBridge/include";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		C0A11E000000000000000050 /* Build configuration list for PBXProject "Cranny" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				C0A11E000000000000000051 /* Debug */,
				C0A11E000000000000000052 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		C0A11E000000000000000060 /* Build configuration list for PBXNativeTarget "Cranny" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				C0A11E000000000000000061 /* Debug */,
				C0A11E000000000000000062 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		C0A11E000000000000000080 /* Build configuration list for PBXNativeTarget "CrannyMediaBridge" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				C0A11E000000000000000081 /* Debug */,
				C0A11E000000000000000082 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		C0A11E000000000000000040 /* XCLocalSwiftPackageReference "CrannyKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/CrannyKit;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		C0A11E000000000000000030 /* CrannyAppShell */ = {
			isa = XCSwiftPackageProductDependency;
			productName = CrannyAppShell;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = C0A11E000000000000000001 /* Project object */;
}
```

### B.2 `Cranny.xcodeproj/xcshareddata/xcschemes/Cranny.xcscheme`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "C0A11E000000000000000010"
               BuildableName = "Cranny.app"
               BlueprintName = "Cranny"
               ReferencedContainer = "container:Cranny.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "C0A11E000000000000000010"
            BuildableName = "Cranny.app"
            BlueprintName = "Cranny"
            ReferencedContainer = "container:Cranny.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "C0A11E000000000000000010"
            BuildableName = "Cranny.app"
            BlueprintName = "Cranny"
            ReferencedContainer = "container:Cranny.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

### B.3 `App/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Merged with the keys Xcode generates (GENERATE_INFOPLIST_FILE = YES). Localized in InfoPlist.xcstrings. -->
	<key>LSUIElement</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Cranny contributors. MIT License.</string>
	<!-- Without this, SwiftPM resource bundles fall back to English (R4 §3.4). -->
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ru</string>
	</array>
	<!-- "owner/repo" for the GitHub Releases update check. Empty = update check disabled. -->
	<key>CrannyGitHubRepository</key>
	<string></string>
	<!-- Privacy usage descriptions. -->
	<key>NSAppleEventsUsageDescription</key>
	<string>Cranny controls Music and Spotify to show and change what is playing when the system media source is unavailable.</string>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Cranny shows your upcoming events and meeting links in the notch. It never edits or uploads them.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>Cranny shows your upcoming events and meeting links in the notch. It never edits or uploads them.</string>
	<key>NSCameraUsageDescription</key>
	<string>Cranny shows a camera preview in the Mirror widget. Video is never recorded.</string>
	<key>NSCameraUseContinuityCameraDeviceType</key>
	<true/>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Cranny shows when Bluetooth devices such as headphones connect, and their battery level.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Cranny listens to system audio output to animate the music visualizer. Audio is never recorded or stored.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Cranny analyzes audio levels to animate the music visualizer. Audio is never recorded or stored.</string>
	<key>NSDesktopFolderUsageDescription</key>
	<string>Cranny keeps the files you drop on the notch in its Tray.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>Cranny keeps the files you drop on the notch in its Tray.</string>
	<key>NSDownloadsFolderUsageDescription</key>
	<string>Cranny keeps the files you drop on the notch in its Tray.</string>
	<key>NSRemovableVolumesUsageDescription</key>
	<string>Cranny keeps the files you drop on the notch in its Tray.</string>
	<key>NSNetworkVolumesUsageDescription</key>
	<string>Cranny keeps the files you drop on the notch in its Tray.</string>
</dict>
</plist>
```

### B.4 `App/InfoPlist.xcstrings`

```json
{
  "sourceLanguage": "en",
  "strings": {
    "CFBundleDisplayName": {
      "comment": "Bundle display name",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny"
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny"
          }
        }
      }
    },
    "NSAppleEventsUsageDescription": {
      "comment": "Privacy - AppleEvents Sending Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny controls Music and Spotify to show and change what is playing when the system media source is unavailable."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny управляет приложениями «Музыка» и Spotify, чтобы показывать и переключать треки, когда системный источник медиа недоступен."
          }
        }
      }
    },
    "NSAudioCaptureUsageDescription": {
      "comment": "Privacy - Audio Capture Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny listens to system audio output to animate the music visualizer. Audio is never recorded or stored."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny анализирует системный звук, чтобы анимировать визуализатор музыки. Звук никогда не записывается и не сохраняется."
          }
        }
      }
    },
    "NSBluetoothAlwaysUsageDescription": {
      "comment": "Privacy - Bluetooth Always Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny shows when Bluetooth devices such as headphones connect, and their battery level."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny показывает подключение Bluetooth-устройств, например наушников, и уровень их заряда."
          }
        }
      }
    },
    "NSCalendarsFullAccessUsageDescription": {
      "comment": "Privacy - Calendars Full Access Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny shows your upcoming events and meeting links in the notch. It never edits or uploads them."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny показывает ближайшие события и ссылки на встречи в вырезе экрана. Он никогда не изменяет и не отправляет их."
          }
        }
      }
    },
    "NSCalendarsUsageDescription": {
      "comment": "Privacy - Calendars Usage Description (legacy)",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny shows your upcoming events and meeting links in the notch. It never edits or uploads them."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny показывает ближайшие события и ссылки на встречи в вырезе экрана. Он никогда не изменяет и не отправляет их."
          }
        }
      }
    },
    "NSCameraUsageDescription": {
      "comment": "Privacy - Camera Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny shows a camera preview in the Mirror widget. Video is never recorded."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny показывает изображение с камеры в виджете «Зеркало». Видео никогда не записывается."
          }
        }
      }
    },
    "NSDesktopFolderUsageDescription": {
      "comment": "Privacy - Desktop Folder Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny keeps the files you drop on the notch in its Tray."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny хранит в Лотке файлы, которые вы перетаскиваете на вырез экрана."
          }
        }
      }
    },
    "NSDocumentsFolderUsageDescription": {
      "comment": "Privacy - Documents Folder Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny keeps the files you drop on the notch in its Tray."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny хранит в Лотке файлы, которые вы перетаскиваете на вырез экрана."
          }
        }
      }
    },
    "NSDownloadsFolderUsageDescription": {
      "comment": "Privacy - Downloads Folder Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny keeps the files you drop on the notch in its Tray."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny хранит в Лотке файлы, которые вы перетаскиваете на вырез экрана."
          }
        }
      }
    },
    "NSMicrophoneUsageDescription": {
      "comment": "Privacy - Microphone Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny analyzes audio levels to animate the music visualizer. Audio is never recorded or stored."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny анализирует уровень звука, чтобы анимировать визуализатор музыки. Звук никогда не записывается и не сохраняется."
          }
        }
      }
    },
    "NSNetworkVolumesUsageDescription": {
      "comment": "Privacy - Network Volumes Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny keeps the files you drop on the notch in its Tray."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny хранит в Лотке файлы, которые вы перетаскиваете на вырез экрана."
          }
        }
      }
    },
    "NSRemovableVolumesUsageDescription": {
      "comment": "Privacy - Removable Volumes Usage Description",
      "extractionState": "extracted_with_value",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "new",
            "value": "Cranny keeps the files you drop on the notch in its Tray."
          }
        },
        "ru": {
          "stringUnit": {
            "state": "translated",
            "value": "Cranny хранит в Лотке файлы, которые вы перетаскиваете на вырез экрана."
          }
        }
      }
    }
  },
  "version": "1.0"
}
```

### B.5 `App/Cranny.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Not sandboxed: Accessibility event taps, MediaRemote bridge, global hotkeys need it. -->
	<!-- Hardened-runtime resource access (required for TCC prompts under ENABLE_HARDENED_RUNTIME). -->
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.personal-information.calendars</key>
	<true/>
</dict>
</plist>
```

### B.6 `App/CrannyApp.swift`

```swift
import SwiftUI
import CrannyAppShell

/// The only Swift file in the app target: everything else lives in CrannyKit.
@main
struct CrannyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        CrannyScenes(appDelegate: appDelegate)
    }
}
```

### B.7 `scripts/lib.sh`

```bash
#!/usr/bin/env bash
# Shared helpers for Cranny scripts. Source it; do not execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Cranny.xcodeproj"
SCHEME="Cranny"
PACKAGE_DIR="$ROOT/Packages/CrannyKit"
BUILD_DIR="$ROOT/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
MIN_XCODE_MAJOR=26   # swift-tools-version 6.2, .icon app icons, objectVersion 77

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Use a full Xcode even when `xcode-select -p` points at the Command Line Tools
# (common on dev machines; changing it needs sudo). DEVELOPER_DIR wins if set.
ensure_xcode() {
  if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    local selected
    selected="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$selected" != *.app/Contents/Developer ]]; then
      local candidate
      for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode_*.app /Applications/Xcode*.app; do
        if [[ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]]; then
          export DEVELOPER_DIR="$candidate/Contents/Developer"
          break
        fi
      done
      [[ -n "${DEVELOPER_DIR:-}" ]] || die "Xcode not found. Install Xcode $MIN_XCODE_MAJOR+ or set DEVELOPER_DIR."
      log "xcode-select points to '$selected'; using DEVELOPER_DIR=$DEVELOPER_DIR"
    fi
  fi
  local version major
  version="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')" || true
  major="${version%%.*}"
  [[ -n "$major" ]] || die "xcodebuild is not usable (DEVELOPER_DIR=${DEVELOPER_DIR:-unset})."
  (( major >= MIN_XCODE_MAJOR )) || die "Xcode $version is too old; need $MIN_XCODE_MAJOR+."
}

# Pretty-print xcodebuild output when xcbeautify is installed (CI images have it).
xcpretty_filter() {
  if command -v xcbeautify >/dev/null 2>&1 && [[ "${VERBOSE:-0}" != 1 ]]; then
    xcbeautify --quieter
  else
    cat
  fi
}

# Read a key from a built app's Info.plist.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
```

### B.8 `scripts/build.sh`

```bash
#!/usr/bin/env bash
# Release build of Cranny.app (universal arm64 + x86_64) -> build/Cranny.app
#
#   scripts/build.sh                 # ad-hoc signed ("Sign to Run Locally"), no Apple account needed
#   ARCHS=arm64 scripts/build.sh     # single-arch (faster)
#   CONFIGURATION=Debug scripts/build.sh
#   SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 scripts/build.sh
source "$(dirname "$0")/lib.sh"
ensure_xcode

CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64 x86_64}"
LOG="$BUILD_DIR/logs/build-$CONFIGURATION.log"
mkdir -p "$BUILD_DIR/logs"

overrides=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Distribution signing (maintainers only). Secure timestamp is required for notarization.
  overrides+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="${TEAM_ID:?TEAM_ID is required with SIGN_IDENTITY}"
              OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi
MARKETING_VERSION="${MARKETING_VERSION:-$(tr -d "[:space:]" < "$ROOT/VERSION")}"
overrides+=(MARKETING_VERSION="$MARKETING_VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && overrides+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

log "Building $SCHEME ($CONFIGURATION, $ARCHS) with $(xcodebuild -version | head -1)"
# 'generic/platform=macOS' (= "Any Mac") is what makes xcodebuild honour ARCHS; with the
# implicit "My Mac" run destination it silently builds only the host architecture.
set +e
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  "${overrides[@]}" 2>&1 | tee "$LOG" | xcpretty_filter
status=${PIPESTATUS[0]}
set -e
(( status == 0 )) || die "xcodebuild failed ($status); full log: $LOG"

PRODUCT="$DERIVED_DIR/Build/Products/$CONFIGURATION/Cranny.app"
rm -rf "$BUILD_DIR/Cranny.app" "$BUILD_DIR/Cranny.app.dSYM"
ditto "$PRODUCT" "$BUILD_DIR/Cranny.app"
[[ -d "$PRODUCT.dSYM" ]] && ditto "$PRODUCT.dSYM" "$BUILD_DIR/Cranny.app.dSYM"

APP="$BUILD_DIR/Cranny.app"
codesign --verify --deep --strict "$APP" || die "code signature verification failed"
log "Built $APP"
log "  version $(plist_value "$APP" CFBundleShortVersionString) ($(plist_value "$APP" CFBundleVersion))"
log "  $(lipo -archs "$APP/Contents/MacOS/Cranny" | sed 's/^/archs: /')"
log "  $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|TeamIdentifier|CodeDirectory)' | tr '\n' ' ')"
```

### B.9 `scripts/run.sh`

```bash
#!/usr/bin/env bash
# Debug build (host arch) + launch.
#
#   scripts/run.sh                      # build, quit the old dev instance, open the new one
#   scripts/run.sh --no-build           # just relaunch
#   scripts/run.sh -- --some-app-arg    # pass arguments to the app
#   XOJIT=1 scripts/run.sh              # keep Xcode-style Debug (XOJIT previews => hardened runtime OFF)
#   DEV_SIGN_IDENTITY="Cranny Dev" scripts/run.sh   # sign with a stable identity so TCC grants survive rebuilds
#
# Launches through LaunchServices (`open`) so macOS attributes TCC prompts
# (Camera, Calendars, Accessibility, Automation...) to Cranny itself rather than to
# the terminal that spawned it.
source "$(dirname "$0")/lib.sh"

build=1
app_args=()
while (($#)); do
  case "$1" in
    --no-build) build=0 ;;
    --) shift; app_args=("$@"); break ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

APP="$DERIVED_DIR/Build/Products/Debug/Cranny.app"
if (( build )); then
  ensure_xcode
  overrides=()
  # With ad-hoc signing, Xcode prints "Disabling hardened runtime with ad-hoc codesigning"
  # for Debug builds while ENABLE_XOJIT_PREVIEWS=YES (the Debug default). Turn it off for CLI
  # runs so the dev build behaves like Release (library validation, hardened-runtime
  # resource entitlements for camera/mic/calendars/Apple Events).
  [[ "${XOJIT:-0}" == 1 ]] || overrides+=(ENABLE_XOJIT_PREVIEWS=NO)
  # Stable code identity keeps TCC grants (Accessibility, Camera, Calendars) across rebuilds:
  #   DEV_SIGN_IDENTITY="Cranny Dev" scripts/run.sh   (a self-signed Code Signing certificate in your login keychain)
  [[ -z "${DEV_SIGN_IDENTITY:-}" ]] || overrides+=(CODE_SIGN_IDENTITY="$DEV_SIGN_IDENTITY")
  log "Building Debug"
  mkdir -p "$BUILD_DIR/logs"
  set +e
  xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED_DIR" \
    ${overrides[@]+"${overrides[@]}"} 2>&1 | tee "$BUILD_DIR/logs/build-Debug.log" | xcpretty_filter
  status=${PIPESTATUS[0]}
  set -e
  (( status == 0 )) || die "xcodebuild failed; see $BUILD_DIR/logs/build-Debug.log"
fi
[[ -d "$APP" ]] || die "$APP not found; run without --no-build first"

# Quit only *this* build's instance (other Cranny copies, e.g. in /Applications, are left alone).
if pgrep -f "$APP/Contents/MacOS/Cranny" >/dev/null; then
  log "Quitting running dev instance"
  pkill -f "$APP/Contents/MacOS/Cranny" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP/Contents/MacOS/Cranny" >/dev/null || break; sleep 0.3; done
fi

log "Launching $APP"
open -n "$APP" --args ${app_args[@]+"${app_args[@]}"}
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if pid="$(pgrep -f "$APP/Contents/MacOS/Cranny" | head -1)" && [[ -n "$pid" ]]; then
    log "Running (pid $pid). Logs: log stream --level debug --predicate 'process == \"Cranny\"'"
    exit 0
  fi
  sleep 0.5
done
die "Cranny did not start; check ~/Library/Logs/DiagnosticReports/Cranny-*.ips"
```

### B.10 `scripts/smoke.sh`

```bash
#!/usr/bin/env bash
# Launch smoke test of build/Cranny.app without UI: `Cranny --diagnostics <json>` writes a report and quits.
# Checks: every CrannyKit resource bundle is embedded, the media bridge dylib is present, the Edit menu exists.
#
#   scripts/smoke.sh                 # uses build/Cranny.app
#   APP=/path/Cranny.app scripts/smoke.sh
source "$(dirname "$0")/lib.sh"

APP="${APP:-$BUILD_DIR/Cranny.app}"
[[ -d "$APP" ]] || die "$APP not found; run scripts/build.sh first"
OUT="$BUILD_DIR/logs/diagnostics.json"
mkdir -p "$BUILD_DIR/logs"; rm -f "$OUT"
# No `timeout` on macOS: perl's alarm kills the app if it hangs (exit 142).
/usr/bin/perl -e 'alarm shift; exec @ARGV' 60 "$APP/Contents/MacOS/Cranny" --diagnostics "$OUT" >/dev/null 2>&1 \
  || die "Cranny --diagnostics failed or timed out"
[[ -s "$OUT" ]] || die "no diagnostics written"
expected=$(find "$PACKAGE_DIR/Sources" -mindepth 2 -maxdepth 2 -name Resources -type d | wc -l | tr -d ' ')
/usr/bin/python3 -I - "$OUT" "$expected" <<'PY' || die "smoke test failed (see $OUT)"
import json, sys
r = json.load(open(sys.argv[1])); expected = int(sys.argv[2])
problems = []
if len(r.get("resourceBundles", [])) != expected: problems.append(f"bundles {len(r.get('resourceBundles', []))} != {expected}")
if r.get("bridge", "(missing)") == "(missing)": problems.append("media bridge dylib missing")
if not any(len(items) >= 4 for m in r.get("mainMenu", []) for items in m.values()): problems.append("no Edit menu key equivalents")
print("\n".join(problems) or "smoke OK: %d bundles, bridge present, Edit menu present" % expected)
sys.exit(1 if problems else 0)
PY
log "Smoke test passed ($OUT)"
```

### B.11 `scripts/dist.sh`

```bash
#!/usr/bin/env bash
# Package build/Cranny.app as dist/Cranny-<version>.zip and .dmg (+ SHA-256 sums).
#
#   scripts/dist.sh                 # uses existing build/Cranny.app, or builds it first
#   REBUILD=1 scripts/dist.sh
#
# Maintainers with an Apple Developer ID can produce a notarized release:
#   xcrun notarytool store-credentials cranny-notary --apple-id you@example.com --team-id TEAMID1234
#   SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 \
#   NOTARY_PROFILE=cranny-notary REBUILD=1 scripts/dist.sh
# Without those variables the app stays ad-hoc signed: users must allow it once in
# System Settings > Privacy & Security ("Open Anyway"), or run
#   xattr -dr com.apple.quarantine /Applications/Cranny.app
source "$(dirname "$0")/lib.sh"

APP="$BUILD_DIR/Cranny.app"
if [[ "${REBUILD:-0}" == 1 || ! -d "$APP" ]]; then
  "$ROOT/scripts/build.sh"
fi
ensure_xcode

VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
DIST="$ROOT/dist"
NAME="Cranny-$VERSION"
mkdir -p "$DIST"
rm -f "$DIST/$NAME.zip" "$DIST/$NAME.dmg"

notarize() { # $1 = file to submit
  log "Notarizing $(basename "$1") (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} --wait
}

# 1) Notarize + staple the app itself first (when configured), so both archives carry the ticket.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$(codesign -dv "$APP" 2>&1 | grep -c 'TeamIdentifier=not set')" == 0 ]] \
    || die "app is ad-hoc signed; rebuild with SIGN_IDENTITY/TEAM_ID before notarizing"
  ditto -c -k --norsrc --keepParent "$APP" "$DIST/notarize-upload.zip"
  notarize "$DIST/notarize-upload.zip"
  rm -f "$DIST/notarize-upload.zip"
  xcrun stapler staple "$APP"
fi

# 2) ZIP. ditto keeps symlinks and signatures intact (plain `zip` can break bundles);
#    --norsrc drops local xattrs (com.apple.provenance...) so no __MACOSX/._ clutter.
log "Creating $NAME.zip"
ditto -c -k --norsrc --keepParent "$APP" "$DIST/$NAME.zip"

# 3) DMG with an /Applications shortcut.
log "Creating $NAME.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/cranny-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Cranny.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Cranny $VERSION" -srcfolder "$STAGE" -fs APFS -format UDZO -ov "$DIST/$NAME.dmg" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DIST/$NAME.dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$DIST/$NAME.dmg"
    xcrun stapler staple "$DIST/$NAME.dmg"
  fi
fi
hdiutil verify "$DIST/$NAME.dmg" >/dev/null

(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME.sha256")
log "Artifacts in $DIST:"
ls -lh "$DIST" | sed 1d >&2
```

### B.12 `scripts/check-modules.sh`

```bash
#!/usr/bin/env bash
# Build every CrannyKit library target on its own (`swift build --target`), each in
# its own scratch path, so a module that accidentally relies on something it does not
# import/depend on fails here instead of only inside the app build.
#
#   scripts/check-modules.sh                 # all non-test targets, sequential
#   scripts/check-modules.sh CrannyMedia     # just these targets
#   JOBS=4 scripts/check-modules.sh          # build targets in parallel
#   TEST=1 scripts/check-modules.sh          # also run `swift test`
source "$(dirname "$0")/lib.sh"
ensure_xcode   # SwiftPM from Xcode's toolchain (CLT's would work too, but keep one toolchain)

# D13: no offline Metal compilation in v1 (the Metal Toolchain is an optional Xcode component).
if find "$PACKAGE_DIR/Sources" -name '*.metal' -print -quit | grep -q .; then
  die "Metal sources found in CrannyKit/Sources (not allowed in v1, see ARCHITECTURE.md D13)"
fi

cd "$PACKAGE_DIR"
if (($#)); then
  targets=("$@")
else
  targets=()
  while IFS= read -r t; do targets+=("$t"); done < <(
    swift package describe --type json 2>/dev/null |
      /usr/bin/python3 -I -c 'import json,sys; [print(t["name"]) for t in json.load(sys.stdin)["targets"] if t["type"] != "test"]' |
      sort)
fi
(( ${#targets[@]} )) || die "no targets found"

mkdir -p "$BUILD_DIR/logs"
build_one() {
  local t="$1" lower scratch
  lower="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
  scratch="$PACKAGE_DIR/.build-$lower"
  if swift build --target "$t" --scratch-path "$scratch" >"$BUILD_DIR/logs/module-$t.log" 2>&1; then
    printf '  \033[32mok\033[0m    %s\n' "$t"
  else
    printf '  \033[31mFAIL\033[0m  %s  (log: build/logs/module-%s.log)\n' "$t" "$t"
    grep -E 'error:' "$BUILD_DIR/logs/module-$t.log" | head -5 | sed 's/^/        /'
    return 1
  fi
}

log "Building ${#targets[@]} targets: ${targets[*]}"
failed=0
if [[ "${JOBS:-1}" -gt 1 ]]; then
  pids=()
  for t in "${targets[@]}"; do
    build_one "$t" & pids+=($!)
    while (( $(jobs -rp | wc -l) >= JOBS )); do sleep 0.2; done
  done
  for p in "${pids[@]}"; do wait "$p" || failed=1; done
else
  for t in "${targets[@]}"; do build_one "$t" || failed=1; done
fi

if [[ "${TEST:-0}" == 1 ]]; then
  log "swift test"
  swift test --scratch-path "$PACKAGE_DIR/.build-test" || failed=1
fi
(( failed == 0 )) || die "module check failed"
log "All modules build independently"
```

### B.13 `scripts/sync-strings.sh`

```bash
#!/usr/bin/env bash
# Update every CrannyKit String Catalog with the keys the compiler extracted from code
# (what Xcode's editor does after a build, but scriptable/CI-friendly).
#
#   scripts/sync-strings.sh          # build targets that have a catalog, then sync
#   CHECK=1 scripts/sync-strings.sh  # fail if a catalog would change (for CI)
#
# Uses the compiler-produced .stringsdata (exact keys such as "%lld minutes left").
# `xcstringstool extract` exists too, but its lightweight parser turns interpolations
# into "%arg" keys, so we do not use it.
source "$(dirname "$0")/lib.sh"
ensure_xcode
cd "$PACKAGE_DIR"

scratch="$PACKAGE_DIR/.build-strings"
changed=0
for catalog in Sources/*/Resources/Localizable.xcstrings; do
  target="$(basename "$(dirname "$(dirname "$catalog")")")"
  log "$target"
  # The .stringsdata paths below are the swift-build backend's layout: request it explicitly
  # (default on SwiftPM 6.4; Xcode 26's SwiftPM 6.2 defaults to the native backend).
  swift build --build-system swiftbuild --target "$target" --scratch-path "$scratch" >/dev/null 2>&1 \
    || die "build of $target failed (run scripts/check-modules.sh $target)"
  stringsdata=()
  while IFS= read -r f; do stringsdata+=("$f"); done < <(
    find "$scratch/out/Intermediates.noindex" -path "*/$target-t.build/*" -name '*.stringsdata' 2>/dev/null)
  (( ${#stringsdata[@]} )) || die "no .stringsdata for $target (is SwiftPM using the swiftbuild backend?)"
  tmp="$(mktemp -d)"
  cp "$catalog" "$tmp/Localizable.xcstrings"
  xcrun xcstringstool sync "$tmp/Localizable.xcstrings" --stringsdata "${stringsdata[@]}"
  if ! cmp -s "$catalog" "$tmp/Localizable.xcstrings"; then
    changed=1
    if [[ "${CHECK:-0}" == 1 ]]; then
      warn "$catalog is out of date"
    else
      cp "$tmp/Localizable.xcstrings" "$catalog"
      log "  updated $catalog"
    fi
  fi
  rm -rf "$tmp"
done
if [[ "${CHECK:-0}" == 1 && $changed == 1 ]]; then
  die "String Catalogs are out of date; run scripts/sync-strings.sh and commit the result"
fi
log "String Catalogs are in sync"
```

### B.14 `Makefile`

```make
# Thin wrapper around scripts/. All targets work when xcode-select points at the
# Command Line Tools: the scripts locate /Applications/Xcode*.app themselves.
SHELL := /bin/bash

.PHONY: help build debug run smoke dist check test strings strings-check list clean distclean

help:            ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

build:           ## Release build, universal -> build/Cranny.app
	@scripts/build.sh

debug:           ## Debug build -> build/Cranny.app
	@CONFIGURATION=Debug ARCHS="$$(uname -m)" scripts/build.sh

run:             ## Debug build + launch (via LaunchServices)
	@scripts/run.sh

smoke:           ## Launch build/Cranny.app with --diagnostics and verify bundles/bridge/menu
	@scripts/smoke.sh

dist: build      ## zip + dmg (+ notarization when NOTARY_PROFILE is set) -> dist/
	@scripts/dist.sh

check:           ## Build every CrannyKit target separately (swift build --target)
	@scripts/check-modules.sh

test:            ## swift test for CrannyKit
	@. scripts/lib.sh && ensure_xcode && cd Packages/CrannyKit && swift test --scratch-path .build-test

strings:         ## Sync String Catalogs with keys used in code
	@scripts/sync-strings.sh

strings-check:   ## Fail if String Catalogs are out of date (CI)
	@CHECK=1 scripts/sync-strings.sh

list:            ## xcodebuild -list
	@. scripts/lib.sh && ensure_xcode && xcodebuild -list -project Cranny.xcodeproj

clean:           ## Remove build outputs
	rm -rf build dist

distclean: clean ## Also remove SwiftPM scratch dirs
	rm -rf Packages/CrannyKit/.build Packages/CrannyKit/.build-* Packages/CrannyKit/.swiftpm
```

### B.15 `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    # Xcode-27 image (arm64, macOS 27, Xcode 27.0 default; public preview since 2026-07-16).
    # Fallback while it is in preview: `macos-26` (Xcode 26.x default) also satisfies the
    # project's minimum (Xcode 26 / Swift 6.2), see docs.
    runs-on: xcode-27
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7

      - name: Toolchain
        run: |
          xcode-select -p
          xcodebuild -version
          swift --version

      - name: Every CrannyKit module builds on its own + unit tests
        run: JOBS=3 TEST=1 scripts/check-modules.sh

      - name: String Catalogs are in sync with code
        run: CHECK=1 scripts/sync-strings.sh

      - name: Release build (universal arm64 + x86_64, ad-hoc signed)
        env:
          BUILD_NUMBER: ${{ github.run_number }}
        run: scripts/build.sh

      - name: Launch smoke test (--diagnostics, no UI)
        run: scripts/smoke.sh

      - name: Package zip + dmg
        run: scripts/dist.sh

      - uses: actions/upload-artifact@v7
        with:
          name: Cranny-${{ github.sha }}
          path: |
            dist/*.zip
            dist/*.dmg
            dist/*.sha256
          if-no-files-found: error
          retention-days: 14

      - uses: actions/upload-artifact@v7
        if: failure()
        with:
          name: logs-${{ github.sha }}
          path: build/logs/
```

### B.16 `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags: ['v*']          # e.g. git tag v0.2.0 && git push origin v0.2.0

permissions:
  contents: write         # create the GitHub Release

jobs:
  release:
    runs-on: xcode-27
    timeout-minutes: 45
    env:
      # Optional Developer ID signing + notarization. When these secrets are absent the
      # release is ad-hoc signed (users allow it once in System Settings > Privacy & Security).
      HAS_SIGNING: ${{ secrets.DEVELOPER_ID_P12_BASE64 != '' && secrets.NOTARY_KEY_P8_BASE64 != '' }}
    steps:
      - uses: actions/checkout@v7

      - name: Version from tag (must match VERSION)
        run: |
          test "$(tr -d '[:space:]' < VERSION)" = "${GITHUB_REF_NAME#v}" || { echo "::error::VERSION file does not match tag $GITHUB_REF_NAME"; exit 1; }
          echo "MARKETING_VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_ENV"
          echo "BUILD_NUMBER=${{ github.run_number }}" >> "$GITHUB_ENV"

      - name: Import Developer ID certificate + notary key
        if: env.HAS_SIGNING == 'true'
        env:
          P12_BASE64: ${{ secrets.DEVELOPER_ID_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
          NOTARY_KEY_P8_BASE64: ${{ secrets.NOTARY_KEY_P8_BASE64 }}
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
          KEYCHAIN_PASSWORD="$(uuidgen)"
          echo "$P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/cert.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
          TEAM_ID="$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')"
          echo "SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
          echo "TEAM_ID=$TEAM_ID" >> "$GITHUB_ENV"
          echo "$NOTARY_KEY_P8_BASE64" | base64 --decode > "$RUNNER_TEMP/notary.p8"
          xcrun notarytool store-credentials cranny-notary \
            --key "$RUNNER_TEMP/notary.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
            --keychain "$KEYCHAIN"
          echo "NOTARY_PROFILE=cranny-notary" >> "$GITHUB_ENV"
          echo "NOTARY_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"

      - name: Build (universal)
        run: scripts/build.sh

      - name: Launch smoke test
        run: scripts/smoke.sh

      - name: Package (+ notarize when signing is configured)
        run: scripts/dist.sh

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" dist/*.zip dist/*.dmg dist/*.sha256 \
            --title "Cranny $MARKETING_VERSION" --generate-notes --verify-tag
```

### B.17 `.gitignore`

```text
# Build outputs
/build/
/dist/
DerivedData/
.derived/
# SwiftPM (one scratch dir per module: .build-<target>)
.build/
.build-*/
.swiftpm/
# Xcode per-user state
xcuserdata/
*.xcuserstate
# macOS
.DS_Store
```

### B.18 `Packages/CrannyKit/Sources/CrannyAppShell/App/Diagnostics.swift`

`Cranny --diagnostics <file.json>` writes this report without creating any window and quits; `scripts/smoke.sh` depends on its keys (`resourceBundles`, `bridge`, `mainMenu`). WP0's `AppDelegate` must call it before building panels (as the verified skeleton does).

```swift
// CrannyAppShell/App/Diagnostics.swift — `Cranny --diagnostics <file.json>`: CI/launch smoke test, no UI.
import AppKit
import CrannyCore
import Foundation

enum Diagnostics {
    static func argument(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func write(to path: String, registry: ModuleRegistry) async {
        var r: [String: Any] = [:]
        let info = AppInfo.current()
        r["app"] = ["id": info.bundleIdentifier, "version": info.version, "build": info.build]
        r["preferredLanguages"] = Locale.preferredLanguages
        r["mainPreferredLocalizations"] = Bundle.main.preferredLocalizations
        r["resourceBundles"] = ((try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.resourcePath ?? "")) ?? [])
            .filter { $0.hasSuffix(".bundle") }.sorted()
        r["registry"] = ["widgets": registry.widgets.map(\.id.rawValue), "activities": registry.activities.map(\.id.rawValue),
                         "pages": registry.pages.map(\.id.rawValue), "shortcuts": registry.shortcuts.map(\.id.rawValue),
                         "permissions": registry.permissionUses.map { "\($0.kind)" }]
        r["permissionTitle.ru"] = Bundle(path: Bundle.main.path(forResource: "CrannyKit_CrannyCore", ofType: "bundle") ?? "")
            .flatMap { b in b.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:)) }?
            .localizedString(forKey: "Accessibility", value: "(missing)", table: nil) ?? "(no bundle)"
        r["mainMenu"] = NSApp.mainMenu?.items.map { item in
            [item.title: item.submenu?.items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) ⌘\($0.keyEquivalent)" } ?? []]
        } ?? []
        let bridge = Bundle.main.privateFrameworksURL?.appending(path: "libCrannyMediaBridge.dylib").path ?? ""
        r["bridge"] = FileManager.default.fileExists(atPath: bridge) ? bridge : "(missing)"
        if let data = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
```

### B.19 `Packages/CrannyKit/Sources/CrannyAppShell/App/CompositionRoot.swift` (skeleton)

```swift
// CrannyAppShell/App/CompositionRoot.swift — the ONLY place that knows every module.
import CrannyCalendar
import CrannyCore
import CrannyHUD
import CrannyMedia
import CrannyMirror
import CrannyNotes
import CrannyQuickApps
import CrannySystemActivities
import CrannyTimer
import CrannyTodos
import CrannyTray

@MainActor enum CompositionRoot {
    /// Registration order = default order of contributions (widget library, settings panes, palette).
    static let modules: [any FeatureModule.Type] = [
        MediaModule.self, CalendarModule.self, QuickAppsModule.self, MirrorModule.self, NotesModule.self,
        TodosModule.self, TimerModule.self, TrayModule.self, HUDModule.self, SystemActivitiesModule.self,
    ]

    static func makeRegistry(notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl) -> ModuleRegistry {
        let settings = SettingsStore()
        let services = CrannyServices(settings: settings, permissions: PermissionsCenter(),
                                      haptics: Haptics(isEnabled: { settings[CoreSettings.haptics] }),
                                      paths: .live, notch: notch, environment: environment, app: app)
        let registry = ModuleRegistry(services: services)
        for module in modules { registry.register(module) }
        return registry
    }
}
```

### B.20 Placeholder icon and assets (R4; replaced by WP-Final's artwork)

`App/AppIcon.icon/icon.json`:

```json
{
  "fill" : {
    "linear-gradient" : [
      "extended-srgb:0.16000,0.10000,0.36000,1.00000",
      "extended-srgb:0.05000,0.05000,0.09000,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "notch.svg",
          "name" : "notch"
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.4 }
    },
    {
      "layers" : [
        {
          "image-name" : "glow.svg",
          "name" : "glow",
          "opacity" : 0.6
        }
      ],
      "blur-material" : 0.5
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}
```

`App/AppIcon.icon/Assets/notch.svg` and `glow.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <path d="M332 0 H692 V96 Q692 176 612 176 H412 Q332 176 332 96 Z" fill="#000000"/>
</svg>
```

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <ellipse cx="512" cy="300" rx="300" ry="120" fill="#8C73FF"/>
</svg>
```

`App/Assets.xcassets/Contents.json` and `AccentColor.colorset/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "0.450", "red" : "0.550" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

---

## Appendix C — Verification log (2026-10-14, macOS 27.0.1, Xcode 27.0, Swift 6.4)

A scratch repository with exactly the layout of §1 was built from R4's working PoC (re-pathed), the `Package.swift` of §2.2, the CrannyCore sources of §3 and Appendix A, DESIGN.md's design-system code, R2's v3 bridge, the reference Timer module, skeletons of Media (port publication), Tray (`TrayIntake` + drop zone), NotchUI (`NotchScene.swift` + canvas rendering widgets and `any LiveActivity` views), SettingsUI, Onboarding and AppShell (R1 panel, composition root, port stubs, diagnostics). Results:

| Check | Result |
|---|---|
| `scripts/check-modules.sh` (17 targets, each `swift build --target` in its own scratch dir, JOBS=6) | all OK, **0 warnings** (clean rebuild); 45 s clean and 4.3 s warm with JOBS=6; ≈ 2.8 GB of per-target scratch dirs (+ 0.5 GB for tests) |
| `swift test` (16 test targets; Swift Testing; MainActor-default test targets) | all pass, incl. settings persistence/reset/namespacing and dictionary-keyed JSON, `SwipeTracker` single commit per sequence, `SemanticVersion` pre-release ordering |
| `scripts/sync-strings.sh` then `CHECK=1` | catalogs updated from compiler `.stringsdata` for all targets (≈ 25 s); check passes; conflicting comments reported as a notice |
| `scripts/build.sh` (universal Release, version from `VERSION`) | **BUILD SUCCEEDED** in ≈ 21 s; `lipo`: `x86_64 arm64`; `flags=0x10002(adhoc,runtime)`; one benign warning (App Intents metadata skipped) |
| Debug build with `ENABLE_XOJIT_PREVIEWS=NO` | hardened (`adhoc,runtime`) |
| Bridge in the app | `Contents/Frameworks/libCrannyMediaBridge.dylib`, universal, adhoc+runtime, exports only `_cranny_bridge_main`; `/usr/bin/perl` loader → `hello`, `pong`, `state`, `artwork`, clean exit on `quit` |
| Merged `Info.plist` and `ru.lproj/InfoPlist.strings` (`plutil -p`) | all keys of B.3; all usage strings translated |
| `Cranny --diagnostics` (via `open -n` and via `scripts/smoke.sh`) | 16 `CrannyKit_*.bundle`s in `Contents/Resources`; Russian lookup from Core's bundle works (`Универсальный доступ`); registry contributions listed; **main menu contains Edit with ⌘Z/X/C/V/A** (D12) |
| `scripts/dist.sh` | zip + DMG (`hdiutil verify` VALID; deprecation warning) + sha256 |
| `ci.yml`, `release.yml` | parse (Ruby YAML); not executed on GitHub |
| Carbon `RegisterEventHotKey` ⌃⌥N + `InstallEventHandler` in Swift 6 | status 0 (registered and unregistered) |
| `AEDeterminePermissionToAutomateTarget` without prompting | −600 when Music isn't running (maps to `.unknown`) |
| SDK checks | `onGeometryChange(for:of:action:)` macOS 13+ (back-deployed); `CBManager.authorization` class property macOS 10.15; `AEDeterminePermissionToAutomateTarget` macOS 10.14; `NSTextLayoutManager.addRenderingAttribute`; `openSettings` environment macOS 14 |
| **Review re-verification** (`scratchpad/poc/review`: the scratch package above + every review change to §3, §4.12, A.1–A.4, A.10, B.12–B.13 and DESIGN.md App. A/§2.3–2.4) | all 17 targets build clean with **0 warnings**; 16 test targets pass (Core: 5 tests incl. snapshot/restore and namespaces); every Core/NotchUI code block in this document is byte-identical to the compiled file |
| SDK name-collision probe (all public Core types aliased in a file importing AppKit, AVFoundation, AudioToolbox, CoreAudio, CoreBluetooth, EventKit, IOKit, QuickLookThumbnailing, ServiceManagement, SwiftUI, UniformTypeIdentifiers) | `ScrollPhase` was **ambiguous** with `SwiftUI.ScrollPhase` (hard error); renamed `SwipePhase`; no other collision |
| B.12 Metal guard; B.13 `--build-system swiftbuild` | guard fails on a planted `.metal` file and passes without it; sync + `CHECK=1` pass on SwiftPM 6.4 |
| Toolchain state on this Mac (2026-10-14, later in the day) | `xcode-select -p` now returns Xcode.app (it pointed at the CLT earlier — scripts handle both); `xcodebuild -showComponent MetalToolchain` = installed (D13 still applies); CLT Swift is also 6.4 but lacks `xcstringstool`/`actool` |
| `com.apple.symbolichotkeys` `AppleSymbolicHotKeys` | readable by a non-sandboxed process (81 entries, `parameters = (ascii, keyCode, modifiers)`); used only for the best-effort conflict warning |
| Not verified here | everything tagged [UNVERIFIED] in §4–§8; runtime behaviour of the full shell (WP13), notarization, the GitHub runner, x86_64 execution (no Rosetta) |

---

## Changelog of review fixes (2026-10-14)

A hard review of this document and DESIGN.md against the feature inventory, R1–R4 and the build PoC. Every item below is fixed in place in both documents.

1. **Contradictions with DESIGN.md resolved in DESIGN.md:** SwiftUI `Settings` scene → AppKit window (D11); `SettingsLink` → `Button` + `AppControl.openSettings`; "draft settings" → live settings with Reset-All Undo (D14); hidden Edit menu → App-lifecycle Edit menu (D12); Low Power Mode "toggle" → deep link (D18); HUD while open adopted into DESIGN §10 (§4.11); light-layer file placement made exact (Core `AmbientPalette.swift` + `CrannyEffects`); the §3.2 code amendments applied in DESIGN's code; icon file renamed `AppIcon.icon` to match `ASSETCATALOG_COMPILER_APPICON_NAME`.
2. **Research contradictions:** DESIGN's Media "source priority" is impossible (MediaRemote exposes one elected player, R2 §9.6) → replaced with ignore list/status/AE fallback/test. D13 restated: the brief says no Metal Toolchain, the research Mac later installed it, `X-metal-verified.md`'s "ship Metal" is superseded; a guard now enforces no `.metal`.
3. **Compile-breaking API:** Core `ScrollPhase` collided with `SwiftUI.ScrollPhase` → `SwipePhase`; new style rule + probe (§9.4).
4. **Parallel-work blockers fixed with additive, compiled contracts:** `ThemeResolver` moved from the shell to CrannyNotchUI (Settings/Onboarding stages could not reuse it); `NotchSceneModel.sampleActivities` (stages could not render `makeSample()` instances); per-activity `options:` rows (shell-owned Live Activities pane could not reach `calendar.leadMinutes`, `media.hidePausedAfterSeconds`, battery thresholds, Bluetooth option); `SettingsPage.namespaces` + keyword rule (pane reset/search of opaque module panes); `SettingsStore.snapshot()/restore(_:)` (Reset-All Undo had no API); `NotchUIActions.setMode/focusWidget/dismissActivity/open` (the scene is owner-written but NotchUI owns ⌘K/⌘E/Esc/VoiceOver); intra-shell signatures fixed by WP0 (§10.0); single writers for `pausedUntil`/`demoMode`; `App/**` edits routed through WP0/WP-Final.
5. **Feature module needing Effects:** Timer's ember burst and the charger sweep could not be drawn by layer-1 modules → `LiveActivity.delight` + `DelightMoment` + scene `delight/delightSerial`, scheduled by the shell (§4.6 step 7) and drawn by NotchUI; to-do motes stay in-widget; `TypewriterText` limited to NotchUI/Onboarding.
6. **Missing/under-specified features:** hide-when-idle timer (`handleIdleDelay`, transitions); transparent handle defined; UI sounds key (`uiSounds`); panel padding tune had no effect (`NookGrid.paddingTune`); zip naming key; satellite swipe-up dismissal; drops onto widgets vs the catch state (grid stays open, `TrayIntake.accept` fallback so drops are never lost); onboarding "Hi" and confirmations (`NotchControl.flash`, `ActivityID.flash`); progress rim data source; Demo-mode semantics aligned; system-shortcut conflict detection (RegisterEventHotKey doesn't fail on system combos); public value types listed for every public key.
7. **Build pipeline:** `DEVELOPER_DIR` + profile-noise rule for manual commands (§2.4); strings tooling pinned to the swift-build backend/Xcode 27 and skipped on the `macos-26` fallback; Metal guard; Intel smoke gap and action versions flagged; menu-bar icon drawn in code and About uses `NSApp.applicationIconImage` (no `Bundle.main` assets from package code, no second icon renderer).
8. **Clean room / licensing:** "Nook" (+ the "Nook | Tray" tab pair) is NotchNook UI text → UI says Cranny/Home/Layout & Widgets, code names unchanged (D20) + a denylist check (§8.7); no bundled Apple fonts; Settings wallpaper miniature avoids Files & Folders prompts; bundle-id domain check before the first release (D16).

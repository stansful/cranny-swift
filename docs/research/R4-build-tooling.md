# R4: Build system and project structure (Cranny)

Research date: 2026-10-14. Machine: macOS 27.0.1 (26A434), Apple Silicon, Xcode 27.0 (27A266a), Swift 6.4 (swiftlang-6.4.0.34.1), MacOSX27.0 SDK.

Working PoC (kept for reuse): `<research-scratchpad>/poc/build/`.
Probe artefacts (logs, screenshots, diagnostics JSON, icon renders): `.../scratchpad/poc/build-probes/`.

How claims are marked:
- **VERIFIED** means it was compiled, run, or inspected on this machine, or checked in the SDK, Xcode or toolchain files.
- **UNVERIFIED** means it comes from documentation, the web, or reasoning, and was not executed here.

---

## 0. Recommendations

1. **Layout.** Use a thin `Cranny.xcodeproj` (objectVersion 77, buildable folders) plus a local package `CrannyKit/` that holds all code. The hand-written project in the PoC builds, archives, lists, launches and localizes correctly with Xcode 27 (VERIFIED). The minimum supported toolchain is **Xcode 26 / Swift 6.2**, because of `swift-tools-version: 6.2`, `.defaultIsolation`, `@concurrent`, `.icon` and `#bundle`.
2. **Package settings.**
   - UI, feature and app-shell targets use `.defaultIsolation(MainActor.self)`.
   - Pure model and service targets (CrannyCore and future model/service modules) use `.defaultIsolation(nil)`.
   - Every target enables `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility` and `ExistentialAny`.
   - These are the same flags Xcode's own app template turns on via `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` (VERIFIED in the swiftc command lines).
   - Codable or Sendable models that must cross threads belong in nonisolated targets, or must be declared `nonisolated struct`.
3. **Keep every SwiftPM product static** (the default `.library`). **Do not link a `.dynamic` package product into the app.** With hardened runtime and ad-hoc signing, the Release app crashes at launch with "mapping process and mapped file (non-platform) have different Team IDs" (VERIFIED). Debug hides this, because Xcode turns hardened runtime off there.
4. **Media bridge dylib.** The same ObjC sources live in `CrannyKit/Sources/CrannyMediaBridge`.
   - The SwiftPM `.dynamic` product is used only by CLI `swift build`.
   - For the app, a small Xcode target `CrannyMediaBridge` (product type `library.dynamic`, buildable folder pointing at the same directory) builds it.
   - A "Copy Files → Frameworks (CodeSignOnCopy)" phase puts it at `Cranny.app/Contents/Frameworks/libCrannyMediaBridge.dylib`. The app never links it.
   - Apple's `/usr/bin/perl` (code-sign flags `0x0`, so no library validation) loads it from inside the signed app (VERIFIED).
   - It is universal (VERIFIED with `lipo`).
5. **Universal builds** need `-destination 'generic/platform=macOS'`. With the implicit "My Mac" destination, xcodebuild silently builds arm64 only, even with `ONLY_ACTIVE_ARCH=NO` and `ARCHS="arm64 x86_64"` (VERIFIED).
6. **App icon.** Use an Icon Composer `AppIcon.icon` as the single source. Xcode 27 generates the macOS 14/15 fallback (an `AppIcon.icns` up to 256 px, plus rendered 32–1024 px images in `Assets.car`). If an `AppIcon.appiconset` with the same name exists, the `.icon` wins (VERIFIED). Keep `Assets.xcassets` for `AccentColor` and other assets only.
7. **Localization.**
   - Each package target gets `Resources/Localizable.xcstrings`.
   - Always pass `bundle: .module` (or `#bundle`).
   - Never use SwiftUI conveniences that take a bare `LocalizedStringKey`, such as `LabeledContent("Version", …)`, `Toggle("…")` or `Text("…")` without `bundle:`. Inside a package these resolve against `Bundle.main` and show English (VERIFIED with screenshot).
   - The app's Info.plist **must** list `CFBundleLocalizations` (en, ru). Without it the package bundles fall back to English even though they contain `ru.lproj` (VERIFIED).
8. **Signing.**
   - Default is `CODE_SIGN_IDENTITY="-"`, `CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM=""`, hardened runtime on. This builds for anyone (VERIFIED).
   - Set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` for Release, otherwise ad-hoc Release builds ship `get-task-allow` (VERIFIED).
   - For TCC-stable development, sign with a persistent identity. Ad-hoc designated requirements are cdhash-based, so permissions go stale on every rebuild (VERIFIED designated requirement; UNVERIFIED impact).
9. **Launch with `open`, never by exec'ing the binary from a terminal.** With `open`, Cranny and its perl child are their own TCC "responsible process". If you run the binary directly, the terminal host becomes responsible (VERIFIED via `responsibility_get_pid_responsible_for_pid`). `scripts/run.sh` does this.
10. **Debug runs from scripts** should pass `ENABLE_XOJIT_PREVIEWS=NO`. Otherwise Xcode prints "Disabling hardened runtime with ad-hoc codesigning" and Debug behaves differently from Release (library validation, resource-access entitlements) (VERIFIED). `scripts/run.sh` does this. Xcode IDE runs keep the default, so previews keep working.
11. **CI.** Use the GitHub-hosted `xcode-27` image (arm64, macOS 27.0.1, Xcode 27.0 default; public preview since 2026-07-16). `macos-26` (Xcode 26.6 default) is the fallback. The workflows were written but not executed (UNVERIFIED).

---

## 1. Environment facts

| Fact | Status |
|---|---|
| `xcodebuild -version` reports Xcode 27.0, build 27A266a | VERIFIED |
| `swift --version` reports Swift 6.4, target arm64-apple-macosx27.0.0. CLT also ships Swift 6.4 plus SDKs 26, 26.5 and 27. | VERIFIED |
| `xcode-select -p` now returns `/Applications/Xcode.app/Contents/Developer`. The brief said it pointed to CLT; it changed during the session. The scripts handle both cases (CLT case tested with a fake `xcode-select` on PATH). | VERIFIED |
| **SwiftPM 6.4 defaults to the "swiftbuild" build system** (`swift build --help`: "default: swiftbuild"; `native` is "deprecated"). Products go to `<scratch>/out/Products/<Config>` with `<scratch>/debug -> out/Products/Debug`. Resource bundles are real macOS bundles (`Contents/Resources`, code-signed). | VERIFIED |
| `swiftc -print-supported-features` lists the upcoming features `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility`, `ExistentialAny`, `InternalImportsByDefault` and `ImmutableWeakCaptures`, all enabled by default in Swift 7. | VERIFIED |
| `PackageDescription` (tools 6.2) has `SwiftSetting.defaultIsolation(MainActor.Type?)`, `treatAllWarnings(as:)`, `treatWarning(_:as:)`, `strictMemorySafety()` and platforms `.v15`, `.v26`, `.v27` | VERIFIED |
| Rosetta 2 is not installed. `arch -x86_64 /usr/bin/perl` fails with "Bad CPU type", so the x86_64 slices could only be checked with `lipo`. | VERIFIED |
| Screen Recording works for the session host: `screencapture -x -R980,0,600,90` captured the Cranny panel | VERIFIED |
| The user's system language is ru-RU, then en-US. The app shows Russian by default. | VERIFIED |

---

## 2. Repository layout (as built in the PoC)

```
Cranny/                                  ← repo root
├─ Cranny.xcodeproj/                     ← hand-written, objectVersion 77
│  ├─ project.pbxproj
│  └─ xcshareddata/xcschemes/Cranny.xcscheme
├─ Cranny/                               ← buildable folder of app target "Cranny"
│  ├─ CrannyApp.swift                    ← the only Swift file: @main → CrannyAppShell
│  ├─ Info.plist                         ← partial plist, merged with generated keys (membership exception!)
│  ├─ Cranny.entitlements
│  ├─ InfoPlist.xcstrings                ← localized usage descriptions (en/ru)
│  ├─ AppIcon.icon/                      ← Icon Composer document (icon.json + Assets/*.svg)
│  └─ Assets.xcassets/                   ← AccentColor (+ future images)
├─ CrannyKit/                            ← local Swift package, ALL code
│  ├─ Package.swift
│  ├─ Sources/CrannyCore/                ← nonisolated default; Resources/Localizable.xcstrings
│  ├─ Sources/CrannyMedia/               ← MainActor default; depends on CrannyCore only
│  ├─ Sources/CrannyAppShell/            ← MainActor default; AppDelegate, NSPanel, scenes
│  ├─ Sources/CrannyMediaBridge/         ← ObjC (.m + include/*.h); also an Xcode dylib target
│  └─ Tests/CrannyCoreTests/             ← Swift Testing
├─ scripts/  lib.sh build.sh run.sh dist.sh check-modules.sh sync-strings.sh
├─ Makefile
├─ .github/workflows/ ci.yml release.yml
└─ .gitignore
```

Outputs (ignored by git):
- `build/Cranny.app`, `build/Cranny.app.dSYM`, `build/DerivedData`, `build/logs/*.log`
- `dist/Cranny-<v>.{zip,dmg,sha256}`
- `CrannyKit/.build-<target>/` (one SwiftPM scratch directory per module)

---

## 3. The Swift package `CrannyKit`

### 3.1 Manifest decisions

The full file is in Appendix A.1.

- `// swift-tools-version: 6.2`. Tools 6.x implies Swift 6 language mode, so no `swiftLanguageModes` is needed.
- `defaultLocalization: "en"` and `platforms: [.macOS(.v14)]`.
- Settings are composed per target from two arrays:
  - `common` = `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility`, `ExistentialAny`.
  - `mainActorByDefault = common + [.defaultIsolation(MainActor.self)]` for CrannyMedia and CrannyAppShell (and future feature modules).
  - `nonisolatedByDefault = common + [.defaultIsolation(nil)]` for CrannyCore and tests.
- Xcode passes these per module (VERIFIED in the xcodebuild log):
  - CrannyMedia gets `-default-isolation MainActor`.
  - CrannyCore gets `-default-isolation nonisolated`.
  - Both get the four `-enable-upcoming-feature` flags and `-swift-version 6`.
  - The app target (via build settings) gets `-default-isolation=MainActor -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault`. In other words, `SWIFT_APPROACHABLE_CONCURRENCY=YES` expands to exactly those two upcoming features.

### 3.2 Isolation rules learned (VERIFIED by compiling `poc/build-probes/isolation`)

- **MainActor default plus InferIsolatedConformances.** A plain `struct Track: Codable` in a MainActor-default module gets a *main-actor-isolated* `Encodable` conformance. `JSONEncoder().encode(track)` inside an `@concurrent` function fails with: `error: main actor-isolated conformance of 'Track' to 'Encodable' cannot be used in @concurrent context`.
  - Fix: declare `nonisolated struct Track: Codable, Sendable`, or put models in a nonisolated-default target. This is the main reason **CrannyCore (models and services) stays nonisolated**.
- `nonisolated` on a type (SE-0449/SE-0466) opts it out of the module default. The PoC uses `public nonisolated enum MediaBridgeLocator` and `public nonisolated struct MediaBridgeClient`.
- With NonisolatedNonsendingByDefault, a `nonisolated async` function runs on the caller's actor. Use `@concurrent` to really leave the main actor. `MediaBridgeClient.hello(dylib:)` is `@concurrent` and does the blocking `Process`/pipe reads there (compiled and ran: VERIFIED).
- The generated `Bundle.module` accessor is `static nonisolated let module`, so it is usable from every isolation domain even in MainActor-default modules (VERIFIED for Xcode 27 and SwiftPM 6.4 with both swiftbuild and native).
  - UNVERIFIED: whether SwiftPM 6.2 or 6.3 (Xcode 26.x) emitted `nonisolated` in its native accessor. CI on Xcode 26 would catch it.

### 3.3 Building modules individually

- `swift build --target <T> --scratch-path .build-<t>` works for every target (VERIFIED: CrannyCore 4.4 s, CrannyMedia 5.4 s, CrannyAppShell 5.4 s from clean).
- `scripts/check-modules.sh` with `JOBS=4` builds all four in parallel plus `swift test` in 15 s wall time (VERIFIED).
- `--target` on the ObjC target only produces the `.o`. Use `swift build --product CrannyMediaBridge` to get `libCrannyMediaBridge.dylib` (VERIFIED). The `.dylib` from SwiftPM is ad-hoc signed by the linker, arm64 only.
- Scratch directories are large: about 56–220 MB per module (VERIFIED). With 15+ modules that is several GB, so `make distclean` removes them. Parallel `swift build` processes with **different** scratch paths do not interfere (VERIFIED).
- `swift test` with Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) passes (VERIFIED). It reports "Target Platform: arm64e-apple-macos14.0".

### 3.4 Resources and String Catalogs

- `resources: [.process("Resources")]` with `Localizable.xcstrings` compiles to `ru.lproj/Localizable.strings` and `.stringsdict`. Plural variants (one/few/many/other) become `.stringsdict`. The `en.lproj` only holds what differs from the keys (for example the en plural `stringsdict`). This holds with Xcode, `swift build` from Xcode, and `swift build` from CLT (VERIFIED).
- **Bundle placement in the app:** `Cranny.app/Contents/Resources/CrannyKit_<Target>.bundle` (VERIFIED).
- **Accessor:** identical for Xcode and `swift build` (swiftbuild). Inspected in `build/DerivedData/Build/Intermediates.noindex/CrannyKit.build/<cfg>/CrannyMedia-t.build/DerivedSources/resource_bundle_accessor.swift`. It tries, in order:
  1. `PACKAGE_RESOURCE_BUNDLE_PATH` (DEBUG only)
  2. `Bundle.main.resourceURL`
  3. `Bundle(for: BundleFinder.self).resourceURL`
  4. `Bundle.main.bundleURL`

  On failure it calls `fatalError("unable to find bundle named …")`. The deprecated native build system instead bakes an absolute build path into the accessor (VERIFIED). Only the Xcode accessor matters for the app.
- **Runtime proof from the Release app** (diagnostics JSON in `build-probes/run/diag-*.json`, screenshots `screen-en.png`, `screen-ru.png`, `screen-final*.png`):
  - With `-AppleLanguages (en)`: "Hello from Cranny", "1 minute left / 3 minutes left…", "Now Playing", "Cranny is running".
  - With `-AppleLanguages (ru)` (or the system default here): "Привет от Cranny", "Осталась 1 минута / Осталось 3 минуты / Осталось 5 минут / Осталась 21 минута", "Сейчас играет", "Cranny работает".
  - `Text(_:bundle: .module)` renders in Russian in the live NSPanel (screenshot) and in `ImageRenderer` snapshots (VERIFIED).
- **Gotcha: `CFBundleLocalizations` is required.**
  - With no `ru.lproj` and no `CFBundleLocalizations` in the *main* bundle, all package bundles report `preferredLocalizations = ["en"]` and show English under ru (VERIFIED).
  - Adding just `CFBundleLocalizations = [en, ru]` to Info.plist fixes it (VERIFIED).
  - An app-level `InfoPlist.xcstrings` with ru also creates `ru.lproj` and fixes it, but the explicit key is the robust fix.
- **Gotcha: main-bundle lookups.** In a package module:
  - `LabeledContent("Version", …)`, `Text("Version")` and `String(localized: "Version")` all look in **Bundle.main** and stay English.
  - `Text("Version", bundle: .module)`, `Text("Version", bundle: #bundle)` and `String(localized: "Version", bundle: #bundle)` show "Версия" (VERIFIED with snapshot `build-probes/run/snap-final-bundles.png`).
  - Rule: in packages, build labels as `Text(…, bundle: .module)` and use the `label:` closure initialisers, or pass `String(localized:bundle:)`.
- `#bundle` (`Foundation` macro, `@available(macOS 12, …)`, in the SDK swiftinterface) works in package targets and resolves to `CrannyKit_<Target>.bundle` (VERIFIED). It is a portable alternative to `.module`.
- **Catalog sync.** `xcodebuild` does *not* write new keys back into `.xcstrings`; only the IDE does (VERIFIED: the md5 was unchanged after adding a new `Text("Paused", bundle:)`). Both Xcode and `swift build` (swiftbuild) emit compiler `.stringsdata` with exact keys, for example `%lld minutes left` (VERIFIED).
  - `scripts/sync-strings.sh` builds each target and runs `xcstringstool sync <catalog> --stringsdata …`, which adds new keys with comments and sorts them like Xcode (VERIFIED).
  - With `CHECK=1` it fails CI when catalogs are stale. It caught the bare `LabeledContent("Version")` key (VERIFIED).
  - Do **not** use `xcstringstool extract`. Its lightweight parser produces `%arg minutes left` instead of `%lld minutes left` (VERIFIED).
- `STRING_CATALOG_GENERATE_SYMBOLS=YES` in the app target is harmless. Symbols are generated only for *manually added* keys (`GeneratedStringSymbols_Localizable.swift` was empty for extracted keys) (VERIFIED).

### 3.5 `#Preview` in modules

- `#Preview` compiles in Xcode Debug and Release builds of the app (VERIFIED). Debug produces `Cranny.debug.dylib` and `__preview.dylib`.
- It also compiles with `swift build --target CrannyMedia` and `CrannyAppShell` using the Xcode toolchain **and** the CLT toolchain, and in `swift build -c release` (VERIFIED).
- The release object exports no preview symbols (`nm -gU … | grep -ci preview` gives 0).
- Conclusion: modules may freely use `#Preview`.

---

## 4. The Xcode project

### 4.1 Hand-written `project.pbxproj` (objectVersion 77)

The full file is in Appendix A.2. The objects used are:

- `PBXProject`:
  - `preferredProjectObjectVersion = 77`
  - `knownRegions = (en, Base, ru)`
  - `packageReferences = (XCLocalSwiftPackageReference)`
  - `minimizedProjectReferenceProxies = 1`
- `PBXFileSystemSynchronizedRootGroup` "Cranny" (`path = Cranny`), plus a `PBXFileSystemSynchronizedBuildFileExceptionSet` with `membershipExceptions = (Info.plist,)`.
  - Without the exception the build still succeeds but warns "The Copy Bundle Resources build phase contains this target's Info.plist file" and copies it as a resource (VERIFIED).
  - `.entitlements`, `.icon`, `.xcassets` and `.xcstrings` need no exceptions. Entitlements are not copied into the bundle (VERIFIED).
- A second synchronized root group `CrannyMediaBridge` with `path = CrannyKit/Sources/CrannyMediaBridge`. A buildable folder may point **into the package** to reuse its sources (VERIFIED).
- `XCLocalSwiftPackageReference` (`relativePath = CrannyKit`) and `XCSwiftPackageProductDependency` (`productName = CrannyAppShell`, **no `package =` key needed** for local packages) (VERIFIED).
- **Important:** every product in `packageProductDependencies` is *linked automatically*, even if it is not listed in the Frameworks phase. Dynamic package products are also **not embedded automatically** in a hand-written project, so the app crashes at launch with "Library not loaded" (VERIFIED with the first variant). Even when embedded, library validation kills the Release app (see §7).
- Targets:
  - `Cranny`: `com.apple.product-type.application`. Phases: Sources, Frameworks, Resources, "Embed Media Bridge" (`PBXCopyFilesBuildPhase`, `dstSubfolderSpec = 10`, `ATTRIBUTES = (CodeSignOnCopy,)`). It has a `PBXTargetDependency` on the bridge.
  - `CrannyMediaBridge`: `com.apple.product-type.library.dynamic`, with `EXECUTABLE_PREFIX = lib`, `SKIP_INSTALL = YES`, `DYLIB_INSTALL_NAME_BASE = @rpath` and `USER_HEADER_SEARCH_PATHS` pointing at `include/`.
- `xcodebuild -list` shows targets Cranny and CrannyMediaBridge, configurations Debug and Release, and schemes Cranny (shared), CrannyAppShell and CrannyMediaBridge. The last two are auto-created package schemes (VERIFIED).
- `xcodebuild archive -scheme Cranny -destination 'generic/platform=macOS'` succeeds. The archive contains a universal `Cranny.app` and both dSYMs, and `SKIP_INSTALL` keeps the dylib out of `Products/` (VERIFIED).
- Xcode created an empty `Cranny.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/` directory and `CrannyKit/.swiftpm/xcode/`. Commit the former only if `Package.resolved` ever appears (when remote dependencies are added).

### 4.2 Build settings (target "Cranny"; shared ones live at project level)

| Setting | Value | Note |
|---|---|---|
| PRODUCT_BUNDLE_IDENTIFIER | app.cranny.Cranny | |
| MACOSX_DEPLOYMENT_TARGET | 14.0 | project level |
| SWIFT_VERSION | 6.0 | gives `-swift-version 6` (VERIFIED) |
| SWIFT_DEFAULT_ACTOR_ISOLATION | MainActor | same as the Xcode 27 "App Base" template |
| SWIFT_APPROACHABLE_CONCURRENCY | YES | gives NonisolatedNonsendingByDefault + InferIsolatedConformances |
| SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY | YES | template default |
| ENABLE_HARDENED_RUNTIME | YES | |
| CODE_SIGN_IDENTITY / CODE_SIGN_STYLE / DEVELOPMENT_TEAM | "-" / Manual / "" | builds without an Apple account |
| CODE_SIGN_INJECT_BASE_ENTITLEMENTS | NO (Release only) | otherwise Release has `get-task-allow=true` (VERIFIED) |
| CODE_SIGN_ENTITLEMENTS | Cranny/Cranny.entitlements | |
| GENERATE_INFOPLIST_FILE + INFOPLIST_FILE | YES + Cranny/Info.plist | file keys are merged with generated ones (VERIFIED) |
| INFOPLIST_KEY_CFBundleDisplayName / NSPrincipalClass | Cranny / NSApplication | |
| MARKETING_VERSION / CURRENT_PROJECT_VERSION | 0.1.0 / 1 | overridable from `scripts/build.sh` via MARKETING_VERSION / BUILD_NUMBER |
| LOCALIZATION_PREFERS_STRING_CATALOGS | YES | |
| SWIFT_EMIT_LOC_STRINGS | YES | gives `-emit-localized-strings` (VERIFIED) |
| STRING_CATALOG_GENERATE_SYMBOLS | YES | |
| ASSETCATALOG_COMPILER_APPICON_NAME / GLOBAL_ACCENT_COLOR_NAME | AppIcon / AccentColor | |
| LD_RUNPATH_SEARCH_PATHS | $(inherited) @executable_path/../Frameworks | |
| ENABLE_PREVIEWS | YES | Xcode forces it to NO outside Debug |
| ONLY_ACTIVE_ARCH | YES (Debug) / NO (Release) | not enough on its own; see §5 |
| ENABLE_USER_SCRIPT_SANDBOXING | YES | template default; we have no script phases |

Other facts:
- `ARCHS_STANDARD` is still `arm64 x86_64` in Xcode 27. `VALID_ARCHS` lists `arm64 arm64e arm64e.x1 i386 x86_64` (VERIFIED).
- Xcode 16+ also offers entitlement build settings (`ENABLE_RESOURCE_ACCESS_CAMERA|AUDIO_INPUT|CALENDARS|BLUETOOTH|…`, `AUTOMATION_APPLE_EVENTS`, `RUNTIME_EXCEPTION_*`). They exist in the SwiftBuild xcspec (VERIFIED). We keep an explicit `.entitlements` file for transparency.
- `INFOPLIST_KEY_*` exists for NSAppleEvents, NSCalendarsFullAccess, NSCamera, NSBluetoothAlways and NSMicrophone usage descriptions, but **not for `NSAudioCaptureUsageDescription`** (VERIFIED: absent in CoreBuildSystem.xcspec). That is one reason to keep a real `Info.plist` file.

### 4.3 Info.plist, entitlements, localized usage strings

- The merged Info.plist (VERIFIED with `plutil -p`) contains:
  - LSUIElement=true, LSMinimumSystemVersion=14.0, CFBundleLocalizations [en, ru]
  - CFBundleIconFile and CFBundleIconName = AppIcon, NSAccentColorName
  - All usage descriptions: AppleEvents, CalendarsFullAccess and Calendars, Camera, BluetoothAlways, AudioCapture, Microphone
- `InfoPlist.xcstrings` in the app folder compiles to `Contents/Resources/ru.lproj/InfoPlist.strings` with translated `NSCameraUsageDescription` and others (VERIFIED).
- Entitlements (hardened runtime, **no App Sandbox**):
  - `com.apple.security.automation.apple-events`
  - `com.apple.security.device.camera`
  - `com.apple.security.device.audio-input`
  - `com.apple.security.personal-information.calendars`

  They are embedded as shown by `codesign -d --entitlements -` (VERIFIED). All keys exist in Xcode's entitlement definitions (VERIFIED by grep in `DVTCorePlistStructDefs.xcplugindata`).
  - Bluetooth has no hardened-runtime entitlement (`com.apple.security.device.bluetooth` is App Sandbox only). The usage string is enough (UNVERIFIED, per Apple's hardened runtime docs).
  - Whether Core Audio taps under hardened runtime need `device.audio-input` is UNVERIFIED (media research). It is included anyway.
  - `NSAudioCaptureUsageDescription` must be added by hand. Without it, tap recordings are silent and no prompt is shown (UNVERIFIED; community sources).

### 4.4 Debug vs Release signing (VERIFIED, important)

- **Release:** `codesign … -o runtime …` gives `flags=0x10002(adhoc,runtime)`. Library validation and hardened-runtime entitlements are enforced.
- **Debug:**
  - Xcode prints `note: Disabling hardened runtime with ad-hoc codesigning.` and signs without `-o runtime` (`flags=0x2(adhoc)`).
  - `-showBuildSettings` reports `ENABLE_HARDENED_RUNTIME = NO` even though the target sets YES.
  - The trigger is `ENABLE_XOJIT_PREVIEWS` (Debug default YES). Overriding `ENABLE_PREVIEWS=NO` or `ENABLE_DEBUG_DYLIB=NO` does *not* stop the note; `ENABLE_XOJIT_PREVIEWS=NO` does.
  - The trigger is also tied to ad-hoc signing: with `CODE_SIGN_IDENTITY="Apple Development"`, showBuildSettings keeps hardened YES.
  - With `ENABLE_XOJIT_PREVIEWS=NO` the Debug build is hardened, has no debug dylib, and launches fine.
- **Consequence:** bugs involving library validation or missing resource-access entitlements reproduce only in Release. `scripts/run.sh` therefore builds Debug with `ENABLE_XOJIT_PREVIEWS=NO`. Use `XOJIT=1` to opt out.

---

## 5. Universal build (arm64 + x86_64)

```
xcodebuild build -project Cranny.xcodeproj -scheme Cranny -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
```

- Without `-destination`, xcodebuild warns "Using the first of multiple matching destinations: { platform:macOS, arch:arm64, … My Mac }" and builds **arm64 only**. All 20 compile jobs were `-target arm64-apple-macos14.0`, even with ONLY_ACTIVE_ARCH=NO in the project (VERIFIED).
- With `generic/platform=macOS`, `lipo` reports `x86_64 arm64` for `Contents/MacOS/Cranny` and for `Contents/Frameworks/libCrannyMediaBridge.dylib` (VERIFIED). A clean universal Release build takes about 10–12 s.
- The macOS 27 SDK still links x86_64 with deployment target 14.0 (VERIFIED).
- The x86_64 slice was not run here (no Rosetta). Apple said macOS 26 Tahoe is the last release for Intel Macs, so x86_64 matters only for macOS 14–26 users on Intel (UNVERIFIED for future Xcode releases).

---

## 6. App icon: Icon Composer `.icon` with fallback

- Xcode 27 ships `Icon Composer.app` with `Contents/Executables/ictool`. Its help text: `ictool file.icon --export-image --output-file out.png --platform macOS --rendition Default --width 512 --height 512 --scale 1 [--design-generation 26|27]` (VERIFIED). `xcrun ictool` (the `Developer/usr/bin` copy) is the actool-style binary and does not accept these options.
- A **hand-written** `.icon` works (VERIFIED). It consists of `icon.json` (with `fill.linear-gradient`, `groups[].layers[].image-name`, `shadow`, `translucency`, `blur-material`, `supported-platforms.squares=[macOS]`) and `Assets/*.svg`.
  - `ictool` rendered it with Liquid Glass for design generations 26 and 27 (`build-probes/icon/render-26.png`, `render-27.png`).
  - The JSON schema is not published by Apple. Author real icons in Icon Composer (UNVERIFIED for all keys).
- The build passes `AppIcon.icon` and `Assets.xcassets` to `actool --app-icon AppIcon --minimum-deployment-target 14.0` (VERIFIED in the log). Output:
  - `AppIcon.icns` with 16/32/128/256 px legacy representations
  - `Assets.car` with rendered "Icon Image" 32…1024 px plus `IconGroup` appearances (Aqua, dark, tintable)
  - partial plist with `CFBundleIconFile` and `CFBundleIconName` = AppIcon

  (VERIFIED with `assetutil --info` and `iconutil`.)
- When both `AppIcon.icon` and `AppIcon.appiconset` exist, the output is byte-identical in size to the `.icon`-only build, and the appiconset's 16 px images are absent. **The `.icon` wins** (VERIFIED). This matches Apple's documentation: "Xcode automatically generates app icon images at build time for those releases from the Icon Composer file".
- Recommendation: only `AppIcon.icon`. Add a separately named appiconset only if hand-tuned pre-26 artwork is wanted. The PoC's generated legacy appiconset was moved to `build-probes/icon/AppIcon.appiconset.unused`, and its generator to `build-probes/icon/generate-icons.swift`.

---

## 7. Media bridge dylib (perl-loaded)

The media research loads a small ObjC dylib into Apple's `/usr/bin/perl` via `DynaLoader::dl_load_file`, `dl_find_symbol` and `dl_install_xsub`. Build-side findings:

| Question | Answer | Status |
|---|---|---|
| Is `/usr/bin/perl` hardened / library-validated? | `codesign -dv /usr/bin/perl`: `Identifier=com.apple.perl`, `flags=0x0(none)`, `Platform identifier=26`. Universal x86_64/arm64e. No hardened runtime, so no library validation. | VERIFIED |
| Can it load an ad-hoc signed dylib? | Yes, both the SwiftPM-built `libCrannyMediaBridge.dylib` and the copy embedded and re-signed in `Cranny.app/Contents/Frameworks/` print `{"t":"hello","host":"/usr/bin/perl","ppid":<Cranny pid>,…}` | VERIFIED |
| Quarantined dylib? | `com.apple.quarantine` flags `0081` or `0083` (downloaded, not approved) cause dlopen to fail with "library load disallowed by system policy". Flags `0040`, `0041`, `00c1`, `01c1` (user-approved bit 0x40) and no xattr load fine. | VERIFIED |
| Arch | Must match perl's slice. The Xcode bridge target builds universal. | VERIFIED (lipo) |
| Link the SwiftPM `.dynamic` product into the app? | **No.** It is auto-linked via `packageProductDependencies`, not auto-embedded ("Library not loaded"). When embedded, the hardened ad-hoc Release app aborts in dyld with "code signature … not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs". | VERIFIED (crash report `~/Library/Logs/DiagnosticReports/Cranny-2026-10-14-005341.ips`) |
| Chosen design | Xcode target `CrannyMediaBridge` (library.dynamic) builds `CrannyKit/Sources/CrannyMediaBridge`. The app target depends on it, does not link it, and copies it to `Contents/Frameworks/` with CodeSignOnCopy. Result: `flags=0x10002(adhoc,runtime)`, and `codesign --verify --deep --strict` passes. `MediaBridgeLocator` finds it via `Bundle.main.privateFrameworksURL`. | VERIFIED |
| Alternative | `com.apple.security.cs.disable-library-validation` would allow linking, but it weakens the app. Not needed. | — |

Distribution risk:
- A Developer-ID-signed **and notarized** release has its stapled ticket cover the nested dylib (UNVERIFIED; no Developer ID available).
- For ad-hoc builds downloaded from GitHub, Archive Utility propagates quarantine to every file. Whether Gatekeeper's "Open Anyway" approval also clears the nested dylib's flag is UNVERIFIED.
- Mitigation (cheap, in the media module): before spawning perl, check `getxattr(dylib, "com.apple.quarantine")`. If present, copy the dylib to `~/Library/Application Support/Cranny/` (Cranny is not `LSFileQuarantineEnabled`, so files it writes are not quarantined) and strip the xattr, or remove the xattr in place. Removing the xattr made the dylib loadable (VERIFIED with `xattr -d`).

---

## 8. TCC permission attribution during development

- **Responsible process** was measured with the private `responsibility_get_pid_responsible_for_pid` (diagnostic tool `build-probes/resp/resp.c`) (VERIFIED):
  - `open -n build/Cranny.app`: Cranny's parent is launchd (ppid 1), Cranny is responsible for itself, and its `/usr/bin/perl` child is attributed to **Cranny**.
  - Running `build/Cranny.app/Contents/MacOS/Cranny` directly from a shell makes the **host terminal app** responsible for both Cranny and its perl child (here Claude Code's `claude.app`; normally Terminal or iTerm). Prompts and grants would then go to the terminal.
  - Launching from the Xcode IDE (Run): Xcode is believed to make the app its own responsible process (UNVERIFIED; no GUI run here).
- **Identity:** ad-hoc builds have `designated => cdhash H"…"` (VERIFIED with `codesign -d -r-`), so each rebuild is a new code identity for TCC.
  - Expect Accessibility, Input Monitoring and Screen Recording toggles to stop applying after rebuilds. Camera, Calendar and Automation may re-prompt (UNVERIFIED; standard TCC behaviour).
  - Fix for contributors: sign Debug with a persistent identity. Options are a free Apple ID "Apple Development" certificate (`CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=<team>`) or a self-signed "Cranny Dev" code-signing certificate from Keychain Access. The designated requirement then becomes certificate-based (UNVERIFIED; the machine has 0 codesigning identities and none was created).
- **Reset:** `tccutil reset <Service> app.cranny.Cranny` (usage `tccutil reset SERVICE [BUNDLE_ID]`, VERIFIED with `man tccutil`; not executed).
  - Service names (VERIFIED as `kTCCService*` keys in `/System/Library/PrivateFrameworks/TCC.framework/Resources/Localizable.loctable`): `Accessibility`, `AppleEvents`, `Calendar`, `Camera`, `Microphone`, `AudioCapture`, `BluetoothAlways`, `ScreenCapture`. `ListenEvent` (Input Monitoring) and `PostEvent` are standard names but were not in that table (UNVERIFIED).
  - `tccutil reset All app.cranny.Cranny` resets everything for the app.
  - For a renamed or experimental bundle ID, reset that ID. The PoC's copy signed as `app.cranny.CrannyNoLoc` never requested permissions.
- Hardened-runtime apps **must** carry the matching `com.apple.security.device.*` or `personal-information.*` entitlement, or TCC denies silently (UNVERIFIED for each service here; Apple documents it). Because ad-hoc Debug builds are *not* hardened (§4.4), test permission flows with `scripts/run.sh` or Release.

---

## 9. Scripts and Makefile (all executed)

| Command | Result |
|---|---|
| `make help` | lists the targets (VERIFIED) |
| `make build` = `scripts/build.sh` | Universal Release, then `build/Cranny.app` + dSYM. Verifies the signature and prints version, architectures and signing flags. About 12 s. Works with `DEVELOPER_DIR` unset and with a simulated CLT `xcode-select` (VERIFIED). |
| `ARCHS=arm64 scripts/build.sh`, `CONFIGURATION=Debug …`, `MARKETING_VERSION=… BUILD_NUMBER=…` | VERIFIED (arm64) / wiring only |
| `SIGN_IDENTITY=… TEAM_ID=… scripts/build.sh` | Developer ID path; adds `OTHER_CODE_SIGN_FLAGS=--timestamp` (UNVERIFIED; no identity) |
| `make run` = `scripts/run.sh` | Debug, host arch, `ENABLE_XOJIT_PREVIEWS=NO` (hardened), quits the previous **dev** instance only, `open -n`, polls `pgrep` (VERIFIED). Supports `--no-build`, `-- <app args>` and `XOJIT=1`. |
| `make dist` = `scripts/dist.sh` | `ditto -c -k --norsrc --keepParent` zip (no `__MACOSX`; the extracted app passes `codesign --verify --deep --strict`), APFS UDZO DMG with an /Applications link (`hdiutil verify` OK), and `.sha256` (VERIFIED). The notarize and staple path runs only with `SIGN_IDENTITY`, `TEAM_ID` and `NOTARY_PROFILE` set (UNVERIFIED; `notarytool` and `stapler` options checked with `--help`). |
| `make check` = `scripts/check-modules.sh` | builds each non-test target with its own `.build-<t>`; `JOBS=N` runs in parallel, `TEST=1` adds `swift test` (VERIFIED) |
| `make strings` / `make strings-check` | `scripts/sync-strings.sh` (VERIFIED, §3.4) |
| `make test`, `make list`, `make clean`, `make distclean` | VERIFIED (test, list) |

Scripts target macOS `/bin/bash` 3.2 (no `mapfile`; empty-array expansions are guarded under `set -u`). `bash -n` passes for all. `xcbeautify` is used if present (CI images have 3.2.1).

---

## 10. Distribution notes

- `spctl -a -vv -t exec build/Cranny.app` gives `rejected` (ad-hoc, not notarized) (VERIFIED). Users of non-notarized builds must use System Settings → Privacy & Security → "Open Anyway". Control-click Open no longer bypasses Gatekeeper on macOS 15+ (UNVERIFIED). The alternative is `xattr -dr com.apple.quarantine /Applications/Cranny.app`. Put both in the README.
- **Maintainer notarization flow** (UNVERIFIED end-to-end; commands checked against `--help`):
  1. Run `xcrun notarytool store-credentials cranny-notary --key AuthKey.p8 --key-id … --issuer …`, or use `--apple-id/--team-id/--password`.
  2. Build with `SIGN_IDENTITY="Developer ID Application: … (TEAMID)" TEAM_ID=TEAMID`.
  3. `scripts/dist.sh` with `NOTARY_PROFILE=cranny-notary`:
     - zips the app, runs `notarytool submit --wait` and `stapler staple` on the app
     - creates the zip and DMG
     - signs the DMG, notarizes it and staples it
  - `get-task-allow` must be absent; Release already ensures this.
  - Hardened runtime and secure timestamp are required for notarization.
- Sparkle or other update frameworks are out of scope. The GitHub Releases check only needs `SemanticVersion` from CrannyCore (included and tested).

---

## 11. GitHub Actions

- **Runners** (sources: runner-images README and GitHub changelog, fetched 2026-10-14):
  - `xcode-27` / `xcode-27-xlarge`: arm64 only, **public preview** since 2026-07-16. The image README dated 2026-10-06 lists macOS 27.0.1 (26A434), Xcode 27.0 27A266a as default at `/Applications/Xcode_27.app` (also symlinked as `/Applications/Xcode.app`), Xcode 27.1 and 27.2 betas, xcbeautify 3.2.1, GitHub CLI 2.102.0, Bash 3.2.57.
  - `macos-26` / `macos-latest`: arm64, macOS 26.6.2, Xcode 26.6 default plus 26.0.1–26.5.
  - `macos-26-intel` / `macos-26-large`: x64.
  - macOS 14 images are deprecated and unsupported from 2026-11-02.
- **Actions versions** (GitHub API, 2026-10-14): `actions/checkout` v7.0.1, `actions/upload-artifact` v7.0.2.
- **`ci.yml`** runs on push to main, on PRs and manually, on `xcode-27`:
  1. toolchain info
  2. `JOBS=3 TEST=1 scripts/check-modules.sh`
  3. `CHECK=1 scripts/sync-strings.sh`
  4. `scripts/build.sh` (universal, ad-hoc, `BUILD_NUMBER=run_number`)
  5. `scripts/dist.sh`
  6. upload zip, DMG and sha256 (14 days); upload logs on failure
- **`release.yml`** runs on tag `v*`:
  1. version from the tag
  2. optional Developer ID import into a temporary keychain and `notarytool store-credentials --keychain`, only when the secrets `DEVELOPER_ID_P12_BASE64` and `NOTARY_KEY_P8_BASE64` exist
  3. build
  4. dist (notarizes when configured)
  5. `gh release create "$GITHUB_REF_NAME" dist/* --generate-notes --verify-tag` (`permissions: contents: write`)
- The YAML parses (Ruby `YAML.load_file`). The workflows were **not executed** (UNVERIFIED). Risk: the `xcode-27` label is a preview; switch to `macos-27` or `macos-latest` when GA, or use `macos-26` (Xcode 26.6, Swift 6.3) as a fallback. On Xcode 26.x, check that the native accessor has `nonisolated` and that `@concurrent`, `nonisolated` types and `#bundle` behave the same.

---

## 12. Launch verification

```
open -n build/Cranny.app --args --diagnostics run/diag-final.json --snapshot run/snap-final.png
pgrep -fl 'build/Cranny.app/Contents/MacOS/Cranny'      → 75992 (and 78382 for the final universal build)
screencapture -x -R980,0,600,90 run/screen-final.png    → exit 0, panel visible (no Screen Recording block)
pkill -f 'build/Cranny.app/Contents/MacOS/Cranny'       → "no Cranny process left"
```

The diagnostics JSON from inside the Release app reports:
- arch arm64
- bundles at `Contents/Resources/CrannyKit_*.bundle`
- `bridgePath …/Contents/Frameworks/libCrannyMediaBridge.dylib`
- `bridgeHello {"arch":"arm64","host":"/usr/bin/perl","pid":…,"ppid":<app pid>,"t":"hello"}`
- localized values as listed in §3.4

`LSUIElement` gives no Dock icon (Info.plist VERIFIED; visual Dock check not done). The MenuBarExtra and Settings scenes compile; their interaction was not exercised.

---

## 13. Open risks

1. **`xcode-27` CI image is a preview.** The label or tooling may change. Keep a `macos-26` fallback job, or pin with `DEVELOPER_DIR=/Applications/Xcode_27.0.app/Contents/Developer`.
2. **Quarantine and the perl-loaded dylib** for non-notarized downloads (§7). Implement the copy-and-unquarantine fallback in the media module and test it with a real browser download plus "Open Anyway".
3. **TCC churn with ad-hoc signing** (§8). Document the stable-identity setup for contributors who test Accessibility or Input Monitoring features.
4. **Debug ≠ Release hardening** in the Xcode IDE (§4.4). Run TCC and library-validation-sensitive tests through `make run` or Release. CI builds Release only.
5. **Swift 6.2 vs 6.4 toolchain differences** (swiftbuild default only in 6.4; accessor isolation in older versions). Minimum Xcode 26 is declared in `scripts/lib.sh`, but only 27.0 was tested.
6. **Hand-written pbxproj maintenance.** Buildable folders keep it small: new Swift files never touch it. Adding targets means editing it by hand or in Xcode. Xcode may reformat it on first open (harmless).
7. **Scratch-dir disk usage** for per-module `swift build` (56–220 MB each).
8. **The `.icon` JSON schema is unofficial.** Create the real icon in Icon Composer; `ictool` can render previews in CI.
9. **x86_64 was never executed** (no Rosetta). Consider a `macos-26-intel` smoke job that launches the app with `--diagnostics`.

---

## Sources

- Apple: [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) (markdown mirror: https://developer.apple.com/tutorials/data/documentation/xcode/creating-your-app-icon-using-icon-composer.md)
- GitHub: [actions/runner-images README](https://github.com/actions/runner-images), [macos-26-arm64 Readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [xcode-27-arm64 Readme](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/xcode-27-arm64-Readme.md), [Changelog: Xcode 27 runner image now in public preview (2026-07-16)](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview)
- NSAudioCaptureUsageDescription background: [insidegui/AudioCap](https://github.com/insidegui/AudioCap), [nonstrict RecordKit guide](https://nonstrict.eu/recordkit/guides/system-audio-recording.html), [Electron PR 49717](https://releases.electronjs.org/pr/49717)
- Local primary sources: the PackageDescription swiftinterface, `swiftc -print-supported-features`, the SwiftBuild `CoreBuildSystem.xcspec`, Xcode project templates (`Base_ProjectSettings`, `App Base`, `Cocoa App Base`), the Foundation swiftinterface (`#bundle`), `ictool --help`, `xcstringstool --help`, `notarytool --help`, `man ditto` and `man tccutil`, and the TCC `Localizable.loctable`.

---

# Appendix A: exact working files (copied verbatim from the PoC)

## A.1 `CrannyKit/Package.swift`

```swift
// swift-tools-version: 6.2
// CrannyKit: all Cranny code lives here as library targets. The thin Xcode app
// target (Cranny.xcodeproj) only contains @main, Info.plist, entitlements and icons.
import PackageDescription

/// Settings shared by every Swift target (Swift 6 language mode is implied by tools 6.x).
let common: [SwiftSetting] = [
    // Swift 7 defaults we opt into now (all VERIFIED to exist in Swift 6.4).
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"), // nonisolated async runs on the caller's actor; use @concurrent to hop off
    .enableUpcomingFeature("InferIsolatedConformances"),      // @MainActor types get @MainActor conformances automatically
    .enableUpcomingFeature("MemberImportVisibility"),         // members need an explicit import of their module (Xcode template default)
    .enableUpcomingFeature("ExistentialAny"),
]

/// UI / feature / app-shell targets: everything is @MainActor unless marked otherwise
/// (same as Xcode 26+ app template SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
let mainActorByDefault: [SwiftSetting] = common + [.defaultIsolation(MainActor.self)]

/// Pure models / services: keep the classic nonisolated default.
let nonisolatedByDefault: [SwiftSetting] = common + [.defaultIsolation(nil)]

let package = Package(
    name: "CrannyKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        // The app links only this product; it re-exports nothing, it just pulls the graph in.
        .library(name: "CrannyAppShell", targets: ["CrannyAppShell"]),
        // Loaded at runtime by /usr/bin/perl (media research); never imported by Swift code.
        // Only for `swift build --product CrannyMediaBridge` (CLI dev). The app does NOT consume
        // this product: linking a .dynamic package product into the hardened, ad-hoc signed app
        // crashes at launch (library validation). Xcode builds the same sources via the
        // "CrannyMediaBridge" dylib target in Cranny.xcodeproj and copies it to Contents/Frameworks.
        .library(name: "CrannyMediaBridge", type: .dynamic, targets: ["CrannyMediaBridge"]),
    ],
    targets: [
        .target(
            name: "CrannyCore",
            resources: [.process("Resources")],
            swiftSettings: nonisolatedByDefault
        ),
        .target(
            name: "CrannyMedia",
            dependencies: ["CrannyCore"],
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault
        ),
        .target(
            name: "CrannyAppShell",
            dependencies: ["CrannyCore", "CrannyMedia"],
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault
        ),
        // Objective-C, ARC (SwiftPM enables -fobjc-arc for ObjC targets by default).
        .target(
            name: "CrannyMediaBridge",
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        .testTarget(
            name: "CrannyCoreTests",
            dependencies: ["CrannyCore"],
            swiftSettings: nonisolatedByDefault
        ),
    ]
)
```

## A.2 `Cranny.xcodeproj/project.pbxproj`

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
		C0A11E000000000000000006 /* Exceptions for "Cranny" folder in "Cranny" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = C0A11E000000000000000010 /* Cranny */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		C0A11E000000000000000005 /* Cranny */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				C0A11E000000000000000006 /* Exceptions for "Cranny" folder in "Cranny" target */,
			);
			path = Cranny;
			sourceTree = "<group>";
		};
		C0A11E000000000000000075 /* CrannyMediaBridge */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			name = CrannyMediaBridge;
			path = CrannyKit/Sources/CrannyMediaBridge;
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
				C0A11E000000000000000005 /* Cranny */,
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
				C0A11E000000000000000005 /* Cranny */,
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
				CODE_SIGN_ENTITLEMENTS = Cranny/Cranny.entitlements;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Cranny/Info.plist;
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
				CODE_SIGN_ENTITLEMENTS = Cranny/Cranny.entitlements;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Cranny/Info.plist;
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
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				USER_HEADER_SEARCH_PATHS = "$(SRCROOT)/CrannyKit/Sources/CrannyMediaBridge/include";
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
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				USER_HEADER_SEARCH_PATHS = "$(SRCROOT)/CrannyKit/Sources/CrannyMediaBridge/include";
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
			relativePath = CrannyKit;
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

## A.3 `Cranny.xcodeproj/xcshareddata/xcschemes/Cranny.xcscheme`

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

## A.4 `Cranny/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Merged with the keys Xcode generates (GENERATE_INFOPLIST_FILE = YES). -->
	<key>LSUIElement</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Cranny contributors. MIT License.</string>
	<!-- Languages the app (incl. its SwiftPM resource bundles) is localized into. -->
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ru</string>
	</array>
	<!-- Privacy usage descriptions (localized in InfoPlist.xcstrings). -->
	<key>NSAppleEventsUsageDescription</key>
	<string>Cranny controls music apps such as Music and Spotify to show and change what is playing.</string>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Cranny shows your upcoming events and meeting links in the notch.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>Cranny shows your upcoming events and meeting links in the notch.</string>
	<key>NSCameraUsageDescription</key>
	<string>Cranny shows a camera preview in the Mirror widget.</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Cranny shows when Bluetooth devices such as headphones connect and their battery level.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Cranny listens to system audio output to animate the music visualizer. Audio is never recorded or stored.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Cranny analyzes audio levels to animate the music visualizer. Audio is never recorded or stored.</string>
</dict>
</plist>
```

## A.5 `Cranny/Cranny.entitlements`

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

## A.6 `Cranny/CrannyApp.swift`

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

## A.7 `Cranny/InfoPlist.xcstrings`

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : {
      "comment" : "Bundle display name",
      "extractionState" : "extracted_with_value",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "new", "value" : "Cranny" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Cranny" } }
      }
    },
    "NSCameraUsageDescription" : {
      "comment" : "Privacy - Camera Usage Description",
      "extractionState" : "extracted_with_value",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "new", "value" : "Cranny shows a camera preview in the Mirror widget." } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Cranny показывает изображение с камеры в виджете «Зеркало»." } }
      }
    },
    "NSCalendarsFullAccessUsageDescription" : {
      "comment" : "Privacy - Calendars Full Access Usage Description",
      "extractionState" : "extracted_with_value",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "new", "value" : "Cranny shows your upcoming events and meeting links in the notch." } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Cranny показывает ближайшие события и ссылки на встречи в вырезе экрана." } }
      }
    }
  },
  "version" : "1.0"
}
```

## A.8 `Cranny/AppIcon.icon/icon.json`

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

## A.9 `Cranny/Assets.xcassets/AccentColor.colorset/Contents.json`

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

## A.10 `scripts/lib.sh`

```bash
#!/usr/bin/env bash
# Shared helpers for Cranny scripts. Source it; do not execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Cranny.xcodeproj"
SCHEME="Cranny"
PACKAGE_DIR="$ROOT/CrannyKit"
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

## A.11 `scripts/build.sh`

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
[[ -n "${MARKETING_VERSION:-}" ]] && overrides+=(MARKETING_VERSION="$MARKETING_VERSION")
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

## A.12 `scripts/run.sh`

```bash
#!/usr/bin/env bash
# Debug build (host arch) + launch.
#
#   scripts/run.sh                      # build, quit the old dev instance, open the new one
#   scripts/run.sh --no-build           # just relaunch
#   scripts/run.sh -- --some-app-arg    # pass arguments to the app
#   XOJIT=1 scripts/run.sh              # keep Xcode-style Debug (XOJIT previews => hardened runtime OFF)
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

## A.13 `scripts/dist.sh`

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

## A.14 `scripts/check-modules.sh`

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

## A.15 `scripts/sync-strings.sh`

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
  swift build --target "$target" --scratch-path "$scratch" >/dev/null 2>&1 \
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

## A.16 `Makefile`

```make
# Thin wrapper around scripts/. All targets work when xcode-select points at the
# Command Line Tools: the scripts locate /Applications/Xcode*.app themselves.
SHELL := /bin/bash

.PHONY: help build debug run dist check test strings strings-check list clean distclean

help:            ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

build:           ## Release build, universal -> build/Cranny.app
	@scripts/build.sh

debug:           ## Debug build -> build/Cranny.app
	@CONFIGURATION=Debug ARCHS="$$(uname -m)" scripts/build.sh

run:             ## Debug build + launch (via LaunchServices)
	@scripts/run.sh

dist: build      ## zip + dmg (+ notarization when NOTARY_PROFILE is set) -> dist/
	@scripts/dist.sh

check:           ## Build every CrannyKit target separately (swift build --target)
	@scripts/check-modules.sh

test:            ## swift test for CrannyKit
	@. scripts/lib.sh && ensure_xcode && cd CrannyKit && swift test --scratch-path .build-test

strings:         ## Sync String Catalogs with keys used in code
	@scripts/sync-strings.sh

strings-check:   ## Fail if String Catalogs are out of date (CI)
	@CHECK=1 scripts/sync-strings.sh

list:            ## xcodebuild -list
	@. scripts/lib.sh && ensure_xcode && xcodebuild -list -project Cranny.xcodeproj

clean:           ## Remove build outputs
	rm -rf build dist

distclean: clean ## Also remove SwiftPM scratch dirs
	rm -rf CrannyKit/.build CrannyKit/.build-* CrannyKit/.swiftpm
```

## A.17 `.github/workflows/ci.yml`

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

## A.18 `.github/workflows/release.yml`

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

      - name: Version from tag
        run: |
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

      - name: Package (+ notarize when signing is configured)
        run: scripts/dist.sh

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" dist/*.zip dist/*.dmg dist/*.sha256 \
            --title "Cranny $MARKETING_VERSION" --generate-notes --verify-tag
```

## A.19 `.gitignore`

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

## A.20 `CrannyKit/Sources/CrannyCore/Resources/Localizable.xcstrings`

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "%lld minutes left" : {
      "comment" : "Meeting countdown",
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld minute left" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld minutes left" } }
            }
          }
        },
        "ru" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "Осталась %lld минута" } },
              "few" : { "stringUnit" : { "state" : "translated", "value" : "Осталось %lld минуты" } },
              "many" : { "stringUnit" : { "state" : "translated", "value" : "Осталось %lld минут" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "Осталось %lld минуты" } }
            }
          }
        }
      }
    },
    "Hello from Cranny" : {
      "comment" : "PoC string in CrannyCore",
      "localizations" : {
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Привет от Cranny" } }
      }
    }
  },
  "version" : "1.0"
}
```

## A.21 `CrannyKit/Sources/CrannyMedia/CrannyMedia.swift`

```swift
import Foundation
import Observation
import SwiftUI
import CrannyCore

// Default isolation in this target = MainActor (see Package.swift).

@Observable
public final class NowPlayingModel {
    public var title: String?
    public var bridgeStatus: String = "not started"
    public init() {}
}

public enum MediaStrings {
    public static var nowPlaying: String {
        String(localized: "Now Playing", bundle: .module, comment: "Media live activity title")
    }
    public static var resourceBundle: Bundle { .module }
}

/// Finds the bridge dylib in every way we build Cranny.
/// `nonisolated` on a type opts it out of the target's MainActor default (SE-0466).
public nonisolated enum MediaBridgeLocator {
    public static func dylibURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates: [URL] = []
        if let override = environment["CRANNY_MEDIA_BRIDGE"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let frameworks = Bundle.main.privateFrameworksURL {
            // Xcode turns a SwiftPM .dynamic product into a framework and embeds it here.
            candidates.append(frameworks.appending(path: "CrannyMediaBridge.framework/CrannyMediaBridge"))
            candidates.append(frameworks.appending(path: "libCrannyMediaBridge.dylib"))
        }
        // `swift build`: the dylib sits next to the executable in .build/<config>/.
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appending(path: "libCrannyMediaBridge.dylib"))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.resolvingSymlinksInPath().path) }
    }
}

public enum MediaBridgeError: Error, CustomStringConvertible {
    case perlFailed(status: Int32, stderr: String)
    public var description: String {
        switch self {
        case let .perlFailed(status, stderr): "perl exited \(status): \(stderr)"
        }
    }
}

/// Launches Apple's /usr/bin/perl, which dlopen()s the bridge and calls its entry point.
public nonisolated struct MediaBridgeClient: Sendable {
    public static let launcherScript = """
    use strict; use DynaLoader;
    my $lib = shift @ARGV or die "missing library path\\n";
    my $h = DynaLoader::dl_load_file($lib, 0) or die "load failed: " . DynaLoader::dl_error() . "\\n";
    my $s = DynaLoader::dl_find_symbol($h, "cranny_bridge_main") or die "entry point missing\\n";
    DynaLoader::dl_install_xsub("main::bridge", $s);
    bridge();
    """

    public init() {}

    /// `@concurrent` = always runs on the global concurrent executor, even though
    /// NonisolatedNonsendingByDefault would otherwise keep it on the caller's actor.
    @concurrent
    public func hello(dylib: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.launcherScript, dylib.path]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MediaBridgeError.perlFailed(status: process.terminationStatus,
                                              stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MediaPeekView: View {
    let model: NowPlayingModel
    public init(model: NowPlayingModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
            // Text(_:bundle:) — key is looked up in this module's String Catalog.
            Text("Now Playing", bundle: .module, comment: "Media live activity title")
            if model.title == nil {
                Text("Nothing is playing", bundle: .module, comment: "Media empty state")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
    }
}

#Preview("Media peek") {
    MediaPeekView(model: NowPlayingModel())
        .padding()
        .background(.black)
}
```

## A.22 `CrannyKit/Sources/CrannyAppShell/AppShell.swift`

```swift
import AppKit
import SwiftUI
import CrannyCore
import CrannyMedia

// Default isolation in this target = MainActor (see Package.swift).

/// Owned by the app target via @NSApplicationDelegateAdaptor.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let media = NowPlayingModel()
    private var panel: NotchPanel?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(rootView: NotchRootView(media: media))
        panel.placeAtTopCenter()
        panel.orderFrontRegardless()
        self.panel = panel
        Task { await Diagnostics.runIfRequested(media: media) }
    }
}

/// Borderless, non-activating panel that floats over the menu bar / notch.
final class NotchPanel: NSPanel {
    init(rootView: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }

    func placeAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height))
    }
}

struct NotchRootView: View {
    let media: NowPlayingModel

    var body: some View {
        VStack(spacing: 4) {
            Text("Cranny is running", bundle: .module, comment: "Notch PoC label")
                .font(.system(size: 13, weight: .semibold))
            MediaPeekView(model: media)
            Text(CrannyCore.minutesLeft(3))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(width: 360, height: 64)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18).fill(.black))
    }
}

/// Scenes the app target plugs into its `App.body`.
public struct CrannyScenes: Scene {
    let appDelegate: AppDelegate
    public init(appDelegate: AppDelegate) { self.appDelegate = appDelegate }

    public var body: some Scene {
        MenuBarExtra {
            SettingsLink { Text("Settings…", bundle: .module, comment: "Menu bar item") }
            Divider()
            Button(String(localized: "Quit Cranny", bundle: .module, comment: "Menu bar item")) {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "rectangle.topthird.inset.filled")
        }
        Settings {
            Form {
                // Controls that take a bare LocalizedStringKey look in Bundle.main; in a package,
                // always pass a Text built with bundle: .module (or #bundle).
                LabeledContent {
                    Text(AppInfo.current().version)
                } label: {
                    Text("Version", bundle: .module, comment: "Settings: app version row")
                }
                Text(CrannyCore.greeting)
            }
            .padding()
            .frame(width: 360)
        }
    }
}

#Preview("Notch") {
    NotchRootView(media: NowPlayingModel())
}
```

## A.23 `CrannyKit/Sources/CrannyMediaBridge/include/CrannyMediaBridge.h`

```c
// Public C interface of the media bridge dylib. Original code, MIT (Cranny).
#ifndef CRANNY_MEDIA_BRIDGE_H
#define CRANNY_MEDIA_BRIDGE_H

/// Entry point called by the perl launcher (installed as an XSUB; perl passes
/// (PerlInterpreter*, CV*) which we ignore). Prints one JSON line to stdout.
void cranny_bridge_main(void *interp, void *cv);

/// Version string, also used by `nm`/dlsym smoke tests.
const char *cranny_bridge_version(void);

#endif
```

## A.24 `CrannyKit/Sources/CrannyMediaBridge/CrannyMediaBridge.m`

```objc
// Trivial stand-in for the real media bridge: proves the dylib can be built by
// SwiftPM/Xcode, embedded in Cranny.app and loaded by Apple's /usr/bin/perl.
// Original code, MIT (Cranny).
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <unistd.h>
#include "CrannyMediaBridge.h"

#if !__has_feature(objc_arc)
#error "CrannyMediaBridge expects ARC"
#endif

const char *cranny_bridge_version(void) { return "cranny-bridge/0.1"; }

void cranny_bridge_main(void *interp, void *cv) {
    (void)interp; (void)cv;
    @autoreleasepool {
        char exe[4096] = {0};
        uint32_t size = sizeof(exe);
        _NSGetExecutablePath(exe, &size);
#if defined(__arm64__)
        NSString *arch = @"arm64";
#elif defined(__x86_64__)
        NSString *arch = @"x86_64";
#else
        NSString *arch = @"unknown";
#endif
        NSDictionary *msg = @{
            @"t": @"hello",
            @"version": @(cranny_bridge_version()),
            @"pid": @(getpid()),
            @"ppid": @(getppid()),
            @"host": @(exe),
            @"arch": arch,
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:msg options:NSJSONWritingSortedKeys error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}
```

Other PoC files (CrannyCore.swift, Diagnostics.swift, tests, the other catalogs, Assets/*.svg) are in the PoC folder.

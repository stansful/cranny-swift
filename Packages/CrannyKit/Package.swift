// swift-tools-version: 6.2
// CrannyKit — ALL Cranny code. The thin Xcode app target (Cranny.xcodeproj, folder App/)
// only contains @main, Info.plist, entitlements, the icon and the asset catalog.
//
// Layering (enforced by the dependency lists below — never add an edge that is not here):
//   L0  CrannyCore                      design system, contracts, settings, permissions, platform utils
//       CrannyMediaBridge (ObjC)        loaded by /usr/bin/perl at runtime, never imported by Swift
//   L1  feature modules + CrannyEffects depend on CrannyCore ONLY (never on each other);
//       CrannyEffects also compiles Metal shaders (Sources/CrannyEffects/Shaders)
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
/// CrannyEffects also owns Metal shaders: `Shaders/*.metal` compile into `default.metallib` inside its
/// resource bundle (needs the Metal Toolchain Xcode component; `scripts/lib.sh` checks for it).
func feature(_ name: String) -> Target {
    let resources: [Resource] = name == "CrannyEffects" ? [.process("Resources"), .process("Shaders")] : [.process("Resources")]
    return .target(name: name, dependencies: ["CrannyCore"], resources: resources,
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

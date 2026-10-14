# Metal + SwiftPM — verified 2026-10-14 (by the lead, after the user installed Metal Toolchain)

- `xcodebuild -showComponent MetalToolchain` → Status: installed; `xcrun metal -v` → Apple metal version 32023.921.
- PoC: scratchpad/poc/metal-spm (Package.swift tools 6.2, target `FX` with `resources: [.process("Shaders.metal")]`).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` uses the swift-build backend
  (outputs in `.build/out/Products/Debug`) and COMPILES the .metal file into
  `MetalPoC_FX.bundle/Contents/Resources/default.metallib`. Build OK.
- SwiftUI stitchable shaders: `#include <SwiftUI/SwiftUI_Metal.h>`, `[[ stitchable ]] half4 fn(float2 position, half4 color, float time)`;
  Swift side: `ShaderLibrary.bundle(.module).fn(.float(t))` → use with `.colorEffect` / `.layerEffect` / `.distortionEffect` (macOS 14+).
- Generated `Bundle.module` accessor (swift-build backend) checks, in order: env override (DEBUG only),
  `Bundle.main.resourceURL` (app bundles → Contents/Resources), `Bundle(for:).resourceURL` (frameworks),
  `Bundle.main.bundleURL` (CLI). → Bundle.module is SAFE inside Cranny.app; package resource bundles live in Contents/Resources.
- Consequence: CrannyEffects may ship Metal shaders (aurora/noise/glow/liquid) with SwiftUI fallbacks only for Reduce Motion / low power.

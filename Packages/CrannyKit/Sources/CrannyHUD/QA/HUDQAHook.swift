// CrannyHUD/QA/HUDQAHook.swift — DEBUG-only visual QA for the HUD, in the spirit of the shell's QAHooks
// (docs/CONTRIBUTING.md "Visual QA hooks"). Shows a HUD for an hour without any key, tap or device:
//
//   --qa-hud volume|muted|brightness|keyboard[:<level 0…1>]   e.g. --qa-hud volume:0.62
//   --qa-hud-fine        show the ⌥⇧ fine-step ticks
//   --qa-hud-device      show an output-device glyph (headphones) instead of the speaker
//
// Combine with the shell's `--qa-exit-after <s>` and `--qa-settings hud`. Compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation

nonisolated enum HUDQAHook {
    /// The display to show, or nil when `--qa-hud` is absent or malformed.
    static func display(arguments: [String]) -> HUDDisplay? {
        guard let value = LaunchArguments(arguments).value(after: "--qa-hud") else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let level = parts.count > 1 ? Double(parts[1]).map(LevelStepper.clamp) : nil
        var display: HUDDisplay
        switch parts.first {
        case "volume": display = HUDDisplay(kind: .volume, level: level ?? 0.62)
        case "muted": display = HUDDisplay(kind: .volume, level: level ?? 0.62, isMuted: true)
        case "brightness": display = HUDDisplay(kind: .brightness, level: level ?? 0.75)
        case "keyboard": display = HUDDisplay(kind: .keyboardBacklight, level: level ?? 0.4)
        default: return nil
        }
        display.showsFineTicks = arguments.contains("--qa-hud-fine")
        if arguments.contains("--qa-hud-device"), display.kind == .volume {
            display.deviceGlyph = "headphones"
        }
        return display
    }
}
#endif

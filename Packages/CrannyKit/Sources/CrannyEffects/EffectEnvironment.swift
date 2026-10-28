// CrannyEffects/EffectEnvironment.swift — what the moments tell the ambient light around them. First light and
// the song-change ripple wrap the ambient layer; they set these values and every ambient path (Metal layer,
// SwiftUI shader, fallback) applies them, so the moments work no matter who draws the light.
import CrannyCore
import Foundation
import SwiftUI

/// First light's reveal (DESIGN.md §5.6): the light shows inside a soft circle around `center`.
nonisolated struct AmbientReveal: Equatable, Sendable {
    /// Unit point in the ambient layer's bounds (the camera: `.top`).
    var center: UnitPoint
    /// Points; everything within `radius − feather` is lit, nothing beyond `radius`.
    var radius: CGFloat
    var feather: CGFloat

    /// The mask value at `distance` points from the centre (`cranny::revealMask`).
    func mask(atDistance distance: CGFloat) -> Double {
        1 - Easing.smoothstep(Double(radius - max(feather, 0.001)), Double(radius), Double(distance))
    }
}

extension EnvironmentValues {
    /// Set by `FirstLight` while it plays.
    @Entry var ambientReveal: AmbientReveal? = nil
    /// The date of the last song change, set by `songChangeRipple(_:)`.
    @Entry var ambientRippleStart: Date? = nil
    /// `.inline` keeps the ambient light inside SwiftUI (`ambientLightRendering(_:)`).
    @Entry var effectRendering: AmbientLightRendering = .automatic
}

public extension View {
    /// How the ambient light inside this view is drawn. The default, `.automatic`, uses a dedicated Metal layer that
    /// snapshots (`ImageRenderer`, `cacheDisplay`), `drawingGroup()` and shader effects over the light cannot see;
    /// `.inline` keeps the light in SwiftUI for them, at a higher CPU cost while it animates.
    func ambientLightRendering(_ rendering: AmbientLightRendering) -> some View {
        environment(\.effectRendering, rendering)
    }
}

/// Debug-only measurement switch: launching a Debug-flagged build with `-CrannyQAEffectsAlwaysOn YES` keeps the
/// ambient light running at full quality while the screen is locked, the panel is occluded, a full-screen app is in
/// front or Low Power Mode is on, so the light's cost can be measured on a locked test machine or one in use
/// (ARCHITECTURE.md §10.1, issue 1); add
/// `-CrannyQAEffectsOnBattery YES` to measure the battery rate (20 fps). Compiled out of Release builds; never changes
/// a system setting.
nonisolated enum EffectsQA {
    #if DEBUG
    static let keepsRunning = UserDefaults.standard.bool(forKey: "CrannyQAEffectsAlwaysOn")
    static let simulatesBattery = UserDefaults.standard.bool(forKey: "CrannyQAEffectsOnBattery")
    #else
    static let keepsRunning = false
    static let simulatesBattery = false
    #endif

    /// `budget` as if on screen, with no full-screen app in front and without Low Power (and on battery if asked)
    /// while the QA switch is set.
    static func adjusted(_ budget: EffectBudget) -> EffectBudget {
        guard keepsRunning else { return budget }
        var adjusted = budget
        adjusted.onScreen = true
        adjusted.fullScreenFront = false
        adjusted.lowPower = false
        adjusted.onBattery = adjusted.onBattery || simulatesBattery
        return adjusted
    }
}

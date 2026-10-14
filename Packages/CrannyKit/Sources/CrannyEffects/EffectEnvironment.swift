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
    /// `.inline` keeps the ambient light inside SwiftUI (tests, `ImageRenderer`).
    @Entry var effectRendering: EffectRendering = .automatic
}

/// Debug-only measurement switch: launching a Debug-flagged build with `-CrannyQAEffectsAlwaysOn YES` keeps the
/// ambient light running while the screen is locked or the panel is occluded, so CPU can be measured on a locked
/// machine (ARCHITECTURE.md §10.1, issue 1). Compiled out of Release builds.
nonisolated enum EffectsQA {
    #if DEBUG
    static let keepsRunning = UserDefaults.standard.bool(forKey: "CrannyQAEffectsAlwaysOn")
    #else
    static let keepsRunning = false
    #endif

    /// `budget` with `onScreen` forced on while the QA switch is set.
    static func adjusted(_ budget: EffectBudget) -> EffectBudget {
        guard keepsRunning else { return budget }
        var adjusted = budget
        adjusted.onScreen = true
        return adjusted
    }
}

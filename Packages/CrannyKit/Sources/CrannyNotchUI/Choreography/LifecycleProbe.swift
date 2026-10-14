// CrannyNotchUI/Choreography/LifecycleProbe.swift — a test seam for view identity. The canvas's long-lived
// views (the surface, the open panel, the light frame) report when they appear and disappear to an optional
// probe in the environment. Tests host the canvas and change its presentation: a view that disappears and
// appears again was re-created instead of updated, which breaks morphs, focus and VoiceOver (DESIGN.md §3.4,
// §4.3, §16). The app never sets a probe, so this costs one nil check per appearance.
import SwiftUI

/// Records `"<name>.appear"` / `"<name>.disappear"` events (tests only).
@MainActor final class NotchLifecycleProbe {
    private(set) var events: [String] = []

    func record(_ event: String) { events.append(event) }

    /// How many times `name` appeared.
    func appearances(of name: String) -> Int { events.filter { $0 == "\(name).appear" }.count }
    /// How many times `name` disappeared.
    func disappearances(of name: String) -> Int { events.filter { $0 == "\(name).disappear" }.count }
}

extension EnvironmentValues {
    /// Nil in the app; set by identity tests.
    @Entry var notchLifecycleProbe: NotchLifecycleProbe? = nil
}

private struct LifecycleReport: ViewModifier {
    @Environment(\.notchLifecycleProbe) private var probe
    let name: String

    func body(content: Content) -> some View {
        content
            .onAppear { probe?.record("\(name).appear") }
            .onDisappear { probe?.record("\(name).disappear") }
    }
}

extension View {
    /// Reports this view's appearances to the environment's `NotchLifecycleProbe`, if any.
    func lifecycleReport(_ name: String) -> some View { modifier(LifecycleReport(name: name)) }
}

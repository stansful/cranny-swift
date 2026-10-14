// CrannyMirror/Model/MirrorVisibility.swift — when a widget instance may run the camera and when the hover
// toolbar shows (pure rules, unit-tested).
import CrannyCore

nonisolated enum MirrorVisibility {
    /// Only a widget in the real open panel may run the camera: never on a Settings or onboarding stage, in a
    /// `#Preview` (`isPreview`), or while the layout is being edited (`isEditingLayout`: live content would
    /// fight the drag, ARCHITECTURE.md §3.5). Such instances never report themselves visible to the model.
    static func isLive(_ context: WidgetContext) -> Bool {
        !context.isPreview && !context.isEditingLayout
    }

    /// The flip and camera controls: only over live frames, and never hover-only (DESIGN.md §1 principle 7):
    /// pointer over the card, keyboard focus in the widget, or VoiceOver running.
    static func showsToolbar(isRunning: Bool, isHovered: Bool, isFocused: Bool, voiceOverRunning: Bool,
                             forced: Bool = false) -> Bool {
        isRunning && (isHovered || isFocused || voiceOverRunning || forced)
    }
}

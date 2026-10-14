// CrannyNotchUI/Compact/ActivityAccessibility.swift — every live activity is ONE VoiceOver element with a label,
// a value and named actions (DESIGN.md §16, ARCHITECTURE.md §9.5): its own `ActivityAction`s, then Open (or
// Show for the satellite) and Dismiss. The same element is used in compact, in a peek row, on the satellite
// and for the HUD in the open header.
import CrannyCore
import Foundation
import SwiftUI

struct ActivityAccessibility: ViewModifier {
    let activity: any LiveActivity
    let id: ActivityID
    let open: (@MainActor () -> Void)?
    let dismiss: (@MainActor () -> Void)?
    let openTitle: Text

    func body(content: Content) -> some View {
        let actions = activity.actions
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: activity.accessibilityLabel))
            // Always applied (an empty value reads nothing): a conditional modifier would re-create the row,
            // replaying the wings' entrance and dropping the activity views' state whenever the value comes or goes.
            .accessibilityValue(Text(verbatim: activity.accessibilityValue ?? ""))
            .accessibilityAddTraits(open == nil ? [] : .isButton)
            .accessibilityIdentifier("activity.\(id.rawValue)")
            .accessibilityAction { open?() }                              // VO-Space: the default action
            .accessibilityActions {
                ForEach(actions) { action in
                    Button { action.perform() } label: { Text(verbatim: action.title) }
                }
                if let open {
                    Button(action: open) { openTitle }
                }
                if let dismiss {
                    Button(action: dismiss) {
                        Text("Dismiss", bundle: .module,
                             comment: "Live activity: VoiceOver action that hides it until something changes")
                    }
                }
            }
    }
}

extension View {
    /// One VoiceOver element for `activity` (see `ActivityAccessibility`).
    func activityAccessibility(_ activity: any LiveActivity, id: ActivityID, open: (@MainActor () -> Void)?,
                               dismiss: (@MainActor () -> Void)?, openTitle: Text? = nil) -> some View {
        modifier(ActivityAccessibility(activity: activity, id: id, open: open, dismiss: dismiss,
                                       openTitle: openTitle ?? Text("Open", bundle: .module,
                                                                    comment: "Notch: VoiceOver action that opens the panel")))
    }
}

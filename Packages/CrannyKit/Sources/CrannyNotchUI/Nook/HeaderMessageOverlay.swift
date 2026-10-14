// CrannyNotchUI/Nook/HeaderMessageOverlay.swift — an activity's message in the open header (DESIGN.md §9.2,
// ARCHITECTURE.md §4.11–§4.12). While the panel is open, the wings and peeks are not drawn, so an activity that
// answers something the user just did there (the shell's Pause Live Activities and Resume confirmation; ⌘K always
// runs in the open panel) takes the header row for its lifetime, as the HUD does: its glyph left of the camera, its
// sentence right of it. The open shape never changes; the swap is `contentSwap`.
import CrannyCore
import SwiftUI

/// An activity that takes the open header while it has a message and is the primary or the scene's `headerActivity`
/// (the render contract, ARCHITECTURE.md §4.12). Its `compactLeading` sits left of the camera; right of it,
/// `headerMessage` when it fits on one line, else its `compactTrailing`. The tabs and actions come back when its
/// message goes, it ends or a HUD leads.
@MainActor public protocol OpenHeaderActivity: LiveActivity {
    /// The sentence for the open header; nil: the activity waits in the lineup while the panel is open, like any other.
    var headerMessage: String? { get }
}

/// What the open header shows instead of its tabs and actions.
enum HeaderTakeover {
    /// A HUD (P0): its wings around the camera (§10 "While the panel is open").
    case hud(ActivityID, any LiveActivity)
    /// An `OpenHeaderActivity` with a message.
    case message(ActivityID, any LiveActivity, String)

    /// A HUD as the primary first, then a message of the primary or of the owner's `headerActivity`. Nil: the
    /// header row (tabs, camera zone, actions).
    static func resolve(primary: (ActivityID, any LiveActivity)?,
                        header: (ActivityID, any LiveActivity)?) -> HeaderTakeover? {
        if let (id, activity) = primary, activity.priority == .hud { return .hud(id, activity) }
        for (id, activity) in [primary, header].compactMap({ $0 }) {
            if let notice = activity as? any OpenHeaderActivity, let message = notice.headerMessage, !message.isEmpty {
                return .message(id, activity, message)
            }
        }
        return nil
    }

    /// Changes when the header swaps (the animation's value).
    var key: String {
        switch self {
        case .hud(let id, _): "hud:\(id.rawValue)"
        case let .message(id, _, message): "message:\(id.rawValue):\(message)"
        }
    }
}

/// The message in the header row's zones (`HeaderRowLayout`): the glyph against the camera zone on the left, the
/// sentence (or the short word, when the sentence does not fit the side) against it on the right.
struct HeaderMessageOverlay: View {
    @Environment(\.cranny) private var theme
    let id: ActivityID
    let activity: any LiveActivity
    let message: String
    let layout: NotchLayout

    var body: some View {
        HeaderRowLayout {
            activity.view(for: .compactLeading)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: NookHeader.cameraZone(layout))         // never draw over the camera
            ViewThatFits(in: .horizontal) {
                Text(verbatim: message).crannyFont(.headline).lineLimit(1)
                activity.view(for: .compactTrailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(theme.palette.label)
        .activityAccessibility(activity, id: id, open: nil, dismiss: nil)
    }
}

#Preview("Confirmation in the open header") {
    let (model, registry) = previewScene(.open, headerMessage: PreviewConfirmation.sentence)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}

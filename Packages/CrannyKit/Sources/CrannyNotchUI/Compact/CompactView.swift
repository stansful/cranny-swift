// CrannyNotchUI/Compact/CompactView.swift — the primary live activity in the wings around the camera
// (DESIGN.md §9.1) and, in a peek, the same band row with 52-pt rows below it (§9.3). One view for both
// phases, so the band row keeps its identity when a peek grows out of it: its elements stay put and only
// the rows are new (§4.3 "Peek").
import CrannyCore
import SwiftUI

/// Compact and peek content: the band row, then the peek rows (peek only).
struct ActivityStack: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        VStack(spacing: 0) {
            CompactBand(model: model, registry: registry, actions: actions)
            if model.phase == .peek {
                PeekRows(model: model, registry: registry, actions: actions)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(theme.animation(.contentOut))))
            }
        }
        .offset(GestureFollow.contentOffset(model.gestureTranslation, phase: model.phase))
        .foregroundStyle(theme.palette.label)
    }
}

/// The band row: leading wing | camera (or the middle label) | trailing wing. Click opens the panel focused on
/// the activity's widget; the row is one VoiceOver element.
private struct CompactBand: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let layout = model.layout
        if let id = model.primary, let activity = model.activity(id, in: registry) {
            CompactRow(layout: layout, id: id, activity: activity, labelWidth: model.middleLabelWidth)
                .contentShape(Rectangle())
                .onTapGesture { actions.activityTapped(id) }
                .activityAccessibility(activity, id: id, open: { actions.activityTapped(id) },
                                       dismiss: { actions.dismissActivity(id) })
        } else {
            Color.clear.frame(height: layout.rowHeight).padding(.top, layout.rowInset)
        }
    }
}

/// One compact row. The wings swap with `crannySlot` when the activity changes (content grows out of the
/// camera edge 0.08 s after the shape starts, and leaves before it shrinks).
struct CompactRow: View {
    @Environment(\.cranny) private var theme
    let layout: NotchLayout
    let id: ActivityID
    let activity: any LiveActivity
    /// `NotchSceneModel.middleLabelWidth` (0 = no label).
    var labelWidth: CGFloat = 0

    var body: some View {
        let reduce = theme.reduceMotion
        let slotIn = theme.contentIn(after: ContentTiming.slotDelay - 0.06)
        CompactSlots(layout: layout, slot: activity.slot, label: labelWidth,
                     leading: {
                         activity.view(for: .compactLeading)
                             .id(id)
                             .transition(.asymmetric(insertion: .crannySlot(edge: .leading, reduceMotion: reduce).animation(slotIn),
                                                     removal: .opacity.animation(theme.animation(.contentOut))))
                     },
                     center: {
                         if labelWidth > 0, let label = activity.middleLabel, !layout.metrics.hasNotch {
                             MiddleLabel(text: label, width: labelWidth)
                         }
                     },
                     trailing: {
                         activity.view(for: .compactTrailing)
                             .id(id)
                             .transition(.asymmetric(insertion: .crannySlot(edge: .trailing, reduceMotion: reduce).animation(slotIn),
                                                     removal: .opacity.animation(theme.animation(.contentOut))))
                     })
            .foregroundStyle(theme.palette.label)
            .lineLimit(1)
    }
}

/// How a two-finger gesture in progress moves the content and the shape (DESIGN.md §4.4). The owner writes
/// the rubber-banded translation into `NotchSceneModel.gestureTranslation`; this maps it per phase (pure).
nonisolated enum GestureFollow {
    /// Compact and peek: horizontal swipes drag the content, a swipe up lifts it (dismiss).
    static func contentOffset(_ t: CGSize, phase: NotchPhase) -> CGSize {
        guard phase == .compact || phase == .peek else { return .zero }
        return CGSize(width: t.width, height: min(t.height, 0))
    }

    /// Closed and compact grow with a swipe down (open); the open shape follows a swipe up (close), ≤ 20 pt.
    static func heightChange(_ t: CGSize, phase: NotchPhase) -> CGFloat {
        switch phase {
        case .idle, .breath, .compact: max(t.height, 0)
        case .open: max(min(t.height, 0), -GestureSpec.verticalTravel)
        default: 0
        }
    }
}

#Preview("Compact · sample activity") {
    let (model, registry) = previewScene(.compact)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 480, height: 70)
        .background(Color(white: 0.25))
}

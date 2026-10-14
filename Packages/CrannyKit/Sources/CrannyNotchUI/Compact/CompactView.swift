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
            CompactRow(layout: layout, id: id, activity: activity, slot: model.primarySlot, labelWidth: model.middleLabelWidth)
                .contentShape(Rectangle())
                .onTapGesture { actions.activityTapped(id) }
                .activityAccessibility(activity, id: id, open: { actions.activityTapped(id) },
                                       dismiss: { actions.dismissActivity(id) })
        } else {
            Color.clear.frame(height: layout.rowHeight).padding(.top, layout.rowInset)
        }
    }
}

/// One compact row. Wing content grows out of the camera edge 0.08 s after the shape starts (`crannySlot`'s
/// look, played on appear so it also runs when the whole row appears) and leaves with `contentOut` before the
/// shape shrinks; a new activity swaps in the same way.
struct CompactRow: View {
    @Environment(\.cranny) private var theme
    let layout: NotchLayout
    let id: ActivityID
    let activity: any LiveActivity
    /// `NotchSceneModel.primarySlot`: the wings match the shape the owner asked for, even for a frame in
    /// which the activity's own `slot` has already changed.
    let slot: SlotWidth
    /// `NotchSceneModel.middleLabelWidth` (0 = no label).
    var labelWidth: CGFloat = 0

    var body: some View {
        let leaving = AnyTransition.crannyLeaving(theme)
        CompactSlots(layout: layout, slot: slot, label: labelWidth,
                     leading: {
                         activity.view(for: .compactLeading)
                             .slotReveal(edge: .leading)
                             .id(id)
                             .transition(leaving)
                     },
                     center: {
                         if labelWidth > 0, let label = activity.middleLabel, !layout.metrics.hasNotch {
                             MiddleLabel(text: label, width: labelWidth)
                         }
                     },
                     trailing: {
                         activity.view(for: .compactTrailing)
                             .slotReveal(edge: .trailing)
                             .id(id)
                             .transition(leaving)
                     })
            .foregroundStyle(theme.palette.label)
            .lineLimit(1)
    }
}

/// `crannySlot` played once on appear: scale 0.6 → 1 anchored on the camera side, blur 4 → 0, opacity 0 → 1,
/// 0.08 s after the shape starts (DESIGN.md §4.3 "Activity in"). Reduce Motion: opacity only.
struct SlotReveal: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.notchRendersFinalState) private var rendersFinalState
    @Environment(\.notchSlotRevealDelay) private var delay
    @State private var revealed = false
    let edge: HorizontalEdge

    func body(content: Content) -> some View {
        let shown = revealed || rendersFinalState
        let reduce = theme.reduceMotion
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading           // the camera side
        content
            .blur(radius: shown || reduce ? 0 : 4)
            .scaleEffect(shown || reduce ? 1 : 0.6, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !revealed else { return }
                if let animation = theme.contentIn(after: max(delay - ContentTiming.headerDelay, 0)) {
                    withAnimation(animation) { revealed = true }
                } else {
                    revealed = true
                }
            }
    }
}

extension EnvironmentValues {
    /// When wing content starts growing after a change of presentation: 0.08 s after the shape (activity in),
    /// 0.22 s when the panel closes back to compact (DESIGN.md §4.3 "Close"). Set by the canvas.
    @Entry var notchSlotRevealDelay: Double = ContentTiming.slotDelay
}

extension View {
    /// Wing content entering from the camera edge (see `SlotReveal`).
    func slotReveal(edge: HorizontalEdge) -> some View { modifier(SlotReveal(edge: edge)) }
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

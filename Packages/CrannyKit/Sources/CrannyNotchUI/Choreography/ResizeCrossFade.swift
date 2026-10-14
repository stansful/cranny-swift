// CrannyNotchUI/Choreography/ResizeCrossFade.swift — Reduce Motion's resize (DESIGN.md §4.2: open, close and
// resize "do not travel: old and new shapes cross-fade at their final sizes"). Open and close swap the whole
// surface (`ShapeMotion.crossFadeKey`), because their content changes anyway. A resize (a tab of another width,
// Notes focus, every step in the layout editor) must keep the open panel as the same view, or keyboard focus, a
// handle drag and the VoiceOver cursor are lost on each step. So the surface takes its new size at once and only
// its outline cross-fades: where just the old shape was, its fill fades out; where just the new shape is, the
// surface fades in; where both are, nothing changes.
import CrannyCore
import SwiftUI

/// The old outline of a resize in progress and how far the cross-fade has got (0 → 1, animated).
struct ResizeFade: Equatable {
    let id = UUID()
    var from: NotchGeometry
    var progress: Double = 0
}

/// The scene's target shape and phase, observed to start a cross-fade on an open → open resize.
struct ShapeTarget: Equatable {
    var phase: NotchPhase
    var geometry: NotchGeometry
}

/// Applied to the surface under Reduce Motion only. Toggling Reduce Motion changes the surface's key anyway
/// (`crossFadeKey`), so this switch never costs the surface its identity on a change of presentation; without
/// Reduce Motion the surface carries no mask (the light layer animates at up to 30 fps behind it).
struct ResizeCrossFade: ViewModifier {
    @Environment(\.cranny) private var theme
    let fade: ResizeFade?
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .mask(alignment: .top) {
                    // The new surface: fully visible where the old shape was, fading in everywhere else.
                    ZStack(alignment: .top) {
                        Color.white.opacity(fade?.progress ?? 1)
                        if let fade { NotchShape(fade.from).fill(Color.white) }
                    }
                }
                .background(alignment: .top) {
                    // The old shape, fading out where the new one does not cover it.
                    if let fade {
                        NotchShape(fade.from).fill(theme.palette.surface).opacity(1 - fade.progress)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            content
        }
    }
}

#Preview("Reduce Motion resize · halfway") {
    let (model, registry) = previewScene(.open)
    let from = model.layout.open(columns: 8)
    var theme = model.theme
    theme.reduceMotion = true
    model.theme = theme
    return NotchCanvasView(model: model, registry: registry)
        .modifier(ResizeCrossFade(fade: ResizeFade(from: from, progress: 0.5), isEnabled: true))
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}

// CrannyNotchUI/NotchCanvasView.swift — the root SwiftUI view of a notch panel or a preview stage.
// WP0 skeleton (ARCHITECTURE.md §10.1): idle/breath, compact via `CompactSlots` + `view(for:)`, peek rows and
// the open panel (header + grid of cards from `CoreSettings.pages`). WP12 grows every presentation.
//
// The view fills the FIXED canvas; the shape is top-centred and every state lays its content out at its
// final size, revealed by the animated clip (DESIGN.md §3, R1 §7.2). Only the scene's owner writes the model.
import CrannyCore
import CrannyEffects
import Foundation
import SwiftUI

/// Renders one `NotchSceneModel`: the notch shape and the presentation of its phase (idle, compact, peek,
/// open). Used by the shell's panels and by the Settings and onboarding stages.
public struct NotchCanvasView: View {
    @Namespace private var namespace
    private let model: NotchSceneModel
    private let registry: ModuleRegistry
    private let actions: NotchUIActions

    /// `actions` route taps and keys back to the scene's owner (the only writer of `model`).
    public init(model: NotchSceneModel, registry: ModuleRegistry, actions: NotchUIActions = NotchUIActions()) {
        self.model = model; self.registry = registry; self.actions = actions
    }

    public var body: some View {
        CanvasBody(model: model, registry: registry, actions: actions)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(.named(NotchCoordinateSpace.name))
            .environment(\.notchContext, model.context)
            .environment(\.notchNamespace, namespace)
            .environment(\.notchZones, model.zones)
            .crannyThemeRoot(model.theme)
    }
}

/// Inside the theme root, so the resolved theme (Reduce Motion, Increase Contrast …) drives the motion.
private struct CanvasBody: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let geometry = model.geometry
        let isOpen = model.phase == .open
        NotchSurface(geometry: geometry, band: model.layout.band,
                     openness: isOpen || model.phase == .peek ? 1 : 0,
                     elevation: model.phase == .peek ? Elevation.peek : Elevation.open,
                     underglow: isOpen && registry.services.settings[CoreSettings.underglow] ? model.ambient.glow1.color : nil) {
            content(geometry)
        }
        .opacity(surfaceOpacity)
        .animation(theme.animation(motion), value: model.phase)
        .animation(theme.animation(.resize), value: model.openColumns)
        .accessibilityAction(named: Text("Open", bundle: .module, comment: "VoiceOver action on the collapsed notch")) {
            actions.open()
        }
    }

    @ViewBuilder private func content(_ geometry: NotchGeometry) -> some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .idle, .breath:
            // Click target = the shape itself (the root view's hitTest limits AppKit to the same bounds).
            Color.clear
                .contentShape(NotchShape(geometry))
                .onTapGesture { actions.open() }
        case .compact:
            CompactView(model: model, registry: registry, actions: actions)
        case .peek:
            PeekView(model: model, registry: registry, actions: actions)
                .transition(.crannyContent(reduceMotion: theme.reduceMotion).animation(theme.animation(.contentIn)))
        case .open:
            NookView(model: model, registry: registry, actions: actions)
                .transition(.crannyContent(reduceMotion: theme.reduceMotion).animation(theme.animation(.contentIn)))
        }
    }

    /// The handle on displays without a notch can be "Hidden until hover" (alpha 0 = click-through).
    private var surfaceOpacity: Double {
        if model.phase == .hidden { return 0 }
        let hiddenHandle = !model.layout.metrics.hasNotch && model.phase == .idle
            && registry.services.settings[CoreSettings.handleVisibility] == .hiddenUntilHover
        return hiddenHandle ? 0 : 1
    }

    /// Geometry grows with bounce and lands without it (DESIGN.md §4.1).
    private var motion: CrannyMotion.Kind {
        switch model.phase {
        case .open: .open
        case .peek: .peekIn
        case .compact: .activityIn
        case .breath: .hoverIn
        case .idle, .hidden: .close
        }
    }
}

// MARK: - Previews (sample scenes: PreviewSupport.swift)

#Preview("Open · 14″ notch") {
    let (model, registry) = previewScene(.open)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: model.layout.canvasSize.height)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Compact · 14″ notch") {
    let (model, registry) = previewScene(.compact)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 80)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Closed · floating island") {
    let (model, registry) = previewScene(.idle, metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920))
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 80)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

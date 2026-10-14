// CrannyNotchUI/NotchCanvasView.swift — the root SwiftUI view of a notch panel or a preview stage.
//
// The view fills the FIXED canvas; the shape is top-centred and every state lays its content out at its
// final size, revealed by the animated clip (DESIGN.md §3, R1 §7.2). One spring moves the shape per change of
// presentation (`ShapeMotion`: grows with bounce, lands without); under Reduce Motion, open/close/resize
// cross-fade at their final sizes instead of travelling. Only the scene's owner writes the model; taps, keys
// and VoiceOver actions go back through `NotchUIActions`.
import CrannyCore
import CrannyEffects
import Foundation
import SwiftUI

/// Renders one `NotchSceneModel`: the notch shape and the presentation of its phase (idle, breath, compact,
/// peek, open). Used by the shell's panels and by the Settings and onboarding stages.
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
            .delightPlayer(moment: model.delight, serial: model.delightSerial)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(.named(NotchCoordinateSpace.name))
            .environment(\.notchContext, context)
            .environment(\.notchNamespace, namespace)
            .environment(\.notchZones, model.zones)
            .crannyThemeRoot(model.theme)
        #if DEBUG
            .task { await NotchUIQAHooks.writeSnapshot(model: model, registry: registry, actions: actions) }   // --qa-snapshot
        #endif
    }

    /// The owner's context with `phase` and `layout` always in step with what is drawn.
    private var context: NotchContext {
        var c = model.context
        c.phase = model.phase
        c.layout = model.layout
        if NotchUIQAHooks.showsHints { c.showsCommandHints = true }       // DEBUG-only visual QA
        return c
    }
}

/// Inside the theme root, so the resolved theme (Reduce Motion, Increase Contrast …) drives the motion.
private struct CanvasBody: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchDelight) private var delight
    @State private var previous: ShapeMotionState?
    @State private var gulp: CGFloat = 0
    @State private var resizeFade: ResizeFade?
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let current = ShapeMotionState(phase: model.phase, isHUD: primaryIsHUD)
        let kind = ShapeMotion.kind(from: previous ?? current, to: current)
        let base = CanvasGeometry.base(model)
        let shown = CanvasGeometry.adjusted(base, phase: model.phase, gesture: model.gestureTranslation, gulp: gulp)
        let key = ShapeMotion.crossFadeKey(phase: model.phase, reduceMotion: theme.reduceMotion)
        ZStack(alignment: .top) {
            surface(shown)
                .modifier(ResizeCrossFade(fade: resizeFade, isEnabled: theme.reduceMotion))
                .id(key)
                .transition(.opacity)
            // The shell writes `satellite` only while it shows (§4.7): beside the wings, or beside the closed shape
            // once the compact inactivity timeout has collapsed them (`.idle`).
            if model.phase == .compact || model.phase == .idle, let id = model.satellite,
               let activity = model.activity(id, in: registry) {
                SatelliteView(id: id, activity: activity, layout: model.layout, compact: shown, actions: actions,
                              budget: momentBudget)
                    .id(id)
                    .transition(.opacity.animation(theme.animation(.contentOut)))
            }
            // Timer done: CrannyEffects' ember burst fans out under the shape's bottom edge (one view per serial).
            if let delight, delight.moment == .emberBurst, DelightPlayback.isSeen(momentBudget) {
                EmberBurst(level: theme.effectiveAmbience, budget: momentBudget)
                    .id(delight.serial)
                    .offset(y: shown.bottom)
            }
        }
        .animation(ShapeMotion.animation(kind, theme: theme), value: base)
        .animation(model.gestureTranslation == .zero ? theme.animation(.snapBack) : nil, value: model.gestureTranslation)
        .opacity(surfaceOpacity)
        .animation(theme.animation(.contentSwap), value: surfaceOpacity)
        .modifier(GulpModifier(depth: $gulp))
        .environment(\.notchSlotRevealDelay, ContentTiming.slotDelay(after: kind))
        .onChange(of: current) { _, new in previous = new }
        .onChange(of: ShapeTarget(phase: model.phase, geometry: base)) { old, new in crossFadeResize(from: old, to: new) }
    }

    /// Reduce Motion: an open → open resize cross-fades the outlines (`ResizeCrossFade`) instead of travelling.
    private func crossFadeResize(from old: ShapeTarget, to new: ShapeTarget) {
        guard new.phase == .open else { resizeFade = nil; return }
        guard theme.reduceMotion, old.phase == .open, old.geometry != new.geometry,
              let animation = theme.animation(.resize) else { return }
        let fade = ResizeFade(from: old.geometry)
        resizeFade = fade
        withAnimation(animation) { resizeFade?.progress = 1 } completion: {
            if resizeFade?.id == fade.id { resizeFade = nil }
        }
    }

    // MARK: Surface

    private func surface(_ geometry: NotchGeometry) -> some View {
        let isOpen = model.phase == .open
        let expanded = isOpen || model.phase == .peek
        // The underglow (open only, DESIGN.md §5.1) stays in the surface in every phase at alpha 0, so it morphs
        // with the shape instead of being inserted at the open size.
        let underglow = registry.services.settings[CoreSettings.underglow] && theme.allowsUnderglow
        return NotchSurface(geometry: geometry, band: model.layout.band, openness: expanded ? 1 : 0,
                            elevation: model.phase == .peek ? Elevation.peek : Elevation.open,
                            keylineTint: keylineTint,
                            underglow: underglow ? model.ambient.glow1.color.opacity(isOpen ? 1 : 0) : nil) {
            ZStack(alignment: .top) {
                LightFrame(geometry: geometry) {
                    if isOpen && theme.effectiveAmbience != .off {
                        NookLightLayer(model: model, registry: registry)
                            .transition(.asymmetric(insertion: .opacity.animation(theme.animation(.ambientIn)),
                                                    removal: .opacity.animation(theme.animation(.ambientOut))))
                    }
                }
                content(geometry)
                rim(geometry)
            }
        }
        .lifecycleReport("surface")
        // NotchSurface is the VoiceOver container "Cranny"; collapsed it reads "Cranny, collapsed" + Open.
        .modifier(CollapsedAccessibility(isCollapsed: model.phase == .idle || model.phase == .breath, open: actions.open))
    }

    @ViewBuilder private func content(_ geometry: NotchGeometry) -> some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .idle, .breath:
            // Click target = the shape itself (the root view's hitTest limits AppKit to the same bounds).
            Color.clear
                .frame(width: geometry.outerWidth, height: geometry.bottom)
                .contentShape(NotchShape(geometry))
                .onTapGesture { actions.open() }
        case .compact, .peek:
            ActivityStack(model: model, registry: registry, actions: actions)
                .transition(.crannyLeaving(theme))
        case .open:
            NookView(model: model, registry: registry, actions: actions)
                .transition(.crannyLeaving(theme))
        }
    }

    /// The progress rim (Appearance ▸ Progress rim, Now Playing in compact) and the charge sweep.
    @ViewBuilder private func rim(_ geometry: NotchGeometry) -> some View {
        if let delight, delight.moment == .chargeSweep, model.phase == .compact || model.phase == .peek,
           DelightPlayback.isSeen(momentBudget) {
            ChargeSweepRim(geometry: geometry, budget: momentBudget)
                .id(delight.serial)
        } else if model.phase == .compact, model.primary == .nowPlaying, registry.services.settings[CoreSettings.progressRim],
                  let source = registry.services.nowPlaying {
            PlaybackRim(geometry: geometry, source: source, isOnScreen: budget.onScreen)
                .transition(.opacity.animation(theme.animation(.contentSwap)))
        }
    }

    // MARK: Derived

    private var primaryIsHUD: Bool {
        model.primary.flatMap { model.activity($0, in: registry) }?.priority == .hud
    }

    /// While music plays, the keyline takes the album accent (DESIGN.md §5.1).
    private var keylineTint: Color? {
        guard let source = registry.services.nowPlaying, source.nowPlaying?.isPlaying == true,
              let accent = source.palette?.accent else { return nil }
        return accent.legible(on: theme.palette.spec.cardOverBlack, ratio: theme.accentContrast).color
    }

    /// The energy budget of this canvas: on screen = not occluded (`isVisibleOnScreen`), not locked, displays awake.
    private var budget: EffectBudget {
        registry.services.environment.effectBudget(isOpen: model.phase != .hidden, isOnScreen: model.isVisibleOnScreen,
                                                   reduceMotion: false)
    }

    /// The budget of the one-shot moments drawn on the canvas (ember burst, charge sweep, satellite neck): their
    /// path (Reduce Motion, Calm and Instant draw the static variant, Low Power the SwiftUI design) and frame rate.
    private var momentBudget: EffectBudget {
        var moment = budget
        moment.reduceMotion = DelightPlayback.drawsReducedVariant(theme)
        return moment
    }

    /// Hidden = alpha 0 (click-through). The handle on displays without a notch may be "Hidden until hover".
    private var surfaceOpacity: Double {
        if model.phase == .hidden { return 0 }
        let hiddenHandle = !model.layout.metrics.hasNotch && model.phase == .idle
            && registry.services.settings[CoreSettings.handleVisibility] == .hiddenUntilHover
        return hiddenHandle ? 0 : 1
    }
}

/// The closed notch for VoiceOver: "Cranny, collapsed" with the action Open (DESIGN.md §16).
///
/// The modifiers are applied in every phase and only their values change: an `if` here would put the surface in
/// a different branch whenever the phase enters or leaves idle/breath, and SwiftUI would re-create it at its final
/// size instead of morphing it out of the camera (identity tests).
struct CollapsedAccessibility: ViewModifier {
    let isCollapsed: Bool
    let open: @MainActor () -> Void
    func body(content: Content) -> some View {
        content
            .accessibilityValue(isCollapsed
                ? Text("Collapsed", bundle: .module, comment: "Closed notch: VoiceOver value (\"Cranny, collapsed\")")
                : Text(verbatim: ""))
            .accessibilityActions {
                if isCollapsed {
                    Button(action: open) {
                        Text("Open", bundle: .module, comment: "Notch: VoiceOver action that opens the panel")
                    }
                }
            }
    }
}

/// The light layer's frame: the shape's body at its CURRENT size. The frame exists in every phase and animates
/// with the shape's spring, so the light, which is inserted only when the panel opens, starts at the size the
/// shape has at that moment and rides its bottom edge down (DESIGN.md §4.3 "backdrop sized to the current
/// shape"). An empty frame costs nothing while closed.
private struct LightFrame<Light: View>: View {
    let geometry: NotchGeometry
    @ViewBuilder let light: () -> Light

    var body: some View {
        Color.clear
            .frame(width: geometry.bodyWidth, height: max(geometry.height, 0))
            .overlay(alignment: .top) { light() }
            .padding(.top, geometry.topInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .lifecycleReport("light")
    }
}

/// The shape as drawn: the scene's geometry plus live direct manipulation (pure, unit-tested).
nonisolated enum CanvasGeometry {
    /// `NotchSceneModel.geometry`, except that a hidden notch keeps the closed shape (it fades to alpha 0
    /// rather than shrinking to nothing).
    @MainActor static func base(_ model: NotchSceneModel) -> NotchGeometry {
        model.phase == .hidden ? model.layout.closed : model.geometry
    }

    /// Adds the gesture's rubber band (swipe down grows closed/compact; the open shape follows a swipe up) and
    /// the gulp (height −3 pt).
    static func adjusted(_ base: NotchGeometry, phase: NotchPhase, gesture: CGSize, gulp: CGFloat) -> NotchGeometry {
        var g = base
        g.height = max(g.height + GestureFollow.heightChange(gesture, phase: phase) + gulp, 0)
        return g
    }
}

// MARK: - Previews (sample scenes: PreviewSupport.swift)

#Preview("Open · 14″ notch") {
    let (model, registry) = previewScene(.open)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: model.layout.canvasSize.height)
        .background(Color(white: 0.25))
}

#Preview("Compact · 14″ notch") {
    let (model, registry) = previewScene(.compact)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 480, height: 80)
        .background(Color(white: 0.25))
}

#Preview("Closed · floating island") {
    let (model, registry) = previewScene(.idle, metrics: PreviewDisplays.external)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 480, height: 60)
        .background(Color(white: 0.25))
}

// CrannyOnboarding/Stage/OnboardingStage.swift — the top half of the Welcome window (DESIGN.md §12.1): a dark
// desktop with the brand aurora, a miniature menu bar, and the REAL notch views (`NotchCanvasView`) rendering
// the stage's own scene. Closed and compact draw at 1:1; the open panel is scaled to fit, and the scale moves
// with the same spring as the shape. One `crannyThemeRoot` for the surface (DESIGN.md §2.0 rule 3). One light at a
// time: the desktop's aurora gives way to the open panel's own light layer (DESIGN.md §4.7).
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

struct OnboardingStage: View {
    let stage: StageScene
    let registry: ModuleRegistry
    /// Step 3 feeds two-finger scrolls over the stage to the practice notch.
    var onScroll: (@MainActor (ScrollSample) -> Void)?

    var body: some View {
        StageContent(stage: stage, registry: registry, onScroll: onScroll)
            .frame(width: stage.size.width, height: stage.size.height, alignment: .top)
            .clipped()
            .crannyThemeRoot(stage.model.theme)
    }
}

/// Inside the theme root, so Reduce Motion and the motion personality drive the stage's animations.
private struct StageContent: View {
    @Environment(\.cranny) private var theme
    let stage: StageScene
    let registry: ModuleRegistry
    let onScroll: (@MainActor (ScrollSample) -> Void)?

    var body: some View {
        let size = stage.size
        let scale = stage.scale
        let logical = CGSize(width: size.width / scale, height: size.height / scale)
        ZStack(alignment: .top) {
            StageBackdrop(level: StageBackdrop.level(theme: theme, panelDrawsLight: stage.phase == .open),
                          budget: registry.services.environment.effectBudget(
                            isOpen: true, isOnScreen: stage.isVisibleOnScreen,
                            reduceMotion: theme.reduceMotion || theme.motion == .instant))
            ZStack(alignment: .top) {
                StageMenuBar(band: stage.model.layout.band)
                NotchCanvasView(model: stage.model, registry: registry)
                    .allowsHitTesting(false)                    // a preview: nothing on the stage is a control
            }
            .frame(width: logical.width, height: logical.height, alignment: .top)
            .scaleEffect(scale, anchor: .top)
            .frame(width: size.width, height: size.height, alignment: .top)
            .animation(theme.animation(stage.model.phase == .open ? .open : .close), value: scale)
            .animation(theme.animation(.resize), value: size)
            if let onScroll {
                ScrollCatcher(onScroll: onScroll)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        switch stage.presentation {
        case .idle:
            String(localized: "Preview: Cranny, closed", bundle: .module, comment: "Welcome stage: VoiceOver description of the preview")
        case .greeting:
            String(localized: "Preview: Cranny says hi", bundle: .module, comment: "Welcome stage: VoiceOver description of the preview")
        case .open:
            String(localized: "Preview: Cranny, open with your layout", bundle: .module, comment: "Welcome stage: VoiceOver description of the preview")
        case .practice:
            String(localized: "Practice notch: swipe with two fingers on the trackpad", bundle: .module, comment: "Welcome stage: VoiceOver description of the gesture practice")
        }
    }
}

#Preview("Stage · open") {
    let registry = ModuleRegistry(services: .preview())
    let stage = StageScene(registry: registry, layout: NotchLayout(metrics: .reference), theme: CrannyTheme(),
                           ambient: .afterglow, greeting: "Hi")
    stage.show(.open, reduceMotion: true)
    return OnboardingStage(stage: stage, registry: registry)
}

#Preview("Stage · greeting, floating island") {
    let registry = ModuleRegistry(services: .preview())
    let metrics = NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)
    let stage = StageScene(registry: registry, layout: NotchLayout(metrics: metrics), theme: CrannyTheme(),
                           ambient: .afterglow, greeting: "Hi")
    stage.show(.greeting, reduceMotion: true)
    return OnboardingStage(stage: stage, registry: registry)
}

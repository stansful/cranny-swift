// CrannyAppShell/Overlay/PanelContentView.swift — what the panel's hosting view shows: NotchUI's canvas plus the
// shell's own layers on top of it — the enlarged drop zone while a file drag is in progress (an alpha-0.001 fill,
// so the window server routes the drag to the panel; R1 §4.1, removed when the drag ends) and the Notch fit
// calibration overlay. Both are drawn only while needed, so the rest of the canvas stays click-through.
import CrannyCore
import CrannyNotchUI
import Observation
import SwiftUI

/// The shell's per-panel layers (written by `NotchPanelController`).
@MainActor @Observable final class PanelChrome {
    /// Appearance ▸ Notch fit is being dragged.
    var calibrating = false
    /// The enlarged drop zone in canvas coordinates (top-left origin) while a file drag is in progress.
    var dropZone: CGRect?
}

struct PanelContentView: View {
    let scene: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions
    let chrome: PanelChrome

    var body: some View {
        ZStack(alignment: .topLeading) {
            NotchCanvasView(model: scene, registry: registry, actions: actions)
            if let zone = chrome.dropZone {
                // Not a colour: the smallest alpha the window server still counts as "drawn" (R1 §4.1).
                Rectangle()
                    .fill(.black.opacity(0.001))
                    .frame(width: zone.width, height: zone.height)
                    .offset(x: zone.minX, y: zone.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if chrome.calibrating {
                CalibrationOverlay(layout: scene.layout)
                    .crannyThemeRoot(scene.theme)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Panel · calibrating over the closed notch") {
    let registry = ModuleRegistry(services: .preview())
    let layout = NotchLayout(metrics: .reference)
    let scene = NotchSceneModel(layout: layout, theme: CrannyTheme())
    scene.phase = .breath
    let chrome = PanelChrome()
    chrome.calibrating = true
    return PanelContentView(scene: scene, registry: registry, actions: NotchUIActions(), chrome: chrome)
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .background(Color.black)
}

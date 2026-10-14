// CrannySettingsUI/Stage/PreviewStage.swift — the signature of Settings (DESIGN.md §11.2): a 176-pt band pinned at
// the top of every pane except Permissions and About, rendering the REAL notch views (`NotchCanvasView`) fed by the
// live settings over a miniature of the user's wallpaper and menu bar. Closed, compact, peek and HUD render at 1:1;
// the open Nook is scaled to fit, never below 0.75. Under it: the state picker, the Simulate chips and Show on Notch.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

struct PreviewStage: View {
    let controller: StageController
    let registry: ModuleRegistry
    @State private var isWindowVisible = true

    var body: some View {
        VStack(spacing: 0) {
            StageCanvas(controller: controller, registry: registry, isLive: isWindowVisible)
                .frame(height: SettingsMetrics.stageHeight)
            StageControlBar(controller: controller)
            Divider()
        }
        .background(WindowVisibilityReader { isWindowVisible = $0 || SettingsQAOptions.keepsStageLive })
        .onAppear {
            controller.start()
            if let chip = SettingsQAOptions.simulate { controller.simulate(chip) }     // Debug visual QA only
        }
        .onDisappear { controller.stop() }
        .onChange(of: isWindowVisible) { _, visible in
            if visible { controller.start() } else { controller.stop() }
        }
    }
}

/// Wallpaper, menu bar and the live notch, clipped to the band.
struct StageCanvas: View {
    let controller: StageController
    let registry: ModuleRegistry
    /// False while the window is hidden or covered: the live canvas (and its light layer clock) is removed.
    let isLive: Bool

    var body: some View {
        let model = controller.model
        GeometryReader { proxy in
            let scale = Self.scale(model: model, in: proxy.size)
            ZStack(alignment: .top) {
                WallpaperMiniature(miniature: controller.wallpaper)
                MenuBarMiniature(layout: model.layout, isLight: controller.wallpaper?.topIsLight ?? false)
                if controller.isOffOnDisplay {
                    OffNotice(displayName: controller.displayName)
                } else if isLive {
                    NotchCanvasView(model: model, registry: registry, actions: controller.actions)
                        .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Notch preview", bundle: .module, comment: "Settings preview stage: VoiceOver label"))
                        .accessibilityValue(Text(verbatim: StageControlBar.title(of: controller.state)))
                }
            }
        }
        .clipped()
    }

    /// 1:1 except the open Nook, which is scaled to fit the band (never below 0.75, §11.2).
    static func scale(model: NotchSceneModel, in size: CGSize) -> CGFloat {
        guard model.phase == .open, size.width > 0, size.height > 0 else { return 1 }
        let open = model.layout.open(columns: model.openColumns)
        let width = open.outerWidth + 2 * Space.xl
        let height = open.bottom + Space.s
        return max(min(1, size.width / width, size.height / height), SettingsMetrics.stageMinimumScale)
    }
}

/// Shown instead of the notch when Cranny is turned off on the display the stage imitates.
private struct OffNotice: View {
    let displayName: String?
    var body: some View {
        Text(displayName.map { String(localized: "Cranny is off on \($0).", bundle: .module,
                                      comment: "Settings preview stage: Cranny is turned off on this display; the argument is its name") }
             ?? String(localized: "Cranny is off on this display.", bundle: .module,
                       comment: "Settings preview stage: Cranny is turned off on the previewed display"))
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension StageController {
    /// The canvas's callbacks: tabs switch the shown page, a click on the notch opens it, edit mode (⌘E) toggles and
    /// a layout edited on the stage is saved. Nothing else acts.
    var actions: NotchUIActions {
        var actions = NotchUIActions()
        let settings = registry.services.settings
        actions.selectPage = { [weak self] page in self?.show(page: page) }
        actions.setMode = { [weak self] mode in self?.setOpenMode(mode) }
        actions.commitLayout = { pages in if settings[CoreSettings.pages] != pages { settings[CoreSettings.pages] = pages } }
        actions.open = { [weak self] in self?.select(.open) }
        actions.activityTapped = { [weak self] _ in self?.select(.open) }
        return actions
    }
}

#Preview("Stage · open") {
    let registry = ModuleRegistry(services: .preview())
    PreviewStage(controller: StageController(registry: registry, state: .open), registry: registry)
        .frame(width: 650)
}

#Preview("Stage · activity") {
    let registry = ModuleRegistry(services: .preview())
    PreviewStage(controller: StageController(registry: registry, state: .activity), registry: registry)
        .frame(width: 650)
}

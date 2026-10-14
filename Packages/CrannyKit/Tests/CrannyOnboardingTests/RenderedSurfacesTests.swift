// Renders the onboarding surfaces that are pure SwiftUI (the stage, preset miniatures, the tip bubble) and
// checks they actually draw. With CRANNY_RENDER_DIR set, the PNGs are written there for a visual check without
// launching the app (AppKit-backed controls such as menus and switches are not rendered by ImageRenderer).
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyOnboarding

@MainActor @Suite struct RenderedSurfacesTests {
    private func render(_ view: some View, name: String, scale: CGFloat = 2) -> NSImage? {
        let renderer = ImageRenderer(content: view.environment(\.isStaticSnapshot, true))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        if let directory = ProcessInfo.processInfo.environment["CRANNY_RENDER_DIR"], let cg = renderer.cgImage {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    @Test func theStageDrawsEveryPresentation() {
        let registry = makeRegistry()
        for (name, presentation) in [("stage-idle", StageScene.Presentation.idle), ("stage-greeting", .greeting), ("stage-open", .open)] {
            let stage = makeStage(registry)
            stage.show(presentation, reduceMotion: true)
            let image = render(OnboardingStage(stage: stage, registry: registry, isVisible: false), name: name)
            #expect(image?.size == WelcomeMetrics.stageSize)
        }
        let island = StageScene(registry: registry, layout: NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0,
                                                                                               bandHeight: 25, screenWidth: 1920)),
                                theme: CrannyTheme(), ambient: .afterglow, greeting: "Hi")
        island.show(.greeting, reduceMotion: true)
        #expect(render(OnboardingStage(stage: island, registry: registry, isVisible: false), name: "stage-island-greeting") != nil)
        island.show(.open, reduceMotion: true)
        #expect(render(OnboardingStage(stage: island, registry: registry, isVisible: false), name: "stage-island-open") != nil)
    }

    @Test func presetMiniaturesKeepTheirProportions() {
        let symbols: [WidgetID: String] = [.media: "music.note", .calendar: "calendar", .quickApps: "app.dashed",
                                           .notes: "note.text", .todos: "checklist", .timer: "timer", .mirror: "web.camera"]
        let scale = MiniPanel.scale(forWidth: 112)
        let row = HStack(spacing: Space.m) {
            ForEach(NookPreset.allCases, id: \.self) { MiniPanel(items: $0.items, symbols: symbols, scale: scale) }
        }
        .padding(Space.l)
        .background(Color.white)
        let image = render(row, name: "mini-panels", scale: 3)
        #expect((image?.size.width ?? 0) > 4 * 100)
    }

    @Test func theTipBubbleDraws() {
        let tips = VStack(spacing: Space.l) {
            TipBubble(content: TipContent(text: "Rest the pointer on the notch, or press", keys: "⌃⌥N", progress: "1 of 5",
                                          mark: .symbol("cursorarrow.motionlines"), actionTitle: "Skip tour"), onAction: {})
            TipBubble(content: TipContent(text: "Drag any file onto the notch", progress: "2 of 5", mark: .done,
                                          actionTitle: "Skip tour"), onAction: {})
            TipBubble(content: TipContent(text: "Rest the pointer here, or press", keys: "⌃⌥N"), onAction: {})
        }
        .padding(Space.huge)
        .background(BrandColor.graphite.color)
        .crannyThemeRoot(CrannyTheme())
        let image = render(tips, name: "tips")
        #expect((image?.size.width ?? 0) <= TipBubble.maximumWidth + 2 * Space.huge + 1)
    }

    @Test func stepsRender() {
        for step in WelcomeStep.allCases {
            let preview = WelcomePreview(step: step)
            #expect(render(WelcomeView(flow: preview.flow).environment(\.colorScheme, .light), name: "welcome-\(step.rawValue)") != nil)
        }
    }
}

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
        renderImage(view, name: name, scale: scale).map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale,
                                                                                            height: CGFloat($0.height) / scale)) }
    }

    private func renderImage(_ view: some View, name: String, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.isStaticSnapshot, true))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        if let directory = ProcessInfo.processInfo.environment["CRANNY_RENDER_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        return cg
    }

    @Test func theStageDrawsEveryPresentation() {
        let registry = makeRegistry()
        for (name, presentation) in [("stage-idle", StageScene.Presentation.idle), ("stage-greeting", .greeting), ("stage-open", .open)] {
            let stage = makeStage(registry)
            stage.show(presentation, reduceMotion: true)
            let image = render(OnboardingStage(stage: stage, registry: registry), name: name)
            #expect(image?.size == WelcomeMetrics.stageSize)
        }
        let island = StageScene(registry: registry, layout: NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0,
                                                                                               bandHeight: 25, screenWidth: 1920)),
                                theme: CrannyTheme(), ambient: .afterglow, greeting: "Hi")
        island.show(.greeting, reduceMotion: true)
        #expect(render(OnboardingStage(stage: island, registry: registry), name: "stage-island-greeting") != nil)
        island.show(.open, reduceMotion: true)
        #expect(render(OnboardingStage(stage: island, registry: registry), name: "stage-island-open") != nil)
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
        #expect(image?.size.width == TipBubble.width + 2 * Space.huge)
    }

    @Test func theTipPanelTakesTheBubblesSize() {
        let model = TipModel(content: TipContent(text: "Swipe sideways with two fingers to change the track and more words to wrap",
                                                 progress: "3 of 5", mark: .symbol("hand.draw.fill"), actionTitle: "Skip tour"))
        let hosting = TipHostingView(rootView: TipBubbleView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        let tour = hosting.intrinsicContentSize
        #expect(tour.width == TipBubble.width + 2 * TipBubble.shadowMargin)
        #expect(tour.height > 80 && tour.height < 200)               // wrapped onto two lines, not one word per line

        model.content = TipContent(text: "Click here, or press", keys: "⌃⌥N")
        hosting.layoutSubtreeIfNeeded()
        let coach = hosting.intrinsicContentSize
        #expect(coach.width < tour.width)                            // the coach mark hugs its single line
        #expect(coach.height < tour.height)

        let frame = TipPanelPresenter.frame(size: coach, under: CGRect(x: 1000, y: 1400, width: 200, height: 32))
        #expect(abs(frame.midX - 1100) <= 0.5)
        #expect(frame.maxY == 1400 - (WelcomeMetrics.tipGap - TipBubble.caretSize.height) + TipBubble.shadowMargin)
    }

    /// Every step draws the whole 640 × 480 window: the dark stage on top, at its height for the step, and the
    /// lower half on the (light) system background.
    @Test func everyStepDrawsTheWindowWithItsStage() throws {
        let scale: CGFloat = 2
        for step in WelcomeStep.allCases {
            let preview = WelcomePreview(step: step)
            let image = try #require(renderImage(WelcomeView(flow: preview.flow).environment(\.colorScheme, .light),
                                                 name: "welcome-\(step.rawValue)", scale: scale))
            #expect(CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) == WelcomeMetrics.window,
                    "\(step)")
            let pixels = try #require(Pixels(image, scale: scale))
            let stageHeight = WelcomeMetrics.stageHeight(for: step)
            #expect(pixels.luminance(at: CGPoint(x: 12, y: stageHeight + 40)) > 0.8, "\(step): the lower half is light")
            // ImageRenderer draws AppKit views as a placeholder: step 3's scroll catcher covers its stage.
            guard step != .gestures else { continue }
            #expect(pixels.luminance(at: CGPoint(x: 12, y: 90)) < 0.45, "\(step): the stage's desktop is dark")
            // Between the two stage heights: still stage on the tall steps, already the lower half on the short ones.
            let between = pixels.luminance(at: CGPoint(x: 12, y: (WelcomeMetrics.stageHeight + WelcomeMetrics.compactStageHeight) / 2))
            if stageHeight == WelcomeMetrics.stageHeight {
                #expect(between < 0.45, "\(step): full stage")
            } else {
                #expect(between > 0.8, "\(step): compact stage")
            }
        }
    }
}

/// Reads a rendered image back (sRGB, 8 bits per channel, the top row first).
private struct Pixels {
    private let bytes: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init?(_ image: CGImage, scale: CGFloat) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Mean relative luminance (0…1) of a 4 × 4-pt patch at `point` (points, from the top-left).
    func luminance(at point: CGPoint) -> Double {
        var total = 0.0
        var samples = 0
        for y in Int(point.y * scale)..<Int((point.y + 4) * scale) where y < height {
            for x in Int(point.x * scale)..<Int((point.x + 4) * scale) where x < width {
                let i = (y * width + x) * 4
                total += (0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])) / 255
                samples += 1
            }
        }
        return samples == 0 ? -1 : total / Double(samples)
    }
}

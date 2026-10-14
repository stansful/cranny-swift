// CrannyMedia/Visualizer/VisualizerBars.swift — the 5-bar visualizer as a SwiftUI view (compact trailing slot,
// the Media widget). Reads the mode from the engine and the colour from the theme accent (the album accent while
// media plays, DESIGN.md §2.1); draws through `VisualizerLayerView`, which asks for Live levels only when the bars
// can show them or feed the light (`VisualizerEngine.wantsLevels`). Decorative: hidden from VoiceOver.
import CrannyCore
import SwiftUI

struct VisualizerBars: View {
    @Environment(\.cranny) private var theme
    let engine: VisualizerEngine
    let isPlaying: Bool
    let trackKey: String?
    let metrics: VisualizerMetrics
    /// The Media widget's bars (open panel only): their Live tap also drives the light's loudness, so they keep it
    /// running while Reduce Motion rests them. Compact bars at rest need no tap.
    var feedsLight = false

    var body: some View {
        let reduceMotion = theme.reduceMotion || theme.motion == .instant
        let render = engine.render(isPlaying: isPlaying, trackKey: trackKey, reduceMotion: reduceMotion)
        if render != .hidden {
            VisualizerLayerView(configuration: VisualizerConfiguration(render: render, metrics: metrics, color: theme.accent,
                                                                       fps: engine.frameRateCap, reduceMotion: theme.reduceMotion,
                                                                       wantsLevels: engine.wantsLevels(reduceMotion: reduceMotion,
                                                                                                       feedsLight: feedsLight)),
                                engine: engine)
                .frame(width: metrics.width, height: metrics.maxHeight)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Visualizer · compact, playing and paused") {
    let service = SampleMedia.previewService()
    VStack(spacing: Space.l) {
        VisualizerBars(engine: service.visualizer, isPlaying: true, trackKey: "a", metrics: .compact(unit: 1))
        VisualizerBars(engine: service.visualizer, isPlaying: true, trackKey: "b", metrics: .widget)
        VisualizerBars(engine: service.visualizer, isPlaying: false, trackKey: "a", metrics: .compact(unit: 1))
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

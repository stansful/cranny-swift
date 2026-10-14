// CrannyMedia/Visualizer/VisualizerBars.swift — the 5-bar visualizer as a SwiftUI view (compact trailing slot,
// the Media widget). Reads the mode from the engine and the colour from the theme accent (the album accent while
// media plays, DESIGN.md §2.1); draws through `VisualizerLayerView`. Decorative: hidden from VoiceOver.
import CrannyCore
import SwiftUI

struct VisualizerBars: View {
    @Environment(\.cranny) private var theme
    let engine: VisualizerEngine
    let isPlaying: Bool
    let trackKey: String?
    let metrics: VisualizerMetrics

    var body: some View {
        let render = engine.render(isPlaying: isPlaying, trackKey: trackKey,
                                   reduceMotion: theme.reduceMotion || theme.motion == .instant)
        if render != .hidden {
            VisualizerLayerView(configuration: VisualizerConfiguration(render: render, metrics: metrics, color: theme.accent,
                                                                       fps: engine.frameRateCap, reduceMotion: theme.reduceMotion),
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

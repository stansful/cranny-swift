// CrannyMedia/UI/MediaWidget.swift — the Media widget (DESIGN.md §7.1, §6.7: 4–6 cells, default 5). Content only:
// CrannyNotchUI draws the card. States (§6.8): playing / paused, nothing playing (last source + Play or
// "Open Music"), loading (quiet ring after 300 ms), error (+ Retry), title only for read-only providers.
import CrannyCore
import Foundation
import SwiftUI

final class MediaWidget: NookWidget {
    let id: WidgetID = .media
    let symbol = "music.note"
    let sizes = WidgetSizes(minimum: 4, preferred: 5, maximum: 6)
    private let service: MediaService
    private let services: CrannyServices
    private var sample: MediaService?

    init(service: MediaService, services: CrannyServices) {
        self.service = service
        self.services = services
    }

    var title: String { MediaStrings.moduleName }
    var summary: String {
        String(localized: "What's playing, with controls", bundle: .module, comment: "Widget library: Media description")
    }

    func makeBody(context: WidgetContext) -> some View {
        MediaWidgetView(service: context.isPreview ? sampleService() : service, context: context,
                        haptics: context.isPreview ? nil : services.haptics, settings: services.settings)
    }

    /// Settings ▸ Layout & Widgets and the card's ⋯ menu.
    func makeOptions() -> some View {
        Toggle(isOn: services.settings.binding(MediaSettings.showsVisualizerInWidget)) {
            Text("Show the visualizer", bundle: .module, comment: "Media widget options: toggle")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    /// Stages and previews never touch the live service (ARCHITECTURE.md §3.5 `isPreview`).
    private func sampleService() -> MediaService {
        if let sample { return sample }
        let made = SampleMedia.service(settings: services.settings, environment: services.environment, permissions: services.permissions)
        sample = made
        return made
    }
}

struct MediaWidgetView: View {
    @Environment(\.cranny) private var theme
    let service: MediaService
    let context: WidgetContext
    let haptics: Haptics?
    let settings: SettingsStore

    var body: some View {
        Group {
            if let np = service.nowPlaying {
                MediaPlayingView(service: service, nowPlaying: np, context: context, haptics: haptics, settings: settings)
            } else {
                switch service.status {
                case .unavailable:
                    WidgetStateView(.error, symbol: "exclamationmark",
                                    message: MediaError.noProvider.errorDescription ?? MediaStrings.nothingPlaying,
                                    actionTitle: MediaStrings.retry) { service.restart() }
                case .starting, .restarting:
                    MediaLoadingView()
                case .idle, .running:
                    MediaEmptyView(service: service, iconSize: context.contentSize.height / 2)
                }
            }
        }
        .frame(width: context.contentSize.width, height: context.contentSize.height, alignment: .topLeading)
        .allowsHitTesting(!context.isEditingLayout)
        .onKeyPress(.space) { toggle(); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            Task { await service.send(press.key == .leftArrow ? .previousTrack : .nextTrack) }
            return .handled
        }
    }

    private func toggle() { Task { await service.send(.togglePlayPause) } }
}

/// Nothing playing: the last source's icon, one line and one action (DESIGN.md §7.1).
private struct MediaEmptyView: View {
    @Environment(\.cranny) private var theme
    let service: MediaService
    let iconSize: CGFloat

    var body: some View {
        let source = service.lastSourceBundleID ?? PlayerApps.music
        let resumable = service.lastSourceBundleID != nil && service.supportsCommands && PlayerApps.isRunning(source)
        HStack(spacing: Space.l) {
            Group {
                if let icon = PlayerApps.icon(for: source) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "music.note").font(.system(size: iconSize * 0.45, weight: .medium))
                        .foregroundStyle(theme.palette.secondaryLabel)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(verbatim: MediaStrings.nothingPlaying)
                    .crannyFont(.callout).foregroundStyle(theme.palette.secondaryLabel)
                if resumable {
                    Button { Task { await service.send(.play) } } label: {
                        Label { Text(verbatim: MediaStrings.play) } icon: { Image(systemName: "play.fill") }
                    }
                    .buttonStyle(CrannyChipButtonStyle(prominent: true))
                } else if PlayerApps.url(for: source) != nil {
                    Button { PlayerApps.open(source) } label: {
                        Text(verbatim: Self.openTitle(PlayerApps.name(for: source)))
                            .crannyFont(.caption).fontWeight(.semibold)
                            .foregroundStyle(theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    static func openTitle(_ app: String) -> String {
        String(localized: "Open \(app)", bundle: .module, comment: "Media widget: empty-state text button that launches the player; argument is its name")
    }
}

/// Longer than 300 ms without a snapshot: a quiet 2.5-pt ring (DESIGN.md §6.8).
private struct MediaLoadingView: View {
    @Environment(\.cranny) private var theme
    @State private var visible = false

    var body: some View {
        ProgressRing(progress: 0.25, color: theme.palette.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
            .frame(width: 18, height: 18)
            .opacity(visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                visible = true
            }
            .accessibilityHidden(!visible)
    }
}

// MARK: - Previews

#Preview("Media widget · 4, 5, 6 cells") {
    let service = SampleMedia.previewService()
    let grid = NookGrid()
    VStack(spacing: Space.l) {
        ForEach([4, 5, 6], id: \.self) { cells in
            MediaWidgetView(service: service, context: WidgetContext(
                cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 24, height: grid.height - 24)),
                haptics: nil, settings: service.settings)
                .crannyCard(cells: cells)
        }
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Media widget · nothing playing") {
    let services = CrannyServices.preview()
    let service = MediaService(settings: services.settings, environment: services.environment,
                               permissions: services.permissions, providers: [])
    MediaWidgetView(service: service, context: WidgetContext(cells: 5, contentSize: CGSize(width: 288, height: 96)),
                    haptics: nil, settings: services.settings)
        .crannyCard(cells: 5)
        .padding(Space.xxl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

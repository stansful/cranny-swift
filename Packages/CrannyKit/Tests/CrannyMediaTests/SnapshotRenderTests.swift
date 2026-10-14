// Opt-in visual QA: renders the Media widget, the Now Playing presentations and their states to PNG files with
// `ImageRenderer`, for a human (or a reviewer) to look at. Runs only with
//   CRANNY_SNAPSHOT_DIR=/some/dir swift test --scratch-path .build-test --filter CrannyMediaTests.SnapshotRenderTests
// (into /some/dir/Media).
// Core Animation bars (an NSView) do not render here; the app shows them (`--qa-media playing`).
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyMedia

@Suite("Snapshot render", .enabled(if: SnapshotOutput.directory("Media") != nil))
@MainActor struct SnapshotRenderTests {
    private var directory: URL {
        SnapshotOutput.directory("Media") ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
    }

    private func write(_ name: String, scale: CGFloat = 2, _ view: some View) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "\(name).png"))
    }

    private func widget(_ service: MediaService, cells: Int, theme: CrannyTheme = CrannyTheme()) -> some View {
        let grid = theme.grid
        let pad = grid.density.cardPadding
        return MediaWidgetView(service: service, context: WidgetContext(
            cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * pad, height: grid.height - 2 * pad)),
            haptics: nil, settings: service.settings)
            .crannyCard(cells: cells)
            .padding(Space.l)
            .background(Color.black)
            .crannyThemeRoot(theme)
    }

    @Test func widgetSizesAndStates() throws {
        let playing = SampleMedia.previewService()
        for cells in [4, 5, 6] { try write("widget-\(cells)-playing", widget(playing, cells: cells)) }
        try write("widget-5-paused", widget(SampleMedia.previewService(playing: false), cells: 5))

        let services = CrannyServices.preview()
        let noArt = MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions, providers: [])
        var np = SampleMedia.nowPlaying()
        np.title = "A rather long track title that will not fit in the card"
        noArt.seed(np, artwork: nil)
        try write("widget-5-no-artwork-long-title", widget(noArt, cells: 5))

        let empty = MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions, providers: [])
        try write("widget-5-nothing-playing", widget(empty, cells: 5))

        var large = CrannyTheme()
        large.textSize = .extraLarge
        try write("widget-5-xl-text", widget(playing, cells: 5, theme: large))
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        try write("widget-5-increase-contrast", widget(playing, cells: 5, theme: contrast))
        // Right to left (Arabic, Hebrew): the card is mirrored, the transport and the scrubber are not.
        for cells in [4, 6] {
            try write("widget-\(cells)-playing-rtl", widget(playing, cells: cells).environment(\.layoutDirection, .rightToLeft))
        }
    }

    @Test func nowPlayingPresentations() throws {
        let service = SampleMedia.previewService()
        let activity = NowPlayingActivity(service: service, settings: service.settings, open: { _ in })
        let layout = NotchLayout(metrics: .reference)
        let compact = layout.compact(.short)
        try write("compact", scale: 3, CompactSlots(layout: layout, slot: activity.slot,
                                                     leading: { activity.compactLeading() }, center: { EmptyView() },
                                                     trailing: { activity.compactTrailing() })
            .frame(width: compact.bodyWidth)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: compact.bottomRadius, bottomTrailingRadius: compact.bottomRadius,
                                               style: .continuous).fill(Color.black))
            .padding(Space.l)
            .background(Color(white: 0.85))
            .crannyThemeRoot(CrannyTheme()))
        let peek = layout.peek()
        try write("peek-row", activity.peekRow()
            .padding(.horizontal, Space.l)
            .frame(width: peek.bodyWidth, height: NotchLayout.peekRow)
            .background(Color.black)
            .padding(Space.l)
            .background(Color(white: 0.2))
            .crannyThemeRoot(CrannyTheme()))
        try write("satellite", scale: 4, activity.minimal()
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black))
            .padding(Space.s)
            .background(Color(white: 0.85))
            .crannyThemeRoot(CrannyTheme()))
    }
}

// CrannyMirror/UI/MirrorWidget.swift — the frameless Mirror widget (DESIGN.md §7.4, 2–3 cells): the dark "Preview
// camera" card, and after one click the camera filling the card, mirrored, with a hover toolbar.
import CrannyCore
import SwiftUI

final class MirrorWidget: NookWidget {
    let model: MirrorModel
    init(model: MirrorModel) { self.model = model }

    let id: WidgetID = .mirror
    var title: String { MirrorCopy.widgetTitle }
    let symbol = MirrorSymbol.camera
    var summary: String { MirrorCopy.widgetSummary }
    /// 2 cells (120 × 120) by default; 3 gives a wider preview (DESIGN.md §6.7).
    let sizes = WidgetSizes(minimum: 2, preferred: 2, maximum: 3)
    /// The preview IS the card: no padding, no smoked fill (the widget draws its own backdrop and hairline).
    var isFrameless: Bool { true }

    func makeBody(context: WidgetContext) -> some View { MirrorWidgetView(model: model, context: context) }
    func makeOptions() -> some View { MirrorOptionsView(model: model) }
}

/// Keyboard focus inside the widget: the card itself, or one of the toolbar buttons.
enum MirrorFocus: Hashable { case card, flip, camera }

struct MirrorWidgetView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let model: MirrorModel
    let context: WidgetContext
    @State private var viewID = UUID()
    @State private var isHovered = false
    @FocusState private var focus: MirrorFocus?

    private var isLive: Bool { MirrorVisibility.isLive(context) }

    var body: some View {
        let presentation = model.presentation(isLive: isLive)
        let showsToolbar = MirrorVisibility.showsToolbar(
            isRunning: presentation.showsFeed, isHovered: isHovered, isFocused: focus != nil || context.isFocused,
            voiceOverRunning: theme.voiceOverRunning, forced: forcesToolbar)
        ZStack(alignment: .topTrailing) {
            MirrorBackdrop(isLit: isHovered && presentation.action != nil && !presentation.showsFeed)
            if presentation.showsFeed, let feed = model.feed {
                MirrorFeedView(feed: feed, isMirrored: model.isMirrored)
                    .transition(.opacity)
            } else {
                MirrorPlaceholderView(presentation: presentation, isHovered: isHovered)
                    .accessibilityHidden(true)                  // the card button below speaks for it
                    .transition(.opacity)
            }
            cardButton(presentation)
            if presentation.showsFeed {
                MirrorToolbar(model: model, focus: $focus)
                    .opacity(showsToolbar ? 1 : 0)
                    .allowsHitTesting(showsToolbar)
                    .accessibilityHidden(!showsToolbar)
            }
        }
        .overlay { edge }
        .onHover { isHovered = $0 }
        .animation(theme.animation(presentation.showsFeed ? .contentIn : .contentOut), value: presentation.showsFeed)
        .animation(theme.animation(.hover), value: showsToolbar)
        // The model decides what counts as visible (only a live context, `MirrorModel.viewAppeared`).
        .onAppear { model.viewAppeared(viewID, context: context) }
        .onDisappear { model.viewDisappeared(viewID) }
        .onChange(of: isLive) { model.viewAppeared(viewID, context: context) }
    }

    /// The whole card is one button (Fitts: the largest possible target), and one VoiceOver element:
    /// "Camera preview, on". Its chip, if any, is only the visual cue for this click.
    private func cardButton(_ presentation: MirrorPresentation) -> some View {
        Button {
            Task { await model.tap() }
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLive || presentation.action == nil)
        .focused($focus, equals: .card)
        .focusEffectDisabled()
        .accessibilityLabel(Text(verbatim: MirrorCopy.previewLabel))
        .accessibilityValue(Text(verbatim: presentation.accessibilityValue))
        .accessibilityHint(Text(verbatim: presentation.accessibilityHint ?? ""))
        .accessibilityAddTraits(presentation.action == .turnOn || presentation.action == .turnOff ? .isToggle : [])
    }

    /// A 1-px hairline keeps the edge crisp over dark frames; the focus ring is inset (the card clips outsets).
    private var edge: some View {
        let p = theme.palette
        return ZStack {
            ContainerRelativeShape()
                .strokeBorder(p.hairline, lineWidth: theme.increaseContrast ? StrokeWidth.regular : StrokeWidth.hairline(displayScale))
            ContainerRelativeShape()
                .strokeBorder(theme.accentColor, lineWidth: StrokeWidth.focus)
                .opacity(focus == .card ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var forcesToolbar: Bool {
        #if DEBUG
        model.showsToolbarForQA
        #else
        false
        #endif
    }
}

// MARK: - Previews (sample parts only: previews never start a camera)

#Preview("Mirror · off, running, 3 cells") {
    let live = WidgetContext(cells: 2, contentSize: CGSize(width: 120, height: 120))
    HStack(spacing: Space.m) {
        MirrorWidgetView(model: .preview(), context: live)
            .crannyCard(cells: 2, frameless: true)
        MirrorWidgetView(model: .preview(phase: .running(deviceID: "sample.builtIn")), context: live)
            .crannyCard(cells: 2, frameless: true)
        MirrorWidgetView(model: .preview(phase: .running(deviceID: "sample.builtIn")),
                         context: WidgetContext(cells: 3, contentSize: CGSize(width: 184, height: 120)))
            .crannyCard(cells: 3, frameless: true)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Mirror · needs access, lid closed, no camera") {
    let live = WidgetContext(cells: 2, contentSize: CGSize(width: 120, height: 120))
    HStack(spacing: Space.m) {
        MirrorWidgetView(model: .preview(authorization: .denied), context: live)
            .crannyCard(cells: 2, frameless: true)
        MirrorWidgetView(model: .preview(cameras: SampleCameraDiscovery.lidClosed), context: live)
            .crannyCard(cells: 2, frameless: true)
        MirrorWidgetView(model: .preview(cameras: SampleCameraDiscovery.none), context: live)
            .crannyCard(cells: 2, frameless: true)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Mirror · Settings stage (isPreview)") {
    MirrorWidgetView(model: .preview(phase: .running(deviceID: "sample.builtIn")),
                     context: WidgetContext(cells: 2, contentSize: CGSize(width: 120, height: 120), isPreview: true))
        .crannyCard(cells: 2, frameless: true)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

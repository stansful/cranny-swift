// CrannyMirror/UI/MirrorPlaceholderView.swift — the card whenever no frames show: the dark backdrop with
// `web.camera` and one caption (DESIGN.md §7.4 "Off"), and the same layout for every other state (§6.8).
import CrannyCore
import SwiftUI

/// Widget-specific measures from DESIGN.md §7.4 that have no general token.
enum MirrorMetrics {
    /// `web.camera` in the off state: 22 pt (DESIGN.md §7.4, §14.1).
    static let glyph: CGFloat = 22
    /// The loading ring replaces the glyph at the same optical size.
    static let ring: CGFloat = 18
    /// Hover toolbar: 24-pt circles (DESIGN.md §7.4) inside a hit target of `HitTarget.preferred`.
    static let toolbarCircle: CGFloat = 24
    /// Circle inset from the card edge: card radius 20 − circle radius 12 keeps the corner concentric.
    static let toolbarInset: CGFloat = Space.m
    /// Radius of the backdrop's soft light behind the glyph.
    static let backdropGlow: CGFloat = 72
    /// The chip under a message: the height of `CrannyChipButtonStyle` (the chip is drawn, the card is the button).
    static let chipHeight: CGFloat = 22
}

/// The dark gradient behind every non-live state: a smoked card, a touch lighter at the top, with soft light
/// behind the glyph that brightens while the pointer is over a clickable card (a fill change only, §6.8).
struct MirrorBackdrop: View {
    @Environment(\.cranny) private var theme
    var isLit = false

    var body: some View {
        let p = theme.palette
        ZStack {
            p.surface
            LinearGradient(colors: [p.cardHover, p.card], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [isLit ? p.control : p.well, p.well.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: MirrorMetrics.backdropGlow)
        }
        .animation(theme.animation(.hover), value: isLit)
        .accessibilityHidden(true)
    }
}

/// Glyph, caption, optional second line and chip, centred in the card.
struct MirrorPlaceholderView: View {
    @Environment(\.cranny) private var theme
    let presentation: MirrorPresentation
    var isHovered = false
    @State private var showsRing = false

    var body: some View {
        let p = theme.palette
        let emphasized = isHovered && presentation.action != nil
        VStack(spacing: Space.s) {
            glyph
                .frame(height: MirrorMetrics.glyph)
            VStack(spacing: Space.xxs) {
                Text(verbatim: presentation.message)
                    .crannyFont(.caption)
                    .foregroundStyle(emphasized ? p.label : p.secondaryLabel)
                if let detail = presentation.detail {
                    Text(verbatim: detail)
                        .crannyFont(.caption)
                        .foregroundStyle(p.tertiaryLabel)
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            if let title = presentation.actionTitle {
                Text(verbatim: title)
                    .crannyFont(.caption).fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(p.label)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: MirrorMetrics.chipHeight)
                    .background(Capsule(style: .continuous).fill(isHovered ? p.controlHover : p.control))
                    .padding(.top, Space.xxs)
            }
        }
        .padding(theme.grid.density.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(theme.animation(.hover), value: emphasized)
        // Loading: nothing for 300 ms, then the ring (DESIGN.md §6.8). One sleep, no timer.
        .task(id: presentation.glyph) {
            showsRing = false
            guard presentation.glyph == .loading else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { showsRing = true }
        }
    }

    @ViewBuilder private var glyph: some View {
        let p = theme.palette
        if presentation.glyph == .loading && showsRing {
            ProgressRing(progress: 0.25, color: p.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
                .frame(width: MirrorMetrics.ring, height: MirrorMetrics.ring)
                .transition(.opacity)
        } else {
            Image(systemName: MirrorSymbol.camera)
                .font(.system(size: MirrorMetrics.glyph, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(presentation.glyph == .problem ? p.danger
                                 : isHovered && presentation.action != nil ? p.label : p.secondaryLabel)
                .transition(.opacity)
        }
    }
}

// MARK: - Previews

#Preview("Placeholder states · 2 cells") {
    let states: [MirrorPresentation] = [
        MirrorPresentation(message: MirrorCopy.previewCamera, action: .turnOn),
        MirrorPresentation(message: MirrorCopy.accessOff, actionTitle: MirrorCopy.openSettings, action: .openSettings),
        MirrorPresentation(message: MirrorCopy.unavailable, detail: MirrorCopy.lidClosed),
        MirrorPresentation(glyph: .problem, message: MirrorCopy.stopped, actionTitle: MirrorCopy.tryAgain, action: .turnOn),
    ]
    HStack(spacing: Space.m) {
        ForEach(states.indices, id: \.self) { i in
            ZStack {
                MirrorBackdrop()
                MirrorPlaceholderView(presentation: states[i])
            }
            .crannyCard(cells: 2, frameless: true)
        }
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Placeholder · hovered, 3 cells") {
    ZStack {
        MirrorBackdrop(isLit: true)
        MirrorPlaceholderView(presentation: MirrorPresentation(message: MirrorCopy.previewCamera, action: .turnOn), isHovered: true)
    }
    .crannyCard(cells: 3, frameless: true)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

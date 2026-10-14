// CrannyNotchUI/Nook/NookHeader.swift — the header row in the band (DESIGN.md §6.2): page tabs left of the
// camera, the camera zone (N + 16) kept empty — time and date on displays without a notch — and the actions
// on the right: ⌕ palette (⌘K), 📌 pin (⌘P), ⚙︎ Settings (⌘,). While a HUD is the primary activity, its views
// take the row instead, around the camera (§10 "While the panel is open", ARCHITECTURE.md §4.11); so does an
// `OpenHeaderActivity` with a message (the Pause Live Activities confirmation, §9.2).
import CrannyCore
import Foundation
import SwiftUI

struct NookHeader: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions
    /// Tab clicks (NookView sets the slide direction first).
    let select: @MainActor (PageID) -> Void
    let perform: @MainActor (NookCommand) -> Void

    var body: some View {
        let takeover = takeover
        ZStack {
            switch takeover {
            case let .hud(id, activity):
                HUDHeaderOverlay(id: id, activity: activity, layout: model.layout, actions: actions)
                    .transition(swap)
            case let .message(id, activity, message):
                HeaderMessageOverlay(id: id, activity: activity, message: message, layout: model.layout)
                    .transition(swap)
            case nil:
                row.transition(swap)
            }
        }
        .animation(theme.animation(.contentSwap), value: takeover?.key)
    }

    /// `contentSwap` with `.blurReplace` (opacity only under Reduce Motion).
    private var swap: AnyTransition {
        (theme.reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace)).animation(theme.animation(.contentSwap))
    }

    private var row: some View {
        let layout = model.layout
        return HeaderRowLayout {
            HeaderTabsView(tabs: tabs, selected: model.open?.page ?? .nook, select: select)
                .frame(maxWidth: .infinity, alignment: .leading)
            if layout.metrics.hasNotch {
                Color.clear.frame(width: NookHeader.cameraZone(layout))         // never draw over the camera
            } else {
                MinuteClock().fixedSize().padding(.horizontal, Space.m)
            }
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// The actions, or the layout editor's bar while editing a grid page.
    @ViewBuilder private var trailing: some View {
        let page = registry.services.settings[CoreSettings.pages].first { $0.id == model.open?.page }
        if model.open?.mode == .editLayout, let page {
            EditLayoutBar(page: page, model: model, registry: registry, actions: actions)
                .transition(swap)
        } else {
            buttons.transition(swap)
        }
    }

    /// The camera housing plus 8 pt each side (DESIGN.md §6.2).
    static func cameraZone(_ layout: NotchLayout) -> CGFloat { layout.middle() + 2 * Space.m }

    private var tabs: [HeaderTab] {
        HeaderTabItems.make(pages: registry.services.settings[CoreSettings.pages], modulePages: registry.pages)
    }

    /// What takes the row: a HUD as the primary (P0), else the primary or the owner's `headerActivity` with a message.
    private var takeover: HeaderTakeover? {
        func lookup(_ id: ActivityID?) -> (ActivityID, any LiveActivity)? {
            id.flatMap { id in model.activity(id, in: registry).map { (id, $0) } }
        }
        return HeaderTakeover.resolve(primary: lookup(model.primary), header: lookup(model.headerActivity))
    }

    // MARK: Actions

    private var buttons: some View {
        let mode = model.open?.mode ?? .grid
        return HStack(spacing: 0) {
            HeaderButton(symbol: "magnifyingglass", isOn: mode == .palette, shortcut: NookKeyMap.palette,
                         label: String(localized: "Command palette", bundle: .module, comment: "Open panel: header button (⌘K)")) {
                perform(.togglePalette)
            }
            HeaderButton(symbol: model.pinned ? "pin.fill" : "pin", isOn: model.pinned, shortcut: NookKeyMap.pin,
                         label: String(localized: "Keep Cranny open", bundle: .module, comment: "Open panel: pin button (⌘P)")) {
                perform(.togglePin)
            }
            HeaderButton(symbol: "gearshape.fill", isOn: false, shortcut: NookKeyMap.settings,
                         label: String(localized: "Settings", bundle: .module, comment: "Open panel: header button (⌘,)")) {
                perform(.openSettings)
            }
        }
    }
}

/// The header row: leading zone | centre | trailing zone, with the centre (the camera zone N + 16, or the clock)
/// exactly in the middle. Both sides get exactly (width − centre) / 2, whatever their content asks for, so wide
/// tabs (Russian, XL text, five pages at the header's minimum width) can never push the camera zone sideways
/// and slide a tab under the housing; the tabs collapse instead (`HeaderTabsView`).
struct HeaderRowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? ideal.reduce(0) { $0 + $1.width },
                      height: proposal.height ?? ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let centre = subviews[1].sizeThatFits(.unspecified).width
        let side = HeaderRowLayout.sideWidth(width: bounds.width, centre: centre)
        let height = ProposedViewSize(width: side, height: bounds.height)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: height)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: centre, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: height)
    }

    /// Width of each side zone (pure).
    nonisolated static func sideWidth(width: CGFloat, centre: CGFloat) -> CGFloat { max((width - centre) / 2, 0) }
}

/// A 28-pt icon button (`CrannyIconButtonStyle`, shape from Appearance ▸ Buttons) with a 32 × 28 hit area:
/// the design owner's decision for open issue 4 (band controls need ≥ 32 × 24, the glyph stays 28). Its
/// shortcut is bound by `NookHiddenShortcuts`; the button shows it as a hold-⌘ hint and a VoiceOver hint.
private struct HeaderButton: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let isOn: Bool
    let shortcut: NookShortcut
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HintSwap(shortcut: shortcut) {
                Image(systemName: symbol).contentTransition(theme.symbolReplace)
            }
        }
        .buttonStyle(HeaderIconButtonStyle(role: isOn ? .filled : .plain))
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .shortcutHint(shortcut)
    }
}

/// `CrannyIconButtonStyle` drawn at 28 pt inside a 32 × 28 tap area.
struct HeaderIconButtonStyle: ButtonStyle {
    let role: CrannyIconButtonStyle.Role

    /// The visual size (DESIGN.md §6.2) and the tap area (§2.3 band targets).
    static let visual: CGFloat = HitTarget.preferred
    static let hitArea = CGSize(width: max(HitTarget.band.width, visual), height: max(HitTarget.band.height, visual))

    func makeBody(configuration: Configuration) -> some View {
        CrannyIconButtonStyle(role, size: Self.visual).makeBody(configuration: configuration)
            .frame(width: Self.hitArea.width, height: Self.hitArea.height)
            .contentShape(Rectangle())
    }
}

/// Time and date in the empty camera zone of displays without a notch. Redraws once a minute, on the minute
/// (Core's `AlignedClock`: one sleep per minute, only while the panel is open; no `TimelineView`).
struct MinuteClock: View {
    @Environment(\.cranny) private var theme

    var body: some View {
        AlignedClock(period: 60) { now in
            Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                .crannyFont(.eyebrow)
                .foregroundStyle(theme.palette.secondaryLabel)
                .lineLimit(1)
        }
    }
}

#Preview("Header · Home selected") {
    let (model, registry) = previewScene(.open)
    NookHeader(model: model, registry: registry, actions: NotchUIActions(), select: { _ in }, perform: { _ in })
        .frame(width: model.layout.open(columns: model.openColumns).bodyWidth - 2 * Space.l, height: model.layout.headerHeight)
        .padding(.horizontal, Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Header · floating island, pinned") {
    let (model, registry) = previewScene(.open, metrics: PreviewDisplays.external)
    model.pinned = true
    return NookHeader(model: model, registry: registry, actions: NotchUIActions(), select: { _ in }, perform: { _ in })
        .frame(width: model.layout.open(columns: model.openColumns).bodyWidth - 2 * Space.l, height: model.layout.headerHeight)
        .padding(.horizontal, Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

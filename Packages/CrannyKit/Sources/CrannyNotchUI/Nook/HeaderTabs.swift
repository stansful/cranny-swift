// CrannyNotchUI/Nook/HeaderTabs.swift — the page tabs left of the camera (DESIGN.md §6.2): a capsule track
// (`control`, 2-pt inset) of 22-pt segments with an icon and a `headline` title; the selected segment is
// `controlPressed` and moves with matched geometry (`tabIndicator`). Built-in pages are Home (code id `nook`)
// and the Tray (with a `micro` count badge); user pages follow. Titles that do not fit (Russian, XL text)
// collapse to icons with tooltips and VoiceOver labels.
import CrannyCore
import Foundation
import SwiftUI

/// One tab of the header.
struct HeaderTab: Identifiable, Equatable {
    let id: PageID
    let title: String
    let symbol: String
    let badge: Int?
}

nonisolated enum HeaderTabItems {
    /// Grid pages first (in the user's order), then module pages by `order` (the Tray).
    @MainActor static func make(pages: [NookPage], modulePages: [PageDescriptor]) -> [HeaderTab] {
        let home = String(localized: "Home", bundle: .module, comment: "Open panel: the built-in widget page (tab)")
        let grid = pages.map { HeaderTab(id: $0.id, title: $0.title ?? home, symbol: $0.symbol, badge: nil) }
        let modules = modulePages.sorted { $0.order < $1.order }.map {
            HeaderTab(id: $0.id, title: $0.title, symbol: $0.symbol, badge: $0.badge().flatMap { $0 > 0 ? $0 : nil })
        }
        return grid + modules
    }
}

struct HeaderTabsView: View {
    @Environment(\.cranny) private var theme
    @Namespace private var selection
    let tabs: [HeaderTab]
    let selected: PageID
    let select: @MainActor (PageID) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            track(showsTitles: true)
            track(showsTitles: false)
        }
        .animation(theme.animation(.tabIndicator), value: selected)
    }

    private func track(showsTitles: Bool) -> some View {
        HStack(spacing: Space.xxs) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                Button { select(tab.id) } label: {
                    TabSegmentLabel(tab: tab, shortcut: NookKeyMap.page(index), showsTitle: showsTitles)
                }
                .buttonStyle(TabSegmentStyle(isSelected: tab.id == selected, indicator: selection,
                                             indicatorID: showsTitles ? "tab.titled" : "tab.icons"))
                .nookShortcut(NookKeyMap.page(index))
                .help(tab.title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: tab.title))
                .modifier(BadgeValue(count: tab.badge))
                .accessibilityAddTraits(tab.id == selected ? [.isButton, .isSelected] : .isButton)
                .shortcutHint(NookKeyMap.page(index))
            }
        }
        .padding(Space.xxs)
        .background(Capsule(style: .continuous).fill(theme.palette.control))
        .fixedSize()
    }
}

private struct TabSegmentLabel: View {
    let tab: HeaderTab
    let shortcut: NookShortcut?
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: Space.xs + 1) {
            HintSwap(shortcut: shortcut) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
            }
            if showsTitle {
                Text(verbatim: tab.title).crannyFont(.headline).lineLimit(1).fixedSize()
            }
            if let badge = tab.badge {
                Text(badge, format: .number)
                    .crannyFont(.micro)
                    .padding(.horizontal, Space.xs)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.14)))
            }
        }
    }
}

/// A segment: 22 pt tall, at least 32 pt wide, hover and press feedback; the tap area reaches 24 pt into the
/// track's inset (DESIGN.md §16 band targets) without changing the layout.
private struct TabSegmentStyle: ButtonStyle {
    let isSelected: Bool
    let indicator: Namespace.ID
    let indicatorID: String

    /// Visual height of a segment (DESIGN.md §6.2).
    static let height: CGFloat = 22
    /// How far the tap area reaches beyond the segment so it is ≥ 24 pt tall.
    static let hitOutset = max(0, (HitTarget.band.height - height) / 2)

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, isSelected: isSelected, indicator: indicator, indicatorID: indicatorID)
    }

    private struct SegmentBody: View {
        @Environment(\.cranny) private var theme
        @State private var hovered = false
        let configuration: Configuration
        let isSelected: Bool
        let indicator: Namespace.ID
        let indicatorID: String

        var body: some View {
            let p = theme.palette
            configuration.label
                .foregroundStyle(isSelected ? p.label : p.secondaryLabel)
                .padding(.horizontal, Space.m + 2)
                .frame(minWidth: HitTarget.band.width)
                .frame(height: TabSegmentStyle.height)
                .background {
                    if isSelected {
                        Capsule(style: .continuous).fill(p.controlPressed)
                            .matchedGeometryEffect(id: indicatorID, in: indicator)
                    } else if hovered || configuration.isPressed {
                        Capsule(style: .continuous).fill(configuration.isPressed ? p.controlHover : p.control)
                    }
                }
                .contentShape(Rectangle().inset(by: -TabSegmentStyle.hitOutset))
                .opacity(configuration.isPressed && theme.reduceMotion ? 0.7 : 1)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
        }
    }
}

/// "3 items" on a tab with a count badge (VoiceOver). Always applied, with an empty value without a badge, so
/// the tab keeps its identity (and hover state) when the count goes from 0 to 1.
struct BadgeValue: ViewModifier {
    let count: Int?
    func body(content: Content) -> some View {
        content.accessibilityValue(count.map {
            Text("\($0) items", bundle: .module, comment: "Open panel: VoiceOver value of a tab's count badge (Tray items)")
        } ?? Text(verbatim: ""))
    }
}

#Preview("Tabs · Home, Focus, Tray 3") {
    let tabs = [HeaderTab(id: .nook, title: "Home", symbol: "square.grid.2x2.fill", badge: nil),
                HeaderTab(id: "page.focus", title: "Focus", symbol: "note.text", badge: nil),
                HeaderTab(id: .tray, title: "Tray", symbol: "tray.full.fill", badge: 3)]
    VStack(alignment: .leading, spacing: Space.l) {
        HeaderTabsView(tabs: tabs, selected: .nook, select: { _ in })
        HeaderTabsView(tabs: tabs, selected: .tray, select: { _ in }).frame(width: 150, alignment: .leading)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

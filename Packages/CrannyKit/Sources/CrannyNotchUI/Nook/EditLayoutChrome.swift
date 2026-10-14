// CrannyNotchUI/Nook/EditLayoutChrome.swift — the layout editor's pieces around the cards (DESIGN.md §6.6): the
// header bar ("N cells left", Add widget ▸, Done), the wiggle and the Reduce Motion "–" badge.
import CrannyCore
import Foundation
import SwiftUI

/// The "–" badge shown instead of the wiggle under Reduce Motion; it removes the widget.
struct RemoveBadge: View {
    @Environment(\.cranny) private var theme
    let action: @MainActor () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.palette.label)
                .frame(width: 18, height: 18)
                .background(Circle().fill(theme.palette.controlPressed))
                .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -Space.s, y: -Space.s)
        .accessibilityLabel(CardStrings.remove)
    }
}

/// The edit-mode wiggle: ±1° at about 1.8 Hz, out of phase per card. Time comes from `EffectClock` at 30 fps
/// and only while editing; Reduce Motion never wiggles (the "–" badge shows instead).
struct Wiggle: ViewModifier {
    let index: Int
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            EffectClock(minimumInterval: 1.0 / 30) { date in
                let t = date.timeIntervalSinceReferenceDate
                content.rotationEffect(.degrees(sin(t * 2 * .pi * 1.8 + Double(index) * 1.3)))
            }
        } else {
            content
        }
    }
}

/// The edit-mode controls in the header, in place of the actions: "N cells left", Add widget ▸, Done (↩).
struct EditLayoutBar: View {
    @Environment(\.cranny) private var theme
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let editing = LayoutEditing(pages: registry.services.settings[CoreSettings.pages], pageID: page.id,
                                    maxColumns: model.layout.maxColumns)
        let addable = registry.widgets.filter { w in !editing.items.contains { $0.widget == w.id } }
        HStack(spacing: Space.s) {
            Text("\(max(editing.cellsLeft, 0)) cells left", bundle: .module,
                 comment: "Layout editor: room left on the page, in grid cells")
                .crannyFont(.caption)
                .foregroundStyle(theme.palette.tertiaryLabel)
                .contentTransition(.numericText(value: Double(editing.cellsLeft)))
                .animation(theme.animation(.contentSwap), value: editing.cellsLeft)
            Menu {
                ForEach(addable) { widget in
                    let over = editing.overflow(adding: widget.sizes)
                    Button {
                        if let next = editing.adding(widget.id, sizes: widget.sizes) { actions.commitLayout(next.pages) }
                    } label: {
                        if over > 0 {
                            Text("\(widget.title) — \(over) cells over; move a widget to another page", bundle: .module,
                                 comment: "Layout editor: an Add widget item that does not fit (widget, cells over the limit)")
                        } else {
                            Label { Text(verbatim: widget.title) } icon: { Image(systemName: widget.symbol) }
                        }
                    }
                    .disabled(over > 0)
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    .frame(width: HitTarget.preferred, height: HitTarget.preferred)
                    .background(CrannyButtonShape(theme.buttonShape).fill(theme.palette.control))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: HeaderIconButtonStyle.hitArea.width, height: HeaderIconButtonStyle.hitArea.height)
            .contentShape(Rectangle())
            .disabled(addable.isEmpty)
            .help(String(localized: "Add widget", bundle: .module, comment: "Layout editor: the + button (widget library)"))
            .accessibilityLabel(Text("Add widget", bundle: .module, comment: "Layout editor: the + button (widget library)"))
            Button { actions.setMode(.grid) } label: {
                Text("Done", bundle: .module, comment: "Layout editor: finishes editing (↩ or Esc)")
            }
            .buttonStyle(CrannyChipButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview("Edit bar") {
    let (model, registry) = previewScene(.open, mode: .editLayout)
    return EditLayoutBar(page: NookPreset.listener.page, model: model, registry: registry, actions: NotchUIActions())
        .padding()
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

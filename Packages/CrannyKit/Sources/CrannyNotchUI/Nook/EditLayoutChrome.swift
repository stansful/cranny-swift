// CrannyNotchUI/Nook/EditLayoutChrome.swift — the layout editor's pieces around the cards (DESIGN.md §6.6): the
// header bar ("N cells left", Add widget ▸, Done), the wiggle and the Reduce Motion "–" badge.
import CrannyCore
import Foundation
import SwiftUI

/// What VoiceOver hears after a layout change (DESIGN.md §6.6 "every change is announced"): from the editor
/// (drag, keys, the "–" badge, the Add menu) and from a card's ⋯ menu or VoiceOver actions.
enum LayoutAnnouncement {
    static func moved(_ widget: String, position: Int) -> String {
        String(localized: "\(widget), position \(position)", bundle: .module,
               comment: "Layout editor: VoiceOver announcement after a move (widget name, new position)")
    }

    static func resized(_ widget: String, cells: Int) -> String {
        String(localized: "\(widget), \(cells) cells", bundle: .module,
               comment: "Layout editor: VoiceOver announcement after a resize (widget name, width in cells)")
    }

    static func removed(_ widget: String) -> String {
        String(localized: "Removed \(widget)", bundle: .module,
               comment: "Layout editor: VoiceOver announcement after a widget was removed")
    }

    static func added(_ widget: String) -> String {
        String(localized: "Added \(widget)", bundle: .module,
               comment: "Layout editor: VoiceOver announcement after a widget was added from the Add widget menu")
    }

    /// Speaks `message` (only while VoiceOver runs).
    @MainActor static func post(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

/// The "–" badge shown instead of the wiggle under Reduce Motion; it removes the widget.
struct RemoveBadge: View {
    @Environment(\.cranny) private var theme
    let action: @MainActor () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .notchGlyph(.removeBadge)
                .foregroundStyle(theme.palette.label)
                .frame(width: RemoveBadge.diameter, height: RemoveBadge.diameter)
                .background(Circle().fill(theme.palette.controlPressed))
                .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -Space.s, y: -Space.s)
        .accessibilityLabel(CardStrings.remove)
    }

    /// The visible circle; the hit area is the Nook's 28 × 24.
    static let diameter: CGFloat = 18
}

/// The edit-mode wiggle: ±1° at about 1.8 Hz, out of phase per card; Reduce Motion never wiggles (the "–" badge
/// shows instead). The time comes from the editor's one `WiggleClock`. The modifier has the same structure
/// whether a card wiggles or not (a still card has rotation 0), so starting a drag never re-creates the cards
/// or the handle whose gesture is in flight.
struct Wiggle: ViewModifier {
    @Environment(\.notchWiggleTime) private var time
    let index: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(isActive ? Wiggle.angle(time: time, index: index) : 0))
    }

    nonisolated static let amplitude = 1.0             // degrees
    nonisolated static let frequency = 1.8             // Hz
    nonisolated static let phaseStep = 1.3             // radians between neighbouring cards

    /// The card's angle at `time` (seconds; nil = the clock is paused, the card rests at 0°). Pure.
    nonisolated static func angle(time: Double?, index: Int) -> Double {
        guard let time else { return 0 }
        return amplitude * sin(time * 2 * .pi * frequency + Double(index) * phaseStep)
    }
}

/// One frame clock for all cards of the layout editor (instead of one per card): `EffectClock` at the effect
/// budget's rate (≤ 30 fps on AC, ≤ 20 on battery; paused while occluded, locked, in full screen, in Low Power
/// Mode and under Reduce Motion or Instant, ARCHITECTURE.md §9.2). Only the cards' `Wiggle` reads the time, so
/// one tick re-evaluates their rotations and nothing else.
struct WiggleClock: ViewModifier {
    let interval: Double?

    func body(content: Content) -> some View {
        EffectClock(minimumInterval: interval) { date in
            content.environment(\.notchWiggleTime,
                                interval == nil ? nil : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
        }
    }
}

extension EnvironmentValues {
    /// Seconds for the edit-mode wiggle (`WiggleClock`); nil = paused.
    @Entry var notchWiggleTime: Double? = nil
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
                                    maxColumns: model.layout.maxColumns, registry: registry)
        let addable = registry.widgets.filter { w in !editing.items.contains { $0.widget == w.id } }
        let left = max(editing.cellsLeft, 0)
        let counter = Text("\(left) cells left", bundle: .module, comment: "Layout editor: room left on the page, in grid cells")
        HStack(spacing: Space.s) {
            // "N cells left", or just N (same tooltip and VoiceOver label) when the header's side zone is narrow.
            ViewThatFits(in: .horizontal) {
                counter.crannyFont(.caption).fixedSize()
                Text(left, format: .number).crannyFont(.caption).fixedSize()
                    .help(counter)
                    .accessibilityLabel(counter)
            }
            .foregroundStyle(theme.palette.tertiaryLabel)
            .contentTransition(.numericText(value: Double(editing.cellsLeft)))
            .animation(theme.animation(.contentSwap), value: editing.cellsLeft)
            Menu {
                ForEach(addable) { widget in
                    let over = editing.overflow(adding: widget.sizes)
                    Button {
                        if let next = editing.adding(widget.id, sizes: widget.sizes) {
                            actions.commitLayout(next.pages)
                            LayoutAnnouncement.post(LayoutAnnouncement.added(widget.title))
                        }
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
                Image(systemName: "plus").notchGlyph(.band)
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

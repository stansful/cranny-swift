// CrannyTimer/UI/TimerWidget.swift — the Timer card (DESIGN.md §7.7; 2 cells by default, 3 with the preset column).
// Content only: the shell draws the card, hover fill, ⋯ menu and the VoiceOver container named "Timer".
// States (DESIGN.md §6.8): content = running / paused / done; empty = idle with its presets (the action is one click
// away). The timer needs no permission, loads nothing slow and has no user-visible errors.
import CrannyCore
import Foundation
import SwiftUI

final class TimerWidget: NookWidget {
    let model: TimerModel
    private let settings: SettingsStore
    private let haptics: Haptics

    init(model: TimerModel, settings: SettingsStore, haptics: Haptics) {
        self.model = model
        self.settings = settings
        self.haptics = haptics
    }

    let id: WidgetID = .timer
    var title: String { TimerCopy.timer }
    let symbol = "timer"
    var summary: String { TimerCopy.summary }
    let sizes = WidgetSizes(minimum: 2, preferred: 2, maximum: 3)

    func makeBody(context: WidgetContext) -> some View {
        TimerFace(model: model, context: context, playHaptic: { [haptics] in haptics.play($0) })
    }

    /// Layout & Widgets ▸ Timer and the card's ⋯ menu: presets and the sound.
    func makeOptions() -> some View { TimerOptionsView(settings: settings) }
}

// MARK: - Previews (a card per state, at the default and the wide size)

@MainActor private func card(_ sample: TimerModel.Sample, cells: Int = 2, focused: Bool = false) -> some View {
    let services = CrannyServices.preview()
    let widget = TimerWidget(model: .sample(sample, settings: services.settings), settings: services.settings,
                             haptics: services.haptics)
    let grid = CrannyTheme().grid
    let inset = grid.density.cardPadding
    return widget.makeBody(context: WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset,
                                                                                    height: grid.height - 2 * inset),
                                                  isFocused: focused))
        .crannyCard(cells: cells)
}

#Preview("Timer widget · 2 cells") {
    HStack(spacing: Space.m) {
        card(.idle)
        card(.running(left: 272, total: 300))
        card(.paused(left: 125, total: 300))
        card(.done(total: 300))
        card(.setup(seconds: 360))
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Timer widget · 3 cells") {
    VStack(spacing: Space.m) {
        card(.idle, cells: 3)
        card(.running(left: 1499, total: 1500), cells: 3)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

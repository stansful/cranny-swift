// CrannyTimer/UI/TimerFace.swift — the Timer widget's content (DESIGN.md §7.7, §6.7, §16):
//   2 cells  idle: 2 × 2 preset tiles; otherwise the ring (running, paused, done, set-up, typing)
//   3 cells  the ring + a column of preset chips
// Input: click (tiles, chips, ⏸ ⏹ on hover), scroll ±1 min per detent (`.levelChange`), keyboard while focused
// (digits ↩ start "25" / "90s", Space pause/resume, ⌫ reset, ↑ ↓ ±1 min), VoiceOver (adjustable ±1 min + actions).
import CrannyCore
import Foundation
import SwiftUI

struct TimerFace: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var notchContext
    let model: TimerModel
    let context: WidgetContext
    let playHaptic: @MainActor (HapticPattern) -> Void

    @State private var hovered = false
    @State private var entry = ""
    @State private var detents = ScrollDetents()
    @FocusState private var focused: Bool

    static let scrollZone: ScrollZoneID = "timer.face"

    var body: some View {
        let state = model.state
        let wide = context.cells >= 3
        let side = max(min(context.contentSize.height, wide ? context.contentSize.height : context.contentSize.width), 0)
        let showsPresetGrid = !wide && state.phase == .idle && model.draft == nil && entry.isEmpty
        let interactive = !context.isPreview && !context.isEditingLayout

        HStack(spacing: Space.m) {
            ZStack {
                if showsPresetGrid {
                    TimerPresetGrid(presets: model.presets, side: side, start: model.start(seconds:))
                        .transition(.crannyContent(reduceMotion: theme.reduceMotion, anchor: .center))
                } else {
                    TimerDial(model: model, diameter: max(side - TimerMetrics.ringInset, 0), entry: entry,
                              showsControls: hovered || focused,
                              showsFocusRing: focused && (notchContext.keyboardNavigation || context.isFocused))
                        .transition(.crannyContent(reduceMotion: theme.reduceMotion, anchor: .center))
                }
            }
            .frame(width: side, height: side)
            .modifier(TimerFaceAccessibility(model: model, showsPresets: showsPresetGrid))
            if wide {
                TimerPresetColumn(presets: model.presets, width: max(context.contentSize.width - side - Space.m, 0),
                                  height: side, start: model.start(seconds:))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(theme.animation(.contentSwap), value: showsPresetGrid)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .focusable(interactive)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0) }
        .background {
            // The zone keeps the closure it was registered with until the card's frame changes, so it exists only
            // while the face takes input: never on a preview stage, removed on entering edit mode.
            if interactive {
                Color.clear.crannyContinuousScrollZone(Self.scrollZone, axis: .vertical) { handleScroll($0) }
            }
        }
        .allowsHitTesting(interactive)
        .onChange(of: context.isFocused, initial: true) { _, isFocused in
            if isFocused && interactive { focused = true }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { entry = "" }
        }
        .onDisappear {
            model.clearDraft()
            entry = ""
        }
    }

    // MARK: Scroll: one detent per 12 pt of finger travel, one `.levelChange` per minute applied

    /// Reads only what stays current in a registered closure (the model, `detents`' storage, the haptic port).
    private func handleScroll(_ update: SwipeUpdate) {
        switch update {
        case .tracking(_, let translation):
            let steps = detents.update(translation: translation)
            guard steps != 0 else { return }
            let direction = steps > 0 ? 1 : -1
            for _ in 0..<abs(steps) {
                guard model.adjust(byMinutes: direction) else { break }        // at a limit: no detent, no haptic
                playHaptic(.levelChange)
            }
        case .committed, .cancelled:
            detents.reset()
        }
    }

    // MARK: Keyboard (DESIGN.md §16: digits ↩ start · Space pause/resume · ⌫ reset) — rules in `TimerKeyMap`

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
              let key = Self.timerKey(press) else { return .ignored }
        let phase: TimerKeyMap.Phase = switch model.state.phase {
        case .idle: .idle
        case .running, .paused: .counting
        case .done: .done
        }
        let result = TimerKeyMap.handle(key, entry: entry, phase: phase, hasDraft: model.draft != nil)
        entry = result.entry
        switch result.command {
        case .none: break
        case .start(let seconds): model.start(seconds: seconds)
        case .startSetup: model.startSetup()
        case .togglePause: model.togglePause()
        case .stop: model.stop()
        case .clearDraft: model.clearDraft()
        case .adjust(let minutes): if model.adjust(byMinutes: minutes) { playHaptic(.levelChange) }
        }
        return result.handled ? .handled : .ignored
    }

    private static func timerKey(_ press: KeyPress) -> TimerKey? {
        switch press.key {
        case .return: return .returnKey
        case .delete: return .delete
        case .escape: return .escape
        case .upArrow: return .up
        case .downArrow: return .down
        case .space: return .space
        default:
            guard press.characters.count == 1, let character = press.characters.first else { return nil }
            return .character(character)
        }
    }
}

#Preview("Face · focused, typing and 3 cells") {
    let services = CrannyServices.preview()
    let size = CGSize(width: 96, height: 96)
    HStack(spacing: Space.l) {
        TimerFace(model: .sample(.running(left: 272, total: 300), settings: services.settings),
                  context: WidgetContext(cells: 2, contentSize: size, isFocused: true), playHaptic: { _ in })
            .crannyCard(cells: 2)
        TimerFace(model: .sample(.idle, settings: services.settings),
                  context: WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96)), playHaptic: { _ in })
            .crannyCard(cells: 3)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

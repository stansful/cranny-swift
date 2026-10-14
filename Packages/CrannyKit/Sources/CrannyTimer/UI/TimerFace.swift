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
                    dial(diameter: max(side - TimerMetrics.ringInset, 0))
                        .transition(.crannyContent(reduceMotion: theme.reduceMotion, anchor: .center))
                }
            }
            .frame(width: side, height: side)
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
        .crannyContinuousScrollZone(Self.scrollZone, axis: .vertical) { handleScroll($0) }
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

    // MARK: The ring as ONE accessibility element: adjustable ±1 min, with the state's actions

    private func dial(diameter: CGFloat) -> some View {
        TimerDial(model: model, diameter: diameter, entry: entry, showsControls: hovered || focused,
                  showsFocusRing: focused && (notchContext.keyboardNavigation || context.isFocused))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(TimerCopy.timer))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.adjust(byMinutes: 1)
                case .decrement: model.adjust(byMinutes: -1)
                @unknown default: break
                }
            }
            .accessibilityActions { accessibilityActions }
    }

    private var accessibilityValue: String {
        let state = model.state
        switch state.phase {
        case .idle: return TimerCopy.setUp(TimerFormat.spoken(model.setupDuration))
        case .running(let end):
            return TimerCopy.left(TimerFormat.spoken(state.displayedSeconds(at: Date())), endingAt: TimerFormat.time(end))
        case .paused:
            return TimerCopy.pausedLeft(TimerFormat.spoken(state.displayedSeconds(at: Date())))
        case .done: return TimerCopy.timerDone
        }
    }

    @ViewBuilder private var accessibilityActions: some View {
        let state = model.state
        if state.phase == .idle {
            Button(TimerCopy.start) { model.startSetup() }
        }
        if state.isCounting {
            Button(state.isPaused ? TimerCopy.resume : TimerCopy.pause) { model.togglePause() }
        }
        if state.isCounting || state.isDone {
            Button(TimerCopy.addMinute) { model.addMinute() }
            Button(TimerCopy.stop) { model.stop() }
        }
    }

    // MARK: Scroll: one detent per 12 pt of finger travel, one `.levelChange` per minute applied

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

    // MARK: Keyboard (DESIGN.md §16: digits ↩ start · Space pause/resume · ⌫ reset)

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        switch press.key {
        case .return: return submit()
        case .delete: return erase()
        case .escape:
            guard !entry.isEmpty else { return .ignored }                       // Esc then closes the panel
            entry = ""
            return .handled
        case .upArrow:
            if model.adjust(byMinutes: 1) { playHaptic(.levelChange) }
            return .handled
        case .downArrow:
            if model.adjust(byMinutes: -1) { playHaptic(.levelChange) }
            return .handled
        case .space where entry.isEmpty:
            guard model.state.isCounting else { return .ignored }
            model.togglePause()
            return .handled
        default:
            guard press.characters.count == 1, let character = press.characters.first,
                  DurationParser.accepts(character) else { return .ignored }
            if entry.count < DurationParser.maximumLength { entry.append(character) }
            return .handled
        }
    }

    private func submit() -> KeyPress.Result {
        if !entry.isEmpty {
            if let seconds = DurationParser.seconds(from: entry) {
                model.start(seconds: seconds)
                entry = ""
            }
            return .handled                                                     // invalid: the hint stays
        }
        switch model.state.phase {
        case .idle: model.startSetup()
        case .running, .paused: model.togglePause()
        case .done: model.stop()
        }
        return .handled
    }

    private func erase() -> KeyPress.Result {
        if !entry.isEmpty {
            entry.removeLast()
            return .handled
        }
        if model.state.phase != .idle {
            model.stop()
            return .handled
        }
        guard model.draft != nil else { return .ignored }
        model.clearDraft()
        return .handled
    }
}

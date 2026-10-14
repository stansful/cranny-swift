// CrannyTimer/UI/TimerFaceAccessibility.swift — the Timer face as ONE VoiceOver element (DESIGN.md §16: "the timer
// (±1 min)" is adjustable): label "Timer", the state as its value, the state's actions. It wraps the 2 × 2 preset
// tiles as well as the ring, so adjusting the presets reveals the set-up ring under the same VoiceOver cursor, and
// the presets are named actions while they are shown. While VoiceOver runs, the time left is refreshed every second.
import CrannyCore
import Foundation
import SwiftUI

struct TimerFaceAccessibility: ViewModifier {
    let model: TimerModel
    /// The 2 × 2 preset tiles are shown (idle, 2 cells): "Choose a duration", one action per preset.
    let showsPresets: Bool

    func body(content: Content) -> some View {
        let actions = Self.actions(model: model, showsPresets: showsPresets)
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(TimerCopy.timer))
            .accessibilityValue(Text(Self.value(model: model, showsPresets: showsPresets)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.adjust(byMinutes: 1)
                case .decrement: model.adjust(byMinutes: -1)
                @unknown default: break
                }
            }
            .accessibilityActions {
                ForEach(actions) { action in
                    Button(action.title, action: action.perform)
                }
            }
            .refreshesSpokenTime(model)
    }

    /// "Choose a duration" · "Set to 6 minutes" · "4 minutes, 59 seconds left, ends 14:35" · "Paused, 2 minutes
    /// left" · "Timer done". The time left reads `spokenSecondsLeft`, so it re-renders with each refresh.
    static func value(model: TimerModel, showsPresets: Bool) -> String {
        switch model.state.phase {
        case .idle:
            return showsPresets ? TimerCopy.choosePreset : TimerCopy.setUp(TimerFormat.spoken(model.setupDuration))
        case .running(let end):
            return TimerCopy.left(TimerFormat.spoken(model.spokenSecondsLeft), endingAt: TimerFormat.time(end))
        case .paused:
            return TimerCopy.pausedLeft(TimerFormat.spoken(model.spokenSecondsLeft))
        case .done:
            return TimerCopy.timerDone
        }
    }

    /// The named actions of the current state (each one also has a click and a key path).
    static func actions(model: TimerModel, showsPresets: Bool) -> [ActivityAction] {
        let state = model.state
        switch state.phase {
        case .idle where showsPresets:
            var seen = Set<Int>()
            var actions = model.presets.filter { seen.insert($0).inserted }.map { seconds in
                ActivityAction(id: "start.\(seconds)", title: TimerCopy.startTitle(seconds: seconds)) {
                    model.start(seconds: seconds)
                }
            }
            let setup = model.setupDuration
            if !seen.contains(setup) {                                  // the last duration (↩, the shortcut)
                actions.append(ActivityAction(id: "startSetup", title: TimerCopy.startTitle(seconds: setup)) {
                    model.startSetup()
                })
            }
            return actions
        case .idle:
            return [ActivityAction(id: "startSetup", title: TimerCopy.start) { model.startSetup() }]
        case .running, .paused:
            return [
                ActivityAction(id: state.isPaused ? "resume" : "pause",
                               title: state.isPaused ? TimerCopy.resume : TimerCopy.pause) { model.togglePause() },
                ActivityAction(id: "addMinute", title: TimerCopy.addMinute) { model.addMinute() },
                ActivityAction(id: "stop", title: TimerCopy.stop) { model.stop() },
            ]
        case .done:
            return [
                ActivityAction(id: "addMinute", title: TimerCopy.addMinute) { model.addMinute() },
                ActivityAction(id: "stop", title: TimerCopy.stop) { model.stop() },
            ]
        }
    }
}

#Preview("Face accessibility · presets and ring") {
    let services = CrannyServices.preview()
    HStack(spacing: Space.l) {
        TimerPresetGrid(presets: [60, 300, 600, 1500], side: 96) { _ in }
            .modifier(TimerFaceAccessibility(model: .sample(.idle, settings: services.settings), showsPresets: true))
        TimerDial(model: .sample(.running(left: 272, total: 300)), diameter: 88, entry: "", showsControls: false,
                  showsFocusRing: false)
            .modifier(TimerFaceAccessibility(model: .sample(.running(left: 272, total: 300)), showsPresets: false))
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

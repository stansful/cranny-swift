// CrannyTimer/TimerModule.swift — the Timer module's single entry point (ARCHITECTURE.md §3.4, §3.17, §10.8):
// one deadline-based model, the Timer widget, the "Timer" (P2) and "Timer done" (P1) live activities with samples,
// ⌘K commands, the "Start timer" shortcut, and the launch/terminate hooks that restore and save the running timer.
import CrannyCore
import Foundation
import SwiftUI

public enum TimerModule: FeatureModule {
    public static var id: ModuleID { .timer }

    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let settings = services.settings
        let model = TimerModel(settings: settings, dependencies: dependencies(for: services))

        registry.add(widget: TimerWidget(model: model, settings: settings, haptics: services.haptics))
        registry.add(activity: TimerRunningActivity(model: model), kind: TimerRunningActivity.kind,
                     sample: { TimerRunningActivity(model: .sample(.running(left: 272, total: 300), settings: settings)) },
                     options: { AnyView(TimerActivityOptions(settings: settings)) })
        registry.add(activity: TimerDoneActivity(model: model), kind: TimerDoneActivity.kind,
                     sample: { TimerDoneActivity(model: .sample(.done(total: 300), settings: settings)) })
        registry.add(commands: TimerCommands(model: model))
        registry.add(shortcut: GlobalShortcut(id: .startTimer, title: TimerCopy.startShortcut) {
            // A timer is already counting: show it. Otherwise start the last duration; the band shows it arrive.
            if model.state.isCounting {
                services.notch.open(page: .nook, focus: .timer, reason: .keyboard)
            } else {
                model.startSetup()
            }
        })
        registry.onLaunch {
            await model.restore()
            model.startObservingSystemClock()
            #if DEBUG
            TimerQA.apply(to: model)
            #endif
        }
        registry.onTerminate {
            model.persistNow()
            model.stopObservingSystemClock()
        }
    }

    private static func dependencies(for services: CrannyServices) -> TimerDependencies {
        #if DEBUG
        // Visual QA (`--qa-timer`): never read or write the user's timer and never make a sound.
        if TimerQA.isRequested { return TimerQA.dependencies(services: services) }
        #endif
        return .live(services: services)
    }
}

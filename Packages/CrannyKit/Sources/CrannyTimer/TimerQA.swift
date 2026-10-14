// CrannyTimer/TimerQA.swift — DEBUG-only visual QA for the Timer (docs/CONTRIBUTING.md "Visual QA hooks"):
//
//   --qa-timer running:<left>[/<total>]   a running timer with <left> seconds left of <total> (default: left)
//   --qa-timer paused:<left>[/<total>]    a paused one
//   --qa-timer done[:<total>]             "Timer done" (no sound)
//   --qa-timer setup:<seconds>            idle with that duration in the set-up ring
//
// With the flag the module uses a throw-away model: it neither restores nor saves `state.json` and stays silent.
// Combine with the shell's `--qa-state closed|open` (closed + a running timer = the compact activity).
#if DEBUG
import CrannyCore
import Foundation
import os

private let log = Log.logger(.timer)

enum TimerQA {
    static let argument = "--qa-timer"

    static var isRequested: Bool { spec != nil }

    private static var spec: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static func dependencies(services: CrannyServices) -> TimerDependencies {
        var dependencies = TimerDependencies.live(services: services)
        dependencies.file = nil
        dependencies.sound = SilentTimerSound()
        return dependencies
    }

    /// Applies the requested state after launch (the model is the QA one: nothing is persisted).
    static func apply(to model: TimerModel) {
        guard let spec, let sample = parse(spec) else { return }
        log.info("QA: timer \(spec, privacy: .public)")
        let (state, draft) = sample.state(at: model.now)
        model.showSample(state, draft: draft)
    }

    /// "running:272/300" → `.running(left: 272, total: 300)`.
    static func parse(_ spec: String) -> TimerModel.Sample? {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let numbers = parts.count > 1 ? parts[1].split(separator: "/").compactMap { TimeInterval($0) } : []
        let first = numbers.first, total = numbers.count > 1 ? numbers[1] : numbers.first
        switch parts.first {
        case "running": return first.map { .running(left: $0, total: total ?? $0) }
        case "paused": return first.map { .paused(left: $0, total: total ?? $0) }
        case "done": return .done(total: first ?? TimerLimits.defaultDuration)
        case "setup": return first.map { .setup(seconds: Int($0)) }
        default: return nil
        }
    }
}
#endif

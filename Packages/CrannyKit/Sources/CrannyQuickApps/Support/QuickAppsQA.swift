// CrannyQuickApps/Support/QuickAppsQA.swift — Debug-only visual QA states for the launcher (docs/CONTRIBUTING.md
// "Visual QA hooks"). Launch argument `-CrannyQAQuickApps <flags>`, comma-separated:
//   editing   the launcher's edit mode (remove badges, "+" tile)
//   states    the first three shortcut tiles show running, finished and failed
// In-memory only: nothing is written to settings, nothing is launched or run. Compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation
import os

private let log = Log.logger(.quickApps)

@MainActor enum QuickAppsQA {
    static let argument = "CrannyQAQuickApps"

    static func apply(to model: QuickAppsModel, defaults: UserDefaults = .standard) {
        guard let value = defaults.string(forKey: argument) else { return }
        let flags = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        log.info("QA: quick apps \(flags.sorted().joined(separator: ","), privacy: .public)")
        Task {
            // After the shell's QA hook opened the panel (it waits 300 ms), so no close event resets edit mode.
            try? await Task.sleep(for: .seconds(1))
            if flags.contains("editing") { model.isEditing = true }
            if flags.contains("states") {
                let states: [ShortcutRunState] = [.running(since: Date()), .succeeded, .failed(.shortcutFailed)]
                for (entry, state) in zip(model.shortcutEntries, states) { model.runs.show(state, for: entry.id) }
            }
        }
    }
}
#endif

// CrannyAppShell/MenuBar/PauseMenu.swift — Pause Live Activities ▸ For 1 Hour · Until Tomorrow · Until I Resume
// (DESIGN.md §13). While a pause runs, the menu says so in a status line and offers Resume in its place, so the
// state is visible without opening a submenu.
import CrannyCore
import Foundation
import SwiftUI

struct PauseMenu: View {
    let pause: PauseController
    /// The Pause activities shortcut, if the user bound one: it pauses for an hour or resumes.
    var shortcut: KeyboardShortcut?

    var body: some View {
        let status = pause.status
        if status.isPaused {
            Text(verbatim: Self.caption(status))
            Button { pause.resume() } label: {
                Text("Resume Live Activities", bundle: .module, comment: "Menu bar and ⌘K: ends a pause of Live Activities")
            }
            .keyboardShortcut(shortcut)
        } else {
            Menu {
                Button { pause.pause(.oneHour) } label: {
                    Text("For 1 Hour", bundle: .module, comment: "Menu bar ▸ Pause Live Activities: duration")
                }
                .keyboardShortcut(shortcut)
                Button { pause.pause(.untilTomorrow) } label: {
                    Text("Until Tomorrow", bundle: .module, comment: "Menu bar ▸ Pause Live Activities: duration (until midnight)")
                }
                Button { pause.pause(.untilResumed) } label: {
                    Text("Until I Resume", bundle: .module, comment: "Menu bar ▸ Pause Live Activities: duration (no end)")
                }
            } label: {
                Text("Pause Live Activities", bundle: .module, comment: "Menu bar: submenu that silences live activities and peeks for a while")
            }
        }
    }

    /// The status line of a running pause: its end in the user's own time format.
    static func caption(_ status: PauseStatus) -> String {
        switch status {
        case .notPaused:
            ""
        case .untilLaterToday(let until):
            String(localized: "Live Activities paused until \(until.formatted(date: .omitted, time: .shortened))", bundle: .module,
                   comment: "Menu bar: status line of a pause; the argument is a time, e.g. 15:42")
        case .untilTomorrow:
            String(localized: "Live Activities paused until tomorrow", bundle: .module, comment: "Menu bar: status line of a pause that ends at midnight")
        case .untilDate(let until):
            String(localized: "Live Activities paused until \(until.formatted(.dateTime.weekday(.abbreviated).hour().minute()))",
                   bundle: .module, comment: "Menu bar: status line of a pause; the argument is a time, e.g. 15:42")
        case .untilResumed:
            String(localized: "Live Activities paused", bundle: .module, comment: "Menu bar: status line of a pause without an end")
        }
    }
}

#Preview("Pause · not paused and paused") {
    let running = PauseController(settings: CrannyServices.preview().settings)
    let paused = PauseController(settings: CrannyServices.preview().settings)
    paused.pause(.oneHour)
    return HStack(spacing: 24) {
        Menu { PauseMenu(pause: running) } label: { Text(verbatim: "Not paused") }
        Menu { PauseMenu(pause: paused) } label: { Text(verbatim: "Paused") }
    }
    .fixedSize()
    .padding()
    .crannyThemeRoot(CrannyTheme())
}

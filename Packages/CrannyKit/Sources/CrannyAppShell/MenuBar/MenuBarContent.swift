// CrannyAppShell/MenuBar/MenuBarContent.swift — the menu bar extra's menu (DESIGN.md §13), WP16.
// WP0 ships the items whose behaviour exists: Open Cranny, Keep Cranny Open, Settings…, About, Quit.
// WP16 adds Pause Live Activities ▸, Show On ▸, Demo Mode, Check for Updates…, Show Tutorial.
import AppKit
import CrannyCore
import SwiftUI

struct MenuBarContent: View {
    let appControl: ShellAppControl

    var body: some View {
        Button { appControl.toggleOpen() } label: { Text("Open Cranny", bundle: .module, comment: "Menu bar item; global shortcut name (Settings ▸ Keyboard)") }
            .keyboardShortcut("n", modifiers: [.control, .option])            // shows ⌃⌥N; the hot key does the work
        Toggle(isOn: Binding(get: { appControl.isPinned }, set: { appControl.setPinned($0) })) {
            Text("Keep Cranny Open", bundle: .module, comment: "Menu bar item (checked while pinned)")
        }
        Divider()
        // A Button, never SettingsLink: there is no SwiftUI Settings scene (D11).
        Button { appControl.openSettings(nil) } label: { Text("Settings…", bundle: .module, comment: "Menu bar item") }
            .keyboardShortcut(",")
        Divider()
        Button { appControl.showAbout() } label: { Text("About Cranny", bundle: .module, comment: "Menu bar item") }
        Button { appControl.quit() } label: { Text("Quit Cranny", bundle: .module, comment: "Menu bar item") }
            .keyboardShortcut("q")
    }
}

#Preview("Menu bar menu") {
    VStack(alignment: .leading, spacing: 4) { MenuBarContent(appControl: ShellAppControl()) }
        .padding()
        .background(.black)
        .preferredColorScheme(.dark)
        .crannyThemeRoot(CrannyTheme())
}

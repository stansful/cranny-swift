// CrannyAppShell/MenuBar/MenuBarContent.swift — the menu bar extra's menu (DESIGN.md §13). A standard native
// menu (`.menuBarExtraStyle(.menu)`), nothing custom:
//
//   Open Cranny  ⌃⌥N · Keep Cranny Open ✓ │ Pause Live Activities ▸ · Show On ▸ · Demo Mode ✓ │
//   Settings… ⌘, · Check for Updates… · Show Tutorial (· Skip Tutorial while it runs) │ About Cranny · Quit Cranny ⌘Q
//
// Global shortcuts show their current binding (or nothing when off). Every item is reachable with the keyboard
// (arrows, type-select, Return) and VoiceOver reads the titles and the checkmarks.
import AppKit
import CrannyCore
import CrannyOnboarding
import Foundation
import ServiceManagement
import SwiftUI

struct MenuBarContent: View {
    let appControl: ShellAppControl

    var body: some View {
        Button { appControl.openPanel() } label: {                    // opens; only the hot key toggles
            Text("Open Cranny", bundle: .module, comment: "Menu bar and Settings ▸ Keyboard: item and shortcut that open the panel")
        }
        .keyboardShortcut(appControl.menuShortcut(.openNook))        // shows the binding; the hot key does the work
        Toggle(isOn: Binding(get: { appControl.isPinned }, set: { appControl.setPinned($0) })) {
            Text("Keep Cranny Open", bundle: .module, comment: "Menu bar: pin item, checked while the panel is pinned")
        }
        .keyboardShortcut(appControl.menuShortcut(.togglePin))
        Divider()
        if let pause = appControl.pause {
            PauseMenu(pause: pause, shortcut: appControl.menuShortcut(.pauseActivities))
        }
        if let displays = appControl.displays {
            ShowOnMenu(displays: displays)
        }
        if let demo = appControl.demo {
            Toggle(isOn: Binding(get: { demo.isOn }, set: { demo.set($0) })) {
                Text("Demo Mode", bundle: .module, comment: "Menu bar: toggles Demo mode (no auto-close, muted sounds, redacted titles)")
            }
        }
        Divider()
        // A Button, never SettingsLink: there is no SwiftUI Settings scene (D11).
        Button { appControl.openSettings(nil) } label: { Text("Settings…", bundle: .module, comment: "Menu bar: opens Settings") }
            .keyboardShortcut(",")
        UpdateMenuItem(appControl: appControl)
        Button { appControl.startTutorial() } label: {
            Text("Show Tutorial", bundle: .module, comment: "Menu bar: replays the interactive tutorial in the notch")
        }
        if appControl.isTutorialRunning {
            // The bubble's Skip tutorial and ⌘K are the other ways out (C-SHELL-12).
            Button { appControl.skipTutorial() } label: {
                Text("Skip Tutorial", bundle: .module, comment: "Menu bar: ends the interactive tutorial; shown only while it runs")
            }
        }
        Divider()
        Button { appControl.showAbout() } label: { Text("About Cranny", bundle: .module, comment: "Menu bar: opens Settings ▸ About") }
        Button { appControl.quit() } label: { Text("Quit Cranny", bundle: .module, comment: "Menu bar: quits the app") }
            .keyboardShortcut("q")
    }
}

/// "Check for Updates…" (opens Settings ▸ About, which shows the result), "Checking for Updates…" while a check
/// runs, or the available update itself.
private struct UpdateMenuItem: View {
    let appControl: ShellAppControl

    var body: some View {
        switch appControl.update {
        case .available(let version, _):
            Button { appControl.openReleasePage() } label: {
                Text("Update Available: Cranny \(version)…", bundle: .module,
                     comment: "Menu bar: opens the release page of a newer version; the argument is the version, e.g. 0.2.0")
            }
        case .checking:
            Button {} label: { Text("Checking for Updates…", bundle: .module, comment: "Menu bar: disabled item while an update check runs") }
                .disabled(true)
        case .idle, .upToDate, .failed:
            Button { appControl.checkForUpdatesFromMenu() } label: {
                Text("Check for Updates…", bundle: .module, comment: "Menu bar: checks GitHub Releases for a newer version")
            }
            .disabled(!(appControl.updates?.isConfigured ?? false))
        }
    }
}

#if DEBUG
extension ShellAppControl {
    /// A menu wired to in-memory services and two sample displays (previews only; nothing touches the system).
    static func preview(paused: Bool = false, demo: Bool = false) -> ShellAppControl {
        let registry = ModuleRegistry(services: .preview())
        let settings = registry.services.settings
        let control = ShellAppControl()
        let pause = PauseController(settings: settings)
        if paused { pause.pause(.untilTomorrow) }
        settings[CoreSettings.demoMode] = demo
        let displays = DisplayList(settings: settings) {
            [ConnectedDisplay(key: "built-in", name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true),
             ConnectedDisplay(key: "studio", name: "Studio Display", isBuiltIn: false, hasNotch: false)]
        }
        displays.start()
        control.attach(loginItems: LoginItemController(service: PreviewLoginItem()),
                       updates: UpdateChecker(settings: settings, configuration: UpdateConfiguration(repository: "cranny/cranny", currentVersion: "0.1.0"),
                                              paths: .temporary(), transport: PreviewUpdateTransport()),
                       pause: pause, demo: DemoMode(settings: settings), displays: displays,
                       tutorial: TutorialController(registry: registry), shortcuts: [])
        return control
    }
}

private final class PreviewLoginItem: LoginItemService {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettingsLoginItems() {}
}

private struct PreviewUpdateTransport: UpdateTransport {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw UpdateFailure.offline }
}

#Preview("Menu bar menu") {
    HStack(spacing: 24) {
        Menu { MenuBarContent(appControl: .preview()) } label: { Text(verbatim: "Cranny") }
        Menu { MenuBarContent(appControl: .preview(paused: true, demo: true)) } label: { Text(verbatim: "Paused · Demo") }
    }
    .fixedSize()
    .padding()
    .crannyThemeRoot(CrannyTheme())
}
#endif

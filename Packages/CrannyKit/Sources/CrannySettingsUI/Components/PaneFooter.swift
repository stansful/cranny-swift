// CrannySettingsUI/Components/PaneFooter.swift — every pane ends with "Reset ‹Pane›…" (DESIGN.md §11.3), which
// resets the namespaces of the rows the pane shows (`SettingsPage.namespaces`, §10.15) after a confirmation.
// Shell and module panes get the same footer, pinned under the pane's scrolling content. Records that share a
// namespace but are not preferences of the pane (the menu bar's Pause, the last update check) are kept.
import CrannyCore
import Foundation
import SwiftUI

struct PaneFooter: View {
    let page: SettingsPage
    let settings: SettingsStore
    @State private var confirming = false

    var body: some View {
        HStack {
            Spacer()
            Button {
                confirming = true
            } label: {
                Text("Reset \(page.title)…", bundle: .module,
                     comment: "Settings: pane footer button; the argument is the pane name (\"Reset General…\")")
            }
            .disabled(page.namespaces.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .alert(Text("Reset \(page.title) settings?", bundle: .module,
                    comment: "Settings: confirmation title for a pane reset; the argument is the pane name"),
               isPresented: $confirming) {
            Button(role: .destructive) {
                PaneReset.reset(page.namespaces, settings: settings)
            } label: {
                Text("Reset", bundle: .module, comment: "Settings: confirm button of a pane reset")
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: .module, comment: "Settings: cancel button of a confirmation")
            }
        } message: {
            Text("Every setting in this pane returns to its default. Notes, to-dos and tray files are not affected.",
                 bundle: .module, comment: "Settings: confirmation message for a pane reset")
        }
    }
}

/// What "Reset ‹Pane›…" does.
enum PaneReset {
    /// Resets every key of `namespaces`, except the records that live there but are no preference the pane shows:
    /// `activities.pausedUntil` (menu bar ▸ Pause Live Activities; written by the shell's PauseController) and
    /// `updates.lastCheck`. Reset All still clears them. They are written back in the same main-actor turn, so
    /// observers (`observe`, SwiftUI) never see them change.
    @MainActor static func reset(_ namespaces: [ModuleID], settings: SettingsStore) {
        let restores = [keeping(CoreSettings.pausedUntil, in: namespaces, settings: settings),
                        keeping(CoreSettings.lastUpdateCheck, in: namespaces, settings: settings)].compactMap { $0 }
        for namespace in namespaces { settings.reset(module: namespace) }
        for restore in restores { restore() }
    }

    @MainActor private static func keeping<V>(_ key: SettingKey<V>, in namespaces: [ModuleID],
                                              settings: SettingsStore) -> (@MainActor () -> Void)? {
        guard namespaces.contains(key.module) else { return nil }
        let value = settings[key]
        return { if settings[key] != value { settings[key] = value } }
    }
}

#Preview("Pane footer") {
    let registry = ModuleRegistry(services: .preview())
    PaneFooter(page: SettingsPage(id: .general, title: "General", symbol: "gearshape.fill", tint: .gray, group: .top, order: 0,
                                  namespaces: [.general]) { AnyView(EmptyView()) },
               settings: registry.services.settings)
        .frame(width: 600)
}

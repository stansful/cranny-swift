// CrannyAppShell/App/CrannyScenes.swift — the scenes the app target plugs into `App.body`.
// Only the menu bar extra: Settings and Welcome are AppKit windows (D11), the notch is an NSPanel per display.
import AppKit
import SwiftUI

public struct CrannyScenes: Scene {
    private let appDelegate: AppDelegate

    public init(appDelegate: AppDelegate) { self.appDelegate = appDelegate }

    public var body: some Scene {
        let appControl = appDelegate.appControl
        MenuBarExtra(isInserted: Binding(get: { appControl.showsMenuBarIcon }, set: { appControl.showsMenuBarIcon = $0 })) {
            MenuBarContent(appControl: appControl)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel(Text(verbatim: "Cranny"))
        }
        .menuBarExtraStyle(.menu)
    }
}

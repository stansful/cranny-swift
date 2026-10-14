// CrannyAppShell/App/CrannyScenes.swift — the scenes the app target plugs into `App.body`.
// Only the menu bar extra: Settings and Welcome are AppKit windows (D11), the notch is an NSPanel per display.
import AppKit
import SwiftUI

/// Every SwiftUI scene of the app: `CrannyApp.body` returns it (the menu bar extra; windows are AppKit).
public struct CrannyScenes: Scene {
    private let appDelegate: AppDelegate

    /// `appDelegate` is the app's `@NSApplicationDelegateAdaptor` instance, which owns the services.
    public init(appDelegate: AppDelegate) { self.appDelegate = appDelegate }

    public var body: some Scene {
        let appControl = appDelegate.appControl
        MenuBarExtra(isInserted: Binding(get: { appControl.showsMenuBarIcon }, set: { appControl.showsMenuBarIcon = $0 })) {
            MenuBarContent(appControl: appControl)
        } label: {
            MenuBarLabel()                     // the icon (badged in Demo mode) and "Cranny, demo mode" for VoiceOver
        }
        .menuBarExtraStyle(.menu)
    }
}

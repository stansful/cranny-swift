import SwiftUI
import CrannyAppShell

/// The only Swift file in the app target: everything else lives in CrannyKit.
@main
struct CrannyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        CrannyScenes(appDelegate: appDelegate)
    }
}

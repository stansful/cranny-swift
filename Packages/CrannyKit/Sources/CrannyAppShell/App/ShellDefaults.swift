// CrannyAppShell/App/ShellDefaults.swift — the one `UserDefaults` the app keeps its own state in, chosen once at
// launch (AppDelegate) and handed to every writer: the settings (`SettingsStore`, through CompositionRoot) and the
// Settings window's last pane and frame. Production uses the standard domain (`app.cranny.Cranny`). A Debug QA run
// started with `--qa-defaults-suite <name>` uses that suite instead (QAHooks+Defaults.swift), so hooks that change
// settings (`--qa-demo`, `--qa-pause`, onboarding, the settings window) never touch the user's preferences
// (ARCHITECTURE §10.20 #29). Modules never create their own `UserDefaults` for state: they read and write settings
// through `services.settings`; reading a `-Cranny…` QA flag from the argument domain writes nothing.
import CrannyCore
import Foundation

/// Where the app keeps the state it stores in `UserDefaults`.
struct ShellDefaults {
    /// The defaults every writer in the app uses.
    let defaults: UserDefaults
    /// The suite of a QA run, nil for the standard domain.
    let qaSuite: String?

    /// The standard domain (production).
    static var standard: ShellDefaults { ShellDefaults(defaults: .standard, qaSuite: nil) }

    /// AppKit's window-frame autosave always writes the standard domain, so a QA run keeps frames for the run only.
    var autosavesWindowFrames: Bool { qaSuite == nil }

    /// The app's choice for this launch: the standard domain, or (Debug builds) the suite named by
    /// `--qa-defaults-suite`.
    static func forLaunch(_ arguments: LaunchArguments = .current) -> ShellDefaults {
        #if DEBUG
        if let qa = QAHooks.defaults(arguments) { return qa }
        #endif
        return .standard
    }
}

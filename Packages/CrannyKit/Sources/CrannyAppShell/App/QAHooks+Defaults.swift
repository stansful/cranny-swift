// CrannyAppShell/App/QAHooks+Defaults.swift — DEBUG-only: `--qa-defaults-suite <name>` keeps a QA run's settings out
// of the user's preferences (docs/CONTRIBUTING.md ▸ Visual QA hooks; ARCHITECTURE §10.20 #29). `CFFIXED_USER_HOME`
// does not do it on macOS 27: Cranny's preferences still went to ~/Library/Preferences/app.cranny.Cranny.plist.
//
// With the switch, `ShellDefaults.forLaunch` hands `UserDefaults(suiteName: name)` to every writer in the app (the
// settings store, the Settings window), so the standard domain is never written by Cranny's code. The suite keeps
// its values between runs (a `--qa-pause` run, then a `--qa-pause resume` run); `defaults delete <name>` starts over.
// Settings seeded as `-cranny.<module>.<name> <data>` launch arguments still apply: the argument domain is part of a
// suite's search list. A name that would be the app's own domain or a global one is refused, and the run keeps its
// settings in memory instead (never in the standard domain).
//
// This is the only code that creates a preferences suite on purpose; Core's `noCodeCreatesAPreferencesSuite` test
// allows this file by name.
#if DEBUG
import CrannyCore
import Foundation
import os

private let log = Log.logger(.app)

extension QAHooks {
    /// The launch argument.
    static let defaultsSuiteArgument = "--qa-defaults-suite"

    /// The defaults of a QA run started with `--qa-defaults-suite <name>`, or nil without the switch. `makeSuite`
    /// opens the suite (tests pass in-memory stand-ins, so no test writes a preferences file).
    static func defaults(_ arguments: LaunchArguments, ownDomain: String? = Bundle.main.bundleIdentifier,
                         makeSuite: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }) -> ShellDefaults? {
        guard arguments.contains(defaultsSuiteArgument) else { return nil }
        let name = arguments.value(after: defaultsSuiteArgument)?.trimmingCharacters(in: .whitespaces) ?? ""
        if isAllowedSuite(name, ownDomain: ownDomain), let suite = makeSuite(name) {
            log.info("QA: settings are kept in the suite \(name, privacy: .public), not in the app's preferences")
            return ShellDefaults(defaults: suite, qaSuite: name)
        }
        log.error("QA: \(defaultsSuiteArgument, privacy: .public) needs a suite name of its own; settings stay in memory")
        let memory = InMemoryDefaults()
        memory.register(defaults: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))   // reads
        return ShellDefaults(defaults: memory, qaSuite: "memory")
    }

    /// A suite name that is not the app's own domain, a global domain or another launch argument.
    static func isAllowedSuite(_ name: String, ownDomain: String?) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.contains("/") else { return false }
        let reserved = [ownDomain, "app.cranny.Cranny", UserDefaults.globalDomain, ".GlobalPreferences",
                        "kCFPreferencesAnyApplication"].compactMap { $0?.lowercased() }
        return !reserved.contains(name.lowercased())
    }
}
#endif

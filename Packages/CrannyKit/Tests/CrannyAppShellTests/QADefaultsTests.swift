// `--qa-defaults-suite <name>` (ARCHITECTURE §10.20 #29): a Debug QA run keeps every setting it writes in its own
// suite and never writes the app's preferences domain. No test here opens a real suite (that would leave a plist in
// ~/Library/Preferences): the suite is a recording in-memory stand-in, and the standard domain of the test process
// is checked before and after.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell

extension ShellDefaults {
    /// Settings and window state in memory, with no frame autosave (tests never write a preferences domain).
    static var inMemory: ShellDefaults { ShellDefaults(defaults: InMemoryDefaults(), qaSuite: "memory") }
}

/// An in-memory `UserDefaults` that records the key of every write (the QA suite's stand-in). `@unchecked Sendable`:
/// its state is behind a lock.
private nonisolated final class RecordingDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var writes: [String] = []

    var written: [String] { lock.withLock { writes } }

    override func object(forKey defaultName: String) -> Any? { lock.withLock { values[defaultName] } }
    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            writes.append(defaultName)
            values[defaultName] = value
        }
    }
    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
    override func dictionaryRepresentation() -> [String: Any] { lock.withLock { values } }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func set(_ value: Int, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
}

/// What Cranny could have written to the standard domain of this process: its settings, the Settings window's pane
/// and frame.
private func crannyState(in defaults: UserDefaults) -> [String: String] {
    defaults.dictionaryRepresentation()
        .filter { $0.key.hasPrefix(SettingsStore.keyPrefix) || $0.key.hasPrefix("CrannySettings") || $0.key.contains("Frame CrannySettings") }
        .mapValues { "\($0)" }
}

@MainActor @Suite struct QADefaultsTests {
    private let suiteName = "app.cranny.Cranny.qa-test"

    @Test func withoutTheSwitchTheAppUsesItsPreferences() {
        #expect(QAHooks.defaults(LaunchArguments(["Cranny", "--qa-state", "open"])) == nil)
        let standard = ShellDefaults.forLaunch(LaunchArguments(["Cranny"]))
        #expect(standard.defaults === UserDefaults.standard && standard.qaSuite == nil && standard.autosavesWindowFrames)
    }

    @Test func theSwitchOpensTheNamedSuite() throws {
        var opened: [String] = []
        let suite = RecordingDefaults()
        let qa = try #require(QAHooks.defaults(LaunchArguments(["Cranny", "--qa-defaults-suite", suiteName]),
                                               ownDomain: "app.cranny.Cranny") { name in opened.append(name); return suite })
        #expect(opened == [suiteName])
        #expect(qa.defaults === suite && qa.qaSuite == suiteName)
        #expect(!qa.autosavesWindowFrames)                       // AppKit's frame autosave writes the standard domain
    }

    /// A name that is the app's own domain, a global one, missing or another argument is refused: the run keeps its
    /// settings in memory, never in the standard domain.
    @Test func aSuiteThatWouldBeTheUsersPreferencesIsRefused() throws {
        for arguments in [["--qa-defaults-suite", "app.cranny.Cranny"], ["--qa-defaults-suite", "App.Cranny.Cranny"],
                          ["--qa-defaults-suite", "com.example.own"], ["--qa-defaults-suite", "NSGlobalDomain"],
                          ["--qa-defaults-suite", ".GlobalPreferences"], ["--qa-defaults-suite", ""],
                          ["--qa-defaults-suite", "--qa-state", "open"], ["--qa-defaults-suite"]] {
            let qa = try #require(QAHooks.defaults(LaunchArguments(["Cranny"] + arguments), ownDomain: "com.example.own") { _ in
                Issue.record("opened a suite for \(arguments)")
                return nil
            })
            #expect(qa.defaults is InMemoryDefaults && qa.defaults !== UserDefaults.standard, "\(arguments)")
            #expect(!qa.autosavesWindowFrames)
        }
    }

    /// With the switch on, the settings store the composition root builds, the one-time upgrade, the hooks' setting
    /// writes (Demo mode, a pause), Reset All and the Settings window's last pane all land in the suite, and the
    /// standard domain gets nothing.
    @Test func withTheSwitchTheStandardDomainIsNeverWritten() throws {
        let before = crannyState(in: .standard)
        let suite = RecordingDefaults()
        let qa = try #require(QAHooks.defaults(LaunchArguments(["Cranny", "--qa-defaults-suite", suiteName]),
                                               ownDomain: "app.cranny.Cranny") { _ in suite })
        let services = CompositionRoot.makeServices(notch: PreviewNotchControl(), environment: PreviewSystemEnvironment(),
                                                    app: PreviewAppControl(), defaults: qa.defaults, paths: .temporary())
        let settings = services.settings
        settings.upgradeStoredSettings()
        settings[CoreSettings.demoMode] = true                                   // what --qa-demo on does
        settings[CoreSettings.typeToCapture] = "todos"
        settings[CoreSettings.openMode] = .click
        settings.reset(CoreSettings.openMode)
        let snapshot = settings.snapshot()
        settings.resetAll()
        settings.restore(snapshot)
        SettingsWindowController(registry: ModuleRegistry(services: services), defaults: qa).rememberLastPane("about")

        #expect(Set(suite.written).isSuperset(of: ["cranny.revision", "cranny.general.demoMode", "cranny.keyboard.typeToCapture",
                                                   "cranny.general.openMode", "CrannySettingsLastPane"]))
        #expect(settings[CoreSettings.demoMode] && settings[CoreSettings.typeToCapture] == "todos")
        #expect(crannyState(in: .standard) == before)                            // the app's preferences: untouched
    }
}

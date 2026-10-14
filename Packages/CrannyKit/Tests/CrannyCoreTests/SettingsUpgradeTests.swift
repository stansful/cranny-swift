import Foundation
import Testing
@testable import CrannyCore

// Ruling E2 (§10.20 #24): Type to capture is Off on a fresh install; an install from before keeps what it had.

@MainActor @Suite struct SettingsUpgradeTests {
    private let captureKey = SettingsStore.keyPrefix + CoreSettings.typeToCapture.id

    @Test func typeToCaptureIsOffOnAFreshInstall() {
        let defaults = InMemoryDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(CoreSettings.typeToCapture.defaultValue == nil)
        store.upgradeStoredSettings()
        #expect(store[CoreSettings.typeToCapture] == nil)
        #expect(defaults.object(forKey: captureKey) == nil)                 // nothing written for it
        #expect(store.storedRevision == SettingsStore.currentRevision)       // later launches are not "old" either
        store.upgradeStoredSettings()
        #expect(store[CoreSettings.typeToCapture] == nil)
    }

    @Test func anEarlierInstallThatKeptTheDefaultKeepsNotes() {
        let defaults = InMemoryDefaults()
        let old = SettingsStore(defaults: defaults)
        old[CoreSettings.onboardingCompletedVersion] = "0.9"               // an install from before revisions
        let store = SettingsStore(defaults: defaults)
        #expect(store[CoreSettings.typeToCapture] == nil)                    // what today's default would give it
        store.upgradeStoredSettings()
        #expect(store[CoreSettings.typeToCapture] == "notes")
        #expect(store.storedRevision == 1)
        store[CoreSettings.typeToCapture] = nil                              // the user turns it off later
        store.upgradeStoredSettings()                                        // the next launch
        #expect(SettingsStore(defaults: defaults)[CoreSettings.typeToCapture] == nil)
    }

    @Test func aValueTheUserChoseIsNeverTouched() throws {
        for chosen in ["todos", "notes"] as [String?] + [nil] {
            let defaults = InMemoryDefaults()
            defaults.set(try JSONEncoder().encode(chosen), forKey: captureKey)  // stored by an earlier version
            let store = SettingsStore(defaults: defaults)
            store.upgradeStoredSettings()
            #expect(store[CoreSettings.typeToCapture] == chosen)
        }
    }

    /// Reset All returns to today's defaults (Off), and neither it nor its Undo makes the install look old again.
    @Test func resetAllAndItsUndoKeepTheRevision() {
        let defaults = InMemoryDefaults()
        let old = SettingsStore(defaults: defaults)
        old[CoreSettings.onboardingCompletedVersion] = "0.9"
        let store = SettingsStore(defaults: defaults)
        store.upgradeStoredSettings()
        #expect(store[CoreSettings.typeToCapture] == "notes")
        let snapshot = store.snapshot()
        store.resetAll()
        #expect(store[CoreSettings.typeToCapture] == nil && store.storedRevision == 1)
        store[CoreSettings.openMode] = .click                                // something stored again
        store.upgradeStoredSettings()                                        // the next launch
        #expect(store[CoreSettings.typeToCapture] == nil)
        store.restore(snapshot)
        #expect(store[CoreSettings.typeToCapture] == "notes" && store.storedRevision == 1)
    }

    /// Launch arguments that seed settings (QA) are not a stored install.
    @Test func onlyStoredKeysMakeAnInstallOld() {
        let defaults = InMemoryDefaults()
        defaults.register(defaults: ["AppleLanguages": ["ru"], "NSSomeAppKitState": true])   // not Cranny keys
        let store = SettingsStore(defaults: defaults)
        store.upgradeStoredSettings()
        #expect(store[CoreSettings.typeToCapture] == nil)
    }
}

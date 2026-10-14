// CrannyCore/Settings/SettingsUpgrades.swift — one-time upgrades of the settings an earlier version stored, run once
// at launch by the shell (AppDelegate, after `--diagnostics` has had its chance to quit, before the modules launch).
//
// The store records the settings revision of the install under `cranny.revision` (kept by Reset All, which returns
// to today's defaults, not to an older version's). A fresh install, one with no Cranny key stored yet, starts at
// today's revision and gets today's defaults; an install from before gets every later step once, in order.
//
// Revision 1 (ruling E2, ARCHITECTURE §10.20 #24): Type to capture became Off by default. The setting is stored only
// when it differs from the default, so an earlier install that kept the old default (Notes) has nothing stored and
// would turn Off: it gets Notes written explicitly. A value the user chose is never touched.
import Foundation
import os

extension SettingsStore {
    /// Where the install's settings revision is kept (not a `SettingKey`: no pane shows it, Reset All keeps it).
    static let revisionKey = keyPrefix + "revision"
    /// Today's settings revision; add a step to `upgrade(from:)` with each bump.
    static let currentRevision = 1

    /// The install's settings revision: today's for a fresh install, 0 for one from before revisions existed.
    var storedRevision: Int? { defaults.object(forKey: Self.revisionKey) as? Int }

    /// Brings settings stored by an earlier version up to today's revision, once (idempotent). Call at launch before
    /// the modules launch; values change through the store, so anything already reading a key updates.
    public func upgradeStoredSettings() {
        let revision = storedRevision ?? (hasStoredSettings ? 0 : Self.currentRevision)
        if revision < Self.currentRevision { upgrade(from: revision) }
        if storedRevision != Self.currentRevision { defaults.set(Self.currentRevision, forKey: Self.revisionKey) }
    }

    /// A Cranny key is stored (seeded launch arguments do not count: they are not stored).
    private var hasStoredSettings: Bool {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        return defaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix(Self.keyPrefix) && key != Self.revisionKey && arguments[key] == nil
        }
    }

    private func upgrade(from revision: Int) {
        if revision < 1, defaults.object(forKey: Self.keyPrefix + CoreSettings.typeToCapture.id) == nil {
            self[CoreSettings.typeToCapture] = "notes"       // the old default, kept for an install that never changed it
            Log.logger(.settings).info("settings upgraded to revision 1: type to capture keeps Notes")
        }
    }
}

// CrannyHUD/Support/CompetingHUDApps.swift — apps known to install their own media-key tap (ARCHITECTURE.md §7.1,
// risk 6). Taps compete and the one inserted last at the head wins, so Settings ▸ HUD warns while one runs.
// The bundle identifiers are [UNVERIFIED] (from the apps' public pages); a wrong one only hides the warning.
import Foundation

nonisolated enum CompetingHUDApps {
    /// Bundle identifier (lowercased) → product name shown in the warning.
    static let known: [String: String] = [
        "me.guillaumeb.monitorcontrol": "MonitorControl",
        "com.rogueamoeba.soundsource": "SoundSource",
        "com.dannystewart.volumehud": "volumeHUD",
    ]

    /// Names of the known apps among `bundleIDs` (running applications), sorted, without duplicates.
    static func running(in bundleIDs: [String?]) -> [String] {
        Set(bundleIDs.compactMap { $0.flatMap { known[$0.lowercased()] } }).sorted()
    }
}

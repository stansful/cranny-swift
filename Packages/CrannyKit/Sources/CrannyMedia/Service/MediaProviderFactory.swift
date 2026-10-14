// CrannyMedia/Service/MediaProviderFactory.swift — the provider chain perl → ruby → AppleScript (opt-in) → none
// (ARCHITECTURE.md §6.2, §6.5). Factories are tried in order; one that returns nil (interpreter or bridge
// missing, fallback switched off) is skipped at once.
import CrannyCore
import Foundation

struct MediaProviderFactory {
    let kind: MediaProviderKind
    /// False = skip this provider (the AppleScript fallback while "Apple Events fallback" is off).
    var isEnabled: @MainActor () -> Bool = { true }
    /// nil = not available on this Mac. May do file I/O off the main actor.
    let make: @MainActor () async -> (any MediaProvider)?
}

extension MediaProviderFactory {
    /// The app's chain. The bridge library is located once, off the main actor (quarantine copy included).
    @MainActor static func standardChain(settings: SettingsStore, paths: AppPaths,
                                         permissions: PermissionsCenter) -> [MediaProviderFactory] {
        let bridge = BridgeResolution(paths: paths)
        return [
            MediaProviderFactory(kind: .perl) {
                let resolved = await bridge.resolve()
                guard resolved.hosts.contains(.perl) else { return nil }
                return resolved.dylib.map { MediaRemoteBridgeProvider(host: .perl, dylib: $0) }
            },
            MediaProviderFactory(kind: .ruby) {
                let resolved = await bridge.resolve()
                guard resolved.hosts.contains(.ruby) else { return nil }
                return resolved.dylib.map { MediaRemoteBridgeProvider(host: .ruby, dylib: $0) }
            },
            MediaProviderFactory(kind: .appleScript, isEnabled: { settings[MediaSettings.allowAppleEvents] }) {
                AppleScriptProvider { bundleID in permissions.status(.automation(bundleID: bundleID)) == .granted }
            },
        ]
    }
}

/// Where the bridge library is and which interpreters exist; resolved once per launch (file I/O off main).
@MainActor final class BridgeResolution {
    nonisolated struct Result: Sendable {
        var dylib: URL?
        var hosts: Set<BridgeConnection.Host>
    }

    private let paths: AppPaths
    private var cached: Result?

    init(paths: AppPaths) { self.paths = paths }

    func resolve() async -> Result {
        if let cached { return cached }
        let result = await Self.lookUp(paths)
        cached = result
        return result
    }

    @concurrent private static func lookUp(_ paths: AppPaths) async -> Result {
        Result(dylib: BridgeLocator.locateForApp(paths: paths),
               hosts: Set(BridgeConnection.Host.allCases.filter(\.isAvailable)))
    }
}

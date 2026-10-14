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
    /// The app's chain. The bridge library is located off the main actor before every helper spawn (quarantine copy
    /// checked against the app's library each time); the interpreters are looked up once.
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
                // A fresh answer, asked off the main actor (PermissionsCenter's cache is refreshed by it).
                AppleScriptProvider { bundleID in await permissions.currentStatus(.automation(bundleID: bundleID)) == .granted }
            },
        ]
    }
}

/// Where the bridge library is and which interpreters exist (file I/O off main). The interpreters are looked up once
/// per launch. The library is located again for every spawn (each provider start and supervisor restart): the
/// quarantine copy sits in a directory other processes of the user can write, so a copy that changed since the last
/// spawn is rewritten from the app's library before perl loads it (`BridgeLocator.unquarantinedCopy`).
@MainActor final class BridgeResolution {
    typealias Host = BridgeConnection.Host

    nonisolated struct Result: Sendable {
        var dylib: URL?
        var hosts: Set<Host>
    }

    private let locate: @Sendable () -> URL?
    private let findHosts: @Sendable () -> Set<Host>
    private var hosts: Set<Host>?

    convenience init(paths: AppPaths) {
        self.init(locate: { BridgeLocator.locateForApp(paths: paths) },
                  hosts: { Set(Host.allCases.filter(\.isAvailable)) })
    }

    init(locate: @escaping @Sendable () -> URL?, hosts: @escaping @Sendable () -> Set<Host>) {
        self.locate = locate
        findHosts = hosts
    }

    func resolve() async -> Result {
        let found = await Self.lookUp(locate, hosts: hosts == nil ? findHosts : nil)
        if let foundHosts = found.hosts { hosts = foundHosts }
        return Result(dylib: found.dylib, hosts: hosts ?? [])
    }

    @concurrent private static func lookUp(_ locate: @Sendable () -> URL?, hosts: (@Sendable () -> Set<Host>)?) async
        -> (dylib: URL?, hosts: Set<Host>?) {
        (locate(), hosts?())
    }
}

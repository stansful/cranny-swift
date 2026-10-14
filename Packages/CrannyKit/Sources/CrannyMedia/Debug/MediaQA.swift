// CrannyMedia/Debug/MediaQA.swift — Debug-only visual QA for media (docs/CONTRIBUTING.md "Visual QA hooks"):
//
//   --qa-media playing | paused | none   replace the live service by the sample track (playing or paused), or by
//                                       a service with no provider ("nothing playing"). No helper is spawned and
//                                       no command ever reaches a real player.
//
// Combine with the shell's hooks: no `--qa-state` shows the compact activity (the arbiter picks Now Playing),
// `--qa-state open` shows the widget, `--qa-settings media` the pane. Compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

enum MediaQA {
    static func service(_ services: CrannyServices, arguments: [String] = ProcessInfo.processInfo.arguments) -> MediaService? {
        guard let i = arguments.firstIndex(of: "--qa-media"), i + 1 < arguments.count else { return nil }
        log.info("QA: media \(arguments[i + 1], privacy: .public)")
        VisualizerNSView.qaIgnoresOcclusion = true
        switch arguments[i + 1] {
        case "playing", "paused":
            return SampleMedia.service(settings: services.settings, environment: services.environment,
                                       permissions: services.permissions, playing: arguments[i + 1] == "playing")
        case "none":
            return MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions,
                                providers: [MediaProviderFactory(kind: .sample) { SampleProvider(snapshot: nil) }])
        default:
            return nil
        }
    }
}
#endif

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
        guard let mode = LaunchArguments(arguments).value(after: "--qa-media") else { return nil }
        log.info("QA: media \(mode, privacy: .public)")
        VisualizerNSView.qaIgnoresOcclusion = true
        switch mode {
        case "playing", "paused":
            return SampleMedia.service(settings: services.settings, environment: services.environment,
                                       permissions: services.permissions, playing: mode == "playing")
        case "none":
            return MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions,
                                providers: [MediaProviderFactory(kind: .sample) { SampleProvider(snapshot: nil) }])
        default:
            return nil
        }
    }
}
#endif

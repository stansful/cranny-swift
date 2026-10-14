// CrannyMedia/MediaModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §10.2). `register(in:)`
// only creates models and contributes; the helper process and the Core Audio listeners start in `onLaunch`.
import CrannyCore
import Foundation
import SwiftUI

/// Media: Now Playing, the Media widget and the media bridge client. Registered by the shell's `CompositionRoot`.
public enum MediaModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.media`).
    public static var id: ModuleID { .media }

    /// Publishes `services.nowPlaying`, then the widget, the Now Playing activity (+ sample, + options row),
    /// Settings ▸ Media, ⌘K commands and the permissions the module may ask for.
    public static func register(in registry: ModuleRegistry) {
        register(in: registry, isInstalled: ScriptablePlayer.isInstalled)
    }

    /// `isInstalled(bundleID)` decides which players get an Automation use: Settings ▸ Permissions and onboarding
    /// list only players this Mac has (the app asks Launch Services, one lookup per player at launch: about 1 ms
    /// for the first lookup in a process, microseconds after it). The registry is fixed after launch, so a player
    /// installed while Cranny runs gets its row from the next launch.
    static func register(in registry: ModuleRegistry, isInstalled: (String) -> Bool) {
        let services = registry.services
        let service = makeService(services)
        services.nowPlaying = service
        let health = BridgeHealthMonitor(service: service)
        service.health = health

        registry.add(widget: MediaWidget(service: service, services: services))
        registry.add(activity: NowPlayingActivity(service: service, settings: services.settings), kind: NowPlayingActivity.kind,
                     sample: {
                         NowPlayingActivity(service: SampleMedia.service(settings: services.settings, environment: services.environment,
                                                                         permissions: services.permissions),
                                            settings: services.settings, open: { _ in })
                     },
                     options: { AnyView(NowPlayingOptions(settings: services.settings)) })
        registry.add(settingsPage: SettingsPage(
            id: .media, title: MediaStrings.moduleName, symbol: "music.note", tint: .red, group: .features, order: 0,
            keywords: MediaPaneStrings.keywords, previewState: .activity) {
                AnyView(MediaSettingsPane(service: service, health: health, services: services))
            })
        registry.add(commands: MediaCommands(service: service))
        for player in ScriptablePlayer.installed(isInstalled) {
            registry.declare(.automation(bundleID: player.bundleID), reason: String(
                localized: "Read and control Music or Spotify when the media helper can’t. Only if you turn on the Apple Events fallback.",
                bundle: .module, comment: "Permissions pane: why Media may ask for Automation"),
                optIn: MediaSettings.allowAppleEvents)              // off by default: onboarding asks only while on
        }
        registry.declare(.systemAudioRecording, reason: String(
            localized: "Let the Live visualizer move with the sound. Cranny never records or saves audio.",
            bundle: .module, comment: "Permissions pane: why Media may ask for System Audio Recording"))

        registry.onLaunch {
            service.start()
            health.start()
        }
        registry.onTerminate {
            health.stop()
            service.stop()                      // closes the helper's stdin and terminates it before Cranny exits
        }
    }

    private static func makeService(_ services: CrannyServices) -> MediaService {
        #if DEBUG
        if let qa = MediaQA.service(services) { return qa }
        #endif
        return MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions,
                            providers: MediaProviderFactory.standardChain(settings: services.settings, paths: services.paths,
                                                                          permissions: services.permissions),
                            allowsLiveVisualizer: true)          // the only service that may run the audio tap
    }
}

/// Settings ▸ Live Activities ▸ Now Playing: "Hide paused media" (DESIGN.md §11.1; key `media.hidePausedAfterSeconds`).
struct NowPlayingOptions: View {
    let settings: SettingsStore

    var body: some View {
        Picker(selection: settings.binding(MediaSettings.hidePausedAfterSeconds)) {
            ForEach(MediaSettings.hidePausedChoices, id: \.self) { seconds in
                Text(verbatim: seconds == 0 ? MediaPaneStrings.never : MediaPaneStrings.after(seconds)).tag(seconds)
            }
        } label: {
            Text(verbatim: MediaPaneStrings.hidePaused)
        }
        .pickerStyle(.menu)
    }
}

#Preview("Now Playing options row") {
    Form { NowPlayingOptions(settings: CrannyServices.preview().settings) }
        .formStyle(.grouped)
        .frame(width: 460, height: 120)
}

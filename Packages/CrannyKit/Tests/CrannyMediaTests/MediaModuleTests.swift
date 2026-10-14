// Registration: every contribution of ARCHITECTURE.md §10.2, published port, declared permissions, no side effects
// (no helper, no hardware, no notch calls) until `onLaunch`.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Media module") @MainActor struct MediaModuleTests {
    @Test func registersWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(MediaModule.self)
        #expect(MediaModule.id == .media)
        #expect(registry.registeringModule == nil)
        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)                                       // registering never opens, flashes or peeks
        let service = try #require(registry.services.nowPlaying as? MediaService)
        #expect(service.status == .idle)                                   // the helper starts in onLaunch
        #expect(service.visualizer.allowsLive)                             // the only service that may tap audio
    }

    @Test func onlyTheLiveServiceMayRunTheAudioTap() throws {
        // Samples (Settings stage, onboarding, widget previews) and Debug QA services show a fictional track:
        // in Live mode their visualizers must draw Ambient, never start a second system audio tap.
        let services = CrannyServices.preview()
        services.settings[MediaSettings.visualizer] = .live
        let sample = SampleMedia.service(settings: services.settings, environment: services.environment, permissions: services.permissions)
        #expect(sample.visualizer.allowsLive == false)
        #expect(sample.visualizer.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .ambient(SyntheticSpectrum(trackKey: "k")))
        sample.visualizer.requestLiveAccess()                              // a no-op: never prompts
        #expect(sample.visualizer.liveStatus == .off)

        let registry = ModuleRegistry(services: .preview())
        registry.register(MediaModule.self)
        let activitySample = try #require(registry.activity(.nowPlaying)?.makeSample?() as? NowPlayingActivity)
        #expect(activitySample.service.visualizer.allowsLive == false)

        #if DEBUG
        defer { VisualizerNSView.qaIgnoresOcclusion = false }
        for argument in ["playing", "paused", "none"] {
            let qa = try #require(MediaQA.service(services, arguments: ["Cranny", "--qa-media", argument]))
            #expect(qa.visualizer.allowsLive == false)
        }
        #endif
    }

    @Test func contributesWidgetActivityPaneCommandsAndPermissions() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(MediaModule.self)

        let widget = try #require(registry.widget(.media))
        #expect(widget.sizes == WidgetSizes(minimum: 4, preferred: 5, maximum: 6))
        #expect(widget.symbol == "music.note")
        #expect(widget.hasOptions)

        let activity = try #require(registry.activity(.nowPlaying))
        #expect(activity.kind == NowPlayingActivity.kind)
        #expect(activity.makeSample != nil)
        #expect(activity.makeOptions != nil)
        let sample = try #require(activity.makeSample?())
        #expect(sample.isActive)
        #expect(sample !== activity.activity)

        let page = try #require(registry.settingsPages.first { $0.id == .media })
        #expect(page.group == .features)
        #expect(page.tint == .red)
        #expect(page.namespaces == [.media])
        #expect(page.previewState == .activity)
        #expect(page.keywords.count >= 8)

        #expect(registry.commandProviders.count == 1)
        let kinds = Set(registry.permissionUses.map(\.kind))
        #expect(kinds == [.automation(bundleID: "com.apple.Music"), .automation(bundleID: "com.spotify.client"), .systemAudioRecording])
        #expect(registry.permissionUses.allSatisfy { $0.module == .media && !$0.reason.isEmpty })
    }

    @Test func diagnosticsNeverContainPersonalData() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(MediaModule.self)
        let diagnostics = try #require(registry.services.nowPlaying as? any NowPlayingDiagnostics).diagnostics
        #expect(diagnostics["media.provider"] == "none")
        #expect(diagnostics["media.status"] == "idle")
        #expect(diagnostics["media.degraded"] == "false")
        #expect(diagnostics["media.electedPlayer"] == "unknown")
        let sample = SampleMedia.previewService().diagnostics
        #expect(sample["media.session"] == "playing")
        #expect(!sample.values.contains { $0.contains(SampleMedia.title) || $0.contains(SampleMedia.artist) || $0.contains("Music") })
    }

    @Test func settingsDefaultsMatchTheArchitecture() {
        #expect(MediaSettings.visualizer.defaultValue == .ambient)
        #expect(MediaSettings.allowAppleEvents.defaultValue == false)
        #expect(MediaSettings.ignoredBundleIDs.defaultValue == [])
        #expect(MediaSettings.showsBrowserMedia.defaultValue == true)
        #expect(MediaSettings.artworkInCompact.defaultValue == true)
        #expect(MediaSettings.hidePausedAfterSeconds.defaultValue == 30)
        #expect(MediaSettings.showsVisualizerInWidget.defaultValue == true)
        #expect(MediaSettings.visualizer.id == "media.visualizer")
        #expect(MediaSettings.hidePausedChoices.contains(MediaSettings.hidePausedAfterSeconds.defaultValue))
    }
}

@Suite("Media commands") @MainActor struct MediaCommandsTests {
    @Test func nothingPlayingOffersNothing() {
        let services = CrannyServices.preview()
        let service = MediaService(settings: services.settings, environment: services.environment,
                                   permissions: services.permissions, providers: [])
        #expect(MediaCommands(service: service).commands(matching: "").isEmpty)
    }

    @Test func playPauseNextPreviousFilteredByQuery() {
        let commands = MediaCommands(service: SampleMedia.previewService())
        #expect(commands.commands(matching: "").map(\.id.rawValue) == ["media.playPause", "media.next", "media.previous"])
        #expect(commands.commands(matching: "").first?.title == MediaStrings.pause)
        #expect(commands.commands(matching: "next").map(\.id.rawValue) == ["media.next"])
        #expect(commands.commands(matching: "midnight").count == 3)        // the track title finds them all
        #expect(commands.commands(matching: "zzz").isEmpty)
    }
}

// CrannySettingsUI/Stage/StageSampleActivity.swift — stand-ins for the well-known live activities on the preview
// stage, used only while their module registers no `makeSample` (ARCHITECTURE §3.6: samples normally come from
// `RegisteredActivity.makeSample`). They follow DESIGN.md §9.2 and §10 with tokens only, hold static sample data,
// never touch a real model and run no clocks: a still frame of Now Playing, Timer, Meeting soon and the volume HUD.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class StageSampleActivity: LiveActivity {
    enum Sample: CaseIterable {
        case nowPlaying, timer, meeting, volume

        var id: ActivityID {
            switch self {
            case .nowPlaying: .nowPlaying
            case .timer: .timerRunning
            case .meeting: .meetingSoon
            case .volume: .hud
            }
        }
    }

    let sample: Sample
    let isActive = true
    let revision = 1

    init(_ sample: Sample) { self.sample = sample }

    /// The stand-in for `id`, or nil when the stage has none for that activity.
    static func make(_ id: ActivityID) -> StageSampleActivity? {
        Sample.allCases.first { $0.id == id }.map(StageSampleActivity.init)
    }

    var id: ActivityID { sample.id }

    var priority: ActivityPriority {
        switch sample {
        case .nowPlaying, .timer: .ongoing
        case .meeting: .alert
        case .volume: .hud
        }
    }

    var slot: SlotWidth {
        switch sample {
        case .nowPlaying: .short
        case .timer, .meeting: .medium
        case .volume: .wide
        }
    }

    var palette: AmbientPalette? {
        switch sample {
        case .nowPlaying: .afterglow
        case .timer: .timer
        case .meeting: .tinted(SemanticColor.info.rgb(false))
        case .volume: nil
        }
    }

    var accessibilityLabel: String {
        switch sample {
        case .nowPlaying:
            String(localized: "Now playing: \(StageSampleText.songTitle) by \(StageSampleText.artist)", bundle: .module,
                   comment: "Settings preview stage: VoiceOver label of the sample Now Playing activity; arguments are a song and an artist")
        case .timer:
            String(localized: "Timer: \(StageSampleText.timerLabel), \(StageSampleText.timerValue) left", bundle: .module,
                   comment: "Settings preview stage: VoiceOver label of the sample timer; arguments are its name and the time left")
        case .meeting:
            String(localized: "Meeting soon: \(StageSampleText.meetingTitle)", bundle: .module,
                   comment: "Settings preview stage: VoiceOver label of the sample meeting; the argument is its title")
        case .volume:
            String(localized: "Volume, \(StageSampleText.volumeValue)", bundle: .module,
                   comment: "Settings preview stage: VoiceOver label of the sample volume HUD; the argument is a percentage")
        }
    }

    func compactLeading() -> some View { StageSampleView(sample: sample, placement: .compactLeading) }
    func compactTrailing() -> some View { StageSampleView(sample: sample, placement: .compactTrailing) }
    func minimal() -> some View { StageSampleView(sample: sample, placement: .minimal) }
    func peekRow() -> some View { StageSampleView(sample: sample, placement: .peekRow) }
}

/// Sample content shown by the stand-ins (the song and artist are names, not translated).
enum StageSampleText {
    static let songTitle = "Midnight Window"
    static let artist = "The Example Band"
    static let volume = 0.62
    static let timerProgress = 0.72
    static let timerSeconds = 299

    static var timerValue: String { Duration.seconds(timerSeconds).formatted(.time(pattern: .minuteSecond)) }
    static var volumeValue: String { volume.formatted(.percent.precision(.fractionLength(0))) }
    static var timerLabel: String { String(localized: "Tea", bundle: .module, comment: "Settings preview stage: name of the sample timer") }
    static var meetingTitle: String {
        String(localized: "Design review", bundle: .module, comment: "Settings preview stage: title of the sample meeting")
    }
    /// "in 4m": a tested `compactLabel` abbreviation (DESIGN.md §9.1).
    static var meetingCountdown: String {
        let minutes = Duration.seconds(240).formatted(.units(allowed: [.minutes], width: .narrow))
        return String(localized: "in \(minutes)", bundle: .module,
                      comment: "Settings preview stage: compact countdown to the sample meeting; the argument is \"4m\" (keep it short)")
    }
    /// "10:30–11:00 · Room 4"
    static var meetingDetail: String {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: Date()) ?? Date()
        let end = start.addingTimeInterval(30 * 60)
        let range = (start..<end).formatted(.interval.hour().minute())
        return String(localized: "\(range) · Room 4", bundle: .module,
                      comment: "Settings preview stage: subtitle of the sample meeting; the argument is a time range")
    }
}

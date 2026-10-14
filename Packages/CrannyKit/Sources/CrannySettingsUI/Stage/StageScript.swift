// CrannySettingsUI/Stage/StageScript.swift — what the preview stage shows, as pure data (DESIGN.md §11.2):
// the scene of each picker state (Closed · Activity · Peek · Open · HUD) and the short choreography each
// Simulate chip plays (Song change · Timer · Meeting · Volume · Drop file) before it hands back to the picker.
// No looping demos: a chip plays once (Reduce Motion included) and the stage settles on the selected state.
import CrannyCore
import CrannyNotchUI
import Foundation
import UniformTypeIdentifiers

/// One presentation of the stage's notch, and the motion token that animates into it.
struct StageScene: Equatable {
    var phase: NotchPhase
    var primary: ActivityID?
    var satellite: ActivityID?
    var peekRows: [ActivityID] = []
    var open: OpenState?
    var motion: CrannyMotion.Kind
    /// A one-shot moment to play on arrival (the stage applies the caps of DESIGN.md §5.5).
    var delight: DelightMoment?
}

/// The Simulate chips (DESIGN.md §11.2).
enum SimulateChip: String, CaseIterable, Identifiable {
    case songChange, timer, meeting, volume, dropFile
    var id: String { rawValue }

    /// The activity the chip shows (nil: Drop file opens the catch state instead).
    var activity: ActivityID? {
        switch self {
        case .songChange: .nowPlaying
        case .timer: .timerRunning
        case .meeting: .meetingSoon
        case .volume: .hud
        case .dropFile: nil
        }
    }
}

/// The sample activities the stage can show, already filtered by the user's toggles and ordered.
struct StageCast: Equatable {
    /// Enabled ongoing (P2) samples in the user's order: the compact primary and the satellite.
    var ongoing: [ActivityID]
    /// Every sample whose activity is turned on (chips are offered only for these).
    var available: Set<ActivityID>
}

/// One step of a chip: wait `delay` after the previous step, then show `scene`.
struct StageStep: Equatable {
    var delay: Duration
    var scene: StageScene
}

enum StageScript {
    /// The scene of a picker state. `page` and `mode` are the open page and its mode (Layout & Widgets edits the
    /// layout on the stage); the satellite shows only when enabled.
    static func scene(for state: PreviewStageState, cast: StageCast, page: PageID, mode: NookMode = .grid,
                      showsSatellite: Bool) -> StageScene {
        let primary = cast.ongoing.first
        let satellite = showsSatellite && cast.ongoing.count > 1 ? cast.ongoing[1] : nil
        switch state {
        case .closed:
            return StageScene(phase: .idle, motion: .close)
        case .activity:
            guard let primary else { return StageScene(phase: .idle, motion: .close) }
            return StageScene(phase: .compact, primary: primary, satellite: satellite, motion: .activityIn)
        case .peek:
            guard let primary else { return StageScene(phase: .idle, motion: .close) }
            return StageScene(phase: .peek, primary: primary, satellite: satellite, peekRows: [primary], motion: .peekIn)
        case .open:
            return StageScene(phase: .open, open: OpenState(page: page, mode: mode, reason: .click), motion: .open)
        case .hud:
            guard cast.available.contains(.hud) else { return StageScene(phase: .idle, motion: .close) }
            return StageScene(phase: .compact, primary: .hud, motion: .hudIn)
        }
    }

    /// The steps of a chip, ending on `base` (the picker's scene). Durations are the design's: a peek stays
    /// `peekDuration` (Live Activities ▸ Peek duration), the HUD 1.5 s.
    static func steps(for chip: SimulateChip, base: StageScene, cast: StageCast, page: PageID,
                      peekDuration: Double, showsSatellite: Bool) -> [StageStep] {
        let peek = Duration.milliseconds(Int(peekDuration * 1000))
        switch chip {
        case .songChange, .timer, .meeting:
            guard let id = chip.activity, cast.available.contains(id) else { return [] }
            let other = cast.ongoing.first { $0 != id }
            let satellite = showsSatellite ? other : nil
            let compact = StageScene(phase: .compact, primary: id, satellite: satellite, motion: .activityIn)
            var peekScene = StageScene(phase: .peek, primary: id, satellite: satellite, peekRows: [id], motion: .peekIn)
            if chip == .songChange { peekScene.delight = .songRipple }
            return [
                StageStep(delay: .zero, scene: compact),
                StageStep(delay: .milliseconds(600), scene: peekScene),
                StageStep(delay: peek, scene: StageScene(phase: .compact, primary: id, satellite: satellite, motion: .peekOut)),
                StageStep(delay: .milliseconds(1400), scene: settle(base)),
            ]
        case .volume:
            guard cast.available.contains(.hud) else { return [] }
            return [
                StageStep(delay: .zero, scene: StageScene(phase: .compact, primary: .hud, motion: .hudIn)),
                StageStep(delay: .milliseconds(Int(HoverIntent.hudAutoDismiss * 1000)), scene: settle(base, motion: .hudOut)),
            ]
        case .dropFile:
            let catching = OpenState(page: page, mode: .catchFiles([.fileURL]), reason: .drag)
            var caught = StageScene(phase: .open, open: OpenState(page: page, reason: .drag), motion: .contentSwap)
            caught.delight = .gulp
            return [
                StageStep(delay: .zero, scene: StageScene(phase: .open, open: catching, motion: .open)),
                StageStep(delay: .milliseconds(1800), scene: caught),
                StageStep(delay: .milliseconds(1400), scene: settle(base)),
            ]
        }
    }

    /// `base` entered with a motion that fits the way back (shrinking lands without bounce).
    private static func settle(_ base: StageScene, motion: CrannyMotion.Kind? = nil) -> StageScene {
        var scene = base
        scene.delight = nil
        scene.motion = motion ?? (base.phase == .open ? .resize : base.phase == .idle ? .close : .activitySwap)
        return scene
    }

    /// The state the stage picks for a pane (its `previewState`), falling back to Closed.
    static func initialState(for page: SettingsPage?) -> PreviewStageState { page?.previewState ?? .closed }

    /// Width of the open Nook in cells for `page`: the sum of its widgets' widths, each clamped to the widget's
    /// sizes when the widget is registered, never more than `maxColumns`.
    static func openColumns(items: [NookItem], sizes: (WidgetID) -> WidgetSizes?, maxColumns: Int) -> Int {
        let cells = items.reduce(0) { sum, item in sum + (sizes(item.widget)?.clamp(item.cells) ?? max(item.cells, 1)) }
        return min(max(cells, 1), maxColumns)
    }
}

// CrannyOnboarding/Tutorial/TutorialSteps.swift — the five steps of the interactive tutorial and how each one
// is recognised from the real notch's events (DESIGN.md §12.2). Pure: tests drive it with `NotchEvent`s.
import CrannyCore
import Foundation

/// The tutorial's steps, in order.
nonisolated enum TutorialStep: String, CaseIterable, Sendable {
    /// "Rest the pointer on the notch, or press ⌃⌥N" — any opening the person made.
    case reachNotch
    /// "Drag any file onto the notch" — the Tray caught files.
    case dropFile
    /// "Swipe sideways with two fingers to change the track" — only while something plays, with a trackpad.
    case swipeTrack
    /// "Hold ⌘ to see every shortcut" — the hints appeared.
    case holdCommand
    /// "Pin it with 📌, then press Esc" — pinned, then closed.
    case pinAndClose
}

/// One run of the tutorial: which steps it has, where it is, and the event matching.
nonisolated struct TutorialRun: Equatable, Sendable {
    private(set) var steps: [TutorialStep]
    private(set) var index = 0
    /// `pinAndClose` is two actions: the pin seen during this step.
    private(set) var hasPinned = false

    /// `includesTrackSwipe`: something plays and a trackpad is present (else step 3 is left out).
    init(includesTrackSwipe: Bool) {
        steps = TutorialStep.allCases.filter { $0 != .swipeTrack || includesTrackSwipe }
    }

    var current: TutorialStep? { index < steps.count ? steps[index] : nil }
    var isFinished: Bool { index >= steps.count }
    /// 1-based position and count for "2 of 5".
    var number: Int { min(index, steps.count - 1) + 1 }
    var count: Int { steps.count }

    /// True when `event` completes the current step.
    mutating func handle(_ event: NotchEvent) -> Bool {
        guard let step = current else { return false }
        switch (step, event) {
        case (.reachNotch, .opened(let reason)):
            return Self.isPersonal(reason)
        case (.dropFile, .filesCaught(let count)):
            return count > 0
        case (.swipeTrack, .activityGesture(_, let gesture)):
            return gesture == .swipeLeft || gesture == .swipeRight
        case (.holdCommand, .commandHintsShown):
            return true
        case (.pinAndClose, .pinned(let pinned)):
            hasPinned = pinned
            return false
        case (.pinAndClose, .closed):
            return hasPinned
        default:
            return false
        }
    }

    /// Moves to the next step. The track swipe is dropped if nothing plays any more when it comes up.
    mutating func advance(isPlaying: Bool) {
        guard !isFinished else { return }
        index += 1
        hasPinned = false
        if current == .swipeTrack, !isPlaying {
            steps.remove(at: index)
        }
    }

    /// Starts at `step` (visual QA); out-of-range values clamp.
    mutating func jump(to step: Int) {
        index = min(max(step, 0), max(steps.count - 1, 0))
        hasPinned = false
    }

    /// Openings the person made themselves (not code, not the tutorial).
    static func isPersonal(_ reason: OpenReason) -> Bool {
        switch reason {
        case .hover, .click, .keyboard, .swipe, .drag, .activity: true
        case .programmatic, .tutorial: false
        }
    }
}

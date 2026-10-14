// CrannyOnboarding/Tutorial/TipConditions.swift — when and where a tip (the tutorial bubble, step 2's coach mark)
// may show. It points at the real shape, so it shows only while the notch itself shows: never under a hidden notch
// (no or an empty shape frame), on a locked screen or sleeping displays, while Live Activities are paused, or over
// a full-screen app unless the person shows everything there (DESIGN.md §3.7, ARCHITECTURE.md §4.8). Hiding never
// ends what the tip waits for; it comes back with the notch. Owners observe a `TipPresentation` with Core's
// `observe(_:onChange:)`, so the tip also follows shape changes that arrive without a `NotchEvent` (a peek, an
// activity, the pointer moving to another display: the shell's shape frame reads its observable scene) and the
// settings its sentence and theme come from — no polling.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation

/// The facts that decide whether a tip shows (pure).
nonisolated struct TipConditions: Equatable, Sendable {
    /// `NotchControl.shapeFrameOnScreen()`: nil, or empty while the notch is hidden.
    var shape: CGRect?
    var isScreenLocked = false
    var areDisplaysAsleep = false
    var areLiveActivitiesPaused = false
    var isFullScreenInFront = false
    /// The notch shows everything over full-screen apps (`FullScreenPolicy.showAll`, or Demo mode).
    var showsOverFullScreen = false

    /// The shape to put the tip under, or nil to hide it.
    var anchor: CGRect? {
        guard let shape, shape.width > 0, shape.height > 0 else { return nil }
        guard !isScreenLocked, !areDisplaysAsleep, !areLiveActivitiesPaused else { return nil }
        guard !isFullScreenInFront || showsOverFullScreen else { return nil }
        return shape
    }
}

/// Everything a tip presenter needs now: where (nil = hidden) and with which theme (the notch's, resolved from the
/// settings like the panel's, so the accent, text size and motion personality match the notch it points at).
struct TipSurroundings: Equatable {
    var anchor: CGRect?
    var theme: CrannyTheme

    init(anchor: CGRect?, theme: CrannyTheme) {
        self.anchor = anchor
        self.theme = theme
    }

    /// Reads the notch, the environment and the settings (observable: call it inside `observe(_:onChange:)`).
    init(services: CrannyServices) {
        let environment = services.environment
        let settings = services.settings
        let conditions = TipConditions(shape: services.notch.shapeFrameOnScreen(),
                                       isScreenLocked: environment.isScreenLocked,
                                       areDisplaysAsleep: environment.areDisplaysAsleep,
                                       areLiveActivitiesPaused: environment.areLiveActivitiesPaused,
                                       isFullScreenInFront: environment.isFullScreenInFront,
                                       showsOverFullScreen: settings[CoreSettings.fullScreenPolicy] == .showAll || environment.isDemoMode)
        #if DEBUG
        anchor = OnboardingVisualQA.showsTipsAnyway ? TipConditions(shape: conditions.shape).anchor : conditions.anchor
        #else
        anchor = conditions.anchor
        #endif
        theme = ThemeResolver.theme(settings: settings, albumAccent: services.nowPlaying?.palette?.accent,
                                    notchUnit: 1, isFloatingDisplay: false)
    }
}

/// A tip as it should be now: what it says (nil = nothing to say) and its surroundings. Owners observe it, so a
/// sentence built from settings (the open mode, the shortcut) follows them too.
struct TipPresentation: Equatable {
    /// A visible tip.
    struct Shown: Equatable {
        var content: TipContent
        var anchor: CGRect
        var theme: CrannyTheme
    }

    var content: TipContent?
    var surroundings: TipSurroundings

    /// What to show under which anchor with which theme; nil hides the tip.
    var shown: Shown? {
        guard let content, let anchor = surroundings.anchor else { return nil }
        return Shown(content: content, anchor: anchor, theme: surroundings.theme)
    }
}

/// Puts `TipPresentation`s on a presenter once per change (observation and events may both ask for the same one).
final class TipRenderer {
    let presenter: any TipPresenter
    private var shown: TipPresentation.Shown?

    init(presenter: any TipPresenter) { self.presenter = presenter }

    func render(_ presentation: TipPresentation) {
        guard let next = presentation.shown else { return hide() }
        guard next != shown else { return }
        shown = next
        presenter.show(next.content, under: next.anchor, theme: next.theme)
    }

    /// Hides the tip if this renderer showed it.
    func hide() {
        guard shown != nil else { return }
        shown = nil
        presenter.hide()
    }
}

#if DEBUG
/// Visual QA (`--qa-welcome`, `--qa-tutorial`): screenshots are taken while the screen may be locked, so tips and
/// the coach mark ignore the lock, sleep, pause, full-screen and window-visibility rules. Debug builds only.
public enum OnboardingVisualQA {
    /// Set once by the shell's QA hook before it shows the welcome or starts the tour.
    public static var showsTipsAnyway = false
}
#endif

// CrannyOnboarding/Tutorial/TutorialController.swift — the 5-step interactive tutorial in the real notch
// (DESIGN.md §12.2), WP15. Intra-shell interface fixed by WP0 (ARCHITECTURE.md §10.0): `start()`.
// It positions its bubble panel under `NotchControl.shapeFrameOnScreen()` and detects every step through
// `NotchControl.addEventObserver`; it may create its own AppKit windows.
import CrannyCore
import Foundation

/// Runs the interactive tutorial in the real notch (DESIGN.md §12.2); owned by the shell, started from the
/// menu bar and Settings ▸ About ("Replay tutorial").
@MainActor public final class TutorialController {
    private let registry: ModuleRegistry
    /// True from `start()` until the tour ends or `stop()`.
    public private(set) var isRunning = false

    /// The registry gives the tutorial `NotchControl` (bubble anchor, step detection) and the settings.
    public init(registry: ModuleRegistry) { self.registry = registry }

    /// Starts (or restarts) the tour. WP0 stub: records the request only.
    public func start() {
        isRunning = true
    }

    /// Ends the tour at once (no completion recorded).
    public func stop() {
        isRunning = false
    }
}

// CrannySettingsUI/Components/ResetAllController.swift — "Reset All Settings…" with a 10-s Undo (DESIGN.md §11.3,
// ARCHITECTURE D14): `settings.snapshot()` → `app.resetAllSettings()` → `settings.restore(_:)` on Undo. One sleep
// to the deadline, no polling. Content (notes, to-dos, tray files) is not settings and is never touched.
import CrannyCore
import Foundation
import Observation

@MainActor @Observable final class ResetAllController {
    /// True while Undo is offered (the banner is visible).
    private(set) var canUndo = false
    @ObservationIgnored private var snapshot: SettingsStore.Snapshot?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let app: any AppControl
    @ObservationIgnored private let undoWindow: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    /// `sleep` is injectable so tests can expire the Undo window without waiting.
    init(settings: SettingsStore, app: any AppControl, undoWindow: Duration = SettingsMetrics.undoWindow,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.settings = settings; self.app = app; self.undoWindow = undoWindow; self.sleep = sleep
    }

    /// Takes a snapshot, resets every setting through the app (so the shell re-applies hot keys, panels…)
    /// and offers Undo until the window elapses.
    func resetAll() {
        snapshot = settings.snapshot()
        app.resetAllSettings()
        canUndo = true
        expiry?.cancel()
        expiry = Task { [weak self, undoWindow, sleep] in
            try? await sleep(undoWindow)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Restores every setting from the snapshot taken by `resetAll()`.
    func undo() {
        guard canUndo, let snapshot else { return }
        settings.restore(snapshot)
        dismiss()
    }

    /// Ends the Undo offer (timeout or the banner's close button).
    func dismiss() {
        expiry?.cancel()
        expiry = nil
        snapshot = nil
        canUndo = false
    }
}

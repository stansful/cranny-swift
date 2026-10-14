// CrannyAppShell/Services/ShellNotchControl.swift — the `NotchControl` port (ARCHITECTURE.md §3.9), WP13.
// Created before the registry (modules receive it in `register(in:)`), then attached to the
// `OverlayCoordinator`, which owns the panels. Calls made before the coordinator exists are ignored.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.overlay)

@MainActor final class ShellNotchControl: NotchControl {
    /// Set by `OverlayCoordinator.init`.
    weak var coordinator: OverlayCoordinator?
    /// The shell-owned transient activity behind `flash(symbol:label:)` (`ActivityID.flash`).
    let flashActivity = FlashActivity()
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]

    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) { coordinator?.open(page: page, focus: focus, reason: reason) }
    func close() { coordinator?.closeAll() }
    func togglePinned() { coordinator?.togglePinned() }
    func setHoldOpen(_ hold: Bool, reason: String) { coordinator?.setHoldOpen(hold, reason: reason) }
    func setFocusMode(_ widget: WidgetID?) { coordinator?.setFocusMode(widget) }
    func requestPeek(_ activity: ActivityID) { log.debug("requestPeek(\(activity.rawValue, privacy: .public)) — WP13") }
    func requestKeyboardFocus() { coordinator?.requestKeyboardFocus() }
    func setCalibrationOverlay(_ visible: Bool) { log.debug("calibration overlay — WP13") }
    func shapeFrameOnScreen() -> CGRect? { coordinator?.shapeFrameOnScreen() }
    func presentAirDrop(_ urls: [URL]) async -> Bool { log.debug("AirDrop — WP13 SharingPresenter"); return false }
    func presentSharePicker(_ urls: [URL]) { log.debug("share picker — WP13 SharingPresenter") }

    /// On the pointer's display only; dropped while paused, locked or hidden (the coordinator decides).
    func flash(symbol: String, label: String) {
        coordinator?.showFlash(symbol: symbol, label: label, duration: HoverIntent.peekAutoDismiss)
    }

    @discardableResult func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    func removeEventObserver(_ id: UUID) { observers[id] = nil }

    /// Called by the coordinator for every event of every display.
    func emit(_ event: NotchEvent) { for observer in observers.values { observer(event) } }
}

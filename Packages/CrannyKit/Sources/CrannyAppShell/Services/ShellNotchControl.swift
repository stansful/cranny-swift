// CrannyAppShell/Services/ShellNotchControl.swift — the `NotchControl` port (ARCHITECTURE.md §3.9).
// Created before the registry (modules receive it in `register(in:)`), then attached to the `OverlayCoordinator`,
// which owns the panels. Calls made before the coordinator exists are ignored (modules must not call it from
// `register`, §3.4). Event observers outlive panel rebuilds: they hang off this object, not off a panel.
import AppKit
import CrannyCore
import Foundation

@MainActor final class ShellNotchControl: NotchControl, NotchSelectionFocus {
    /// Set by `OverlayCoordinator.init`.
    weak var coordinator: OverlayCoordinator?
    /// The shell-owned transient activity behind `flash(symbol:label:)` (`ActivityID.flash`).
    let flashActivity = FlashActivity()
    /// AirDrop and the share picker (anchored below the notch; wired by the coordinator).
    let sharing = SharingPresenter()
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]

    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) { coordinator?.open(page: page, focus: focus, reason: reason) }
    func close() { coordinator?.closeAll() }
    func togglePinned() { coordinator?.togglePinned() }
    func setHoldOpen(_ hold: Bool, reason: String) { coordinator?.setHoldOpen(hold, reason: reason) }
    func setFocusMode(_ widget: WidgetID?) { coordinator?.setFocusMode(widget) }
    /// A one-off peek on the pointer's display; ignored while paused, open, hidden or not shown there (§4.7).
    func requestPeek(_ activity: ActivityID) { coordinator?.requestPeek(activity) }
    func requestKeyboardFocus() { coordinator?.requestKeyboardFocus() }
    /// Key status for a selection (a Tray tile): the panel still closes when the pointer leaves (`KeyHold`).
    func requestSelectionFocus() { coordinator?.requestSelectionFocus() }
    func setCalibrationOverlay(_ visible: Bool) { coordinator?.setCalibrating(visible) }
    func shapeFrameOnScreen() -> CGRect? { coordinator?.shapeFrameOnScreen() }
    func presentAirDrop(_ urls: [URL]) async -> Bool { await sharing.presentAirDrop(urls) }
    func presentSharePicker(_ urls: [URL]) { sharing.presentSharePicker(urls) }

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

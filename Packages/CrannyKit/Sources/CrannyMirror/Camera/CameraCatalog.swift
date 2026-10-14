// CrannyMirror/Camera/CameraCatalog.swift — the cameras the Mirror can use and which one it shows.
// Lazy and event-driven: nothing is enumerated until the widget (or its options) first appears, then
// hot-plug, preferred-camera, suspension (lid, privacy shutter) and display changes trigger a refresh while a
// user (a live widget or the options) is on screen. While none is, a change only marks the list stale and the
// next appearance enumerates once, so a wake or display change never lists cameras for a closed panel. No
// polling (ARCHITECTURE.md §9.2).
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.mirror)

@MainActor @Observable final class CameraCatalog {
    /// Connected cameras in menu order (Desk View removed).
    private(set) var devices: [CameraDevice] = []
    /// `AVCaptureDevice.systemPreferredCamera`; nil when there is no camera.
    private(set) var systemPreferredID: String?
    /// False until the first enumeration finished: before that "no camera" is unknown, not true.
    private(set) var isLoaded = false

    /// Called after a refresh that changed something (the model re-resolves its camera).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// Internal (not private) so tests can check which discovery the live module uses.
    @ObservationIgnored let discovery: any CameraDiscovering
    @ObservationIgnored private var isWatching = false
    /// Views that show the list now (`activate` / `release` pairs): live widgets and the options popover.
    @ObservationIgnored private var users = 0
    /// A change arrived while no user was on screen: the next `activate` (or `ensureLoaded`) enumerates.
    @ObservationIgnored private var isStale = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false

    init(discovery: any CameraDiscovering) { self.discovery = discovery }

    /// A user appeared (live widget or options): on first use start watching for changes; enumerate when the
    /// list was never loaded or changed while nobody showed it. Balance every call with `release()`.
    func activate() {
        users += 1
        if !isWatching {
            isWatching = true
            discovery.startWatching { [weak self] in self?.changeObserved() }
        }
        refreshIfNeeded()
    }

    /// A user left the screen. The observers stay armed (they are passive); with no user left a change only
    /// marks the list stale instead of enumerating.
    func release() {
        users = max(users - 1, 0)
    }

    /// App termination: remove the observers.
    func deactivate() {
        guard isWatching else { return }
        isWatching = false
        discovery.stopWatching()
    }

    /// Waits until the list is known and current (a click never acts on a list that has not loaded yet, or that
    /// missed a change while hidden).
    func ensureLoaded() async {
        refreshIfNeeded()
        await refreshTask?.value
    }

    /// Enumerates again and waits for the result.
    func refresh() async {
        scheduleRefresh()
        await refreshTask?.value
    }

    /// Enumerates again soon (the camera reported a state the list may not know yet, e.g. suspended).
    func requestRefresh() { scheduleRefresh() }

    /// The discovery reported a possible change: enumerate now while someone sees the list, else later.
    private func changeObserved() {
        if users > 0 { scheduleRefresh() } else { isStale = true }
    }

    /// Enumerates when the list was never loaded or a change arrived while nobody showed it.
    private func refreshIfNeeded() {
        guard !isLoaded || isStale else { return }
        isStale = false
        scheduleRefresh()
    }

    /// Bursts of notifications (a dock with two cameras) collapse into one running and one queued refresh.
    private func scheduleRefresh() {
        guard refreshTask == nil else { refreshAgain = true; return }
        refreshTask = Task { [weak self, discovery] in
            var again = true
            while again {
                self?.refreshAgain = false
                let snapshot = await discovery.snapshot()
                self?.apply(snapshot)
                again = self?.refreshAgain ?? false
            }
            self?.refreshTask = nil
        }
    }

    private func apply(_ snapshot: CameraSnapshot) {
        let arranged = Self.arrange(snapshot.devices)
        let preferred = snapshot.systemPreferredID
        guard !isLoaded || arranged != devices || preferred != systemPreferredID else { return }
        devices = arranged
        systemPreferredID = preferred
        isLoaded = true
        log.info("cameras: \(arranged.count, privacy: .public), suspended: \(arranged.filter(\.isSuspended).count, privacy: .public)")
        onChange?()
    }

    // MARK: Rules (pure, unit-tested)

    /// Menu order: built-in, Continuity, USB, then the rest, each by name. Desk View is a top-down crop of the
    /// desk for sharing, never a mirror, so it is dropped (R3 §5); duplicates (same `uniqueID`) are dropped.
    nonisolated static func arrange(_ devices: [CameraDevice]) -> [CameraDevice] {
        var seen = Set<String>()
        return devices
            .filter { $0.kind != .deskView && seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.kind != b.kind { return a.kind < b.kind }
                let byName = a.name.localizedStandardCompare(b.name)
                return byName == .orderedSame ? a.id < b.id : byName == .orderedAscending
            }
    }

    /// The camera to show, always a working one while any camera works: the user's pick while it is connected
    /// and not suspended; otherwise the system's preferred camera; otherwise the first camera that is not
    /// suspended. A pick that is unplugged or suspended (lid closed) is used again when it returns, because the
    /// setting is kept. Only when every camera is suspended is a suspended one returned (the pick, else the
    /// preferred, else the first), so the widget can say why it cannot run. nil = no camera.
    nonisolated static func resolve(selectedID: String?, devices: [CameraDevice], systemPreferredID: String?) -> CameraDevice? {
        let picked = selectedID.flatMap { id in devices.first { $0.id == id } }
        let preferred = systemPreferredID.flatMap { id in devices.first { $0.id == id } }
        let inOrder = [picked, preferred].compactMap { $0 } + devices
        return inOrder.first { !$0.isSuspended } ?? inOrder.first
    }
}

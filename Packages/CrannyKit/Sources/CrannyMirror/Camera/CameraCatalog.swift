// CrannyMirror/Camera/CameraCatalog.swift — the cameras the Mirror can use and which one it shows.
// Lazy and event-driven: nothing is enumerated until the widget (or its options) first appears, then
// hot-plug, preferred-camera, suspension (lid, privacy shutter) and display changes trigger a refresh. No polling
// (ARCHITECTURE.md §9.2).
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
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false

    init(discovery: any CameraDiscovering) { self.discovery = discovery }

    /// First use (widget or options appeared): start watching for changes and enumerate once.
    func activate() {
        if !isWatching {
            isWatching = true
            discovery.startWatching { [weak self] in self?.scheduleRefresh() }
        }
        if !isLoaded { scheduleRefresh() }
    }

    /// App termination: remove the observers.
    func deactivate() {
        guard isWatching else { return }
        isWatching = false
        discovery.stopWatching()
    }

    /// Waits until the list is known (a click never acts on a list that has not loaded yet).
    func ensureLoaded() async {
        if !isLoaded { scheduleRefresh() }
        await refreshTask?.value
    }

    /// Enumerates again and waits for the result.
    func refresh() async {
        scheduleRefresh()
        await refreshTask?.value
    }

    /// Enumerates again soon (the camera reported a state the list may not know yet, e.g. suspended).
    func requestRefresh() { scheduleRefresh() }

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

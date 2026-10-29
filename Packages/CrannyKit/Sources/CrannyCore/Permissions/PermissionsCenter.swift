// CrannyCore/Permissions/PermissionsCenter.swift
// The ONLY place that queries or requests TCC permissions (R3 §11). Modules call `request` from the
// inline "needs permission" state of their widget — never at launch, never in bulk.
import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import EventKit
import Observation

/// A privacy permission a module may ask for (declared with `registry.declare(_:reason:)`).
public nonisolated enum PermissionKind: Hashable, Codable, Sendable {
    case accessibility                  // HUD key interception (CGEventTap on NX_SYSDEFINED)
    case calendar                       // EventKit full access
    case camera                         // Mirror
    case bluetooth                      // optional "Show all Bluetooth devices" (IOBluetooth)
    case systemAudioRecording           // optional Live visualizer (Core Audio process tap, macOS 14.2+)
    case automation(bundleID: String)   // Apple Events to Music / Spotify (media fallback)

    /// System Settings deep link (scheme verified on macOS 27; anchors UNVERIFIED there).
    public var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: URL(string: base + "Privacy_Accessibility")
        case .calendar: URL(string: base + "Privacy_Calendars")
        case .camera: URL(string: base + "Privacy_Camera")
        case .bluetooth: URL(string: base + "Privacy_Bluetooth")
        case .systemAudioRecording: URL(string: base + "Privacy_ScreenCapture")
        case .automation: URL(string: base + "Privacy_Automation")
        }
    }
}

/// What macOS says about a permission (Settings shows it with `PermissionStatusPill`).
public nonisolated enum PermissionStatus: String, Codable, Sendable {
    case notDetermined, granted, denied, restricted
    /// No query API (system audio recording) or the automation target is not running.
    case unknown
}

/// The one place that queries and requests permissions (`services.permissions`). Requests come only from an explicit
/// user action (a widget's permission state, Settings ▸ Permissions, onboarding).
///
/// Automation answers are cached per app (§10.20 #27): `AEDeterminePermissionToAutomateTarget` is asked off the main
/// actor, never from a view body, and only again on a refresh (Settings appearing, the app becoming active), after a
/// request, or when a caller needs a fresh answer (`currentStatus`). Until an app's first answer lands, `knownStatus`
/// is nil (rows show a spinner) and `status` reads `.unknown`.
///
/// The other kinds are synchronous queries (`init`, `refresh()`, after a request, `currentStatus`), except where
/// nothing reads the answer in the same turn: an activation of Cranny and `refreshInBackground` ask macOS off the main
/// actor (`EKEventStore.authorizationStatus` alone can take 20 ms when its cache is cold, a stall in the middle of an
/// animation), and the answers land a moment later for the observers of `statuses`. One such query runs at a time: a
/// refresh asked for while it runs asks once more when it lands, and an answer newer than the query (a synchronous
/// refresh, a request, `record`) wins over it.
@MainActor @Observable public final class PermissionsCenter {
    /// macOS's Automation answer for one app, computed off the main actor (`@concurrent`: awaiting it returns to the
    /// main actor); `ask` false never prompts. The app uses `systemAutomationStatus`; tests inject a probe that records
    /// its calls.
    public typealias AutomationProbe = @concurrent @Sendable (_ bundleID: String, _ ask: Bool) async -> PermissionStatus
    /// macOS's answer for a kind with a query API (Accessibility, Calendar, Camera, Bluetooth), off the main actor;
    /// never prompts. The app uses `systemStatus`; tests inject a probe that records its calls.
    public typealias StatusProbe = @concurrent @Sendable (_ kind: PermissionKind) async -> PermissionStatus
    /// The same answer on the main actor, for the synchronous queries (`init`, `refresh()`, after a request,
    /// `currentStatus`); never prompts. The app uses `systemStatus`; `preview()` answers without asking macOS.
    public typealias StatusQuery = @Sendable (_ kind: PermissionKind) -> PermissionStatus

    /// The kinds with a query API (System Audio Recording has none; Automation is asked per app).
    private static let queriedKinds: [PermissionKind] = [.accessibility, .calendar, .camera, .bluetooth]

    /// The last known status of each permission (observable).
    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private var accessibilityWatch: Task<Void, Never>?
    @ObservationIgnored private var recorded: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private let automationProbe: AutomationProbe
    @ObservationIgnored private let statusProbe: StatusProbe
    @ObservationIgnored private let statusQuery: StatusQuery
    /// Per kind (Automation: per app), the number of the latest query or answer; an older query that lands later is
    /// dropped.
    @ObservationIgnored private var generation: [PermissionKind: Int] = [:]
    /// Apps whose first Automation query runs (`knownStatus` starts one at most).
    @ObservationIgnored private var firstQueries: Set<String> = []
    /// A background query (`statusProbe`) is on its way.
    @ObservationIgnored private var isQuerying = false
    /// Kinds asked for while that query ran: asked again when it lands.
    @ObservationIgnored private var queryAgain: Set<PermissionKind> = []
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    /// Queries every permission except Automation once (never prompts; Camera and Bluetooth ask tccd every time,
    /// ≈ 20 ms each on an idle Mac). `automationProbe` answers Automation questions and `statusProbe` the background
    /// queries, both off the main actor; `statusQuery` the synchronous ones. With `refreshesOnActivation`
    /// (the app's one center), every activation of Cranny refreshes the statuses in the background: the user may have
    /// changed them in System Settings meanwhile. Nothing reads them in that turn: rows and the HUD's config follow
    /// them by observation, and the HUD's own check refreshes synchronously when it finds Accessibility stale.
    public init(automationProbe: @escaping AutomationProbe = { await PermissionsCenter.systemAutomationStatus($0, ask: $1) },
                statusProbe: @escaping StatusProbe = { PermissionsCenter.systemStatus($0) },
                statusQuery: @escaping StatusQuery = { PermissionsCenter.systemStatus($0) },
                refreshesOnActivation: Bool = false) {
        self.automationProbe = automationProbe
        self.statusProbe = statusProbe
        self.statusQuery = statusQuery
        for kind in Self.queriedKinds + [.systemAudioRecording] { update(kind, to: query(kind)) }
        if refreshesOnActivation {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshInBackground() }         // queue: .main
            }
        }
    }

    /// A center that never asks macOS (`CrannyServices.preview()`: unit tests and `#Preview`): every kind reads what
    /// a Mac that was never asked answers (`.notDetermined`; Automation `.unknown`, as for a player that is not
    /// running), so a test behaves the same on every Mac, and no tccd or Calendar round trip runs on the main actor
    /// once per test (on a loaded CI machine they add up to seconds, and every real-time bound waits behind them).
    public static func preview() -> PermissionsCenter {
        PermissionsCenter(automationProbe: { _, _ in .unknown }, statusProbe: { _ in .notDetermined },
                          statusQuery: { _ in .notDetermined })
    }

    /// The last known status. Automation: the cached answer, `.unknown` until the first one lands (asking for it
    /// starts the query off the main actor; never a synchronous Apple Events query). Other kinds are queried if
    /// they were never asked for.
    public func status(_ kind: PermissionKind) -> PermissionStatus {
        if case .automation = kind { return knownStatus(kind) ?? .unknown }
        return statuses[kind] ?? query(kind)
    }

    /// The last known status, or nil while an app's first Automation answer is still on its way (asking starts it;
    /// views read this to show a spinner instead of a wrong status). Never blocks.
    public func knownStatus(_ kind: PermissionKind) -> PermissionStatus? {
        guard case .automation(let bundleID) = kind else { return status(kind) }
        if let known = statuses[kind] { return known }
        if firstQueries.insert(bundleID).inserted {
            Task { [weak self] in
                await self?.queryAutomation(bundleID)
                self?.firstQueries.remove(bundleID)
            }
        }
        return nil
    }

    /// Asks macOS now (Automation off the main actor; never prompts) and updates the cache: for a caller that must
    /// not act on an answer older than this moment (the media fallback before its scripts).
    public func currentStatus(_ kind: PermissionKind) async -> PermissionStatus {
        guard case .automation(let bundleID) = kind else {
            let answer = query(kind)
            land(answer, for: kind)
            return answer
        }
        return await queryAutomation(bundleID)
    }

    /// Re-query everything (a pane or step that reads the statuses as it appears, a click about to act on the
    /// status): the cheap kinds at once, the Automation answers already known off the main actor (they land a moment
    /// later).
    public func refresh() {
        for kind in Self.queriedKinds + [.systemAudioRecording] { land(query(kind), for: kind) }
        refreshKnownApps()
    }

    /// `refresh()` with every query off the main actor: the answers land a moment later. For a caller that follows
    /// `statuses` by observation (a pane as it appears, an activation of Cranny); never for one that reads a status
    /// right after the call (that one uses `refresh()`).
    public func refreshInBackground() {
        queryInBackground(Self.queriedKinds)
        refreshKnownApps()
    }

    /// `refreshInBackground()` for one kind, for a caller that shows only that permission (a widget as it appears in
    /// the opening Nook).
    public func refreshInBackground(_ kind: PermissionKind) {
        switch kind {
        case .accessibility, .calendar, .camera, .bluetooth: queryInBackground([kind])
        case .systemAudioRecording: update(kind, to: query(kind))
        case .automation(let bundleID): Task { [weak self] in await self?.queryAutomation(bundleID) }
        }
    }

    /// Asks again for every app whose Automation answer is known, off the main actor.
    private func refreshKnownApps() {
        for case .automation(let bundleID) in statuses.keys {
            Task { [weak self] in await self?.queryAutomation(bundleID) }
        }
    }

    /// Shows the system prompt when one exists; otherwise opens System Settings. Returns the new status.
    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt is a mutable C global (Swift 6 error) — use its literal value.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            watchAccessibility()
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .bluetooth:
            await BluetoothPrompt.trigger()
        case .systemAudioRecording:
            break   // prompted by AudioDeviceStart in CrannyMedia; it reports back via `record`
        case .automation(let bundleID):
            let answer = await automationProbe(bundleID, true)           // off the main actor: it blocks while asking
            land(answer, for: kind)                                      // the person's answer: queries begun before
            return answer                                                // it (during the prompt) are dropped
        }
        let s = query(kind)
        land(s, for: kind)                                               // likewise
        return s
    }

    /// Opens the permission's page of Privacy & Security in System Settings.
    public func openSystemSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// For kinds without a query API, or an answer a feature observed (tap delivered audio → granted; an Apple Event
    /// refused with −1743 → denied). A query for the kind still running is superseded.
    public func record(_ status: PermissionStatus, for kind: PermissionKind) {
        recorded[kind] = status
        land(status, for: kind)
    }

    // MARK: Answers

    /// Asks `automationProbe` (never prompts) and stores the answer unless a newer query or answer came meanwhile.
    @discardableResult
    private func queryAutomation(_ bundleID: String) async -> PermissionStatus {
        let kind = PermissionKind.automation(bundleID: bundleID)
        let asked = nextGeneration(kind)
        let answer = await automationProbe(bundleID, false)
        if generation[kind] == asked { update(kind, to: answer) }
        return answer
    }

    /// Asks `statusProbe` for `kinds` off the main actor, one query at a time: kinds asked for while one runs are
    /// asked again when it lands. Each answer is stored unless a newer answer for its kind came meanwhile.
    private func queryInBackground(_ kinds: [PermissionKind]) {
        queryAgain.formUnion(kinds)
        guard !isQuerying else { return }
        let ask = Self.queriedKinds.filter(queryAgain.contains)
        queryAgain.removeAll()
        guard !ask.isEmpty else { return }
        isQuerying = true
        let asked = ask.map { (kind: $0, generation: nextGeneration($0)) }
        let probe = statusProbe
        Task { [weak self] in
            let answers = await Self.answers(for: ask, probe)
            guard let self else { return }
            self.isQuerying = false
            for (kind, generation) in asked where self.generation[kind] == generation {
                if let answer = answers[kind] { self.update(kind, to: answer) }
            }
            self.queryInBackground([])                                       // asked for meanwhile
        }
    }

    /// `probe`'s answers for `kinds`, all asked in one hop off the main actor.
    @concurrent private nonisolated static func answers(for kinds: [PermissionKind],
                                                        _ probe: StatusProbe) async -> [PermissionKind: PermissionStatus] {
        var answers: [PermissionKind: PermissionStatus] = [:]
        for kind in kinds { answers[kind] = await probe(kind) }
        return answers
    }

    /// An answer newer than any query on its way (a request, a recorded observation): stored now, and a query that
    /// began before it is dropped when it lands.
    private func land(_ status: PermissionStatus, for kind: PermissionKind) {
        _ = nextGeneration(kind)
        update(kind, to: status)
    }

    private func nextGeneration(_ kind: PermissionKind) -> Int {
        let next = (generation[kind] ?? 0) + 1
        generation[kind] = next
        return next
    }

    /// Writes only a change, so observers (rows reading `statuses`) are not invalidated by every refresh.
    private func update(_ kind: PermissionKind, to status: PermissionStatus) {
        if statuses[kind] != status { statuses[kind] = status }
    }

    // MARK: Queries (never prompt)

    /// The synchronous answer (`init`, `refresh()`, after a request, `currentStatus`).
    private func query(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility, .calendar, .camera, .bluetooth:
            return statusQuery(kind)
        case .systemAudioRecording:
            return recorded[kind] ?? .unknown
        case .automation:
            return statuses[kind] ?? .unknown         // never queried synchronously: see `queryAutomation`
        }
    }

    /// Accessibility changes do not notify: poll every 1.5 s for up to 2 minutes after a request.
    private func watchAccessibility() {
        accessibilityWatch?.cancel()
        accessibilityWatch = Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self, !Task.isCancelled else { return }
                if AXIsProcessTrusted() { self.land(.granted, for: .accessibility); return }
            }
        }
    }
}

/// Creating a CBCentralManager is what shows the Bluetooth prompt.
@MainActor private enum BluetoothPrompt {
    static var manager: CBCentralManager?
    static func trigger() async {
        guard CBManager.authorization == .notDetermined else { return }
        manager = CBCentralManager(delegate: nil, queue: nil)
        for _ in 0..<60 where CBManager.authorization == .notDetermined {
            try? await Task.sleep(for: .milliseconds(500))
        }
        manager = nil
    }
}

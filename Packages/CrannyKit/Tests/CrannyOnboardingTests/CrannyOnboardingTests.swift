// Shared helpers for the onboarding tests: a registry on preview services with the sample permission uses and a
// notch whose shape frame the test controls, a stage without any screen, and waiting for the main actor's
// follow-up tasks.
import CoreGraphics
import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannyOnboarding

/// `PreviewNotchControl` with a shape on screen (tips show only under a real shape). The frame is observable,
/// like the shell's (`scene.geometry`), so a tip follows it without an event.
@MainActor @Observable final class TestNotch: NotchControl {
    /// The closed notch of a 1512-pt screen; nil or empty = hidden.
    var frame: CGRect? = TestNotch.closed
    static let closed = CGRect(x: 663, y: 950, width: 185, height: 32)
    @ObservationIgnored private(set) var calls: [String] = []
    @ObservationIgnored private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]

    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        calls.append("open(\(page?.rawValue ?? "-"),\(focus?.rawValue ?? "-"),\(reason.rawValue))")
    }
    func close() { calls.append("close") }
    func togglePinned() { calls.append("togglePinned") }
    func setHoldOpen(_ hold: Bool, reason: String) {}
    func setFocusMode(_ widget: WidgetID?) {}
    func requestPeek(_ activity: ActivityID) {}
    func requestKeyboardFocus() { calls.append("key") }
    func setCalibrationOverlay(_ visible: Bool) {}
    func shapeFrameOnScreen() -> CGRect? { frame }
    func presentAirDrop(_ urls: [URL]) async -> Bool { false }
    func presentSharePicker(_ urls: [URL]) {}
    func flash(symbol: String, label: String) { calls.append("flash(\(symbol))") }
    func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    func removeEventObserver(_ id: UUID) { observers[id] = nil }
    /// Simulates the shell emitting an event.
    func emit(_ event: NotchEvent) { for observer in observers.values { observer(event) } }
}

@MainActor func makeRegistry(trackpad: Bool = true) -> ModuleRegistry {
    let environment = PreviewSystemEnvironment()
    environment.hasTrackpad = trackpad
    let services = CrannyServices(settings: SettingsStore(defaults: InMemoryDefaults()), permissions: PermissionsCenter(),
                                  haptics: Haptics(isEnabled: { false }), paths: .temporary(), notch: TestNotch(),
                                  environment: environment, app: PreviewAppControl())
    let registry = ModuleRegistry(services: services)
    registerSamplePermissionUses(in: registry)
    return registry
}

@MainActor func makeStage(_ registry: ModuleRegistry) -> StageScene {
    StageScene(registry: registry, layout: NotchLayout(metrics: .reference), theme: CrannyTheme(), ambient: .afterglow,
               greeting: "Hi")
}

/// A resolver for which exactly `bundleIDs` are installed (an injected lookup, never Launch Services), with those
/// apps already looked up.
@MainActor func installedApps(_ bundleIDs: Set<String>) async -> AppIdentityResolver {
    await FakeInstalls(bundleIDs).resolver(lookingUp: bundleIDs)
}

/// Installed apps a test can change while a flow runs (a player installed meanwhile). `@unchecked Sendable`: the set
/// is behind a lock.
nonisolated final class FakeInstalls: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: Set<String>

    init(_ installed: Set<String> = []) { self.installed = installed }

    func install(_ bundleID: String) { lock.withLock { _ = installed.insert(bundleID) } }
    func contains(_ bundleID: String) -> Bool { lock.withLock { installed.contains(bundleID) } }

    /// A resolver that answers from this set (never Launch Services), with `bundleIDs` already looked up.
    @MainActor func resolver(lookingUp bundleIDs: Set<String>) async -> AppIdentityResolver {
        let identities = AppIdentityResolver(locate: { [self] id in
            contains(id) ? AppIdentity.Location(url: URL(fileURLWithPath: "/Applications/\(id).app"), name: id,
                                                isSafeToRead: false) : nil
        }, icon: { _ in nil })
        for id in bundleIDs { _ = identities.identity(of: id) }
        for _ in 0..<3000 where identities.isLookingUp { try? await Task.sleep(for: .milliseconds(10)) }
        return identities
    }
}

/// Lets follow-up `Task`s on the main actor run, until `condition` holds (or about a second passed).
@MainActor func settle(until condition: () -> Bool = { false }) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor extension ModuleRegistry {
    var testNotch: TestNotch? { services.notch as? TestNotch }
    var previewApp: PreviewAppControl? { services.app as? PreviewAppControl }
    var previewEnvironment: PreviewSystemEnvironment? { services.environment as? PreviewSystemEnvironment }
}

@Test func tutorialStartsAndStops() {
    let tutorial = TutorialController(registry: makeRegistry(), presenter: RecordingTipPresenter())
    #expect(!tutorial.isRunning)
    tutorial.start()
    #expect(tutorial.isRunning)
    tutorial.stop()
    #expect(!tutorial.isRunning)
}

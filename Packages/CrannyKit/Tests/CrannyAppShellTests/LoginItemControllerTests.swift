// Launch at login (ARCHITECTURE.md §7.9) against a fake `SMAppService` — the real login items are never touched.
import AppKit
import CrannyCore
import Foundation
import ServiceManagement
import Testing
@testable import CrannyAppShell

/// Records every call; `register()` moves to `statusAfterRegister` or throws. `statusReads` counts the reads of
/// `status` (each one is an XPC round trip with the real `SMAppService`).
final class FakeLoginItem: LoginItemService {
    var status: SMAppService.Status {
        get { statusReads += 1; return storedStatus }
        set { storedStatus = newValue }
    }
    private var storedStatus: SMAppService.Status = .notRegistered
    private(set) var statusReads = 0
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerFails = false
    private(set) var calls: [String] = []

    struct Refused: Error {}

    func register() throws {
        calls.append("register")
        if registerFails { throw Refused() }
        status = statusAfterRegister
    }
    func unregister() throws {
        calls.append("unregister")
        status = .notRegistered
    }
    func openSystemSettingsLoginItems() { calls.append("openSettings") }
}

private let applications = URL(filePath: "/Applications/Cranny.app")

@Test func loginItemStatusesMapToStates() {
    #expect(LoginItemController.state(for: .enabled) == .enabled)
    #expect(LoginItemController.state(for: .requiresApproval) == .requiresApproval)
    #expect(LoginItemController.state(for: .notRegistered) == .disabled)
    #expect(LoginItemController.state(for: .notFound) == .disabled)              // an ad-hoc app never registered (R3 §9)
}

@Test func translocatedCopiesAreDetected() {
    #expect(LoginItemController.isTranslocated(URL(filePath: "/private/var/folders/xy/T/AppTranslocation/1234-ABCD/d/Cranny.app")))
    #expect(!LoginItemController.isTranslocated(applications))
    #expect(!LoginItemController.isTranslocated(URL(filePath: "/Users/me/Downloads/Cranny.app")))
}

@Test func turningOnRegistersAndOffUnregisters() {
    let fake = FakeLoginItem()
    let controller = LoginItemController(service: fake, bundleURL: applications)
    controller.refresh()
    #expect(controller.state == .disabled)
    controller.setEnabled(true)
    #expect(controller.state == .enabled && fake.calls == ["register"])
    controller.setEnabled(true)                                                     // already on: nothing to do
    #expect(fake.calls == ["register"])
    controller.setEnabled(false)
    #expect(controller.state == .disabled && fake.calls == ["register", "unregister"])
    controller.setEnabled(false)
    #expect(fake.calls == ["register", "unregister"])
}

@Test func approvalIsFinishedInSystemSettings() {
    let fake = FakeLoginItem()
    fake.statusAfterRegister = .requiresApproval
    let controller = LoginItemController(service: fake, bundleURL: applications)
    controller.setEnabled(true)
    #expect(controller.state == .requiresApproval && fake.calls == ["register", "openSettings"])
    controller.setEnabled(true)                                                     // "Open Login Items…"
    #expect(fake.calls == ["register", "openSettings", "openSettings"])
    fake.status = .enabled                                                          // approved there; Cranny becomes active again
    controller.refresh()
    #expect(controller.state == .enabled)
}

@Test func aRefusedRegistrationExplainsAndThenOpensLoginItems() {
    let fake = FakeLoginItem()
    fake.registerFails = true
    let controller = LoginItemController(service: fake, bundleURL: applications)
    controller.setEnabled(true)
    #expect(controller.state == .unavailable(LoginItemController.refusedMessage) && fake.calls == ["register"])
    controller.setEnabled(true)                                                     // second try goes to System Settings
    #expect(fake.calls == ["register", "openSettings"])
    controller.refresh()                                                            // back from System Settings: the real status
    #expect(controller.state == .disabled)
}

@Test func aTranslocatedCopyAsksToBeMovedAndNeverRegisters() {
    let fake = FakeLoginItem()
    let controller = LoginItemController(service: fake, bundleURL: URL(filePath: "/private/var/folders/T/AppTranslocation/X/d/Cranny.app"))
    controller.refresh()
    #expect(controller.state == .unavailable(LoginItemController.moveToApplicationsMessage))
    controller.setEnabled(true)
    #expect(fake.calls.isEmpty && controller.state == .unavailable(LoginItemController.moveToApplicationsMessage))
}

@Test func theStatusIsReadAgainWhenCrannyBecomesActive() async throws {
    let fake = FakeLoginItem()
    let controller = LoginItemController(service: fake, bundleURL: applications)
    controller.start()
    defer { controller.stop() }
    #expect(controller.state == .disabled)
    fake.status = .enabled                                                          // changed in System Settings meanwhile
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    for _ in 0..<40 where controller.state != .enabled { try await Task.sleep(for: .milliseconds(25)) }
    #expect(controller.state == .enabled)
}

/// Counts deliveries of one test's own posts (other tests post `didBecomeActive` too).
@MainActor private final class Deliveries {
    var count = 0
}

/// The status is an XPC round trip, and only Settings and the welcome show it: neither the launch (`start()`) nor an
/// activation before anything showed it reads it. The first reader gets the real status, and from then on every
/// activation reads it again.
@Test func theStatusIsReadOnFirstUseNotAtLaunch() async throws {
    let fake = FakeLoginItem()
    fake.status = .enabled
    let controller = LoginItemController(service: fake, bundleURL: applications)
    controller.start()
    defer { controller.stop() }
    #expect(fake.statusReads == 0)

    // Main-queue observers of one post run in the order they were added: once the probe ran, the controller's
    // observer (added first, for every sender) has run too.
    let sender = NSObject(), deliveries = Deliveries()
    let probe = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: sender,
                                                       queue: .main) { _ in MainActor.assumeIsolated { deliveries.count += 1 } }
    defer { NotificationCenter.default.removeObserver(probe) }
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: sender)
    for _ in 0..<400 where deliveries.count < 1 { try await Task.sleep(for: .milliseconds(25)) }
    #expect(deliveries.count == 1 && fake.statusReads == 0)                         // nothing showed it yet

    #expect(controller.state == .enabled && fake.statusReads == 1)                  // the first reader asks
    #expect(controller.state == .enabled && fake.statusReads == 1)                  // later reads do not

    fake.status = .notRegistered                                                    // changed in System Settings
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: sender)
    for _ in 0..<400 where controller.state != .disabled { try await Task.sleep(for: .milliseconds(25)) }
    #expect(controller.state == .disabled && fake.statusReads >= 2)
}

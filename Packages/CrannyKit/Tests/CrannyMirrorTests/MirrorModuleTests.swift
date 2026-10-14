import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyMirror

@MainActor struct MirrorModuleTests {
    @Test func registersTheWidgetAndThePermissionWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(MirrorModule.self)
        #expect(MirrorModule.id == .mirror)
        #expect(registry.registeringModule == nil)

        let widget = try #require(registry.widget(.mirror))
        #expect(widget.sizes == WidgetSizes(minimum: 2, preferred: 2, maximum: 3))   // DESIGN.md §6.7
        #expect(widget.isFrameless)
        #expect(widget.hasOptions)
        #expect(widget.symbol == "web.camera")
        #expect(widget.title == MirrorCopy.widgetTitle)

        #expect(registry.permissionUses == [PermissionUse(kind: .camera, module: .mirror, reason: MirrorCopy.permissionReason)])
        #expect(registry.activities.isEmpty && registry.settingsPages.isEmpty && registry.shortcuts.isEmpty)

        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)                      // registering never opens, flashes, peeks or holds
    }

    @Test func liveModelUsesTheRealCameraParts() {
        let model = MirrorModule.makeModel(.preview())
        #expect(model.controller is CameraController)
        #expect(model.authorization is PermissionsCenterAuthorization)
        #expect(model.catalog.discovery is AVCameraDiscovery)
        #expect(model.phase == .off)
        #expect(!model.catalog.isLoaded)                  // nothing enumerated at registration
    }

    // MARK: Lifecycle wiring (onLaunch / onTerminate), on fakes and a private notification center

    @Test(arguments: SystemSleepObserver.names)
    func theCameraStopsWhenTheMacSleeps(_ name: Notification.Name) async {
        let center = NotificationCenter()
        let sleep = SystemSleepObserver(center: center)
        let h = MirrorHarness(activated: false)
        let registry = ModuleRegistry(services: .preview())
        MirrorModule.contribute(to: registry, model: h.model, sleep: sleep)
        #expect(!sleep.isObserving)                       // nothing observed before launch
        await registry.runLaunchHooks()
        #expect(sleep.isObserving)

        await h.run()
        #expect(h.model.phase == .running(deviceID: Cameras.builtIn.id))
        center.post(name: name, object: nil)
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .off)
    }

    @Test func launchObservesTheNotchAndTerminateReleasesEverything() async {
        let center = NotificationCenter()
        let sleep = SystemSleepObserver(center: center)
        let h = MirrorHarness(activated: false)
        let registry = ModuleRegistry(services: .preview())
        MirrorModule.contribute(to: registry, model: h.model, sleep: sleep)

        // Before launch nothing observes the notch: a close changes nothing.
        await h.run()
        h.notch.emit(.closed)
        #expect(h.controller.stops == 0)
        h.model.halt(.closed)
        #expect(h.controller.stops == 1)

        await registry.runLaunchHooks()
        await h.model.tap()
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        h.notch.emit(.closed)                             // the launch hook wired the notch observer
        #expect(h.controller.stops == 2)

        await h.model.tap()
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        registry.runTerminateHooks()
        #expect(h.controller.stops == 3)                  // termination releases the camera
        #expect(!sleep.isObserving)
        #expect(!h.discovery.isWatching)

        // After termination nothing observes any more (checked with a camera that runs again).
        await h.model.tap()
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        #expect(h.model.phase == .running(deviceID: Cameras.builtIn.id))
        h.notch.emit(.closed)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(h.controller.stops == 3)
    }
}

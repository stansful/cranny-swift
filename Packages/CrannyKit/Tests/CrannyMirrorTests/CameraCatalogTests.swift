// Camera list rules (Desk View, order, selection fallback) and the lazy, event-driven catalog.
import CrannyCore
import Testing
@testable import CrannyMirror

@MainActor struct CameraCatalogTests {
    @Test func deskViewIsNeverOffered() {
        let arranged = CameraCatalog.arrange([Cameras.deskView, Cameras.builtIn])
        #expect(arranged == [Cameras.builtIn])
    }

    @Test func menuOrderIsBuiltInContinuityUSBThenByName() {
        let b = CameraDevice(id: "b", name: "b Cam", kind: .external)
        let a = CameraDevice(id: "a", name: "A Cam", kind: .external)
        let other = CameraDevice(id: "o", name: "Aaa", kind: .other)
        let arranged = CameraCatalog.arrange([other, b, Cameras.usb, Cameras.iPhone, a, Cameras.builtIn])
        #expect(arranged.map(\.id) == [Cameras.builtIn.id, Cameras.iPhone.id, a.id, b.id, Cameras.usb.id, other.id])
    }

    @Test func duplicatesAreDropped() {
        #expect(CameraCatalog.arrange([Cameras.builtIn, Cameras.builtIn]).count == 1)
    }

    @Test func resolvePrefersTheUsersPickWhileConnected() {
        let devices = [Cameras.builtIn, Cameras.iPhone]
        #expect(CameraCatalog.resolve(selectedID: Cameras.iPhone.id, devices: devices, systemPreferredID: Cameras.builtIn.id) == Cameras.iPhone)
    }

    @Test func resolveFallsBackToTheSystemsPreferredCamera() {
        let devices = [Cameras.builtIn, Cameras.iPhone]
        // Automatic.
        #expect(CameraCatalog.resolve(selectedID: nil, devices: devices, systemPreferredID: Cameras.iPhone.id) == Cameras.iPhone)
        // The pick is unplugged: use the preferred camera until it returns (the setting is kept).
        #expect(CameraCatalog.resolve(selectedID: Cameras.usb.id, devices: devices, systemPreferredID: Cameras.builtIn.id) == Cameras.builtIn)
    }

    @Test func resolveWithoutAPreferredCameraPicksOneThatWorks() {
        let closed = CameraDevice(id: "closed", name: "Built-in", kind: .builtIn, isSuspended: true)
        #expect(CameraCatalog.resolve(selectedID: nil, devices: [closed, Cameras.usb], systemPreferredID: nil) == Cameras.usb)
        // Only suspended cameras: return one, so the widget can say why it cannot run.
        #expect(CameraCatalog.resolve(selectedID: nil, devices: [closed], systemPreferredID: nil) == closed)
        #expect(CameraCatalog.resolve(selectedID: nil, devices: [], systemPreferredID: nil) == nil)
    }

    @Test func aSuspendedPickFallsBackLikeAnUnpluggedOne() {
        let closed = Cameras.builtInSuspended
        // Picked the built-in camera, lid closed: the system's preferred camera...
        #expect(CameraCatalog.resolve(selectedID: closed.id, devices: [closed, Cameras.usb, Cameras.iPhone],
                                      systemPreferredID: Cameras.iPhone.id) == Cameras.iPhone)
        // ...else the first camera that works (the preferred one may be suspended or unknown).
        #expect(CameraCatalog.resolve(selectedID: closed.id, devices: [closed, Cameras.usb], systemPreferredID: closed.id) == Cameras.usb)
        #expect(CameraCatalog.resolve(selectedID: closed.id, devices: [closed, Cameras.usb], systemPreferredID: nil) == Cameras.usb)
        // Every camera suspended: the pick, so the widget explains the camera the user chose.
        let shut = CameraDevice(id: "shut", name: "Shut", kind: .external, isSuspended: true)
        #expect(CameraCatalog.resolve(selectedID: closed.id, devices: [shut, closed], systemPreferredID: shut.id) == closed)
        #expect(CameraCatalog.resolve(selectedID: nil, devices: [closed, shut], systemPreferredID: shut.id) == shut)
    }

    @Test func aSuspensionChangeIsAListChange() async {
        // The live discovery observes each camera's `isSuspended` and calls back; the catalog must treat a flag
        // change alone as a change worth telling the model about.
        let discovery = FakeDiscovery(Cameras.builtInOnly)
        let catalog = CameraCatalog(discovery: discovery)
        var changes = 0
        catalog.onChange = { changes += 1 }
        catalog.activate()
        await catalog.ensureLoaded()
        discovery.change(Cameras.lidClosed)
        #expect(await eventually { catalog.devices.first?.isSuspended == true })
        #expect(changes == 2)
        // `requestRefresh` re-reads without any notification.
        discovery.snapshotValue = Cameras.builtInOnly
        catalog.requestRefresh()
        #expect(await eventually { catalog.devices.first?.isSuspended == false })
        #expect(changes == 3)
    }

    @Test func nothingIsEnumeratedUntilActivated() async {
        let discovery = FakeDiscovery(Cameras.two)
        let catalog = CameraCatalog(discovery: discovery)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(discovery.enumerations == 0)
        #expect(!discovery.isWatching)
        #expect(!catalog.isLoaded)

        catalog.activate()
        await catalog.ensureLoaded()
        #expect(catalog.isLoaded)
        #expect(discovery.isWatching)
        #expect(catalog.devices == [Cameras.builtIn, Cameras.iPhone])
        #expect(catalog.systemPreferredID == Cameras.builtIn.id)
    }

    @Test func hotPlugRefreshesAndNotifies() async {
        let discovery = FakeDiscovery(Cameras.builtInOnly)
        let catalog = CameraCatalog(discovery: discovery)
        var changes = 0
        catalog.onChange = { changes += 1 }
        catalog.activate()
        await catalog.ensureLoaded()
        #expect(changes == 1)

        discovery.change(CameraSnapshot(devices: [Cameras.builtIn, Cameras.usb, Cameras.deskView], systemPreferredID: Cameras.builtIn.id))
        #expect(await eventually { catalog.devices.count == 2 })
        #expect(catalog.devices.map(\.id) == [Cameras.builtIn.id, Cameras.usb.id])
        #expect(changes == 2)

        // A refresh that finds the same list does not notify.
        await catalog.refresh()
        #expect(changes == 2)
    }

    @Test func aChangeWhileNobodyShowsTheListWaitsForTheNextAppearance() async {
        // A wake, a display change or a hot-plug while the panel is closed must not enumerate: it marks the
        // list stale, and the next appearance enumerates once.
        let discovery = FakeDiscovery(Cameras.builtInOnly)
        let catalog = CameraCatalog(discovery: discovery)
        catalog.activate()
        await catalog.ensureLoaded()
        catalog.release()
        #expect(discovery.isWatching)                     // the observers stay armed: they are passive
        let enumerations = discovery.enumerations

        discovery.change(Cameras.builtInAndUSB)
        discovery.change(Cameras.builtInAndUSB)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(discovery.enumerations == enumerations)
        #expect(catalog.devices == [Cameras.builtIn])

        catalog.activate()
        await catalog.ensureLoaded()
        #expect(discovery.enumerations == enumerations + 1)
        #expect(catalog.devices.map(\.id) == [Cameras.builtIn.id, Cameras.usb.id])

        // Nothing changed while hidden: the next appearance does not enumerate.
        catalog.release()
        catalog.activate()
        await catalog.ensureLoaded()
        #expect(discovery.enumerations == enumerations + 1)
    }

    @Test func aClickAfterAHiddenChangeWaitsForTheFreshList() async {
        let discovery = FakeDiscovery(Cameras.two)
        let catalog = CameraCatalog(discovery: discovery)
        catalog.activate()
        await catalog.ensureLoaded()
        catalog.release()
        discovery.change(Cameras.builtInOnly)
        await catalog.ensureLoaded()
        #expect(catalog.devices == [Cameras.builtIn])
    }

    @Test func aSecondUserKeepsChangesLive() async {
        // The options popover and a live widget at once: closing one leaves the other refreshing at once.
        let discovery = FakeDiscovery(Cameras.builtInOnly)
        let catalog = CameraCatalog(discovery: discovery)
        catalog.activate()
        catalog.activate()
        await catalog.ensureLoaded()
        catalog.release()
        discovery.change(Cameras.builtInAndUSB)
        #expect(await eventually { catalog.devices.count == 2 })
        // An extra release never makes the count negative.
        catalog.release()
        catalog.release()
        catalog.activate()
        discovery.change(Cameras.builtInOnly)
        #expect(await eventually { catalog.devices.count == 1 })
    }

    @Test func deactivateStopsWatching() async {
        let discovery = FakeDiscovery(Cameras.two)
        let catalog = CameraCatalog(discovery: discovery)
        catalog.activate()
        await catalog.ensureLoaded()
        catalog.deactivate()
        #expect(!discovery.isWatching)
    }
}

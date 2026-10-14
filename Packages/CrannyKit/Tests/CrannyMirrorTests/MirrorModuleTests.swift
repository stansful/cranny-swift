import CrannyCore
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
        #expect(model.phase == .off)
        #expect(!model.catalog.isLoaded)                  // nothing enumerated at registration
    }
}

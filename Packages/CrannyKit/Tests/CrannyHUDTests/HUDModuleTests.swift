import CrannyCore
import Testing
@testable import CrannyHUD

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(HUDModule.self)
    #expect(HUDModule.id == .hud)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

import CrannyCore
import Testing
@testable import CrannyQuickApps

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(QuickAppsModule.self)
    #expect(QuickAppsModule.id == .quickApps)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

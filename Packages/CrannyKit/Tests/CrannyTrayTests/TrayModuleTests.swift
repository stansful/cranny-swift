import CrannyCore
import Testing
@testable import CrannyTray

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(TrayModule.self)
    #expect(TrayModule.id == .tray)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

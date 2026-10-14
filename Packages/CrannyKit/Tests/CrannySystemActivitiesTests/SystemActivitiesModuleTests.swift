import CrannyCore
import Testing
@testable import CrannySystemActivities

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(SystemActivitiesModule.self)
    #expect(SystemActivitiesModule.id == .system)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

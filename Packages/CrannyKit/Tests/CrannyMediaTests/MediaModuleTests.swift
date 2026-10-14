import CrannyCore
import Testing
@testable import CrannyMedia

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(MediaModule.self)
    #expect(MediaModule.id == .media)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

import CrannyCore
import Testing
@testable import CrannyTimer

@Test func registersEveryContributionWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(TimerModule.self)
    #expect(registry.registeringModule == nil)
    #expect(registry.widget(.timer)?.sizes == WidgetSizes(minimum: 2, preferred: 2, maximum: 3))
    #expect(registry.activity(.timerRunning)?.activity.isActive == false)   // nothing runs at launch
    #expect(registry.shortcuts.map(\.id) == [.startTimer])
    #expect(registry.commandProviders.count == 1)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)
}

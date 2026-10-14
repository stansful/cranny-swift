import CrannyCore
import Testing
@testable import CrannyOnboarding

@Test func tutorialStartsAndStops() {
    let tutorial = TutorialController(registry: ModuleRegistry(services: .preview()))
    #expect(!tutorial.isRunning)
    tutorial.start()
    #expect(tutorial.isRunning)
    tutorial.stop()
    #expect(!tutorial.isRunning)
}

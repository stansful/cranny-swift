// Shared helpers for the onboarding tests: a registry on preview services with the sample permission uses,
// a stage without any screen, and waiting for the main actor's follow-up tasks.
import CrannyCore
import Foundation
import Testing
@testable import CrannyOnboarding

@MainActor func makeRegistry(trackpad: Bool = true) -> ModuleRegistry {
    let environment = PreviewSystemEnvironment()
    environment.hasTrackpad = trackpad
    let registry = ModuleRegistry(services: .preview(environment: environment))
    registerSamplePermissionUses(in: registry)
    return registry
}

@MainActor func makeStage(_ registry: ModuleRegistry) -> StageScene {
    StageScene(registry: registry, layout: NotchLayout(metrics: .reference), theme: CrannyTheme(), ambient: .afterglow,
               greeting: "Hi")
}

/// Lets follow-up `Task`s on the main actor run, until `condition` holds (or about a second passed).
@MainActor func settle(until condition: () -> Bool = { false }) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor extension ModuleRegistry {
    var previewNotch: PreviewNotchControl? { services.notch as? PreviewNotchControl }
    var previewApp: PreviewAppControl? { services.app as? PreviewAppControl }
}

@Test func tutorialStartsAndStops() {
    let tutorial = TutorialController(registry: makeRegistry(), presenter: RecordingTipPresenter())
    #expect(!tutorial.isRunning)
    tutorial.start()
    #expect(tutorial.isRunning)
    tutorial.stop()
    #expect(!tutorial.isRunning)
}

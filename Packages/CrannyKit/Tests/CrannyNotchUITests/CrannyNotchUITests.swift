import CrannyCore
import Foundation
import Observation
import SwiftUI
import Testing
@testable import CrannyNotchUI

@MainActor @Observable private final class SampleActivity: LiveActivity {
    let id: ActivityID
    var isActive = true
    let priority: ActivityPriority = .ongoing
    let slot: SlotWidth = .short
    var revision = 0
    var accessibilityLabel: String { "sample" }
    init(id: ActivityID) { self.id = id }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

@Test func stagesPreferSampleActivitiesOverLiveOnes() {
    let registry = ModuleRegistry(services: .preview())
    let live = SampleActivity(id: .timerRunning)
    registry.add(activity: live, kind: ActivityKind(id: .timerRunning, module: .timer, title: "Timer", symbol: "timer",
                                                    defaultPriority: .ongoing))
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    #expect(scene.activity(.timerRunning, in: registry) === live)
    let sample = SampleActivity(id: .timerRunning)
    scene.sampleActivities[.timerRunning] = sample
    #expect(scene.activity(.timerRunning, in: registry) === sample)
    #expect(scene.activity(.nowPlaying, in: registry) == nil)
}

@Test func sceneGeometryFollowsThePhase() {
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    #expect(scene.geometry == scene.layout.closed)
    scene.phase = .open
    scene.openColumns = 10
    #expect(scene.geometry.bodyWidth == 656)
    scene.open = OpenState(page: .nook, mode: .focus(.notes), reason: .click)
    #expect(scene.geometry.height == 234)                                        // Notes focus: 3 rows
    scene.phase = .hidden
    #expect(scene.geometry == .zero)
}

@Test func placeholderCardsNameWellKnownWidgets() {
    #expect(WidgetPlaceholder(.media).symbol == "music.note")
    #expect(WidgetPlaceholder(.airDrop).title == "AirDrop")
    #expect(WidgetPlaceholder("custom.widget").title == "custom.widget")
}

@Test func themeResolverAppliesSettingsAndNotchFit() throws {
    let services = CrannyServices.preview()
    let settings = services.settings
    settings[CoreSettings.density] = .roomy
    settings[CoreSettings.notchFit] = ["1552-41001": NotchFit(widthTune: 2, radiusTune: 1)]
    let theme = ThemeResolver.theme(settings: settings, albumAccent: nil, notchUnit: 1, isFloatingDisplay: false)
    #expect(theme.density == .roomy && theme.ambience == .subtle)
    let layout = ThemeResolver.layout(metrics: .reference, displayModel: "1552-41001", style: .floatingIsland, settings: settings,
                                      textSize: theme.textSize, density: theme.density, widgetStyle: theme.widgetStyle)
    #expect(layout.closed.bodyWidth == 185 + 2 - 1 && layout.grid.density == .roomy)
    #expect(ThemeResolver.ambientPalette(topActivity: .timer, accent: .automatic, systemAccent: RGB(hex: 0x0A84FF)) == .timer)
    #expect(ThemeResolver.ambientPalette(topActivity: nil, accent: .monochrome, systemAccent: RGB(hex: 0x0A84FF)) == .mono)
}

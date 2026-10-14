import CrannyCore
import Testing
@testable import CrannyOnboarding

@Suite struct PresetLayoutTests {
    private let userPage = NookPage(id: "page.1234", title: "Work", symbol: "briefcase", items: [NookItem(.timer, cells: 2)])

    @Test func theDefaultLayoutIsTheListenerPreset() {
        #expect(PresetLayout.matching(CoreSettings.pages.defaultValue) == .listener)
    }

    @Test func pickingRewritesOnlyHome() {
        var home = NookPreset.listener.page
        home.title = "Mine"
        let pages = [userPage, home]
        let result = PresetLayout.applying(.maker, to: pages)
        #expect(result.count == 2)
        #expect(result[0] == userPage)                       // user pages are untouched and keep their place
        #expect(result[1].id == .nook)
        #expect(result[1].title == "Mine")                   // Home keeps its title and symbol
        #expect(result[1].items == NookPreset.maker.items)
        #expect(PresetLayout.matching(result) == .maker)
    }

    @Test func withoutHomeThePresetPageComesFirst() {
        let result = PresetLayout.applying(.minimal, to: [userPage])
        #expect(result.map(\.id) == [.nook, userPage.id])
        #expect(PresetLayout.homeItems(result) == NookPreset.minimal.items)
    }

    @Test func aLayoutOfOnesOwnMatchesNoPreset() {
        let custom = NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: [NookItem(.notes, cells: 6)])
        #expect(PresetLayout.matching([custom]) == nil)
    }

    @Test func columnsClampToRegisteredSizes() {
        let items = [NookItem(.media, cells: 9), NookItem(.timer, cells: 2), NookItem(.notes, cells: 0)]
        let sizes: [WidgetID: WidgetSizes] = [.media: WidgetSizes(minimum: 4, preferred: 5, maximum: 6)]
        #expect(PresetLayout.columns(of: items, sizes: sizes) == 6 + 2 + 1)
        #expect(PresetLayout.columns(of: [], sizes: [:]) == 1)
        #expect(NookPreset.allCases.allSatisfy { PresetLayout.columns(of: $0.items, sizes: [:]) <= 10 })
    }

    @Test func aLayoutsFeaturesAreItsWidgetsModules() {
        #expect(PresetLayout.modules(of: NookPreset.listener.items) == [.media, .calendar, .quickApps])
        #expect(PresetLayout.modules(of: NookPreset.meetings.items) == [.calendar, .mirror, .timer, .quickApps])
    }
}

@Suite struct PermissionPlanTests {
    private let uses: [PermissionUse] = [
        PermissionUse(kind: .calendar, module: .calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them."),
        PermissionUse(kind: .accessibility, module: .hud, reason: "Replace the system HUD."),
        PermissionUse(kind: .automation(bundleID: "com.apple.Music"), module: .media, reason: "Control music apps."),
        PermissionUse(kind: .automation(bundleID: "com.spotify.client"), module: .media, reason: "Control music apps."),
        PermissionUse(kind: .systemAudioRecording, module: .media, reason: "Live visualizer."),
        PermissionUse(kind: .camera, module: .mirror, reason: "Mirror."),
        PermissionUse(kind: .bluetooth, module: .system, reason: "All Bluetooth devices."),
        PermissionUse(kind: .calendar, module: .calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them."),
    ]

    @Test func listenerAsksForWhatDesignLists() {
        let rows = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.listener.items))
        #expect(rows.map(\.group) == [.calendar, .accessibility, .automation, .bluetooth])
        let automation = rows.first { $0.group == .automation }
        #expect(automation?.kinds == [.automation(bundleID: "com.apple.Music"), .automation(bundleID: "com.spotify.client")])
        #expect(automation?.reasons == ["Control music apps."])
        #expect(rows.first?.kinds == [.calendar])           // declared twice, asked once
    }

    @Test func cameraAndAudioRecordingAreNeverAskedHere() {
        let everything: Set<ModuleID> = [.media, .mirror, .calendar, .hud, .system]
        let rows = PermissionPlan.rows(uses: uses, modules: everything)
        let kinds = rows.flatMap(\.kinds)
        #expect(!kinds.contains(.camera))
        #expect(!kinds.contains(.systemAudioRecording))
        #expect(PermissionGroup(.camera) == nil)
        #expect(PermissionGroup(.systemAudioRecording) == nil)
    }

    @Test func onlyTheFeaturesOfTheLayoutCount() {
        let maker = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.maker.items))
        #expect(maker.map(\.group) == [.accessibility, .bluetooth])   // HUD and devices work with every layout
        let meetings = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.meetings.items))
        #expect(meetings.map(\.group) == [.calendar, .accessibility, .bluetooth])
        #expect(PermissionPlan.rows(uses: [], modules: [.calendar]).isEmpty)
    }

    @Test func rowStateFollowsEveryKind() {
        #expect(PermissionRowState.combining([], requested: false) == .askable)
        #expect(PermissionRowState.combining([.granted, .granted], requested: false) == .granted)
        #expect(PermissionRowState.combining([.granted, .notDetermined], requested: true) == .askable)
        #expect(PermissionRowState.combining([.denied, .granted], requested: true) == .denied)
        #expect(PermissionRowState.combining([.restricted], requested: false) == .restricted)
        #expect(PermissionRowState.combining([.unknown], requested: false) == .askable)
        #expect(PermissionRowState.combining([.unknown, .granted], requested: true) == .deferred)
    }
}

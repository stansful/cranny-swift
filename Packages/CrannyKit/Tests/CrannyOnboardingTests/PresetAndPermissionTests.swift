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

/// Type to capture follows the preset (ruling E2, §10.20 #24): the Keyboard warning never follows from a preset.
@MainActor @Suite struct PresetCaptureTests {
    private let targets = [
        CaptureTarget(id: "notes", title: "Notes", symbol: "note.text", widget: .notes) { _ in .notes },
        CaptureTarget(id: "todos", title: "To-dos", symbol: "checklist", widget: .todos) { _ in .todos },
    ]
    private let todosPage = NookPage(id: "page.5678", title: "Lists", symbol: "checklist", items: [NookItem(.todos, cells: 3)])

    private func target(_ preset: NookPreset, current: String?, userPages: [NookPage] = []) -> String? {
        let pages = PresetLayout.applying(preset, to: [NookPreset.listener.page] + userPages)
        return PresetLayout.captureTarget(home: preset.items, pages: pages, current: current, targets: targets)
    }

    @Test func aPresetWithNotesSetsNotes() {
        #expect(NookPreset.maker.items.contains { $0.widget == .notes })
        #expect(target(.maker, current: nil) == "notes")                  // a fresh install picking Maker
        #expect(target(.maker, current: "todos") == "notes")              // Maker has both: Notes wins
    }

    @Test func aPresetWithToDosButNoNotesSetsToDos() {
        // No built-in preset has To-dos without Notes today; the rule holds for any Home that does.
        let home = [NookItem(.calendar, cells: 4), NookItem(.todos, cells: 3)]
        let pages = [NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: home)]
        #expect(PresetLayout.captureTarget(home: home, pages: pages, current: nil, targets: targets) == "todos")
        #expect(PresetLayout.captureTarget(home: home, pages: pages, current: "notes", targets: targets) == "todos")
    }

    @Test func aPresetWithNeitherTurnsCaptureOffUnlessItsWidgetStaysOnAPage() {
        for preset in [NookPreset.listener, .meetings, .minimal] {
            #expect(target(preset, current: nil) == nil)
            #expect(target(preset, current: "notes") == nil)                // Maker, then Listener: back to Off
            #expect(target(preset, current: "todos", userPages: [todosPage]) == "todos")   // a user page keeps To-dos
            #expect(target(preset, current: "journal") == "journal")        // not registered here: left alone
        }
    }

    @Test func noPresetLeavesATargetWhoseWidgetIsOnNoPage() {
        for preset in NookPreset.allCases {
            for current in [nil, "notes", "todos"] {
                let pages = PresetLayout.applying(preset, to: [NookPreset.listener.page])
                guard let id = PresetLayout.captureTarget(home: preset.items, pages: pages, current: current, targets: targets),
                      let widget = targets.first(where: { $0.id == id })?.widget else { continue }
                #expect(pages.contains { $0.items.contains { $0.widget == widget } }, "\(preset) \(String(describing: current))")
            }
        }
    }
}

@Suite struct PermissionPlanTests {
    private static let appleEvents = SettingKey<Bool>(.media, "allowAppleEvents", default: false)
    private static let allDevices = SettingKey<Bool>(.system, "showsAllBluetoothDevices", default: false)
    private let uses: [PermissionUse] = [
        PermissionUse(kind: .calendar, module: .calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them."),
        PermissionUse(kind: .accessibility, module: .hud, reason: "Replace the system HUD."),
        PermissionUse(kind: .automation(bundleID: "com.apple.Music"), module: .media, reason: "Control music apps.", optIn: Self.appleEvents),
        PermissionUse(kind: .automation(bundleID: "com.spotify.client"), module: .media, reason: "Control music apps.", optIn: Self.appleEvents),
        PermissionUse(kind: .systemAudioRecording, module: .media, reason: "Live visualizer."),
        PermissionUse(kind: .camera, module: .mirror, reason: "Mirror."),
        PermissionUse(kind: .bluetooth, module: .system, reason: "All Bluetooth devices.", optIn: Self.allDevices),
        PermissionUse(kind: .calendar, module: .calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them."),
    ]
    /// Every opt-in switched on (Settings ▸ Media's Apple Events fallback, every Bluetooth device).
    private let allOn: (SettingKey<Bool>) -> Bool = { _ in true }
    /// The defaults of a first run: every opt-in off.
    private let defaults: (SettingKey<Bool>) -> Bool = { $0.defaultValue }

    @Test func listenerAsksForWhatDesignListsOnceItsSwitchesAreOn() {
        let rows = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.listener.items), isOn: allOn)
        #expect(rows.map(\.group) == [.calendar, .accessibility, .automation, .bluetooth])
        let automation = rows.first { $0.group == .automation }
        #expect(automation?.kinds == [.automation(bundleID: "com.apple.Music"), .automation(bundleID: "com.spotify.client")])
        #expect(automation?.reasons == ["Control music apps."])
        #expect(rows.first?.kinds == [.calendar])           // declared twice, asked once
    }

    @Test func aFirstRunAsksOnlyForWhatAGrantMakesWork() {
        // The Apple Events fallback and "every Bluetooth device" are off by default: Automation for Music and
        // Spotify, and Bluetooth, would be granted for nothing. Their switches ask when they are turned on.
        let listener = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.listener.items), isOn: defaults)
        #expect(listener.map(\.group) == [.calendar, .accessibility])
        let minimal = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.minimal.items), isOn: defaults)
        #expect(minimal.map(\.group) == [.accessibility])
        let onlyAppleEvents = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.listener.items),
                                                  isOn: { $0 == Self.appleEvents })
        #expect(onlyAppleEvents.map(\.group) == [.calendar, .accessibility, .automation])
    }

    @Test func cameraAndAudioRecordingAreNeverAskedHere() {
        let everything: Set<ModuleID> = [.media, .mirror, .calendar, .hud, .system]
        let rows = PermissionPlan.rows(uses: uses, modules: everything, isOn: allOn)
        let kinds = rows.flatMap(\.kinds)
        #expect(!kinds.contains(.camera))
        #expect(!kinds.contains(.systemAudioRecording))
        #expect(PermissionGroup(.camera) == nil)
        #expect(PermissionGroup(.systemAudioRecording) == nil)
    }

    @Test func onlyTheFeaturesOfTheLayoutCount() {
        let maker = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.maker.items), isOn: allOn)
        #expect(maker.map(\.group) == [.accessibility, .bluetooth])   // HUD and devices work with every layout
        let meetings = PermissionPlan.rows(uses: uses, modules: PermissionPlan.modules(for: NookPreset.meetings.items), isOn: allOn)
        #expect(meetings.map(\.group) == [.calendar, .accessibility, .bluetooth])
        #expect(PermissionPlan.rows(uses: [], modules: [.calendar], isOn: allOn).isEmpty)
    }

    @Test func rowStateFollowsEveryKind() {
        #expect(PermissionRowState.combining([], requested: false) == .askable)
        #expect(PermissionRowState.combining([.granted, .granted], requested: false) == .granted)
        #expect(PermissionRowState.combining([.granted, .notDetermined], requested: true) == .askable)
        #expect(PermissionRowState.combining([.denied, .granted], requested: true) == .denied)
        #expect(PermissionRowState.combining([.restricted], requested: false) == .restricted)
        #expect(PermissionRowState.combining([.unknown], requested: false) == .askable)
        #expect(PermissionRowState.combining([.unknown, .granted], requested: true) == .deferred)
        // An Automation answer still on its way: a spinner, never "Allow" for a player that may be allowed already.
        #expect(PermissionRowState.combining([.granted, nil], requested: false) == .checking)
        #expect(PermissionRowState.combining([nil, .notDetermined], requested: true) == .checking)
    }
}

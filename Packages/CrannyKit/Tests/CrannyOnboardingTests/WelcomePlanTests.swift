import CrannyCore
import Testing
@testable import CrannyOnboarding

@Suite struct WelcomePlanTests {
    @Test func sixStepsWithATrackpad() {
        let plan = WelcomePlan(hasTrackpad: true)
        #expect(plan.steps == [.hello, .openIt, .gestures, .preset, .permissions, .done])
        #expect(plan.count == 6)
        #expect(plan.number(of: .openIt) == 2)           // VoiceOver: "Step 2 of 6"
        #expect(plan.number(of: .done) == 6)
    }

    @Test func theGestureStepIsSkippedWithoutATrackpad() {
        let plan = WelcomePlan(hasTrackpad: false)
        #expect(plan.steps == [.hello, .openIt, .preset, .permissions, .done])
        #expect(plan.next(after: .openIt) == .preset)
        #expect(plan.previous(before: .preset) == .openIt)
        #expect(plan.resolve(.gestures) == .preset)
        #expect(plan.number(of: .preset) == 3)
        #expect(plan.count == 5)
    }

    @Test func navigationStopsAtBothEnds() {
        let plan = WelcomePlan(hasTrackpad: true)
        #expect(plan.previous(before: .hello) == nil)
        #expect(plan.next(after: .done) == nil)
        #expect(plan.first == .hello)
        #expect(plan.last == .done)
        var step = plan.first
        var visited = [step]
        while let next = plan.next(after: step) { step = next; visited.append(step) }
        #expect(visited == plan.steps)
    }

    @Test func progressLabelNamesBothNumbers() {
        let label = ProgressDots.label(current: 2, count: 6)
        #expect(label.contains("2") && label.contains("6"))
    }
}

@Suite struct OpenMethodTests {
    @Test func realOpeningsMapToTheirCard() {
        #expect(OpenMethod(OpenReason.hover) == .hover)
        #expect(OpenMethod(OpenReason.click) == .click)
        #expect(OpenMethod(OpenReason.keyboard) == .shortcut)
        for reason in [OpenReason.swipe, .drag, .activity, .programmatic, .tutorial] {
            #expect(OpenMethod(reason) == nil)
        }
    }

    @Test func onlyOpeningEventsProveAMethod() {
        #expect(OpenMethod.detected(by: .opened(.keyboard)) == .shortcut)
        #expect(OpenMethod.detected(by: .closed) == nil)
        #expect(OpenMethod.detected(by: .pinned(true)) == nil)
        #expect(OpenMethod.detected(by: .opened(.programmatic)) == nil)
    }

    @Test func cardsSelectTheMatchingOpenMode() {
        for method in OpenMethod.allCases {
            #expect(OpenMethod(mode: method.mode) == method)
        }
        #expect(OpenMethod.shortcut.mode == .shortcutOnly)
    }
}

@Suite struct ShortcutTextTests {
    @Test func theDefaultIsControlOptionN() {
        #expect(ShortcutText.openCranny([:]) == "⌃⌥N")
    }

    @Test func theUsersBindingWins() {
        let combo = KeyCombo(keyCode: 31, modifiers: [.command, .option], display: "⌥⌘O")
        #expect(ShortcutText.openCranny([.openNook: combo]) == "⌥⌘O")
        let off: [ShortcutID: KeyCombo?] = [.openNook: nil]
        #expect(ShortcutText.openCranny(off) == nil)
        #expect(ShortcutText.openCranny([.togglePin: combo]) == "⌃⌥N")
    }

    @Test func theCheatSheetHasSixKeysStartingWithOpenCranny() {
        let sheet = CheatSheetEntry.sheet(openCranny: "⌃⌥N")
        #expect(sheet.count == 6)
        #expect(sheet.first == CheatSheetEntry(action: .open, keys: "⌃⌥N"))
        #expect(Set(sheet.map(\.action)) == Set(CheatSheetEntry.Action.allCases))
        #expect(CheatSheetEntry.sheet(openCranny: nil).count == 5)
    }
}

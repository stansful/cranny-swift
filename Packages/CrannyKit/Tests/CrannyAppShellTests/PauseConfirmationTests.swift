// Pausing and resuming Live Activities confirm themselves (DESIGN.md §9.2, §13; ARCHITECTURE.md §10.20 issue 5): the
// menu, the shortcut and ⌘K go through `PauseController`, which hands each user action to the coordinator; the flash
// (pause or play glyph, a word in the wings, the sentence in its peek row or, while the panel is open, in its header)
// outlasts the pause it confirms, and VoiceOver hears the sentence as feedback. No windows are created.
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI
import Testing
@testable import CrannyAppShell

@MainActor private final class Recorder {
    var confirmations: [PauseConfirmation] = []
    var announcements: [String] = []
}

@Test func everyPauseAndResumeTheUserAsksForIsConfirmed() {
    let settings = CrannyServices.preview().settings
    let recorder = Recorder()
    let pause = PauseController(settings: settings, confirm: { recorder.confirmations.append($0) })
    pause.pause(.untilTomorrow)
    pause.resume()
    pause.resume()                                                              // nothing paused: nothing to confirm
    pause.toggle()                                                              // the shortcut: one hour …
    pause.toggle()                                                              // … then resume
    pause.pause(.untilResumed)
    #expect(recorder.confirmations == [.paused(.untilTomorrow), .resumed, .paused(.oneHour), .resumed, .paused(.untilResumed)])
}

@Test func aPauseThatEndsByItselfIsNotConfirmed() async throws {
    let settings = CrannyServices.preview().settings
    let recorder = Recorder()
    let pause = PauseController(settings: settings, confirm: { recorder.confirmations.append($0) })
    pause.start()
    defer { pause.stop() }
    settings[CoreSettings.pausedUntil] = Date().addingTimeInterval(0.1)          // as if paused before a relaunch
    for _ in 0..<60 where settings[CoreSettings.pausedUntil] != nil { try await Task.sleep(for: .milliseconds(50)) }
    #expect(settings[CoreSettings.pausedUntil] == nil && recorder.confirmations.isEmpty)
    settings[CoreSettings.pausedUntil] = .distantFuture
    settings.resetAll()                                                         // Reset All is not the user resuming
    #expect(recorder.confirmations.isEmpty)
}

@Test func theConfirmationSaysWhatWasChosen() {
    let all: [PauseConfirmation] = PauseDuration.allCases.map { .paused($0) } + [.resumed]
    #expect(Set(all.map(\.message)).count == all.count && all.allSatisfy { !$0.message.isEmpty })
    #expect(all.allSatisfy { !$0.label.isEmpty && WingTextMetrics.fits($0.label, slot: .wide) })   // measured (E4)
    #expect(PauseConfirmation.paused(.oneHour).symbol == "pause.fill" && PauseConfirmation.resumed.symbol == "play.fill")
    #expect(PauseConfirmation.paused(.oneHour).message.contains("1"))
    // The menu's status line and the confirmation are one sentence.
    #expect(PauseMenu.caption(.untilTomorrow) == PauseConfirmation.paused(.untilTomorrow).message)
    #expect(PauseMenu.caption(.untilResumed) == PauseConfirmation.paused(.untilResumed).message)
}

@Test func theConfirmationFlashOutlastsThePauseAndSpellsItOut() {
    let flash = FlashActivity()
    let confirmation = PauseConfirmation.paused(.oneHour)
    flash.show(symbol: confirmation.symbol, label: confirmation.label, detail: confirmation.message, duration: 60,
               outlastsPause: true)
    #expect(flash.isActive && flash.outlastsPause && flash.accessibilityLabel == confirmation.message)
    flash.show(symbol: "doc.on.doc", label: "Copied", duration: 60)            // an ordinary flash replaces it
    #expect(!flash.outlastsPause && flash.detail == nil && flash.accessibilityLabel == "Copied")
    flash.show(symbol: confirmation.symbol, label: confirmation.label, detail: confirmation.message, duration: 60,
               outlastsPause: true)
    flash.hide()
    #expect(!flash.isActive && !flash.outlastsPause)
}

@Test func onlyTheConfirmingFlashShowsWhileActivitiesArePaused() {
    func snapshot(_ id: ActivityID, _ priority: ActivityPriority, ignoresPause: Bool = false) -> ActivitySnapshot {
        ActivitySnapshot(id: id, registrationIndex: 0, isActive: true, priority: priority, slot: .wide, revision: 1,
                         expiresAt: nil, isEnabled: true, peeksOnChange: false, delight: nil, ignoresPause: ignoresPause)
    }
    var arbiter = ActivityArbiter()
    let paused = ArbiterSettings(paused: true)
    let plain = arbiter.update([snapshot(.flash, .alert), snapshot("media", .ongoing)], settings: paused, now: Date())
    #expect(plain.ranked.isEmpty)
    let confirming = arbiter.update([snapshot(.flash, .alert, ignoresPause: true), snapshot("media", .ongoing)],
                                    settings: paused, now: Date())
    #expect(confirming.ranked.map(\.id) == [.flash])
}

@MainActor private func makeOverlay(_ recorder: Recorder) -> (OverlayCoordinator, ModuleRegistry) {
    let registry = ModuleRegistry(services: .preview())
    registry.services.announcer = Announcer(post: { recorder.announcements.append($0) }, now: { 0 })
    return (OverlayCoordinator(registry: registry, environment: ShellEnvironment()), registry)
}

/// The announcement is feedback: two confirmations in a row are both heard (an alert would wait 10 s).
@MainActor @Test func theConfirmationIsAnnouncedEveryTime() {
    let recorder = Recorder()
    let (overlay, _) = makeOverlay(recorder)
    overlay.confirmPause(.paused(.oneHour))
    overlay.confirmPause(.resumed)
    #expect(recorder.announcements == [PauseConfirmation.paused(.oneHour).message, PauseConfirmation.resumed.message])
    #expect(!overlay.notchControl.flashActivity.isActive)                       // no panel to show it on
}

/// The shell's own controllers (the shortcut and ⌘K; the menu's lives in `ShellAppServices`) confirm through the
/// coordinator.
@MainActor @Test func theShortcutConfirmsThroughTheCoordinator() throws {
    let recorder = Recorder()
    let (overlay, registry) = makeOverlay(recorder)
    ShellContributions.register(in: registry, overlay: overlay)
    let shortcut = try #require(registry.shortcuts.first { $0.id == .pauseActivities })
    shortcut.perform()
    shortcut.perform()
    #expect(recorder.announcements == [PauseConfirmation.paused(.oneHour).message, PauseConfirmation.resumed.message])
}

/// The Russian wing words are short states, «Пауза» and «Активны»: the Resume verb («Возобновлены», 12 characters)
/// is 96 pt wide at 1u, and the wing holds 72. The menu and the sentence keep the verb.
@Test func theRussianWingWordsAreShortStates() throws {
    let path = try #require(Bundle.module.path(forResource: "ru", ofType: "lproj"))
    let russian = try #require(Bundle(path: path))
    func text(_ key: String) -> String { russian.localizedString(forKey: key, value: "\u{0}", table: "Localizable") }
    #expect(text("Paused") == "Пауза" && text("Resumed") == "Активны")
    #expect(text("Resume Live Activities").hasPrefix("Возобнов") && text("Live Activities resumed").hasSuffix("возобновлены"))
}

@MainActor @Observable private final class AlertProbe: LiveActivity {
    let id: ActivityID = "probe.meeting"
    let isActive = true
    let priority: ActivityPriority = .alert
    let slot: SlotWidth = .medium
    let revision = 1
    var accessibilityLabel: String { "Meeting soon" }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

/// While the panel is open (⌘K always runs there) the flash can neither show in the wings nor peek: the open header
/// shows the confirmation instead (DESIGN.md §9.2, §10), also when another alert leads this display's lineup.
@MainActor @Test func withThePanelOpenTheConfirmationTakesTheHeader() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.add(activity: AlertProbe(), kind: ActivityKind(id: "probe.meeting", module: "probe", title: "Meeting",
                                                            symbol: "calendar", defaultPriority: .alert))
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    let flash = overlay.notchControl.flashActivity
    let confirmation = PauseConfirmation.resumed
    flash.show(symbol: confirmation.symbol, label: confirmation.label, detail: confirmation.message, duration: 60,
               outlastsPause: true)
    // The coordinator's arbitration for the pointer's display, where it was shown: registered first, the meeting leads.
    let here: DisplayKey = "display-here"
    overlay.pointerDisplay = here
    overlay.flashDisplay = here
    var filter = overlay.displayFilter(for: here)
    filter.isPointerDisplay = true                                              // its panel (none is built here)
    let input = try #require(overlay.arbitrationInput())
    let ranked = overlay.arbiter.update(input.activities, settings: input.settings, now: Date()).ranked
    let lineup = overlay.arbiter.lineup(ranked, on: filter, satellite: true)
    #expect(lineup.primary == "probe.meeting" && lineup.satellite == .flash)

    // That display's panel is open.
    let viewModel = NotchViewModel(scene: NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme()),
                                   registry: registry)
    viewModel.pointerKeys = { (false, false) }
    viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    viewModel.setLineup(lineup)
    let open = PeekScheduler.Display(key: here, isPointerDisplay: true, isOpen: true, isHidden: false, showsPeeks: true,
                                     lineup: lineup)
    #expect(PeekScheduler.target(for: .flash, among: [open], paused: false) == nil)                 // no peek there …
    #expect(viewModel.scene.phase == .open && viewModel.scene.headerActivity == .flash)            // … the header
    #expect((viewModel.activity(.flash) as? any OpenHeaderActivity)?.headerMessage == confirmation.message)

    // An ordinary flash that replaces it waits in the lineup (the arbiter's `.activityChanged` re-syncs the scene).
    flash.show(symbol: "doc.on.doc", label: "Copied", duration: 60)
    viewModel.send(.activityChanged)
    #expect(viewModel.scene.headerActivity == nil)
}

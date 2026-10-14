// The per-display reducer, row by row of ARCHITECTURE.md §4.4 (plus §4.2 phases, §4.5 holds, §4.7 timeouts and
// DESIGN.md §4.6 menu-bar courtesy). Pure: no windows, no timers; time is the index of the input.
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

private let idle = NotchMachineConfig()
private let compact: NotchMachineConfig = {
    var c = NotchMachineConfig()
    c.primary = "test.primary"
    c.primaryWidget = "test.widget"
    c.primaryWidgetPage = "page.focus"
    return c
}()
private let handle: NotchMachineConfig = {
    var c = NotchMachineConfig()
    c.hasHandle = true
    return c
}()

/// Reduces `inputs` one per second from `start`; returns the final state and every effect in order.
private func run(_ inputs: [NotchInput], from start: NotchMachineState = NotchMachineState(),
                 config: NotchMachineConfig = idle) -> (NotchMachineState, [NotchEffect]) {
    var state = start
    var effects: [NotchEffect] = []
    for (i, input) in inputs.enumerated() {
        let (next, fx) = NotchMachine.reduce(state, input, now: Double(i), config: config)
        state = next
        effects += fx
    }
    return (state, effects)
}

private func opened(_ config: NotchMachineConfig = idle) -> NotchMachineState {
    run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: config).0
}

private func phase(_ s: NotchMachineState, _ c: NotchMachineConfig = idle) -> NotchPhase { NotchMachine.phase(s, config: c) }

// MARK: - Hover (rows 1–3, 20–21)

@Test func hoverDwellOpensTheConfiguredPage() {
    var c = idle
    c.lastPage = "page.focus"
    let (dwelling, fx1) = run([.pointerEntered], config: c)
    #expect(fx1 == [.schedule(.dwell, after: HoverIntent.defaultDelay.seconds)])
    #expect(phase(dwelling, c) == .breath)                                     // the breath acknowledges the dwell
    let (open, fx2) = run([.dwellElapsed(shouldOpen: true)], from: dwelling, config: c)
    #expect(open.surface == .open(OpenState(page: "page.focus", reason: .hover)))
    #expect(fx2.contains(.emit(.opened(.hover))))
    #expect(!fx2.contains(.makeKey))                                            // hover never takes keyboard focus
    #expect(phase(open, c) == .open)
}

@Test func passingThroughOrLeavingDoesNotOpen() {
    let (passed, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: false)])
    #expect(passed.isClosed && passed.hover == .inside && phase(passed) == .idle)
    let (left, fx) = run([.pointerEntered, .pointerLeft])
    #expect(left.hover == .outside && fx.last == .cancel(.dwell) && phase(left) == .idle)
    let (late, _) = run([.dwellElapsed(shouldOpen: true)], from: left)       // a dwell that was cancelled
    #expect(late.isClosed)
    // Still moving fast when the dwell elapsed: look again soon (never a 0-s spin); it opens once the pointer rests.
    let (travelling, fx2) = run([.pointerEntered, .dwellRetry])
    #expect(fx2 == [.schedule(.dwell, after: HoverIntent.defaultDelay.seconds), .schedule(.dwell, after: NotchMachine.dwellRetryFloor)])
    #expect(run([.dwellElapsed(shouldOpen: true)], from: travelling).0.isOpen)
    #expect(run([.dwellRetry], from: left).1.isEmpty)                          // gone: nothing to retry
    var instant = idle
    instant.hoverDelay = 0
    #expect(run([.pointerEntered, .dwellRetry], config: instant).1.last == .schedule(.dwell, after: NotchMachine.dwellRetryFloor))
}

/// The dwell is measured against what is required now: a full-screen Space found when the dwell fires (§5.7
/// "lazily, right before a hover-open") extends it to 0.40 s from entry; the retry waits only the rest.
@Test func aDwellThatTurnsOutTooShortWaitsTheRest() {
    let (dwelling, _) = NotchMachine.reduce(NotchMachineState(), .pointerEntered, now: 10, config: idle)
    var fullScreen = NotchEnvironment()
    fullScreen.fullScreen = true                                               // `.alertsAndHUD`
    let (restricted, _) = NotchMachine.reduce(dwelling, .environment(fullScreen), now: 10.12, config: idle)
    #expect(NotchMachine.requiredDwell(restricted, config: idle) == HoverIntent.fullScreenDwell)
    let (_, fx) = NotchMachine.reduce(restricted, .dwellRetry, now: 10.12, config: idle)
    #expect(fx.count == 1)
    if case .schedule(.dwell, let rest)? = fx.first { #expect(abs(rest - 0.28) < 0.0001) } else { Issue.record("no dwell: \(fx)") }
    // Over compact the quick-peek dwell applies whatever the hover delay (DESIGN.md §4.6).
    var long = compact
    long.hoverDelay = HoverIntent.Delay.long.seconds
    #expect(NotchMachine.requiredDwell(dwelling, config: long) == HoverIntent.peekDwell)
    #expect(NotchMachine.requiredDwell(restricted, config: long) == HoverIntent.fullScreenDwell)
}

@Test func compactDwellsForAQuickPeekAndFullScreenDwellsLonger() {
    let (dwell, fx) = run([.pointerEntered], config: compact)
    #expect(fx == [.schedule(.dwell, after: HoverIntent.peekDwell)] && phase(dwell, compact) == .compact)
    let (peek, peekFx) = run([.dwellElapsed(shouldOpen: true)], from: dwell, config: compact)
    #expect(peek.surface == .peek(.hover) && phase(peek, compact) == .peek && !peekFx.contains(.emit(.opened(.hover))))
    var noQuickPeek = compact
    noQuickPeek.quickPeekOnHover = false
    let (inside, none) = run([.pointerEntered], config: noQuickPeek)
    #expect(none.isEmpty && inside.hover == .inside)

    var fullScreen = NotchMachineState()
    fullScreen.environment.fullScreen = true                                   // `.alertsAndHUD` is the default policy
    let (_, slow) = run([.pointerEntered], from: fullScreen)
    #expect(slow == [.schedule(.dwell, after: HoverIntent.fullScreenDwell)])
}

@Test func openModesAndVoiceOverGateHover() {
    var click = idle
    click.openMode = .click
    let (breath, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: click)
    #expect(breath.isClosed && phase(breath, click) == .breath)                // breath only …
    let (open, _) = run([.click], from: breath, config: click)
    #expect(open.surface == .open(OpenState(page: .nook, reason: .click)))     // … the click opens
    var shortcutOnly = idle
    shortcutOnly.openMode = .shortcutOnly
    let (quiet, fx) = run([.pointerEntered], config: shortcutOnly)
    #expect(fx.isEmpty && phase(quiet, shortcutOnly) == .idle)
    var voiceOver = idle
    voiceOver.voiceOverRunning = true
    let (vo, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: voiceOver)
    #expect(vo.isClosed)                                                        // VoiceOver: click, shortcut or VO action
}

@Test func leavingClosesAfterGraceUnlessReentered() {
    let open = opened()
    let (leaving, fx) = run([.pointerLeft], from: open)
    #expect(fx == [.schedule(.grace, after: HoverIntent.closeGrace)] && leaving.timers.contains(.grace))
    let (back, fxBack) = run([.pointerEntered, .timerElapsed(.grace)], from: leaving)
    #expect(back.isOpen && fxBack.first == .cancel(.grace))                    // re-entering cancels the close
    let (closed, fxClosed) = run([.timerElapsed(.grace)], from: leaving)
    #expect(closed.isClosed)
    #expect(fxClosed == [.relinquishKey, .emit(.closed)])                      // row "open → closed"
    var stays = idle
    stays.closeOnLeave = false
    let (kept, _) = run([.pointerLeft, .timerElapsed(.grace)], from: opened(stays), config: stays)
    #expect(kept.isOpen)
}

@Test func aHoverPeekClosesAfterLeavingWithoutAClosedEvent() {
    let (peek, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: compact)
    let (closed, fx) = run([.pointerLeft, .timerElapsed(.grace)], from: peek, config: compact)
    #expect(closed.isClosed && phase(closed, compact) == .compact)
    #expect(!fx.contains(.emit(.closed)) && !fx.contains(.relinquishKey))      // a peek is not the open panel
}

// MARK: - Holds (§4.5)

@Test func pinsHoldsAndModesKeepItOpen() {
    let open = opened()
    let (pinned, fx) = run([.setPinned(true), .pointerLeft], from: open)
    #expect(pinned.isOpen && !pinned.timers.contains(.grace) && fx == [.emit(.pinned(true))])
    let (unpinned, fx2) = run([.setPinned(false)], from: pinned)
    #expect(fx2 == [.emit(.pinned(false)), .schedule(.grace, after: HoverIntent.closeGrace)] && unpinned.isOpen)
    let (held, _) = run([.hold("notes.editing", true), .pointerLeft], from: open)
    #expect(!held.timers.contains(.grace))
    let (released, _) = run([.hold("notes.editing", false), .timerElapsed(.grace)], from: held)
    #expect(released.isClosed)
    for mode in [NookMode.palette, .editLayout, .focus("notes.editor")] {
        let (modal, _) = run([.setMode(mode), .pointerLeft, .timerElapsed(.grace)], from: open)
        #expect(modal.isOpen, "\(mode) holds the panel open")
    }
}

/// §4.4 "pointer leaves exit zone → grace → closed" requires "panel not key"; §4.5 lists "panel is key (typing)",
/// a tracking menu and a popover as holds.
@Test func aKeyPanelATrackingMenuOrAPopoverIsNotClosedByLeaving() {
    for hold in [NotchMachineState.typingHold, NotchMachineState.menuHold, NotchMachineState.popoverHold] {
        let (held, _) = run([.hold(hold, true)], from: opened())
        let (crossed, fx) = run([.pointerEntered, .pointerLeft, .timerElapsed(.grace)], from: held)
        #expect(crossed.isOpen && !crossed.timers.contains(.grace))
        #expect(!fx.contains(.schedule(.grace, after: HoverIntent.closeGrace)) && !fx.contains(.relinquishKey))
        let (released, fx2) = run([.hold(hold, false)], from: crossed)
        #expect(fx2 == [.schedule(.grace, after: HoverIntent.closeGrace)] && released.isOpen)
        #expect(run([.timerElapsed(.grace)], from: released).0.isClosed)
    }
    // A hold that arrives during the grace cancels it.
    let (leaving, _) = run([.pointerLeft], from: opened())
    let (heldLate, fx) = run([.hold(NotchMachineState.menuHold, true)], from: leaving)
    #expect(fx == [.cancel(.grace)] && heldLate.isOpen)
}

// MARK: - Click, hot key, Esc, pin (rows 4, 8, 23–24, 32)

@Test func aClickOpensFocusedOnThePrimarysWidget() {
    let (open, fx) = run([.click], config: compact)
    #expect(open.surface == .open(OpenState(page: "page.focus", focus: "test.widget", reason: .click)))
    #expect(fx.contains(.emit(.opened(.click))) && !fx.contains(.makeKey))     // a click never steals the keyboard
    let (peek, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: compact)
    #expect(run([.click], from: peek, config: compact).0.isOpen)
    let (idleOpen, _) = run([.click])
    #expect(idleOpen.surface == .open(OpenState(page: .nook, reason: .click)))
}

@Test func theHotKeyTogglesAndTakesTheKeyboard() {
    let (open, fx) = run([.hotKey])
    #expect(open.surface == .open(OpenState(page: .nook, reason: .keyboard)) && fx.contains(.makeKey))
    let (closed, fx2) = run([.hotKey], from: open)
    #expect(closed.isClosed && fx2.contains(.relinquishKey) && fx2.contains(.emit(.closed)))
    var locked = NotchMachineState()
    locked.environment.isLocked = true
    #expect(run([.hotKey], from: locked).0.isClosed)                           // "any visible"
}

@Test func escapeLeavesModesFirstThenClosesAndHandsFocusBack() {
    let (open, _) = run([.hotKey])
    for mode in [NookMode.palette, .editLayout, .focus("notes.editor")] {
        let (grid, fx) = run([.setMode(mode), .escape], from: open)
        #expect(grid.surface == .open(OpenState(page: .nook, mode: .grid, reason: .keyboard)) && !fx.contains(.relinquishKey))
    }
    let (closed, fx) = run([.escape], from: open)
    #expect(closed.isClosed && fx.contains(.relinquishKey) && fx.contains(.emit(.closed)))
}

@Test func pinTogglesEmitAndPaletteOpeningIsAnnounced() {
    let (pinned, fx) = run([.setPinned(true), .setPinned(true)], from: opened())
    #expect(pinned.pinned && fx == [.emit(.pinned(true))])                    // no event for a no-op
    let (closed, closeFx) = run([.escape], from: pinned)                        // closing ends the pin
    #expect(closed.isClosed && !closed.pinned && closeFx.contains(.emit(.pinned(false))))
    let (palette, fx2) = run([.setMode(.palette)], from: opened())
    #expect(palette.openState?.mode == .palette && fx2 == [.emit(.paletteOpened)])
}

@Test func programmaticOpensKeepThePageAndOnlyNamedFocusTakesTheKeyboard() {
    let (open, fx) = run([.open(page: .tray, focus: nil, reason: .programmatic)])
    #expect(open.openState?.page == .tray && !fx.contains(.makeKey))
    let (again, fx2) = run([.open(page: nil, focus: "timer.clock", reason: .programmatic)], from: open)
    #expect(again.openState == OpenState(page: .tray, focus: "timer.clock", reason: .programmatic))
    #expect(fx2 == [.makeKey])                                                  // "gives it keyboard focus"; no 2nd `.opened`
    let (moved, fx3) = run([.open(page: .nook, focus: nil, reason: .programmatic)], from: again)
    #expect(moved.openState?.page == .nook && fx3 == [.emit(.pageChanged(.nook))])
    let (paged, fx4) = run([.selectPage("page.focus"), .selectPage("page.focus")], from: open)
    #expect(paged.openState?.page == "page.focus" && fx4 == [.emit(.pageChanged("page.focus"))])
    let (focused, _) = run([.setFocus("notes.editor")], from: open)
    #expect(focused.openState?.focus == "notes.editor")
}

// MARK: - Swipes (rows 7, 9–13)

@Test func swipesOpenCloseDismissAndChangeTracks() {
    let (open, fx) = run([.swipe(.down, target: .shape)], config: compact)
    #expect(open.openState?.reason == .swipe && fx.first == .haptic(.alignment))
    let (closed, fx2) = run([.swipe(.up, target: .header)], from: open, config: compact)
    #expect(closed.isClosed && fx2.first == .haptic(.alignment) && fx2.contains(.emit(.closed)))
    let (_, dismiss) = run([.swipe(.up, target: .shape)], config: compact)
    #expect(dismiss == [.haptic(.alignment), .dismissActivity("test.primary")])
    var withSatellite = compact
    withSatellite.satellite = "test.satellite"
    let (_, satellite) = run([.swipe(.up, target: .satellite)], config: withSatellite)
    #expect(satellite == [.haptic(.alignment), .dismissActivity("test.satellite")])
    let (unchanged, track) = run([.swipe(.left, target: .shape)], config: compact)
    #expect(unchanged.isClosed && track == [.haptic(.alignment), .activityGesture("test.primary", .swipeLeft),
                                            .emit(.activityGesture("test.primary", .swipeLeft))])
    let (peek, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: compact)
    let (afterDismiss, peekFx) = run([.swipe(.up, target: .shape)], from: peek, config: compact)
    #expect(afterDismiss.isClosed && peekFx.contains(.dismissActivity("test.primary")))
}

/// A peek's gestures act on what it shows (DESIGN.md §4.4): an auto-peek's activity (here not the primary), or
/// the hover peek's row under the fingers; the band row of a hover peek is the primary.
@Test func swipesOnAPeekActOnThePeekedActivity() {
    let (auto, _) = run([.autoPeek("test.other", until: 2.6)], config: compact)
    let (_, track) = run([.swipe(.left, target: .shape)], from: auto, config: compact)
    #expect(track == [.haptic(.alignment), .activityGesture("test.other", .swipeLeft), .emit(.activityGesture("test.other", .swipeLeft))])
    let (dismissed, up) = run([.swipe(.up, target: .shape)], from: auto, config: compact)
    #expect(up.contains(.dismissActivity("test.other")) && !up.contains(.dismissActivity("test.primary")) && dismissed.isClosed)
    let (hover, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: compact)
    #expect(run([.swipe(.up, target: .row("test.third"))], from: hover, config: compact).1.contains(.dismissActivity("test.third")))
    #expect(run([.swipe(.right, target: .row("test.third"))], from: hover, config: compact).1.contains(.activityGesture("test.third", .swipeRight)))
    #expect(run([.swipe(.up, target: .shape)], from: hover, config: compact).1.contains(.dismissActivity("test.primary")))
}

@Test func swipeSettingsGateEveryGesture() {
    var off = compact
    off.swipeOpenClose = false; off.swipeToDismiss = false; off.trackSwipe = false
    for (direction, target) in [(SwipeDirection.down, SwipeTarget.shape), (.up, .shape), (.left, .shape), (.right, .shape)] {
        let (s, fx) = run([.swipe(direction, target: target)], config: off)
        #expect(s.isClosed && fx.isEmpty, "\(direction) is off")
    }
    let (open, _) = run([.hotKey], config: off)
    #expect(run([.swipe(.up, target: .header)], from: open, config: off).0.isOpen)
    // Swipes over an open panel's content belong to the widgets.
    #expect(run([.swipe(.up, target: .shape)], from: open, config: compact).0.isOpen)
}

// MARK: - Idle handle (rows 13–15) and compact inactivity (§4.7)

@Test func theIdleHandleHidesAndComesBack() {
    let (swiped, fx) = run([.swipe(.up, target: .shape)], config: handle)
    #expect(swiped.hidden == .idleHandle && fx == [.haptic(.alignment)] && phase(swiped, handle) == .hidden)
    #expect(run([.pointerEntered], from: swiped, config: handle).0.hidden == nil)  // geometric hover brings it back
    #expect(run([.activityChanged], from: swiped, config: handle).0.hidden == nil) // so does the next activity

    var timed = handle
    timed.hidesIdleHandle = true
    timed.handleIdleDelay = 10
    let (armed, armFx) = run([.configChanged], config: timed)
    #expect(armFx == [.schedule(.handleIdle, after: 10)])
    let (faded, _) = run([.timerElapsed(.handleIdle)], from: armed, config: timed)
    #expect(faded.hidden == .idleHandle)
    var withActivity = timed
    withActivity.primary = "test.primary"
    #expect(run([.configChanged], config: withActivity).1.isEmpty)            // never while an activity shows
}

@Test func compactInactivityCollapsesUntilTheNextRevision() {
    var c = compact
    c.compactInactivityTimeout = 20
    let (armed, fx) = run([.configChanged], config: c)
    #expect(fx == [.schedule(.compactIdle, after: 20)])
    let (collapsed, _) = run([.timerElapsed(.compactIdle)], from: armed, config: c)
    #expect(collapsed.compactCollapsed && phase(collapsed, c) == .idle)
    let (back, _) = run([.activityChanged], from: collapsed, config: c)
    #expect(phase(back, c) == .compact)
    let (hovered, hoverFx) = run([.pointerEntered], from: armed, config: c)   // hovering is activity
    #expect(hoverFx.contains(.cancel(.compactIdle)) && !hovered.timers.contains(.compactIdle))
}

@Test func openInactivityClosesOnlyWhenNothingHoldsIt() {
    var c = idle
    c.openInactivityTimeout = 15
    let (outside, fx) = run([.hotKey], config: c)                            // hot key: pointer outside
    #expect(fx.contains(.schedule(.inactivity, after: 15)))
    #expect(run([.configChanged], from: outside, config: c).1.isEmpty)        // armed once, not re-armed
    #expect(run([.timerElapsed(.inactivity)], from: outside, config: c).0.isClosed)
    let (pinned, pinFx) = run([.setPinned(true)], from: outside, config: c)
    #expect(pinFx.contains(.cancel(.inactivity)) && run([.timerElapsed(.inactivity)], from: pinned, config: c).0.isOpen)
}

// MARK: - File drags (rows 16–19)

private let pdf: [UTType] = [.pdf]

@Test func aFileDragOpensTheCatchStateOnlyWithATray() {
    var tray = compact
    tray.acceptsFileDrags = true
    let (caught, fx) = run([.fileDragEntered(pdf)], config: tray)
    #expect(caught.openState == OpenState(page: .nook, mode: .catchFiles(pdf), reason: .drag))
    #expect(fx.contains(.emit(.opened(.drag))) && caught.holds.contains(NotchMachineState.dragHold))
    let (noTray, _) = run([.fileDragEntered(pdf)], config: compact)
    #expect(noTray.isClosed && noTray.fileDrag == pdf)
}

@Test func aDragOverTheOpenGridKeepsTheGridAndHoldsIt() {
    var tray = idle
    tray.acceptsFileDrags = true
    let (grid, _) = run([.fileDragEntered(pdf), .pointerLeft, .timerElapsed(.grace)], from: opened(tray), config: tray)
    #expect(grid.openState?.mode == .grid && grid.isOpen)                     // widget zones take the drop
    let (dropped, fx) = run([.filesDropped(count: 2)], from: grid, config: tray)
    #expect(dropped.openState?.mode == .grid && dropped.fileDrag == nil)
    #expect(fx.prefix(3) == [.emit(.filesCaught(count: 2)), .haptic(.generic), .playSound(.pop)])
    #expect(fx.contains(.schedule(.grace, after: HoverIntent.closeGrace)))     // the pointer is outside: grace again
}

@Test func aDropInTheCatchStateGulpsThenReturns() {
    var tray = idle
    tray.acceptsFileDrags = true
    let (caught, _) = run([.fileDragEntered(pdf), .pointerEntered], config: tray)
    let (dropped, fx) = run([.filesDropped(count: 1)], from: caught, config: tray)
    #expect(fx.contains(.schedule(.catchEnd, after: NotchMachine.catchGulp)) && dropped.isOpen)
    let (returned, fx2) = run([.timerElapsed(.catchEnd)], from: dropped, config: tray)
    #expect(returned.isClosed && fx2.contains(.emit(.closed)) && returned.holds.isEmpty)
    let (refused, refusedFx) = run([.filesDropped(count: 0)], from: caught, config: tray)
    #expect(!refusedFx.contains(.emit(.filesCaught(count: 0))) && refused.timers.contains(.catchEnd))
}

/// Dropped file promises resolve asynchronously: the `drop` hold keeps the panel (and the zone that takes the
/// drop) until the payload is handed over; then the catch gulps and returns, the grid's grace resumes.
@Test func droppedPromisesHoldThePanelUntilDelivered() {
    var tray = idle
    tray.acceptsFileDrags = true
    let (caught, _) = run([.fileDragEntered(pdf), .pointerEntered], config: tray)
    let (waiting, fx) = run([.hold(NotchMachineState.dropHold, true), .filesDropped(count: 1), .pointerLeft,
                             .timerElapsed(.catchEnd)], from: caught, config: tray)
    #expect(waiting.isCatching && fx.contains(.emit(.filesCaught(count: 1))))
    #expect(!fx.contains(.schedule(.catchEnd, after: NotchMachine.catchGulp)) && !waiting.timers.contains(.catchEnd))
    let (delivered, fx2) = run([.hold(NotchMachineState.dropHold, false)], from: waiting, config: tray)
    #expect(fx2.contains(.schedule(.catchEnd, after: NotchMachine.catchGulp)))
    #expect(run([.timerElapsed(.catchEnd)], from: delivered, config: tray).0.isClosed)

    let (grid, _) = run([.fileDragEntered(pdf), .hold(NotchMachineState.dropHold, true), .filesDropped(count: 1), .pointerLeft],
                        from: opened(tray), config: tray)
    #expect(grid.isOpen && !grid.timers.contains(.grace))
    let (released, fx3) = run([.hold(NotchMachineState.dropHold, false)], from: grid, config: tray)
    #expect(fx3 == [.schedule(.grace, after: HoverIntent.closeGrace)] && released.isOpen)
}

@Test func aDragThatEndsOrLeavesReturnsAfterTheGrace() {
    var tray = idle
    tray.acceptsFileDrags = true
    let (caught, _) = run([.fileDragEntered(pdf), .pointerEntered], config: tray)
    let (ended, fx) = run([.fileDragEnded], from: caught, config: tray)
    #expect(fx == [.schedule(.catchEnd, after: HoverIntent.closeGrace)])
    #expect(run([.timerElapsed(.catchEnd)], from: ended, config: tray).0.isClosed)
    let (left, fx2) = run([.pointerLeft], from: caught, config: tray)          // still dragging, left the zones
    #expect(fx2 == [.schedule(.catchEnd, after: HoverIntent.closeGrace)])
    let (back, fx3) = run([.pointerEntered, .timerElapsed(.catchEnd)], from: left, config: tray)
    #expect(back.isCatching && fx3.first == .cancel(.catchEnd))
    #expect(run([.fileDragEnded, .fileDragEnded], from: caught, config: tray).1.count == 1)   // idempotent
}

// MARK: - Peeks (rows 25–26)

@Test func autoPeeksShowTheirActivityUntilTheirTimeUnlessHovered() {
    let (peek, fx) = run([.autoPeek("calendar.meetingSoon", until: 2.6)], config: compact)
    #expect(peek.surface == .peek(.auto("calendar.meetingSoon", until: 2.6)) && fx == [.schedule(.peekEnd, after: 2.6)])
    #expect(run([.timerElapsed(.peekEnd)], from: peek, config: compact).0.isClosed)
    let (hovered, _) = run([.pointerEntered, .timerElapsed(.peekEnd)], from: peek, config: compact)
    #expect(hovered.isPeeking)                                                  // "a hover keeps it"
    let (held, heldFx) = run([.autoPeek(.flash, until: .infinity)], config: compact)
    #expect(held.isPeeking && heldFx.isEmpty)                                   // QA: no endless sleep
    #expect(run([.autoPeek(.flash, until: 9)], from: opened(), config: compact).0.isOpen)   // never while open
    let (hoverPeek, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: compact)
    #expect(run([.autoPeek(.flash, until: 9)], from: hoverPeek, config: compact).0.surface == .peek(.hover))
}

/// §4.7 "a hover keeps it": an auto-peek that arrives while the pointer dwells on the notch is kept by it.
@Test func anAutoPeekDuringADwellIsKeptByThePointer() {
    let (dwelling, _) = run([.pointerEntered], config: compact)
    let (peek, fx) = run([.autoPeek("test.primary", until: 2.6)], from: dwelling, config: compact)
    #expect(peek.hover == .inside && fx.contains(.cancel(.dwell)) && !peek.timers.contains(.dwell))
    let (kept, _) = run([.dwellElapsed(shouldOpen: true), .timerElapsed(.peekEnd)], from: peek, config: compact)
    #expect(kept.surface == .peek(.auto("test.primary", until: 2.6)))
    let (left, _) = run([.pointerLeft, .timerElapsed(.grace)], from: kept, config: compact)
    #expect(left.isClosed)
}

// MARK: - Environment (rows 27–31)

@Test func lockAndSleepHideAndCloseEverything() {
    for hide in [\NotchEnvironment.isLocked, \.displaysAsleep] {
        var environment = NotchEnvironment()
        environment[keyPath: hide] = true
        let (hidden, fx) = run([.environment(environment)], from: opened())
        #expect(hidden.isClosed && fx.contains(.relinquishKey) && phase(hidden) == .hidden)
        #expect(run([.pointerEntered, .click], from: hidden).0.isClosed)       // no input while hidden
        let (shown, _) = run([.environment(NotchEnvironment())], from: hidden)
        #expect(shown.hidden == nil && shown.isClosed)                         // "previous surface = closed"
    }
}

@Test func fullScreenFollowsThePolicy() {
    var hideAll = NotchEnvironment()
    hideAll.policy = .hideAll
    hideAll.fullScreen = true
    #expect(run([.environment(hideAll)], from: opened()).0.hidden == .fullScreen)
    hideAll.fullScreen = false
    hideAll.excludedApp = true
    #expect(run([.environment(hideAll)]).0.hidden == .excludedApp)
    var alerts = NotchEnvironment()
    alerts.fullScreen = true
    let (restricted, _) = run([.environment(alerts)])
    #expect(restricted.hidden == nil && restricted.environment.restrictsToAlerts)
    var showAll = alerts
    showAll.policy = .showAll
    #expect(!showAll.restrictsToAlerts && showAll.hardHidden == nil)
}

@Test func demoModeNeverAutoClosesOrHides() {
    var demo = NotchEnvironment()
    demo.demoMode = true
    demo.policy = .hideAll
    demo.fullScreen = true
    let (shown, _) = run([.environment(demo)], from: opened())
    #expect(shown.hidden == nil && shown.isOpen)
    let (stays, _) = run([.pointerLeft, .timerElapsed(.grace)], from: shown)
    #expect(stays.isOpen)
    var off = demo
    off.demoMode = false
    off.fullScreen = false
    let (_, fx) = run([.environment(off)], from: stays)
    #expect(fx == [.schedule(.grace, after: HoverIntent.closeGrace)])          // leaving Demo mode resumes the grace
}

@Test func thePointerSelectionHidesOtherDisplaysButNotAnOpenPanel() {
    var elsewhere = NotchEnvironment()
    elsewhere.notThisDisplay = true
    #expect(run([.environment(elsewhere)]).0.hidden == .notThisDisplay)
    let (open, _) = run([.environment(elsewhere)], from: opened())
    #expect(open.isOpen && open.hidden == nil)                                  // it hides once it closes
    #expect(run([.close], from: open).0.hidden == .notThisDisplay)
}

// MARK: - Menu-bar courtesy (DESIGN.md §4.6) and calibration (§3.1)

@Test func theWingsRetractForTheMenuBarAndReturnAfterLeavingTheBand() {
    var c = compact
    c.menuBarCourtesy = true
    let (retracted, _) = run([.band(.courtesy)], config: c)
    #expect(retracted.wingsRetracted && phase(retracted, c) == .idle)
    let (inBand, fx) = run([.band(.band)], from: retracted, config: c)
    #expect(inBand.wingsRetracted && fx.isEmpty)                               // still reaching for menus
    let (left, fx2) = run([.band(.outside)], from: inBand, config: c)
    #expect(fx2 == [.schedule(.wingsReturn, after: NotchMachine.wingsReturnDelay)])
    #expect(phase(run([.timerElapsed(.wingsReturn)], from: left, config: c).0, c) == .compact)
    #expect(!run([.pointerEntered], from: retracted, config: c).0.wingsRetracted)   // came for the notch itself
    var off = c
    off.menuBarCourtesy = false
    #expect(!run([.band(.courtesy)], config: off).0.wingsRetracted)
    #expect(!run([.band(.courtesy)]).0.wingsRetracted)                         // nothing to retract
}

/// §4.7, DESIGN.md §9.2: the compact inactivity timeout collapses the wings but the satellite stays (and can be
/// swiped away); it goes with the wings for the menu bar, while hidden and while open.
@Test func theSatelliteStaysAfterTheCompactTimeout() {
    var c = compact
    c.satellite = "test.satellite"
    c.compactInactivityTimeout = 20
    #expect(NotchMachine.satelliteIsVisible(NotchMachineState(), config: c))
    let (armed, _) = run([.configChanged], config: c)
    let (collapsed, _) = run([.timerElapsed(.compactIdle)], from: armed, config: c)
    #expect(phase(collapsed, c) == .idle && NotchMachine.satelliteIsVisible(collapsed, config: c))
    #expect(run([.swipe(.up, target: .satellite)], from: collapsed, config: c).1.contains(.dismissActivity("test.satellite")))
    let (retracted, _) = run([.band(.courtesy)], config: c)
    #expect(!NotchMachine.satelliteIsVisible(retracted, config: c))
    #expect(!NotchMachine.satelliteIsVisible(opened(c), config: c))
    var locked = NotchMachineState()
    locked.environment.isLocked = true
    #expect(!NotchMachine.satelliteIsVisible(locked, config: c))
    #expect(!NotchMachine.satelliteIsVisible(NotchMachineState(), config: compact))     // no second activity
}

@Test func calibrationFreezesTheClosedShapeInTheBreath() {
    let (calibrating, _) = run([.calibration(true)], config: compact)
    #expect(phase(calibrating, compact) == .breath)
    #expect(phase(run([.calibration(false)], from: calibrating, config: compact).0, compact) == .compact)
}

// MARK: - Phases (§4.2)

@Test func phasesFollowTheDerivationTable() {
    #expect(phase(NotchMachineState()) == .idle)
    #expect(phase(NotchMachineState(), compact) == .compact)
    var hidden = NotchMachineState()
    hidden.environment.isLocked = true
    #expect(phase(hidden, compact) == .hidden)
    #expect(phase(opened(), compact) == .open)
    let (peek, _) = run([.autoPeek("x", until: 3)], config: compact)
    #expect(phase(peek, compact) == .peek)
}

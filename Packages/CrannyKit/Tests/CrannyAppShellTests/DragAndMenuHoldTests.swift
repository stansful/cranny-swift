// What a file drag and a tracking menu leave behind on a panel (ARCHITECTURE.md §4.4–§4.5, §10.20 issues 8, 12 and
// 25): a closed panel keeps no drag state or `drag` hold, and a menu opened from the panel keeps it open while the
// pointer stays where the menu was (ruling E3), until the pointer leaves that region or the panel closes. The reducer
// is driven through the production pointer code: `PanelHover` (as `NotchPanelController` wires it, `surfaceChanged`
// after every input) and `PanelHover.menuTracking` (as `OverlayCoordinator` calls it). No windows, no input.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

private let pdf: [UTType] = [.pdf]
private let dragHold = NotchMachineState.dragHold
private let menuHold = NotchMachineState.menuHold

private let tray: NotchMachineConfig = {
    var c = NotchMachineConfig()
    c.acceptsFileDrags = true
    return c
}()

private func run(_ inputs: [NotchInput], from start: NotchMachineState = NotchMachineState(),
                 config: NotchMachineConfig = tray) -> (NotchMachineState, [NotchEffect]) {
    var state = start
    var effects: [NotchEffect] = []
    for (i, input) in inputs.enumerated() {
        let (next, fx) = NotchMachine.reduce(state, input, now: Double(i), config: config)
        state = next
        effects += fx
    }
    return (state, effects)
}

// MARK: - File drags (issue 8)

@Test func closingThePanelDropsTheDragAndItsHold() {
    let (caught, _) = run([.fileDragEntered(pdf), .pointerEntered])
    #expect(caught.isCatching && caught.fileDrag == pdf && caught.holds.contains(dragHold))
    var locked = NotchEnvironment()
    locked.isLocked = true
    for close in [NotchInput.escape, .hotKey, .close, .swipe(.up, target: .header), .environment(locked)] {
        let (closed, _) = run([close], from: caught)
        #expect(closed.isClosed && closed.fileDrag == nil && !closed.holds.contains(dragHold), "\(close)")
    }
    // The grid that a drag passed over closes with nothing left of it, too.
    let (grid, _) = run([.hotKey, .fileDragEntered(pdf)])
    #expect(grid.openState?.mode == .grid && grid.holds.contains(dragHold))
    let (gone, _) = run([.close], from: grid)
    #expect(gone.isClosed && gone.fileDrag == nil && gone.holds.isEmpty)
}

/// The catch state returns once the pointer left with the drag still going: the drag no longer belongs to the closed
/// panel, comes back as a new entry within the drag zone, and its end is nothing to the closed panel.
@Test func aDragThatLeavesTheClosedPanelOpensItAgainWhenItComesBack() {
    let (caught, _) = run([.fileDragEntered(pdf), .pointerEntered])
    let (returned, _) = run([.pointerLeft, .timerElapsed(.catchEnd)], from: caught)
    #expect(returned.isClosed && returned.fileDrag == nil && returned.holds.isEmpty)
    let (again, fx) = run([.fileDragEntered(pdf)], from: returned)
    #expect(again.isCatching && fx.contains(.emit(.opened(.drag))))
    #expect(run([.fileDragEnded], from: returned).1.isEmpty)
    // Pinned, the panel stays on its grid while the drag goes on (an open grid can still take the drop) …
    let (pinned, _) = run([.setPinned(true), .pointerLeft, .timerElapsed(.catchEnd)], from: caught)
    #expect(pinned.openState?.mode == .grid && pinned.fileDrag == pdf)
    // … until the drag ends there.
    let (ended, _) = run([.fileDragEnded], from: pinned)
    #expect(ended.isOpen && ended.fileDrag == nil && ended.holds.isEmpty)
}

/// A drag session that ends without a drop takes everything it left: a panel without a Tray holds without opening, a
/// hidden panel records the drag without the hold.
@Test func aDragThatEndsWithoutADropLeavesNothing() {
    let (noTray, _) = run([.fileDragEntered(pdf)], config: NotchMachineConfig())
    #expect(noTray.isClosed && noTray.holds.contains(dragHold))
    let (ended, _) = run([.fileDragEnded], from: noTray, config: NotchMachineConfig())
    #expect(ended.fileDrag == nil && ended.holds.isEmpty)

    var hidden = NotchMachineState()
    hidden.environment.isLocked = true
    let (seen, _) = run([.fileDragEntered(pdf)], from: hidden)
    #expect(seen.fileDrag == pdf && seen.holds.isEmpty && seen.isClosed)
    #expect(run([.fileDragEnded], from: seen).0.fileDrag == nil)

    // Only the `drag` hold is left (the drag state went first): the hold goes and the grace resumes.
    let (open, _) = run([.hotKey, .pointerEntered, .pointerLeft, .hold(dragHold, true)])
    #expect(open.fileDrag == nil && !open.timers.contains(.grace))
    let (released, fx) = run([.fileDragEnded], from: open)
    #expect(released.holds.isEmpty && fx.contains(.schedule(.grace, after: HoverIntent.closeGrace)))
}

// MARK: - Menus opened from the panel (issues 12 and 25, ruling E3)

/// Mirror's camera menu, 220 × 160 pt, opened from the camera button of a card in the lower row.
private let cameraButton = CGPoint(x: 980, y: 860)
private let cameraMenu = CGSize(width: 220, height: 160)
/// Where the picked camera was: below the exit zone (y 768), within the menu.
private let pickedItem = CGPoint(x: 1000, y: 720)
/// Below the menu's region (its extent ends 160 + 32 pt below the camera button, at y 668).
private let belowTheMenu = CGPoint(x: 1000, y: 600)

/// One panel as `NotchPanelController` wires it: the production `PanelHover` on the open shape's zones, feeding the
/// reducer. The check `closeGrace` after a menu is run by hand (`checkAfterTheGrace`).
@MainActor private final class Panel {
    nonisolated static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// The open shape, top-centred (screen coordinates, bottom-left origin).
    nonisolated static let open = CGRect(x: 406, y: 782, width: 700, height: 200)
    nonisolated static let inside = CGPoint(x: 756, y: 900)

    private(set) var state: NotchMachineState
    private(set) var effects: [NotchEffect] = []
    let hover = PanelHover()
    /// Where the pointer is (what `NSEvent.mouseLocation` would say).
    var pointer = Panel.inside
    /// False: the pointer cannot be read (`PanelHover.readPointer` finds it on no display).
    var pointerIsReadable = true
    private var checks: [@MainActor () -> Void] = []
    private var time = 0.0

    init(state: NotchMachineState) {
        self.state = state
        hover.zones = { [unowned self] in
            HoverZones(shape: Self.open, satellite: nil, wings: nil, screenFrame: Self.screen, band: 32,
                       expanded: self.state.isOpen || self.state.isPeeking)
        }
        hover.send = { [unowned self] input in self.send(input) }
        hover.pointer = { [unowned self] in self.pointerIsReadable ? self.pointer : nil }
        hover.after = { [unowned self] delay, work in
            #expect(delay == HoverIntent.closeGrace)
            self.checks.append(work)
        }
    }

    func send(_ input: NotchInput) {
        time += 1
        let (next, fx) = NotchMachine.reduce(state, input, now: time, config: NotchMachineConfig())
        state = next
        effects += fx
        hover.surfaceChanged()                               // the controller's `didSync`, after every input
    }

    /// A pointer event (the monitors see none while a menu tracks).
    func move(to point: CGPoint) {
        pointer = point
        hover.moved(to: point)
    }

    /// `closeGrace` has passed since the menu closed: the region's safety check runs.
    func checkAfterTheGrace() {
        let due = checks
        checks = []
        for work in due { work() }
    }

    var graceScheduled: Bool { effects.contains(.schedule(.grace, after: HoverIntent.closeGrace)) }
    func clearEffects() { effects = [] }
}

/// The coordinator's side: each NSMenu notification goes through `PanelHover.menuTracking`, with the hold fanned out
/// to every panel as `OverlayCoordinator.setHoldOpen` does.
@MainActor private final class MenuSession {
    private var tracking = MenuTracking()
    private let panels: [Panel]
    /// How often the pointer was read (`NSEvent.mouseLocation` in the app).
    private(set) var pointerReads = 0

    init(_ panels: Panel...) { self.panels = panels }

    func began(at point: CGPoint, size: CGSize = cameraMenu) { notify(began: true, at: point, size: size) }
    func ended(at point: CGPoint, size: CGSize = cameraMenu) { notify(began: false, at: point, size: size) }

    private func notify(began: Bool, at point: CGPoint, size: CGSize) {
        for panel in panels { panel.pointer = point }
        PanelHover.menuTracking(&tracking, began: began, size: size, panels: panels.map(\.hover),
                                pointer: { pointerReads += 1; return point }) { on in
            for panel in panels { panel.send(.hold(menuHold, on)) }
        }
    }
}

@MainActor private func openPanel() -> Panel {
    let panel = Panel(state: run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: NotchMachineConfig()).0)
    panel.move(to: Panel.inside)
    panel.clearEffects()
    return panel
}

@MainActor @Test func aTrackingMenuNeverStartsTheCloseGrace() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    panel.move(to: pickedItem)                               // events that do arrive while the menu tracks
    panel.send(.timerElapsed(.grace))                        // a stale grace from before the menu
    #expect(panel.state.isOpen && !panel.graceScheduled && panel.state.hover == .outside)
}

/// Mirror's camera menu: the camera picked hangs below the panel. After the menu closed, the place where it hung
/// counts as inside: coming back up keeps the panel without a grace, and later leaves are ordinary ones.
@MainActor @Test func aMenuFromThePanelKeepsItsRegion() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)                              // the hover tracker saw nothing while it tracked
    #expect(panel.state.isOpen && panel.state.hover == .inside && !panel.graceScheduled)
    panel.move(to: CGPoint(x: 1000, y: 745))                 // back up toward the panel
    panel.move(to: Panel.inside)                             // inside again: the region has done its job
    panel.checkAfterTheGrace()                               // nothing left to check
    #expect(!panel.graceScheduled && panel.state.hover == .inside && panel.hover.linger.region == nil)
    panel.move(to: pickedItem)                               // leaving the same way later is an ordinary leave
    #expect(panel.graceScheduled)
}

/// Ruling E3: the panel stays while the pointer rests where the menu was, past the grace and the safety check, and
/// while it moves within that region; the grace starts when it leaves the region.
@MainActor @Test func theMenusRegionLastsWhileThePointerStaysInIt() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)
    panel.move(to: CGPoint(x: 990, y: 725))                  // still where the menu was
    panel.checkAfterTheGrace()                               // 0.3 s after the menu closed: the pointer is still there
    #expect(!panel.graceScheduled && panel.state.hover == .inside && panel.hover.linger.region != nil)
    panel.move(to: CGPoint(x: 1180, y: 690))                 // anywhere the menu could have hung, any time later
    panel.send(.timerElapsed(.grace))                        // a stale grace changes nothing either
    #expect(panel.state.isOpen && !panel.graceScheduled && panel.state.hover == .inside)
    panel.move(to: belowTheMenu)                             // out of the region: the usual grace
    #expect(panel.graceScheduled && panel.state.hover == .outside && panel.hover.linger.region == nil)
    panel.move(to: pickedItem)                               // the region is gone: back over it is still outside
    #expect(panel.state.hover == .outside)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)
}

/// A pointer that leaves the region before the safety check gets the grace at once; the check then finds nothing.
@MainActor @Test func leavingTheRegionStartsTheGraceAtOnce() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    panel.move(to: pickedItem)                               // pointer events that arrived while it tracked
    menus.ended(at: pickedItem)
    #expect(panel.state.hover == .inside && !panel.graceScheduled)
    panel.move(to: belowTheMenu)
    #expect(panel.graceScheduled && panel.state.hover == .outside)
    panel.clearEffects()
    panel.checkAfterTheGrace()                               // the region had already gone
    #expect(panel.effects.isEmpty)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)
}

/// The safety expiry: a pointer that cannot be read when the check comes ends the region, and the last position seen
/// (where the menu was, outside the exit zone) starts the usual grace.
@MainActor @Test func anUnreadablePointerEndsTheRegionAtTheSafetyCheck() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)
    #expect(!panel.graceScheduled && panel.hover.linger.region != nil)
    panel.pointerIsReadable = false
    panel.checkAfterTheGrace()
    #expect(panel.graceScheduled && panel.state.hover == .outside && panel.hover.linger.region == nil)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)
}

/// A panel that closed while the pointer rested in the region (Esc, the hot key) loses the region as it closes, so the
/// check finds nothing and opening it again later does not count the old menu's place as inside.
@MainActor @Test func aPanelClosedMeanwhileLosesTheRegion() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)
    panel.send(.escape)
    #expect(panel.state.isClosed && panel.hover.linger.region == nil && panel.state.hover == .outside)
    panel.clearEffects()
    panel.checkAfterTheGrace()
    #expect(panel.hover.linger.region == nil && panel.state.hover == .outside && panel.effects.isEmpty)
    panel.send(.hotKey)
    panel.move(to: pickedItem)
    #expect(panel.state.isOpen && panel.state.hover == .outside)
}

/// The panel closed after the safety check, while the pointer rested in the region (Esc), and opened again before the
/// pointer moved (the hot key): the region went with the close, so the old menu's place is outside the reopened panel.
@MainActor @Test func aPanelClosedAfterTheCheckLosesTheRegion() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)
    panel.checkAfterTheGrace()                               // the pointer rests where the menu was: the region stays
    #expect(panel.hover.linger.region != nil && panel.state.hover == .inside)
    panel.send(.escape)
    #expect(panel.state.isClosed && panel.hover.linger.region == nil && !panel.hover.linger.fromPanel)
    panel.send(.hotKey)                                      // open again, the mouse has not moved
    panel.move(to: CGPoint(x: 1180, y: 690))                 // where the old menu could have hung
    #expect(panel.state.isOpen && panel.state.hover == .outside && panel.hover.linger.region == nil)
}

/// A panel hidden while the region lasts (zones nil) loses it too, and so does a menu still tracking on it.
@MainActor @Test func aHiddenPanelLosesTheRegionAndTheMenuOrigin() {
    let hover = PanelHover()
    var zones: HoverZones? = HoverZones(shape: Panel.open, satellite: nil, wings: nil, screenFrame: Panel.screen,
                                        band: 32, expanded: true)
    var inputs: [NotchInput] = []
    hover.zones = { zones }
    hover.send = { inputs.append($0) }
    hover.pointer = { pickedItem }
    hover.after = { _, _ in }
    hover.menuBegan(at: cameraButton)
    hover.menuEnded(at: pickedItem, reach: cameraMenu)
    hover.surfaceChanged()                                   // still open: nothing changes
    #expect(hover.linger.region != nil)
    zones = nil
    hover.surfaceChanged()
    #expect(hover.linger.region == nil && inputs.last == .pointerLeft && !hover.isInside)
    zones = HoverZones(shape: Panel.open, satellite: nil, wings: nil, screenFrame: Panel.screen, band: 32, expanded: true)
    hover.menuBegan(at: cameraButton)
    zones?.expanded = false                                  // closed while the menu tracked
    hover.surfaceChanged()
    zones?.expanded = true
    hover.menuEnded(at: pickedItem, reach: cameraMenu)
    #expect(!hover.linger.fromPanel && hover.linger.region == nil)
}

/// Only where the menu could have been: a menu dismissed by a click far away (or with Esc after the pointer moved
/// away) leaves no region, and the panel closes after the grace as for any leave. A menu of unknown size neither.
@MainActor @Test func aMenuDismissedFarAwayLeavesNoRegion() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: CGPoint(x: 100, y: 100))                 // the click that dismissed it, near the bottom left
    #expect(panel.graceScheduled && panel.state.hover == .outside && panel.hover.linger.region == nil)
    for point in [CGPoint(x: 300, y: 400), CGPoint(x: 1000, y: 300), CGPoint(x: 200, y: 700), CGPoint(x: 1100, y: 150)] {
        panel.move(to: point)
        #expect(panel.state.hover == .outside)
    }
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)

    let unknown = openPanel()
    let sizeless = MenuSession(unknown)
    sizeless.began(at: cameraButton, size: .zero)
    sizeless.ended(at: pickedItem, size: .zero)
    #expect(unknown.graceScheduled && unknown.hover.linger.region == nil)
}

/// A menu that did not open from the panel (the menu bar extra's, a Settings pop-up) holds it while it tracks and
/// leaves nothing behind: a pointer outside closes it after the grace as before.
@MainActor @Test func aMenuFromElsewhereLeavesNoRegion() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    panel.move(to: CGPoint(x: 1400, y: 978))                 // off to the menu bar extra
    #expect(panel.graceScheduled)
    panel.clearEffects()
    menus.began(at: CGPoint(x: 1400, y: 978))
    #expect(panel.effects == [.cancel(.grace)])
    menus.ended(at: CGPoint(x: 1400, y: 960))
    #expect(panel.graceScheduled)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)
}

/// The coordinator's order, through the production sequence: the panels read the pointer at the first begin and the
/// last end only (a submenu is part of the session), and before the hold changes. So releasing the hold never starts
/// (and then cancels) a grace for a pointer that is inside the menu's region.
@MainActor @Test func theSessionReadsThePointerBeforeTheHoldChanges() {
    let panel = openPanel()
    let other = Panel(state: NotchMachineState())            // another display's panel, closed
    let menus = MenuSession(panel, other)
    menus.began(at: cameraButton)
    #expect(menus.pointerReads == 1 && panel.state.holds.contains(menuHold) && other.state.holds.contains(menuHold))
    #expect(panel.hover.linger.fromPanel && !other.hover.linger.fromPanel)
    panel.move(to: pickedItem)                               // the pointer left while it tracked: the hold keeps it

    let submenu = CGSize(width: 200, height: 120)
    menus.began(at: CGPoint(x: 1150, y: 700), size: submenu)
    menus.ended(at: CGPoint(x: 1150, y: 700), size: submenu)  // the submenu closed, the menu still tracks
    #expect(menus.pointerReads == 1 && panel.state.holds.contains(menuHold) && panel.hover.linger.fromPanel)

    panel.clearEffects()
    let inSubmenu = CGPoint(x: 1200, y: 700)                 // the item picked in the submenu: within both menus' reach
    menus.ended(at: inSubmenu)
    #expect(menus.pointerReads == 2 && !panel.state.holds.contains(menuHold) && !other.state.holds.contains(menuHold))
    #expect(panel.state.hover == .inside && panel.hover.linger.region?.contains(inSubmenu) == true)
    #expect(!panel.effects.contains { if case .schedule(.grace, _) = $0 { true } else { false } })
    #expect(other.state.isClosed && other.hover.linger.region == nil)
}

@Test func menuSessionsNestAndAddUpTheirReach() {
    var tracking = MenuTracking()
    #expect(tracking.update(began: false, size: cameraMenu) == nil && !tracking.isTracking)   // an end without a begin
    #expect(tracking.update(began: true, size: CGSize(width: 200, height: 100)) == .began)
    #expect(tracking.update(began: true, size: CGSize(width: 150, height: 80)) == nil)
    #expect(tracking.reach == CGSize(width: 350, height: 180) && tracking.isTracking)
    #expect(tracking.update(began: false, size: .zero) == nil && tracking.isTracking)
    // A menu that filled in its items as it opened is as large at its end as it was then.
    #expect(tracking.update(began: false, size: CGSize(width: 400, height: 90)) == .ended(reach: CGSize(width: 400, height: 180)))
    #expect(!tracking.isTracking && tracking.reach == .zero)
}

/// The region is where the session's menus can have hung (`MenuLinger.region`): within their size, plus the 32-pt
/// control allowance, of both the control that opened them and the item picked, on the panel's screen. It holds the
/// picked item and the control, so the way back up to the panel stays inside, and nothing beyond the menus' size from
/// either point: not the band beside the panel, not above the screen's top edge.
@Test func theMenuRegionIsWhereTheMenusCouldHang() throws {
    let zones = HoverZones(shape: Panel.open, satellite: nil, wings: nil, screenFrame: Panel.screen, band: 32,
                           expanded: true)
    var linger = MenuLinger()
    linger.began(at: cameraButton, zones: zones)
    #expect(linger.fromPanel && linger.origin == cameraButton)
    let recorded = linger.ended(at: pickedItem, zones: zones, reach: cameraMenu)
    let serial = try #require(recorded)
    let region = try #require(linger.region)
    let extent = MenuLinger.extent(from: cameraButton, reach: cameraMenu)
    #expect(region == MenuLinger.region(from: cameraButton, to: pickedItem, reach: cameraMenu, screen: Panel.screen))
    #expect(region == extent.intersection(MenuLinger.extent(from: pickedItem, reach: cameraMenu)))
    #expect(region.contains(pickedItem) && region.contains(cameraButton))
    // Below: as far as a menu hanging from the button reaches. Above and to the left: as far as one holding the item.
    #expect(region.minY == cameraButton.y - cameraMenu.height - MenuLinger.controlSlack)
    #expect(region.maxY == pickedItem.y + cameraMenu.height + MenuLinger.controlSlack)
    #expect(region.minX == pickedItem.x - cameraMenu.width - MenuLinger.controlSlack)
    #expect(region.maxX == cameraButton.x + cameraMenu.width + MenuLinger.controlSlack)
    #expect(!region.contains(belowTheMenu) && !region.contains(CGPoint(x: 600, y: 720)))   // beyond the menu's size
    #expect(!region.contains(CGPoint(x: 740, y: 700)))                       // left of where the item allows
    #expect(!region.contains(CGPoint(x: 1150, y: 970)))                      // the band beside the panel
    #expect(!region.contains(CGPoint(x: 1000, y: 1000)))                     // a display above
    #expect(!linger.fromPanel)                                                // one menu, one region

    // It counts as inside only while the panel shows open (or peeks).
    var withRegion = zones
    withRegion.menuRegion = region
    #expect(withRegion.contains(pickedItem) && !zones.contains(pickedItem))
    withRegion.expanded = false
    #expect(!withRegion.contains(pickedItem))

    // No region for an item picked inside the exit zone, a menu that began elsewhere or on a closed panel, a menu of
    // unknown size (even within the control allowance), an end beyond the menu's reach from where it began, or one off
    // the panel's screen.
    var near = MenuLinger()
    near.began(at: cameraButton, zones: zones)
    #expect(near.ended(at: CGPoint(x: 1000, y: 775), zones: zones, reach: cameraMenu) == nil && near.region == nil)
    var elsewhere = MenuLinger()
    elsewhere.began(at: CGPoint(x: 1400, y: 978), zones: zones)
    #expect(elsewhere.ended(at: pickedItem, zones: zones, reach: cameraMenu) == nil)
    var closed = MenuLinger()
    var closedZones = zones
    closedZones.expanded = false
    closed.began(at: cameraButton, zones: closedZones)
    #expect(closed.ended(at: pickedItem, zones: closedZones, reach: cameraMenu) == nil)
    var sizeless = MenuLinger()
    let lowButton = CGPoint(x: 980, y: 790)                                   // a control at the panel's bottom
    sizeless.began(at: lowButton, zones: zones)
    #expect(sizeless.ended(at: CGPoint(x: 980, y: 760), zones: zones, reach: .zero) == nil)
    #expect(extent.contains(pickedItem) && !extent.contains(CGPoint(x: 100, y: 100)))
    var beyond = MenuLinger()
    beyond.began(at: cameraButton, zones: zones)
    #expect(beyond.ended(at: CGPoint(x: extent.midX, y: extent.minY - 1), zones: zones, reach: cameraMenu) == nil)
    var offScreen = MenuLinger()                                              // on the display to the right
    offScreen.began(at: cameraButton, zones: zones)
    #expect(offScreen.ended(at: CGPoint(x: 1550, y: 800), zones: zones, reach: CGSize(width: 600, height: 160)) == nil)

    // The region ends when the pointer leaves it, comes back inside, or the panel closes; never by itself …
    var moving = linger
    moving.pointerMoved(to: CGPoint(x: 1000, y: 745), zones: withRegion.expandedCopy)
    moving.pointerMoved(to: CGPoint(x: 1200, y: 680), zones: withRegion.expandedCopy)
    #expect(moving.region == region && moving.isCurrent(serial))
    moving.pointerMoved(to: Panel.inside, zones: withRegion.expandedCopy)
    #expect(moving.region == nil && !moving.isCurrent(serial))
    var leaving = linger
    leaving.pointerMoved(to: CGPoint(x: 100, y: 300), zones: withRegion.expandedCopy)
    #expect(leaving.region == nil)
    var closing = linger
    closing.pointerMoved(to: pickedItem, zones: withRegion)                 // `expanded` is false: closed
    #expect(closing.region == nil)

    // … or when the safety check cannot read the pointer; an earlier region's check leaves a later one alone.
    var expiring = linger
    #expect(expiring.expire(serial) && expiring.region == nil && !expiring.expire(serial))
    var later = linger
    later.began(at: cameraButton, zones: zones)
    let laterRecorded = later.ended(at: pickedItem, zones: zones, reach: cameraMenu)
    let next = try #require(laterRecorded)
    #expect(next == serial + 1 && !later.isCurrent(serial) && !later.expire(serial) && later.region != nil)
    #expect(later.expire(next) && later.region == nil)
}

/// AppKit does not say where a menu hung, only its size, so the region must hold the menu wherever it was: a pull-down
/// below its button (aligned to either edge), a pop-up with the chosen item over the button, a context menu at the
/// click (flipped left near an edge), and a header menu that AppKit moved down to keep it on the screen. After any
/// pick outside the exit zone the region holds that whole menu (on the screen), and never more than the screen.
@Test func theMenuRegionHoldsTheMenuWhereverItHung() throws {
    let zones = HoverZones(shape: Panel.open, satellite: nil, wings: nil, screenFrame: Panel.screen, band: 32,
                           expanded: true)
    let button = CGRect(x: 960, y: 846, width: 80, height: 28)                   // the control around `cameraButton`
    let w = cameraMenu.width, h = cameraMenu.height
    let header = CGPoint(x: 980, y: 960)                                         // a control in the open header
    let tall = CGSize(width: 220, height: 300)
    let placements: [(name: String, origin: CGPoint, size: CGSize, menu: CGRect)] = [
        ("pull-down, leading edge", cameraButton, cameraMenu, CGRect(x: button.minX, y: button.minY - 4 - h, width: w, height: h)),
        ("pull-down, trailing edge", cameraButton, cameraMenu, CGRect(x: button.maxX - w, y: button.minY - 4 - h, width: w, height: h)),
        ("pop-up over the button", cameraButton, cameraMenu, CGRect(x: button.minX - 12, y: button.midY - 100, width: w, height: h)),
        ("context menu at the click", cameraButton, cameraMenu, CGRect(x: cameraButton.x, y: cameraButton.y - h, width: w, height: h)),
        ("context menu flipped left", cameraButton, cameraMenu, CGRect(x: cameraButton.x - w, y: cameraButton.y - h, width: w, height: h)),
        ("header pop-up kept on the screen", header, tall, CGRect(x: header.x - 20, y: Panel.screen.maxY - tall.height,
                                                                   width: tall.width, height: tall.height)),
    ]
    var regions = 0
    for placement in placements {
        let menu = placement.menu
        let inner = menu.insetBy(dx: 1, dy: 1)
        let picks = [CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                     CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY),
                     CGPoint(x: menu.midX, y: menu.midY)]
        for item in picks where !zones.hoverZone.contains(item) {
            var linger = MenuLinger()
            linger.began(at: placement.origin, zones: zones)
            _ = linger.ended(at: item, zones: zones, reach: placement.size)
            let region = try #require(linger.region, "\(placement.name): no region for a pick at \(item)")
            regions += 1
            #expect(region.contains(menu) && region.contains(placement.origin) && region.contains(item),
                    "\(placement.name): \(menu) picked at \(item) → \(region)")
            #expect(region.maxY <= Panel.screen.maxY + 1 && region.minX >= Panel.screen.minX)
        }
    }
    #expect(regions >= 15)
}

private extension HoverZones {
    var expandedCopy: HoverZones {
        var copy = self
        copy.expanded = true
        return copy
    }
}

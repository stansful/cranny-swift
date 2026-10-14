// What a file drag and a tracking menu leave behind on a panel (ARCHITECTURE.md §4.4–§4.5, §10.20 issues 8 and 12):
// a closed panel keeps no drag state or `drag` hold, and a menu opened from the panel does not close it the moment the
// item it picked hung below the panel. The reducer is driven through the production pointer code: `PanelHover` (as
// `NotchPanelController` wires it) and `PanelHover.menuTracking` (as `OverlayCoordinator` calls it). No windows, no
// input.
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

// MARK: - Menus opened from the panel (issue 12)

/// Mirror's camera menu, 220 × 160 pt, opened from the camera button of a card in the lower row.
private let cameraButton = CGPoint(x: 980, y: 860)
private let cameraMenu = CGSize(width: 220, height: 160)
/// Where the picked camera was: below the exit zone (y 768), within the menu.
private let pickedItem = CGPoint(x: 1000, y: 720)

/// One panel as `NotchPanelController` wires it: the production `PanelHover` on the open shape's zones, feeding the
/// reducer. The close grace after a menu is run by hand (`graceAfterTheMenuRunsOut`).
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
    private var expiries: [@MainActor () -> Void] = []
    private var time = 0.0

    init(state: NotchMachineState) {
        self.state = state
        hover.zones = { [unowned self] in
            HoverZones(shape: Self.open, satellite: nil, wings: nil, screenFrame: Self.screen, band: 32,
                       expanded: self.state.isOpen || self.state.isPeeking)
        }
        hover.send = { [unowned self] input in self.send(input) }
        hover.pointer = { [unowned self] in self.pointer }
        hover.after = { [unowned self] delay, work in
            #expect(delay == HoverIntent.closeGrace)
            self.expiries.append(work)
        }
    }

    func send(_ input: NotchInput) {
        time += 1
        let (next, fx) = NotchMachine.reduce(state, input, now: time, config: NotchMachineConfig())
        state = next
        effects += fx
    }

    /// A pointer event (the monitors see none while a menu tracks).
    func move(to point: CGPoint) {
        pointer = point
        hover.moved(to: point)
    }

    /// The close grace after the menu closed has passed.
    func graceAfterTheMenuRunsOut() {
        let due = expiries
        expiries = []
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

/// Mirror's camera menu: the camera picked hangs below the panel. For the grace after the menu closed, the place where
/// it hung counts as inside: coming back up keeps the panel without a grace, and later leaves are ordinary ones.
@MainActor @Test func aMenuFromThePanelKeepsItsRegionForTheGrace() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)                              // the hover tracker saw nothing while it tracked
    #expect(panel.state.isOpen && panel.state.hover == .inside && !panel.graceScheduled)
    panel.move(to: CGPoint(x: 1000, y: 745))                 // back up toward the panel
    panel.move(to: Panel.inside)                             // inside again: the region has done its job
    panel.graceAfterTheMenuRunsOut()                         // nothing left to expire
    #expect(!panel.graceScheduled && panel.state.hover == .inside && panel.hover.linger.region == nil)
    panel.move(to: pickedItem)                               // leaving the same way later is an ordinary leave
    #expect(panel.graceScheduled)
}

/// The region lasts the grace, not longer: a pointer that stays where the menu hung is read again when the grace is
/// over and gets the usual grace from there; one that leaves the region gets it at once.
@MainActor @Test func theMenusRegionEndsWithTheGraceOrWhenThePointerLeavesIt() {
    let panel = openPanel()
    let menus = MenuSession(panel)
    menus.began(at: cameraButton)
    menus.ended(at: pickedItem)
    panel.move(to: CGPoint(x: 990, y: 725))                  // still where the menu was
    #expect(!panel.graceScheduled)
    panel.graceAfterTheMenuRunsOut()                         // 0.3 s after the menu closed
    #expect(panel.graceScheduled && panel.state.hover == .outside && panel.hover.linger.region == nil)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)

    let second = openPanel()
    let again = MenuSession(second)
    again.began(at: cameraButton)
    second.move(to: pickedItem)                              // pointer events that arrived while it tracked
    again.ended(at: pickedItem)
    #expect(second.state.hover == .inside && !second.graceScheduled)
    second.move(to: CGPoint(x: 1000, y: 600))                // below the menu's region
    #expect(second.graceScheduled && second.state.hover == .outside)
    second.graceAfterTheMenuRunsOut()                        // the region had already gone
    second.send(.timerElapsed(.grace))
    #expect(second.state.isClosed)
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

@Test func theMenuRegionSpansFromTheExitZoneToThePickedItem() throws {
    let zones = HoverZones(shape: Panel.open, satellite: nil, wings: nil, screenFrame: Panel.screen, band: 32,
                           expanded: true)
    var linger = MenuLinger()
    linger.began(at: cameraButton, zones: zones)
    #expect(linger.fromPanel && linger.origin == cameraButton)
    let recorded = linger.ended(at: pickedItem, zones: zones, reach: cameraMenu)
    let serial = try #require(recorded)
    let region = try #require(linger.region)
    #expect(region.contains(pickedItem) && region.contains(zones.hoverZone))
    #expect(region.minY == pickedItem.y - HoverIntent.exitInflation)
    #expect(!linger.fromPanel)                                                // one menu, one region

    // It counts as inside only while the panel shows open (or peeks).
    var withRegion = zones
    withRegion.menuRegion = region
    #expect(withRegion.contains(pickedItem) && !zones.contains(pickedItem))
    withRegion.expanded = false
    #expect(!withRegion.contains(pickedItem))

    // No region for an item picked inside the exit zone, a menu that began elsewhere or on a closed panel, or an end
    // beyond the menu's reach from where it began.
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
    let extent = MenuLinger.extent(from: cameraButton, reach: cameraMenu)
    #expect(extent.contains(pickedItem) && !extent.contains(CGPoint(x: 100, y: 100)))
    #expect(extent.minY == cameraButton.y - cameraMenu.height - MenuLinger.controlSlack)
    var beyond = MenuLinger()
    beyond.began(at: cameraButton, zones: zones)
    #expect(beyond.ended(at: CGPoint(x: extent.midX, y: extent.minY - 1), zones: zones, reach: cameraMenu) == nil)

    // The region ends when the pointer leaves it, comes back inside, or the panel closes …
    var moving = linger
    moving.pointerMoved(to: CGPoint(x: 1000, y: 745), zones: withRegion.expandedCopy)
    #expect(moving.region == region)
    moving.pointerMoved(to: Panel.inside, zones: withRegion.expandedCopy)
    #expect(moving.region == nil)
    var leaving = linger
    leaving.pointerMoved(to: CGPoint(x: 100, y: 300), zones: withRegion.expandedCopy)
    #expect(leaving.region == nil)
    var closing = linger
    closing.pointerMoved(to: pickedItem, zones: withRegion)                 // `expanded` is false: closed
    #expect(closing.region == nil)

    // … and with its grace; an earlier region's expiry leaves a later one alone.
    var expiring = linger
    #expect(expiring.expire(serial) && expiring.region == nil && !expiring.expire(serial))
    var later = linger
    later.began(at: cameraButton, zones: zones)
    let laterRecorded = later.ended(at: pickedItem, zones: zones, reach: cameraMenu)
    let next = try #require(laterRecorded)
    #expect(next == serial + 1 && !later.expire(serial) && later.region != nil && later.expire(next))
}

private extension HoverZones {
    var expandedCopy: HoverZones {
        var copy = self
        copy.expanded = true
        return copy
    }
}

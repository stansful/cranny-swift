// What a file drag and a tracking menu leave behind on a panel (ARCHITECTURE.md §4.4–§4.5, §10.20 issues 8 and 12):
// a closed panel keeps no drag state or `drag` hold, and a menu opened from the panel does not close it when the item
// it picked hung below the panel. The reducer is driven as the controller drives it: `HoverTracker` turns pointer
// positions into enter/leave, `MenuLinger` keeps the menu's region inside. No windows, no input.
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

/// One panel as `NotchPanelController` drives it: zones from the open shape, `HoverTracker`, `MenuLinger`, the reducer.
@MainActor private final class PanelHover {
    nonisolated static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// The open shape, top-centred (screen coordinates, bottom-left origin).
    nonisolated static let open = CGRect(x: 406, y: 782, width: 700, height: 200)
    nonisolated static let inside = CGPoint(x: 756, y: 900)
    /// Where a menu that hung below the panel had the picked item.
    nonisolated static let menuItem = CGPoint(x: 700, y: 600)

    var state: NotchMachineState
    private(set) var effects: [NotchEffect] = []
    private let tracker = HoverTracker()
    private var linger = MenuLinger()
    private var time = 0.0

    init(state: NotchMachineState) { self.state = state }

    var zones: HoverZones {
        HoverZones(shape: Self.open, satellite: nil, wings: nil, screenFrame: Self.screen, band: 32,
                   expanded: state.isOpen || state.isPeeking, menuRegion: linger.region)
    }

    func send(_ input: NotchInput) {
        time += 1
        let (next, fx) = NotchMachine.reduce(state, input, now: time, config: NotchMachineConfig())
        state = next
        effects += fx
    }

    func move(to point: CGPoint) {
        let zones = zones
        for input in tracker.update(point, zones: zones) { send(input) }
        linger.pointerMoved(to: point, zones: zones)
    }

    /// `OverlayCoordinator.menuTracking`: the panel learns the pointer, then the `menu` hold changes.
    func menuBegan(at point: CGPoint) {
        linger.began(at: point, zones: zones)
        send(.hold(menuHold, true))
    }

    func menuEnded(at point: CGPoint) {
        linger.ended(at: point, zones: zones)
        move(to: point)
        send(.hold(menuHold, false))
    }

    var graceScheduled: Bool { effects.contains(.schedule(.grace, after: HoverIntent.closeGrace)) }
    func clearEffects() { effects = [] }
}

@MainActor private func openPanel() -> PanelHover {
    let panel = PanelHover(state: run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: NotchMachineConfig()).0)
    panel.move(to: PanelHover.inside)
    panel.clearEffects()
    return panel
}

@MainActor @Test func aTrackingMenuNeverStartsTheCloseGrace() {
    let panel = openPanel()
    panel.menuBegan(at: PanelHover.inside)
    panel.move(to: PanelHover.menuItem)                     // events that do arrive while the menu tracks
    panel.send(.timerElapsed(.grace))                        // a stale grace from before the menu
    #expect(panel.state.isOpen && !panel.graceScheduled && panel.state.hover == .outside)
}

/// Mirror's camera menu: the item picked hangs below the panel. The panel stays while the pointer is where the menu
/// was or comes back up; leaving from there closes it after the usual grace.
@MainActor @Test func aMenuFromThePanelKeepsItsRegionAfterItCloses() {
    let panel = openPanel()
    panel.menuBegan(at: PanelHover.inside)
    panel.menuEnded(at: PanelHover.menuItem)                 // the hover tracker saw nothing while it tracked
    #expect(panel.state.isOpen && panel.state.hover == .inside && !panel.graceScheduled)
    panel.move(to: CGPoint(x: 720, y: 700))                  // back up toward the panel
    #expect(!panel.graceScheduled)
    panel.move(to: PanelHover.inside)                        // inside again: the region has done its job
    panel.move(to: PanelHover.menuItem)                      // leaving the same way later is an ordinary leave
    #expect(panel.graceScheduled)

    // The same, with pointer events arriving while it tracked (the machine already saw the pointer leave).
    let second = openPanel()
    second.menuBegan(at: PanelHover.inside)
    second.move(to: PanelHover.menuItem)
    second.menuEnded(at: PanelHover.menuItem)
    #expect(second.state.hover == .inside && !second.graceScheduled)
    second.move(to: CGPoint(x: 700, y: 450))                 // away from the panel, out of the menu's region
    #expect(second.graceScheduled && second.state.hover == .outside)
    second.send(.timerElapsed(.grace))
    #expect(second.state.isClosed)
}

/// A menu that did not open from the panel (the menu bar extra's, a Settings pop-up) holds it while it tracks and
/// leaves nothing behind: a pointer outside closes it after the grace as before.
@MainActor @Test func aMenuFromElsewhereLeavesNoRegion() {
    let panel = openPanel()
    panel.move(to: CGPoint(x: 1400, y: 978))                 // off to the menu bar extra
    #expect(panel.graceScheduled)
    panel.clearEffects()
    panel.menuBegan(at: CGPoint(x: 1400, y: 978))
    #expect(panel.effects == [.cancel(.grace)])
    panel.menuEnded(at: CGPoint(x: 1400, y: 960))
    #expect(panel.graceScheduled)
    panel.send(.timerElapsed(.grace))
    #expect(panel.state.isClosed)
}

@Test func theMenuRegionSpansFromTheExitZoneToThePickedItem() throws {
    let zones = HoverZones(shape: PanelHover.open, satellite: nil, wings: nil, screenFrame: PanelHover.screen, band: 32,
                           expanded: true)
    var linger = MenuLinger()
    linger.began(at: PanelHover.inside, zones: zones)
    #expect(linger.fromPanel)
    linger.ended(at: PanelHover.menuItem, zones: zones)
    let region = try #require(linger.region)
    #expect(region.contains(PanelHover.menuItem) && region.contains(zones.hoverZone))
    #expect(region.minY == PanelHover.menuItem.y - HoverIntent.exitInflation)
    #expect(!linger.fromPanel)                                                // one menu, one region

    // It counts as inside only while the panel shows open (or peeks).
    var withRegion = zones
    withRegion.menuRegion = region
    #expect(withRegion.contains(PanelHover.menuItem) && !zones.contains(PanelHover.menuItem))
    withRegion.expanded = false
    #expect(!withRegion.contains(PanelHover.menuItem))

    // An item picked inside the exit zone needs no region; neither does a menu that began elsewhere or on a closed panel.
    var near = MenuLinger()
    near.began(at: PanelHover.inside, zones: zones)
    near.ended(at: CGPoint(x: 700, y: 775), zones: zones)
    #expect(near.region == nil)
    var elsewhere = MenuLinger()
    elsewhere.began(at: CGPoint(x: 1400, y: 978), zones: zones)
    elsewhere.ended(at: PanelHover.menuItem, zones: zones)
    #expect(elsewhere.region == nil)
    var closed = MenuLinger()
    var closedZones = zones
    closedZones.expanded = false
    closed.began(at: PanelHover.inside, zones: closedZones)
    closed.ended(at: PanelHover.menuItem, zones: closedZones)
    #expect(closed.region == nil)

    // The region ends when the pointer leaves it, comes back inside, or the panel closes.
    var moving = linger
    moving.pointerMoved(to: CGPoint(x: 720, y: 700), zones: withRegion.expandedCopy)
    #expect(moving.region == region)
    moving.pointerMoved(to: PanelHover.inside, zones: withRegion.expandedCopy)
    #expect(moving.region == nil)
    var leaving = linger
    leaving.pointerMoved(to: CGPoint(x: 100, y: 300), zones: withRegion.expandedCopy)
    #expect(leaving.region == nil)
    var closing = linger
    closing.pointerMoved(to: PanelHover.menuItem, zones: withRegion)          // `expanded` is false: closed
    #expect(closing.region == nil)
}

private extension HoverZones {
    var expandedCopy: HoverZones {
        var copy = self
        copy.expanded = true
        return copy
    }
}

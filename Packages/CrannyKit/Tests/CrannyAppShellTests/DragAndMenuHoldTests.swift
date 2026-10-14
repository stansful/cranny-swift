// What a file drag leaves behind on a panel (ARCHITECTURE.md §4.4, §10.20 issue 8): a closed panel keeps no
// drag state or `drag` hold, and a drag session that ends without a drop takes everything it left. Pure reducer
// runs: no windows, no input.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

private let pdf: [UTType] = [.pdf]
private let dragHold = NotchMachineState.dragHold

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

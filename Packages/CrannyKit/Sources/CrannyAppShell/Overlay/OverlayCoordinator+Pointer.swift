// CrannyAppShell/Overlay/OverlayCoordinator+Pointer.swift — the pointer and file drags across the panels
// (ARCHITECTURE.md §5.5). Each pointer event finds the pointer's display, feeds the drag detector (which reads the
// drag pasteboard only while the pointer is within some panel's drag zone) and each panel's hover.
//
// With the pointer tap, only the events that can change something reach this file (`pointerGate()`): every up and
// every change between moving and dragging, a display change, and events within some panel's hover or exit zone, band,
// menu region or (dragging) drag zone; everything while a panel has the pointer inside, in its band or in a menu's
// region, while a file drag is in progress, while a display change waits for its rebuild, and until the gate is
// published again after any of this changed (`PointerMonitor.gateChanged`: the panels' zones and hover, the displays,
// the pointer's display, a file drag starting or ending).
//
// While the pointer can change nothing, its events pause: one display, and it shows no panel or its panel is
// hard-hidden (lock, display sleep, In full-screen apps ▸ Hide with a full-screen or excluded app in front), so there
// are no hover or drag zones and the pointer's display cannot change. The pause starts after a plain move was handled
// (the panels have seen the pointer leave; no drag is in progress) and ends with the display facts that let the
// pointer matter again (`applyDisplayFacts`). Then the panels learn where the pointer is at its next event, exactly
// as without the pause. Mouse-downs still arrive while paused, so the drag detector's baseline stays what it would
// have been.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.overlay)

extension OverlayCoordinator {
    func pointerEvent(_ point: CGPoint, kind: PointerMonitor.Kind) {
        updatePointerDisplay(point)
        // A file drag acts only within a drag zone; elsewhere the detector leaves the drag pasteboard alone. Asked only
        // while the drag waits for its inspection (once per mouse-down).
        let nearPanel = kind == .dragged && drags.awaitsInspection
            && controllers.values.contains { $0.hoverZones?.dragZone.contains(point) == true }
        if let change = drags.update(kind, nearPanel: nearPanel) {
            pointer.gateChanged()                                              // a file drag started or ended
            if change == nil { for controller in controllers.values { controller.dragEnded() } }
        }
        for controller in controllers.values {
            controller.pointerMoved(to: point)
            if let contents = drags.current { controller.dragMoved(to: point, contents: contents) }
        }
        if kind == .moved, pointerCanPause {
            pointer.pause { [weak self] in self?.drags.pressedWhilePaused() }
            log.debug("pointer paused: nothing it does can show")
        }
    }

    /// A drop on `source` ends the drag everywhere. The detector may never see the source's mouse-up, so it would
    /// never report the end: every other panel the drag passed (its catch state, `drag` hold and enlarged drop zone)
    /// lets go now. The dropping panel keeps its zones until the drop router has delivered the payload.
    func dropFinished(on source: NotchPanelController?) {
        drags.reset()
        pointer.gateChanged()
        for controller in controllers.values {
            if controller === source { controller.dropFinished() } else { controller.dragEnded() }
        }
    }

    /// O(displays), no allocation: the cached frames, the top row included (y == maxY, R1 §2.5).
    func updatePointerDisplay(_ point: CGPoint) {
        var found: (key: DisplayKey, id: CGDirectDisplayID)?
        for screen in screens where point.x >= screen.frame.minX && point.x < screen.frame.maxX
            && point.y >= screen.frame.minY && point.y <= screen.frame.maxY {
            found = (screen.key, screen.id)
            break
        }
        guard let found, found.key != pointerDisplay else { return }
        pointerDisplay = found.key
        pointer.gateChanged()
        environment.setPointerDisplay(found.id)
        // Now, not on the next observation hop: sliding along the menu bar onto the other display's notch must
        // find its panel already shown (`.pointer` selection) and its alerts already moved.
        if !controllers.isEmpty { applyDisplayFacts() }
    }

    // MARK: Pointer tap

    /// What the pointer tap needs to keep the events that change nothing off the main actor (`PointerGate`). Built only
    /// after a change (`PointerMonitor.gateChanged`), from each panel's cached zones.
    func pointerGate() -> PointerGate {
        var gate = PointerGate(screens: screens.map(\.frame), primaryTop: primaryTop,
                               forwardAll: drags.current != nil || displayChanges.isPending)
        gate.pointerScreen = pointerDisplay.flatMap { key in screens.firstIndex { $0.key == key } }
        for controller in controllers.values {
            let hover = controller.hover
            gate.addPanel(zones: hover.hoverZones, inside: hover.isInside, band: hover.band, lingers: hover.linger.region != nil)
        }
        return gate
    }

    // MARK: Pausing

    /// The display facts changed (`applyDisplayFacts`): a paused pointer resumes as soon as it could change something.
    func resumePointerIfNeeded() {
        guard pointer.isPaused, !pointerCanPause else { return }
        drags.resumed(buttonsDown: NSEvent.pressedMouseButtons != 0)
        pointer.resume()
        log.debug("pointer resumed")
    }

    /// Nothing the pointer does can show now (allocation-free: it is asked after every plain move).
    private var pointerCanPause: Bool {
        Self.pointerCanPause(displays: screens.count, panels: controllers.values.lazy.map { $0.viewModel.state.environment })
    }

    /// Pure: one display, and every panel on it (none, or its one) is hard-hidden, so it has no hover or drag zones.
    /// With more displays the pointer still picks the alert display (and, under `.pointer`, the one that shows).
    static func pointerCanPause<Panels: Sequence>(displays: Int, panels: Panels) -> Bool
        where Panels.Element == NotchEnvironment {
        displays == 1 && panels.allSatisfy { $0.hardHidden != nil }
    }
}

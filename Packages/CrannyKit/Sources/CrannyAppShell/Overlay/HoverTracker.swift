// CrannyAppShell/Overlay/HoverTracker.swift — geometric hover for one panel (ARCHITECTURE.md §4.3, §5.5,
// DESIGN.md §3.6, §4.6). `HoverZones` is pure zone math in AppKit screen coordinates (bottom-left origin);
// `HoverTracker` turns pointer positions into the machine's enter/leave and band inputs, only on change;
// `MenuLinger` keeps a menu's region inside for the grace after a menu opened from the panel closes, `MenuTracking`
// counts the NSMenu sessions and `PanelHover` is one panel's pointer, as the controller and the tests drive it (§4.5).
// Zones reach above the screen's top edge, because the pointer's y can equal `frame.maxY` (R1 §2.5).
import AppKit
import CrannyCore
import Foundation

nonisolated struct HoverZones: Equatable, Sendable {
    /// The shape as drawn (or the hidden handle), from the screen's top edge down to its bottom.
    var shape: CGRect
    /// The satellite bubble beside compact, if one is showing.
    var satellite: CGRect?
    /// The compact wings for menu-bar courtesy (also while they are retracted).
    var wings: CGRect?
    var screenFrame: CGRect
    /// Menu bar / notch band height.
    var band: CGFloat
    /// Open or peek: the exit zone (+14 pt) applies instead of the entry zone (+4 pt).
    var expanded: Bool
    /// Where a menu opened from the panel was, still counted as inside after it closed (`MenuLinger`; open or peek).
    var menuRegion: CGRect?

    /// Entry zone (shape + 4 pt) or exit zone (shape + 14 pt), extended above the top edge.
    var hoverZone: CGRect {
        let inflation = expanded ? HoverIntent.exitInflation : HoverIntent.entryInflation
        var zone = satellite.map { shape.union($0) } ?? shape
        zone = zone.insetBy(dx: -inflation, dy: -inflation)
        zone.size.height = screenFrame.maxY + 1 - zone.minY
        return zone
    }

    /// A file drag here opens the catch state with no dwell: the closed shape + 80 pt on each side, down to
    /// 40 pt below the band (§4.3). Over an open panel it is the exit zone.
    var dragZone: CGRect {
        if expanded { return hoverZone }
        let proximity = HoverIntent.dragProximity
        let top = screenFrame.maxY + 1
        let bottom = min(screenFrame.maxY - band - proximity.height, shape.minY)
        return CGRect(x: shape.minX - proximity.width, y: bottom,
                      width: shape.width + 2 * proximity.width, height: top - bottom)
    }

    /// The menu bar band across the whole display.
    var bandRect: CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.maxY - band, width: screenFrame.width, height: band + 1)
    }

    func contains(_ point: CGPoint) -> Bool {
        hoverZone.contains(point) || (expanded && menuRegion?.contains(point) == true)
    }

    /// Courtesy = in the band within 24 pt beside the wings, outside the entry zone (DESIGN.md §4.6). The satellite
    /// sits in that strip; the pointer on it came for the satellite, not for the menu bar.
    func bandPosition(_ point: CGPoint) -> BandPosition {
        let band = bandRect
        guard band.contains(point) else { return .outside }
        guard let wings, !expanded, !hoverZone.contains(point) else { return .band }
        let reach = HoverIntent.menuBarCourtesy, gap = HoverIntent.entryInflation
        let left = CGRect(x: wings.minX - reach, y: band.minY, width: reach - gap, height: band.height)
        let right = CGRect(x: wings.maxX + gap, y: band.minY, width: reach - gap, height: band.height)
        return left.contains(point) || right.contains(point) ? .courtesy : .band
    }

    // MARK: Building

    /// The rect of `geometry` drawn top-centred in a panel at `panelFrame` (screen coordinates).
    static func shapeRect(_ geometry: NotchGeometry, panelFrame: CGRect) -> CGRect {
        CGRect(x: panelFrame.midX - geometry.outerWidth / 2, y: panelFrame.maxY - geometry.bottom,
               width: geometry.outerWidth, height: geometry.bottom)
    }

    /// A rect in the canvas (top-left origin) converted to screen coordinates.
    static func screenRect(_ canvasRect: CGRect, panelFrame: CGRect) -> CGRect {
        CGRect(x: panelFrame.minX + canvasRect.minX, y: panelFrame.maxY - canvasRect.maxY,
               width: canvasRect.width, height: canvasRect.height)
    }
}

/// A menu opened from the panel (a widget's menu such as Mirror's cameras, a context menu) hangs below it, so the
/// pointer that picks an item is usually outside the exit zone when the menu closes, over a place that no longer shows
/// anything. While the menu tracks, its `menu` hold keeps the panel. After it closes, the rect from the exit zone to
/// where the pointer was (+14 pt) counts as inside for the close grace (`HoverIntent.closeGrace`): the grace does not
/// start while the pointer is still where the menu hung. The region ends when that time is up (the owner calls
/// `expire`), when the pointer leaves it or when it comes back to the panel; then the usual grace applies.
///
/// Only the menu's own region: a menu that did not begin with the pointer on the open (or peeking) panel — the menu bar
/// extra's, a Settings pop-up — leaves nothing, and neither does one that ended with the pointer beyond the menus' own
/// size from where it began (dismissed by a click elsewhere, Esc after the pointer moved away). Pure.
nonisolated struct MenuLinger: Equatable, Sendable {
    /// Where the pointer was when the tracking menu began on this panel; nil for a menu from elsewhere.
    private(set) var origin: CGPoint?
    /// The region that still counts as inside (screen coordinates), or nil.
    private(set) var region: CGRect?
    /// Numbers the regions, so the expiry of an earlier one leaves a later one alone.
    private(set) var serial = 0

    /// The tracking menu began with the pointer on this panel.
    var fromPanel: Bool { origin != nil }

    /// A menu began tracking (nested menus: the first).
    mutating func began(at point: CGPoint, zones: HoverZones?) {
        region = nil
        origin = zones.flatMap { $0.expanded && $0.contains(point) ? point : nil }
    }

    /// The last menu stopped tracking with the pointer at `point`; `reach` is how far the session's menus extend
    /// (`MenuTracking.reach`). Returns the serial of the region it recorded, for `expire` after the grace; nil when
    /// it recorded none.
    mutating func ended(at point: CGPoint, zones: HoverZones?, reach: CGSize) -> Int? {
        defer { origin = nil }
        region = nil
        guard let origin, let zones, zones.expanded, !zones.hoverZone.contains(point),
              Self.extent(from: origin, reach: reach).contains(point) else { return nil }
        region = Self.region(from: zones.hoverZone, to: point)
        serial += 1
        return serial
    }

    /// The pointer moved (after `HoverTracker.update` saw it with the region): the region ends once the pointer is
    /// outside it, back inside the exit zone, or the panel no longer shows open.
    mutating func pointerMoved(to point: CGPoint, zones: HoverZones?) {
        guard let current = region else { return }
        let stays = zones.map { $0.expanded && current.contains(point) && !$0.hoverZone.contains(point) } ?? false
        if !stays { region = nil }
    }

    /// The grace after the menu closed is over. True when region `serial` was still there and has gone now (the owner
    /// then re-reads the pointer, so a pointer still outside the exit zone starts the usual grace).
    mutating func expire(_ serial: Int) -> Bool {
        guard serial == self.serial, region != nil else { return false }
        region = nil
        return true
    }

    /// The smallest rect holding the exit zone and the point, grown by the exit hysteresis.
    static func region(from exit: CGRect, to point: CGPoint) -> CGRect {
        let inflation = HoverIntent.exitInflation
        return exit.union(CGRect(origin: point, size: .zero)).insetBy(dx: -inflation, dy: -inflation)
    }

    /// Where the menus of a session that began with the pointer at `origin` can be. A menu opens from the control
    /// under the pointer (a pull-down below it, a context menu at the click, a pop-up over its button; any of them
    /// flipped at the screen's edges, a submenu beside its item), so it lies within `reach` of that point in every
    /// direction, plus the control itself (`controlSlack`).
    static func extent(from origin: CGPoint, reach: CGSize) -> CGRect {
        CGRect(x: origin.x - reach.width, y: origin.y - reach.height, width: 2 * reach.width, height: 2 * reach.height)
            .insetBy(dx: -controlSlack, dy: -controlSlack)
    }

    /// The control a menu hangs from, beside the point that opened it: a band control's height (DESIGN.md §2.3).
    static let controlSlack: CGFloat = 32
}

/// The NSMenu tracking sessions the coordinator counts (§4.5). Menus nest (a submenu tracks inside its menu's
/// session), so the `menu` hold lasts from the first begin to the last end. `reach` adds up the sizes of the
/// session's menus (`NSMenu.size`): how far from where the session began they can extend. Pure.
nonisolated struct MenuTracking: Equatable, Sendable {
    /// The first menu began, or the last one ended (with the session's reach).
    enum Edge: Equatable, Sendable {
        case began
        case ended(reach: CGSize)
    }

    private(set) var depth = 0
    private(set) var reach: CGSize = .zero
    var isTracking: Bool { depth > 0 }

    /// One begin or end notification of a menu `size` large (zero when unknown). Returns the edge when this began the
    /// first menu or ended the last one. An end without a begin changes nothing.
    mutating func update(began: Bool, size: CGSize) -> Edge? {
        if began {
            depth += 1
            reach = depth == 1 ? size : CGSize(width: reach.width + size.width, height: reach.height + size.height)
            return depth == 1 ? .began : nil
        }
        guard depth > 0 else { return nil }
        // A menu may fill in its items only as it opens, so its size at the end counts too.
        reach = CGSize(width: max(reach.width, size.width), height: max(reach.height, size.height))
        depth -= 1
        guard depth == 0 else { return nil }
        defer { reach = .zero }
        return .ended(reach: reach)
    }
}

/// The pointer as one panel sees it (§4.3, §4.5): `HoverTracker` turns positions into the machine's inputs and
/// `MenuLinger` keeps a menu's region inside for the grace after it closed. `NotchPanelController` owns one and wires
/// the closures to its panel; tests wire them to a reducer, so both run this code.
@MainActor final class PanelHover {
    /// The panel's hover zones without a menu's region; nil while hidden.
    var zones: @MainActor () -> HoverZones? = { nil }
    /// Feeds the panel's machine.
    var send: @MainActor (NotchInput) -> Void = { _ in }
    /// Where the pointer is now, read when a menu's region expires.
    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    /// Runs the work once after the delay (one sleep, no polling). Tests run it by hand.
    var after: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            work()
        }
    }

    private let tracker = HoverTracker()
    private(set) var linger = MenuLinger()

    /// The zones the pointer is measured against, with a menu's region while it lasts.
    var hoverZones: HoverZones? {
        guard var zones = zones() else { return nil }
        zones.menuRegion = linger.region
        return zones
    }

    var isInside: Bool { tracker.isInside }

    /// A pointer move (and the re-read after a menu): enter/leave and band inputs on change.
    func moved(to point: CGPoint) {
        let zones = hoverZones
        for input in tracker.update(point, zones: zones) { send(input) }
        linger.pointerMoved(to: point, zones: zones)
    }

    /// A file drag moved: true when it just came within the drag zone, false when it just left, nil otherwise.
    func dragMoved(to point: CGPoint) -> Bool? { tracker.updateDrag(point, zones: hoverZones) }

    /// The drag ended: the next drag starts outside.
    func resetDrag() { tracker.resetDrag() }

    // MARK: Menus (§4.5)

    /// The first menu began tracking: remember whether it opened from this panel.
    func menuBegan(at point: CGPoint) {
        linger.began(at: point, zones: hoverZones)
    }

    /// The last menu stopped tracking with the pointer at `point`. The machine learns where the pointer is now (the
    /// tracker sees no events while a menu tracks), with the menu's region inside when it came from this panel; the
    /// region expires after the close grace.
    func menuEnded(at point: CGPoint, reach: CGSize) {
        if let serial = linger.ended(at: point, zones: hoverZones, reach: reach) {
            after(HoverIntent.closeGrace) { [weak self] in self?.expire(serial) }
        }
        moved(to: point)
    }

    private func expire(_ serial: Int) {
        guard linger.expire(serial) else { return }
        moved(to: pointer())
    }

    /// One NSMenu begin or end notification for every panel (`OverlayCoordinator`), in this order: at the first begin
    /// and the last end each panel reads the pointer, then the `menu` hold follows the session. So the machine knows
    /// where the pointer is (and the menu's region) before the hold that kept the panel is released, and a grace that
    /// started while the menu tracked is cancelled as the hold comes on.
    static func menuTracking(_ tracking: inout MenuTracking, began: Bool, size: CGSize, panels: [PanelHover],
                             pointer: () -> CGPoint, hold: (Bool) -> Void) {
        switch tracking.update(began: began, size: size) {
        case .began:
            let point = pointer()
            for panel in panels { panel.menuBegan(at: point) }
        case .ended(let reach):
            let point = pointer()
            for panel in panels { panel.menuEnded(at: point, reach: reach) }
        case nil:
            break
        }
        hold(tracking.isTracking)
    }
}

/// Remembers where the pointer was for one panel and reports transitions.
@MainActor final class HoverTracker {
    private(set) var isInside = false
    private(set) var band: BandPosition = .outside
    private(set) var isInDragZone = false

    /// Inputs for a pointer move (empty when nothing changed). `zones == nil`: hidden, so the pointer is outside.
    func update(_ point: CGPoint, zones: HoverZones?) -> [NotchInput] {
        var inputs: [NotchInput] = []
        let inside = zones?.contains(point) ?? false
        if inside != isInside {
            isInside = inside
            inputs.append(inside ? .pointerEntered : .pointerLeft)
        }
        let position = zones?.bandPosition(point) ?? .outside
        if position != band {
            band = position
            inputs.append(.band(position))
        }
        return inputs
    }

    /// True when a file drag just came within the drag zone; false when it just left; nil otherwise.
    func updateDrag(_ point: CGPoint, zones: HoverZones?) -> Bool? {
        let inside = zones?.dragZone.contains(point) ?? false
        guard inside != isInDragZone else { return nil }
        isInDragZone = inside
        return inside
    }

    /// The drag ended: the next drag starts outside.
    func resetDrag() { isInDragZone = false }
}

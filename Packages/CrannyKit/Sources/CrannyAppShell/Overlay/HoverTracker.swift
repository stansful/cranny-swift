// CrannyAppShell/Overlay/HoverTracker.swift — geometric hover for one panel (ARCHITECTURE.md §4.3, §5.5,
// DESIGN.md §3.6, §4.6). `HoverZones` is pure zone math in AppKit screen coordinates (bottom-left origin);
// `HoverTracker` turns pointer positions into the machine's enter/leave and band inputs, only on change.
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

    func contains(_ point: CGPoint) -> Bool { hoverZone.contains(point) }

    /// Courtesy = in the band within 24 pt beside the wings, outside the entry zone (DESIGN.md §4.6).
    func bandPosition(_ point: CGPoint) -> BandPosition {
        let band = bandRect
        guard band.contains(point) else { return .outside }
        guard let wings, !expanded else { return .band }
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

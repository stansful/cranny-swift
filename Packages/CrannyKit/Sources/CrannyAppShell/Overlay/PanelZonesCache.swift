// CrannyAppShell/Overlay/PanelZonesCache.swift — one panel's hover zones between the moments they can change
// (ARCHITECTURE.md §5.5). Every pointer event asks every panel for its zones (twice during a file drag), but they
// derive only from the machine's state and scene, the panel's frame and its screen's frame. `NotchPanelController`
// drops them after every sync of its machine (`didSync`: state, lineup and scene, which a new layout or middle-label
// width is always followed by), after it moves the panel and when its display changes; the two frames are compared
// on every read as well, so a frame AppKit changed on its own is never served stale. Pure.
import CoreGraphics

nonisolated struct PanelZonesCache {
    private var entry: (panelFrame: CGRect, screenFrame: CGRect, zones: HoverZones?)?

    /// The zones stored for these frames since the last `invalidate()` (`.some(nil)`: the panel is hidden, it has
    /// none); nil when they must be built.
    func zones(panelFrame: CGRect, screenFrame: CGRect) -> HoverZones?? {
        guard let entry, entry.panelFrame == panelFrame, entry.screenFrame == screenFrame else { return nil }
        return .some(entry.zones)
    }

    /// Keeps `zones`, built for these frames.
    mutating func store(_ zones: HoverZones?, panelFrame: CGRect, screenFrame: CGRect) {
        entry = (panelFrame, screenFrame, zones)
    }

    /// Something the zones derive from changed: the next read builds them again.
    mutating func invalidate() {
        entry = nil
    }
}

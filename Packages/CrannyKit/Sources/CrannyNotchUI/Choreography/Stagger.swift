// CrannyNotchUI/Choreography/Stagger.swift — widgets enter radiating outward from the camera, peek rows top
// to bottom (DESIGN.md §4.3, §4.5). Ring math is pure (unit-tested); `StaggeredReveal` plays it once on appear.
import CrannyCore
import SwiftUI

nonisolated enum Stagger {
    /// Ring of every widget of a row of `cells` widths: 0 for the widget under the camera (the grid's centre),
    /// then +1 per widget outward, capped at 4 (`CrannyMotion.stagger` caps the delay the same way). When the
    /// centre falls on a gutter, both neighbours are ring 0.
    static func rings(cells: [Int]) -> [Int] {
        guard !cells.isEmpty else { return [] }
        let widths = cells.map { Double(max($0, 1)) }
        let total = widths.reduce(0, +)
        let centre = total / 2
        var start = 0.0
        var left = 0, right = 0                       // the widgets nearest the centre on each side
        var found = false
        for (index, width) in widths.enumerated() {
            let end = start + width
            if start < centre && centre < end { left = index; right = index; found = true; break }
            if abs(end - centre) < 0.001 { left = index; right = min(index + 1, widths.count - 1); found = true; break }
            start = end
        }
        if !found { left = 0; right = 0 }
        return cells.indices.map { index in
            let ring = index <= left ? left - index : index - right
            return min(max(ring, 0), 4)
        }
    }

    /// Delay of a widget after `contentIn`'s own 0.06 s: 18 ms per ring (none under Reduce Motion).
    static func delay(ring: Int, reduceMotion: Bool) -> Double {
        CrannyMotion.stagger(ring: ring, reduceMotion: reduceMotion)
    }
}

/// Plays `crannyContent`'s entrance once, when the view appears: blur 6 → 0, scale 0.96 → 1, opacity 0 → 1,
/// after `delay` (Reduce Motion: opacity only, no delay). Used where a parent's insertion must not hide the
/// stagger of its children (the open panel's header and widgets, peek rows). Only during an entrance
/// (`notchEntrance`): the open panel's widgets radiate out of the camera when the panel opens, not again on
/// every tab switch or return from the palette or the editor (those use the `crannyTab` slide or `contentSwap`,
/// DESIGN.md §4.3).
struct StaggeredReveal: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.notchRendersFinalState) private var rendersFinalState
    @Environment(\.notchEntrance) private var entrance
    @State private var revealed = false
    let delay: Double
    var anchor: UnitPoint = .top

    func body(content: Content) -> some View {
        let reduce = theme.reduceMotion
        let animation = theme.contentIn(after: reduce ? 0 : delay)
        let revealed = StaggeredReveal.isShown(revealed: revealed, rendersFinalState: rendersFinalState, entrance: entrance)
        content
            .blur(radius: revealed || reduce ? 0 : 6)
            .scaleEffect(revealed || reduce ? 1 : 0.96, anchor: anchor)
            .opacity(revealed ? 1 : 0)
            .onAppear {
                guard !self.revealed, entrance else { return }
                if let animation { withAnimation(animation) { self.revealed = true } } else { self.revealed = true }
            }
    }

    /// Whether the content is drawn revealed: after its entrance played, in a snapshot, or at once when it
    /// appears outside an entrance. Pure.
    nonisolated static func isShown(revealed: Bool, rendersFinalState: Bool, entrance: Bool) -> Bool {
        revealed || rendersFinalState || !entrance
    }
}

extension View {
    /// Reveals this view once on appear (see `StaggeredReveal`).
    func staggeredReveal(delay: Double, anchor: UnitPoint = .top) -> some View {
        modifier(StaggeredReveal(delay: delay, anchor: anchor))
    }
}

extension EnvironmentValues {
    /// Snapshot rendering (`ImageRenderer` in tests): one-shot entrances render their final state, because a
    /// single rasterized frame never runs `onAppear` animations.
    @Entry var notchRendersFinalState = false
    /// True while a presentation makes its entrance (the open panel's first appearance; peek rows always).
    /// The open panel clears it once its first content has appeared, so later pages appear without a stagger.
    @Entry var notchEntrance = true
}

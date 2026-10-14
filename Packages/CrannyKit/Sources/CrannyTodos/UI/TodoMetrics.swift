// CrannyTodos/UI/TodoMetrics.swift — the widget's own sizes (DESIGN.md §7.6: 22-pt rows, a 16-pt circle).
// Like the grid cell, they grow with Appearance ▸ Text size (never shrink), so larger text never clips.
import CrannyCore
import SwiftUI

struct TodoMetrics: Equatable {
    /// 1 for Small and Standard, 1.12 / 1.24 for Large / Extra Large.
    let scale: CGFloat

    init(textSize: CrannyTextSize) { scale = max(textSize.scale, 1) }

    /// One to-do: a 22-pt row.
    var rowHeight: CGFloat { (22 * scale).rounded() }
    /// The check circle.
    var circle: CGFloat { (16 * scale).rounded() }
    /// The circle's outline (`stroke`, 1.5 pt).
    var circleLine: CGFloat { StrokeWidth.emphasis }
    /// The black check drawn on the accent fill.
    var checkLine: CGFloat { (circle * 0.11 * 4).rounded() / 4 }
    /// "To-dos" + "3 left".
    var headerHeight: CGFloat { (16 * scale).rounded() }
    /// The fade at the bottom of a list that scrolls (the same 12 pt as Calendar, DESIGN.md §7.2).
    var fade: CGFloat { Space.l }
    /// The `plus` glyph of the "New to-do" row.
    var plusGlyph: CGFloat { (11 * scale).rounded() }

}

extension View {
    /// Grows the clickable area of a small control (`size` drawn) to at least the Nook minimum of 28 × 24
    /// (DESIGN.md §16) without changing its layout; the extra area overlaps the gaps around it.
    func todoHitArea(_ size: CGSize) -> some View {
        let h = max((HitTarget.nook.width - size.width) / 2, 0)
        let v = max((HitTarget.nook.height - size.height) / 2, 0)
        return padding(.horizontal, h).padding(.vertical, v)
            .contentShape(Rectangle())
            .padding(.horizontal, -h).padding(.vertical, -v)
    }
}

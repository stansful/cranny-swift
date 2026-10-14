// CrannyCore/Additions/PhaseC-CaptureTargetWidget.swift — additive Core change (Phase C, C-SHELL-1): a type-to-capture
// target names the widget that shows what it creates, so the shell sends the first keys there only while that widget
// is on a page (DESIGN.md §7.5). Without it the default layout (no Notes on Home) silently created hidden notes.
import Foundation

extension CaptureTarget {
    /// A capture target whose items appear in `widget` (Notes: `.notes`, To-dos: `.todos`).
    public init(id: String, title: String, symbol: String, widget: WidgetID,
                capture: @escaping @MainActor (String) -> WidgetID) {
        self.id = id; self.title = title; self.symbol = symbol; self.capture = capture; self.widget = widget
    }
}

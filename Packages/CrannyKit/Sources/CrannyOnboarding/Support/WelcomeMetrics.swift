// CrannyOnboarding/Support/WelcomeMetrics.swift — the Welcome window's own measurements (DESIGN.md §12.1).
// The window is an ordinary system window: its lower half uses system text styles and colours (DESIGN.md
// §2.0 "two worlds"); spacing still comes from the `Space` scale.
import CoreGraphics
import CrannyCore

nonisolated enum WelcomeMetrics {
    /// 640 × 480, not resizable (DESIGN.md §12.1).
    static let window = CGSize(width: 640, height: 480)
    /// The preview stage: the top half, minus a little so the lower half fits six steps of copy and controls.
    static let stageHeight: CGFloat = 216
    static var stageSize: CGSize { CGSize(width: window.width, height: stageHeight) }
    /// Side inset of the lower half.
    static let inset = Space.huge
    /// Space the stage keeps around the notch when the open panel must be scaled down to fit.
    static let stageMargin = Space.xxxl
    /// The open panel never shrinks below this on the stage (DESIGN.md §11.2 keeps ≥ 0.75 on a wider stage).
    static let minimumStageScale: CGFloat = 0.6
    /// The tutorial bubble and the coach mark sit this far under the shape (DESIGN.md §12.2).
    static let tipGap: CGFloat = 10
    /// Corner radius of option, preset and permission cards in the window (a system-world surface).
    static let cardRadius = Radius.tile
}

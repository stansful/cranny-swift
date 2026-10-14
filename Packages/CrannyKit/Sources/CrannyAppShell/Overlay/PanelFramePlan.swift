// CrannyAppShell/Overlay/PanelFramePlan.swift — where one display's panel goes (ARCHITECTURE.md §4.9, §5.1, §5.3):
// top-centred on the camera housing (the screen centre without one), and what a new appearance or display
// geometry does to the frame while the surface is open or closed. Pure; `NotchPanelController` applies it.
import CoreGraphics
import Foundation

/// What a new appearance does to the panel's frame (ARCHITECTURE.md §4.9, §5.1). Pure; unit-tested.
/// - Only the position changed (the display moved in the arrangement, the primary display changed, the lid opened
///   in clamshell): move now, whatever the surface shows. Moving the fixed-size canvas never disturbs a morph.
/// - The layout or canvas size changed: while closed, apply both now; otherwise follow the display with the
///   current size and let the layout wait (`.pending`) until the surface is closed.
nonisolated struct PanelFramePlan: Equatable {
    enum Layout: Equatable { case unchanged, apply, pending }
    var frame: CGRect
    var layout: Layout

    /// Top-centred on the notch (or the screen), pixel-aligned, clamped inside the screen. `leftArea`/`rightArea`
    /// are `NSScreen.auxiliaryTopLeftArea`/`…RightArea` (the menu-bar areas beside the camera housing).
    static func frame(canvas: CGSize, screenFrame f: CGRect, leftArea l: CGRect?, rightArea r: CGRect?) -> CGRect {
        var midX = f.midX
        if let l, let r, l.width > 0, r.width > 0 {
            midX = f.minX + (f.width + l.width - r.width) / 2               // centre of the camera housing
        }
        var frame = CGRect(x: midX - canvas.width / 2, y: f.maxY - canvas.height, width: canvas.width, height: canvas.height)
        frame.origin.x = min(max(frame.minX, f.minX), f.maxX - frame.width)
        return frame.integral
    }
}

extension PanelFramePlan {
    /// `frame(size)` is the top-centred frame of a canvas of that size on the display as it is now.
    init(current: CGRect, canvas: CGSize, layoutChanged: Bool, isClosed: Bool, frame: (CGSize) -> CGRect) {
        let target = frame(canvas)
        if !layoutChanged && target.size == current.size {
            self.frame = target; layout = .unchanged
        } else if isClosed {
            self.frame = target; layout = .apply
        } else {
            self.frame = CGRect(origin: frame(current.size).origin, size: current.size); layout = .pending
        }
    }
}

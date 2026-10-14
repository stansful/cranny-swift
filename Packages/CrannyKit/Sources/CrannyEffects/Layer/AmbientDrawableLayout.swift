// CrannyEffects/Layer/AmbientDrawableLayout.swift — how large the ambient layer's drawable is and where it sits in the
// light's view (pure geometry, unit-tested). `AmbientMetalNSView` applies it to the subview that owns the CAMetalLayer.
//
// Two energy rules (ARCHITECTURE.md §9.2):
//  * Only the lit band is drawn. Aurora and motes are clear in the top 40 % of the light, the tide above its lines
//    (`AmbientRenderer.litTop`), so the drawable covers only the rows below: fewer fragments, tile stores and drawable
//    memory, and the window server re-blends only that band on every frame. The band keeps its place: `offset` pixel
//    rows of the view lie above it and the shader adds them back (`AmbientUniforms.counts.y`), so every pixel is the
//    one a drawable of the whole view would hold.
//  * A resize does not reallocate on every frame. A new `drawableSize` drops the layer's drawables, and the open and
//    close morph change the size on every display frame (≈ 50 new IOSurfaces per morph, 0.3–0.6 ms of main thread
//    each). While the view resizes, the drawable only grows, in 64-pixel steps; a scissor keeps the shader to the band
//    (`region`), the view clips the rest, and the next frame that is not a resize frame returns to the exact size.
import CoreGraphics

nonisolated struct AmbientDrawableLayout: Equatable, Sendable {
    /// The drawable in whole pixels (`CAMetalLayer.drawableSize`).
    var pixels: CGSize
    /// The pixels the light fills, from the drawable's top-left corner: the band, as wide and as low as the view.
    var region: CGSize
    /// Pixel rows of the view above the drawable.
    var offset: Int
    /// The drawable view's frame in the light's (unflipped) view: its top edge `offset` pixels below the view's top,
    /// one pixel of the drawable per device pixel.
    var frame: CGRect

    /// Whether the drawable holds pixels outside the band (left by a resize).
    var hasSlack: Bool { pixels != region }

    /// The growth step of a resizing drawable, in pixels.
    static let step = 64

    /// The layout for a view of `bounds` points at `scale` pixels per point whose top `litTop` points are always clear;
    /// nil while the view has no size. `current` (while resizing): the drawable now, kept while it is large enough,
    /// otherwise grown in `step`s; nil: exactly the band.
    init?(bounds: CGSize, scale: CGFloat, litTop: CGFloat, growingFrom current: CGSize? = nil) {
        guard scale > 0, bounds.width >= 1, bounds.height >= 1 else { return nil }
        let width = Self.wholePixels(bounds.width * scale), height = Self.wholePixels(bounds.height * scale)
        let offset = min(Int((max(litTop, 0) * scale).rounded(.down)), height - 1)
        var w = width, h = height - offset
        region = CGSize(width: w, height: h)
        if let current {
            w = Int(current.width) >= w ? Int(current.width) : Self.stepped(w)
            h = Int(current.height) >= h ? Int(current.height) : Self.stepped(h)
        }
        pixels = CGSize(width: w, height: h)
        self.offset = offset
        frame = CGRect(x: 0, y: bounds.height - CGFloat(offset + h) / scale,
                       width: CGFloat(w) / scale, height: CGFloat(h) / scale)
    }

    /// Pixels that cover `length` (a sub-pixel remainder counts as a pixel; float noise below 0.001 does not).
    private static func wholePixels(_ length: CGFloat) -> Int { max(Int((length - 0.001).rounded(.up)), 1) }

    private static func stepped(_ pixels: Int) -> Int { (pixels + step - 1) / step * step }
}

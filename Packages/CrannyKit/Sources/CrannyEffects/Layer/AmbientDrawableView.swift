// CrannyEffects/Layer/AmbientDrawableView.swift — the view that owns the ambient light's CAMetalLayer. It is a subview
// of `AmbientMetalNSView`, framed to the drawable (`AmbientDrawableLayout.frame`): only the lit band of the light,
// one drawable pixel per device pixel. It never takes a click and is hidden from VoiceOver.
import AppKit
import CoreGraphics
import QuartzCore

/// The view that owns the `CAMetalLayer`: a subview of `AmbientMetalNSView` framed to its drawable
/// (`AmbientDrawableLayout.frame`). The drawable fills its bounds, one pixel per device pixel.
final class AmbientDrawableView: NSView {
    let metalLayer = CAMetalLayer()

    init() {
        super.init(frame: .zero)
        metalLayer.pixelFormat = AmbientRenderer.pixelFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.presentsWithTransaction = false
        metalLayer.needsDisplayOnBoundsChange = false
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = []
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

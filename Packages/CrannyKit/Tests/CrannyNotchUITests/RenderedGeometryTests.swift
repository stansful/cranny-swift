// The drawn shape equals DESIGN.md §3.3 within 0.5 pt (ARCHITECTURE.md §10.13 acceptance), measured on the
// rasterized canvas — so the canvas really centres, insets and clips the geometry it is given.
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

@MainActor private func scene(_ phase: NotchPhase, metrics: NotchMetrics = PreviewDisplays.notch, style: NoNotchStyle = .floatingIsland,
                              configure: (NotchSceneModel) -> Void = { _ in }) -> (NotchSceneModel, ModuleRegistry) {
    let (model, registry) = previewScene(phase, metrics: metrics, style: style)
    var theme = model.theme
    theme.ambience = .off                                  // measure the shape, not the light inside it
    model.theme = theme
    configure(model)
    return (model, registry)
}

private func near(_ a: CGFloat?, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

/// Width across the ears `y` pt below the screen edge: the concave quarter circles of radius `ear` flare from
/// the body to `body + 2 · ear` at the edge (DESIGN.md §3.2), so a row just under the edge is a little narrower.
private func earWidth(body: CGFloat, ear: CGFloat, y: CGFloat = 0.25) -> CGFloat {
    body + 2 * (ear - (ear * ear - (ear - y) * (ear - y)).squareRoot())
}

@MainActor @Suite("Rendered geometry · 14″ notch (DESIGN.md §3.3)") struct NotchedGeometryTests {
    @Test func closedIsTheCutout() throws {
        let (model, registry) = scene(.idle)
        let probe = try #require(Snapshot.probe(model, registry))
        let extent = try #require(probe.verticalExtent)
        #expect(near(extent.top, 0) && near(extent.bottom, 31.5))
        #expect(near(probe.rowWidth(atPoint: 15), 184))
    }

    @Test func hoverBreath() throws {
        let (model, registry) = scene(.breath)
        let probe = try #require(Snapshot.probe(model, registry))
        #expect(near(probe.verticalExtent?.bottom, 34.5))
        #expect(near(probe.rowWidth(atPoint: 17), 196))
        #expect(near(probe.rowWidth(atPoint: 0.25), earWidth(body: 196, ear: 4), 1))      // ears: outer 204
    }

    /// Outer widths 277 / 301 / 333 / 381 with 6-pt ears.
    @Test(arguments: [(SlotWidth.glyph, 265.0), (.short, 289), (.medium, 321), (.wide, 369)])
    func compactSlots(slot: SlotWidth, body: CGFloat) throws {
        let (model, registry) = scene(.compact) { $0.primarySlot = slot }
        let probe = try #require(Snapshot.probe(model, registry))
        #expect(near(probe.verticalExtent?.bottom, 32))
        #expect(near(probe.rowWidth(atPoint: 16), body))
        #expect(near(probe.rowWidth(atPoint: 0.25), earWidth(body: body, ear: 6), 1))
    }

    @Test(arguments: [(1, 92.0), (2, 144), (4, 248)])
    func peekRows(rows: Int, height: CGFloat) throws {
        let (model, registry) = scene(.peek) { $0.peekRows = Array([ActivityID.nowPlaying, .timerRunning, .meetingSoon, .charging].prefix(rows)) }
        let probe = try #require(Snapshot.probe(model, registry))
        #expect(near(probe.verticalExtent?.bottom, height))
        #expect(near(probe.rowWidth(atPoint: 50), 425))
    }

    @Test func openTenCells() throws {
        let (model, registry) = scene(.open) { $0.openColumns = 10 }
        let probe = try #require(Snapshot.probe(model, registry))
        #expect(near(probe.verticalExtent?.bottom, 170))
        #expect(near(probe.rowWidth(atPoint: 100), 656))
        #expect(near(probe.rowWidth(atPoint: 0.25), earWidth(body: 656, ear: 10), 1))   // outer 676
    }

    @Test func openTwelveCellsAndNotesFocus() throws {
        let (wide, registry) = scene(.open) { $0.openColumns = 12 }
        #expect(near(Snapshot.probe(wide, registry)?.rowWidth(atPoint: 100), 784))
        let (focus, focusRegistry) = scene(.open) { $0.open = OpenState(page: .nook, mode: .focus(.notes), reason: .click) }
        let probe = try #require(Snapshot.probe(focus, focusRegistry))
        #expect(near(probe.verticalExtent?.bottom, 234))
        #expect(near(probe.rowWidth(atPoint: 120), 784))
    }

    /// The Ø 24 bubble sits 6 pt beyond the compact body, centred in the band (its click target is larger).
    @Test func satelliteBubble() throws {
        let (model, registry) = scene(.compact) { $0.satellite = .timerRunning }
        let probe = try #require(Snapshot.probe(model, registry))
        let compact = model.geometry
        let canvas = CGRect(origin: .zero, size: model.layout.canvasSize)
        let bubble = model.layout.satelliteFrame(beside: compact, in: canvas)
        // Its centre column (beyond the body): dark from the bubble's top to its bottom (the glyph sits inside).
        let column = Int(bubble.midX * probe.scale)
        let top = try #require((0..<probe.height).first { probe.isDark(x: column, y: $0) })
        let bottom = try #require((0..<probe.height).last { probe.isDark(x: column, y: $0) })
        #expect(near(CGFloat(bottom - top + 1) / probe.scale, 24, 1))
        #expect(near(CGFloat(top + bottom + 1) / 2 / probe.scale, bubble.midY, 1))
        // Nothing is drawn right of the bubble.
        let band = 0..<Int(model.layout.band * probe.scale)
        let rightmost = try #require(band.compactMap { y in (0..<probe.width).last { probe.isDark(x: $0, y: y) } }.max())
        #expect(near(CGFloat(rightmost + 1) / probe.scale, bubble.maxX, 1))
    }

    @Test func hiddenDrawsNothing() throws {
        let (model, registry) = scene(.hidden)
        #expect(Snapshot.probe(model, registry)?.hasDarkPixels == false)
    }
}

@MainActor @Suite("Rendered geometry · external display, menu bar 30 (DESIGN.md §3.3)") struct ExternalGeometryTests {
    @Test func floatingHandle() throws {
        let (model, registry) = scene(.idle, metrics: PreviewDisplays.external)
        let probe = try #require(Snapshot.probe(model, registry))
        let extent = try #require(probe.verticalExtent)
        #expect(near(extent.top, 4) && near(extent.bottom, 9))
        #expect(near(probe.rowWidth(atPoint: 6.5), 64))
    }

    @Test func floatingCompactHUDPeekOpen() throws {
        let (compact, r1) = scene(.compact, metrics: PreviewDisplays.external) { $0.middleLabelWidth = 0 }
        let p1 = try #require(Snapshot.probe(compact, r1))
        #expect(near(p1.verticalExtent?.top, 3) && near(p1.verticalExtent?.bottom, 27))
        #expect(near(p1.rowWidth(atPoint: 15), 110))

        let (hud, r2) = scene(.compact, metrics: PreviewDisplays.external) { $0.primarySlot = .wide; $0.middleLabelWidth = 0 }
        #expect(near(Snapshot.probe(hud, r2)?.rowWidth(atPoint: 15), 184))

        let (peek, r3) = scene(.peek, metrics: PreviewDisplays.external)
        let p3 = try #require(Snapshot.probe(peek, r3))
        #expect(near(p3.verticalExtent?.bottom, 3 + 84) && near(p3.rowWidth(atPoint: 40), 405))

        let (open, r4) = scene(.open, metrics: PreviewDisplays.external) { $0.openColumns = 10 }
        let p4 = try #require(Snapshot.probe(open, r4))
        #expect(near(p4.verticalExtent?.top, 6) && near(p4.verticalExtent?.bottom, 6 + 168))
        #expect(near(p4.rowWidth(atPoint: 90), 656))
    }

    @Test func attachedCompact() throws {
        let (model, registry) = scene(.compact, metrics: PreviewDisplays.external, style: .attached) { $0.middleLabelWidth = 0 }
        let probe = try #require(Snapshot.probe(model, registry))
        #expect(near(probe.verticalExtent?.top, 0) && near(probe.verticalExtent?.bottom, 30))
        #expect(near(probe.rowWidth(atPoint: 15), 110))
    }

    @Test func middleLabelWidensTheIsland() throws {
        let (model, registry) = scene(.compact, metrics: PreviewDisplays.external) { $0.middleLabelWidth = 80 }
        #expect(near(Snapshot.probe(model, registry)?.rowWidth(atPoint: 15), 80 + 2 * 49))
    }
}


@MainActor @Suite("Rendered geometry · accessibility variants") struct VariantGeometryTests {
    /// Reduce Motion swaps the morph for a cross-fade; Increase Contrast and Reduce Transparency change tokens.
    /// None of them may change a size.
    @Test(arguments: ["reduceMotion", "increaseContrast", "reduceTransparency", "vivid"])
    func variantsKeepTheGeometry(variant: String) throws {
        for (phase, height, width, row) in [(NotchPhase.open, 170.0, 656.0, 100.0), (.compact, 32, 289, 16), (.peek, 92, 425, 50)] {
            let (model, registry) = scene(phase) { model in
                var theme = model.theme
                switch variant {
                case "reduceMotion": theme.reduceMotion = true
                case "increaseContrast": theme.increaseContrast = true
                case "reduceTransparency": theme.reduceTransparency = true
                default: theme.ambience = .vivid
                }
                model.theme = theme
                model.openColumns = 10
            }
            let probe = try #require(Snapshot.probe(model, registry))
            // Increase Contrast strokes a 45 % keyline ON the outline: its inner pixel is lighter than the probe's
            // dark threshold, so the measured width can lose one device pixel per side.
            let tolerance: CGFloat = variant == "increaseContrast" ? 1 : 0.5
            #expect(near(probe.verticalExtent?.bottom, height, tolerance), "\(variant) \(phase)")
            #expect(near(probe.rowWidth(atPoint: row), width, tolerance), "\(variant) \(phase)")
        }
    }
}

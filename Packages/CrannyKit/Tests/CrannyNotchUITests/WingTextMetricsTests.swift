// Band text against the compact wings (design ruling E4, ARCHITECTURE.md §10.20 #26): the helper's wing is the one
// `CompactSlots` lays out, its widths are what SwiftUI draws, and a fit holds at every notch unit, which a character
// count cannot promise. The flash labels themselves are rendered by the shell's `FlashLabelFitTests`.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

/// The units of whole-point band heights (rendering every unit the helper checks would take too long).
private let bandUnits: [CGFloat] = [0.8] + (26...40).map { CGFloat($0) / 32 }

@MainActor @Suite("Wing text (ruling E4)") struct WingTextMetricsTests {
    /// A wing's content as `CompactSlots` proposes it, read from inside the trailing wing.
    private final class Probe {
        var width: CGFloat = -1
    }

    @Test func theUnitsCoverEveryBandHeight() {
        let units = WingTextMetrics.notchUnits
        #expect(units.first == 0.8 && units.last == 1.25 && units.contains(1) && units == units.sorted())
        #expect(zip(units, units.dropFirst()).allSatisfy { $1 - $0 <= 1.0 / 1024 + 1e-9 })     // no gap wider than 1/1024
        // `NotchMetrics.unit` of every whole-point band height a display reports is one of them.
        for band in stride(from: CGFloat(20), through: 44, by: 1) {
            let unit = NotchMetrics(hasNotch: true, notchWidth: 185, bandHeight: band, screenWidth: 1512).unit
            #expect(units.contains(unit), "band \(band): unit \(unit)")
        }
    }

    @Test(arguments: [SlotWidth.glyph, .short, .medium, .wide])
    func theWingIsTheOneCompactSlotsLaysOut(slot: SlotWidth) {
        for unit in bandUnits {
            let layout = NotchLayout(metrics: NotchMetrics(hasNotch: true, notchWidth: 185, bandHeight: 32 * unit,
                                                           screenWidth: 1512))
            let probe = Probe()
            let slots = CompactSlots(layout: layout, slot: slot, leading: { EmptyView() }, center: { EmptyView() },
                                     trailing: {
                                         GeometryReader { proxy in
                                             let _ = probe.width = proxy.size.width
                                             Color.clear
                                         }
                                     })
            var theme = CrannyTheme()
            theme.notchUnit = layout.u
            let host = NSHostingView(rootView: slots.crannyThemeRoot(theme))
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            #expect(abs(probe.width - WingTextMetrics.contentWidth(slot, notchUnit: layout.u)) < 0.01,
                    "\(slot) at \(layout.u)u: CompactSlots \(probe.width), helper \(WingTextMetrics.contentWidth(slot, notchUnit: layout.u))")
        }
        #expect(WingTextMetrics.contentWidth(.wide, notchUnit: 1) == 72 && WingTextMetrics.contentWidth(.medium, notchUnit: 1) == 48)
    }

    /// The helper measures what `crannyFont(.compact)` draws (SF Rounded semibold, monospaced digits), rounded up.
    @Test(arguments: ["Hi", "Done", "Copied", "Resumed", "Готово", "Активны", "4:59", "Скопировано"])
    func measuresTheDrawnFont(text: String) {
        for unit in bandUnits {
            var theme = CrannyTheme()
            theme.notchUnit = unit
            let drawn = NSHostingView(rootView: Text(verbatim: text).crannyFont(.compact).fixedSize().crannyThemeRoot(theme))
                .fittingSize.width
            let measured = WingTextMetrics.width(of: text, notchUnit: unit)
            #expect(measured >= drawn - 0.01 && measured - drawn < 1.01, "\(text) at \(unit)u: measured \(measured), drawn \(drawn)")
        }
    }

    /// The narrowest slot that holds the text at every unit; none for a text no wing holds. «Скопировано» (11 letters)
    /// is wider than the wide wing although it has fewer than 12 characters, and "Copied" (6) needs the wide wing at
    /// some units where «Готово» (6) still fits the medium one.
    @Test func picksTheNarrowestSlotThatFitsEverywhere() {
        let slots: [SlotWidth] = [.wide, .medium]                      // order does not matter
        #expect(WingTextMetrics.narrowestSlot(for: "Hi", among: slots) == .medium)
        #expect(WingTextMetrics.narrowestSlot(for: "Скопировано", among: slots) == nil)
        #expect(!WingTextMetrics.fits("Path copied", slot: .wide))
        #expect(WingTextMetrics.fits("Resumed", slot: .wide) && !WingTextMetrics.fits("Resumed", slot: .medium))
        #expect(WingTextMetrics.narrowestSlot(for: "", among: slots) == .medium)
        for text in ["Copied", "Готово", "Paused", "Пауза", "Ошибка"] {
            let slot = WingTextMetrics.narrowestSlot(for: text, among: slots)
            let fitsMediumEverywhere = WingTextMetrics.notchUnits.allSatisfy {
                WingTextMetrics.width(of: text, notchUnit: $0) <= WingTextMetrics.contentWidth(.medium, notchUnit: $0)
            }
            #expect(slot == (fitsMediumEverywhere ? .medium : .wide), "\(text)")
        }
    }
}

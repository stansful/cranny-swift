// Each activity's slot (DESIGN.md §3.3, §9.2) is the narrowest class whose content budget holds its band values.
// The values are measured at the reference notch unit, on the floating island (u = 0.94) and with "Larger Text"
// (u = 1.156), rendered off screen and never shown. A plain level ("82%") fits `short`; the Bluetooth device's
// ring + level does not, so it takes `medium`.
import CrannyCore
import SwiftUI
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct SlotFitTests {
    static let units: [CGFloat] = [1, 0.94, 1.156]
    /// Both ends of each digit count. Digits are monospaced, so the width depends only on how many there are.
    static let levels = [0, 5, 9, 10, 45, 84, 99, 100]
    static let classes: [SlotWidth] = [.glyph, .short, .medium, .wide]

    /// One side's content budget: the slot minus the 12u outer margin and the 8u gap to the camera (§3.3).
    static func budget(_ slot: SlotWidth, unit: CGFloat) -> CGFloat { slot.points(unit: unit) - 20 * unit }

    /// The view's ideal width, to a quarter point.
    private func width(_ view: some View, unit: CGFloat) -> CGFloat {
        var theme = CrannyTheme()
        theme.notchUnit = unit
        let renderer = ImageRenderer(content: view.environment(\.cranny, theme))
        renderer.scale = 4
        guard let image = renderer.cgImage else {
            Issue.record("did not render at u = \(unit)")
            return .infinity
        }
        return CGFloat(image.width) / 4
    }

    /// The narrowest a level can be drawn without truncation: `BandLevel`'s last variant, its text at the minimum
    /// scale.
    private func narrowestLevel(_ percent: Int, ring: Bool, unit: CGFloat) -> CGFloat {
        let text = width(BandLevelForm(percent: percent, variant: .tight), unit: unit)
        let whole = width(BandLevelForm(percent: percent, variant: .tight, showsRing: ring), unit: unit)
        return whole - text * (1 - BandLevelForm.minimumScale)
    }

    private func widestLevel(ring: Bool, unit: CGFloat) -> CGFloat {
        Self.levels.map { narrowestLevel($0, ring: ring, unit: unit) }.max() ?? .infinity
    }

    private func narrowestSlot(holding content: CGFloat, unit: CGFloat) -> SlotWidth? {
        Self.classes.first { content <= Self.budget($0, unit: unit) }
    }

    @Test func aPlainLevelFitsShortButRingAndLevelNeedMedium() {
        for unit in Self.units {
            let plain = widestLevel(ring: false, unit: unit)
            let ringed = widestLevel(ring: true, unit: unit)
            #expect(narrowestSlot(holding: plain, unit: unit) == .short, "u = \(unit): \(plain) pt")
            #expect(narrowestSlot(holding: ringed, unit: unit) == .medium, "u = \(unit): \(ringed) pt")
            // With the ring, even a two-digit level at its smallest overflows `short`.
            let typical = narrowestLevel(84, ring: true, unit: unit)
            #expect(typical > Self.budget(.short, unit: unit), "u = \(unit): \(typical) pt")
        }
    }

    @Test func eachActivityTakesTheNarrowestSlotThatHoldsBothSides() {
        let charging = [ChargingContent.Phase.charging, .charged, .notCharging, .onBattery].map { ChargingActivity.sample($0) }
        let lowBattery = [LowBatteryContent.Level.warning, .critical].map { LowBatteryActivity.sample($0) }
        let bluetooth = BluetoothActivity.SampleDevice.allCases.map { BluetoothActivity.sample($0) }
        for unit in Self.units {
            let chargingSide = max(charging.map { width($0.compactLeading(), unit: unit) }.max() ?? .infinity,
                                   widestLevel(ring: false, unit: unit))
            #expect(charging[0].slot == narrowestSlot(holding: chargingSide, unit: unit), "u = \(unit): \(chargingSide) pt")

            let lowBatterySide = max(lowBattery.map { width($0.compactLeading(), unit: unit) }.max() ?? .infinity,
                                     widestLevel(ring: false, unit: unit))
            #expect(lowBattery[0].slot == narrowestSlot(holding: lowBatterySide, unit: unit), "u = \(unit): \(lowBatterySide) pt")

            // The level-unknown ✓ is one glyph; the ring + level is the widest thing the device shows.
            let bluetoothSide = max(bluetooth.map { width($0.compactLeading(), unit: unit) }.max() ?? .infinity,
                                    width(BluetoothActivity.sample(.headphones).compactTrailing(), unit: unit),
                                    widestLevel(ring: true, unit: unit))
            #expect(bluetooth[0].slot == narrowestSlot(holding: bluetoothSide, unit: unit), "u = \(unit): \(bluetoothSide) pt")
        }
    }
}

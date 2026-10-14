// The three LiveActivity objects: presentation lifecycle, revisions, delight, VoiceOver strings and actions.
import CrannyCore
import Foundation
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct ActivityTests {
    @Test func chargingLifecycle() {
        let activity = ChargingActivity()
        #expect(!activity.isActive && activity.delight == nil && activity.palette == nil)
        let now = Date()
        activity.present(ChargingContent(phase: .charging, percent: 82, minutes: 80), for: 2.6, now: now)
        #expect(activity.isActive && activity.revision == 1)
        #expect(activity.expiresAt == now.addingTimeInterval(2.6))
        #expect(activity.slot == .short)
        activity.update(ChargingContent(phase: .charging, percent: 83, minutes: 78))
        #expect(activity.revision == 1 && activity.content?.percent == 83)
        activity.end()
        #expect(!activity.isActive && activity.expiresAt == nil)
        activity.update(ChargingContent(phase: .charging, percent: 90))      // ignored while hidden
        #expect(!activity.isActive)
    }

    @Test func chargingCopyCoversEveryPhase() {
        for phase in [ChargingContent.Phase.charging, .charged, .notCharging, .onBattery] {
            let content = ChargingContent(phase: phase, percent: 50, minutes: 75)
            #expect(!ChargingActivity.title(content).isEmpty)
            #expect(ChargingActivity.detail(content)?.isEmpty == false)
        }
        // Estimates still being calculated read as such, never as "0 min".
        let estimating = ChargingContent(phase: .charging, percent: 50, minutes: nil)
        #expect(ChargingActivity.detail(estimating) == SystemCopy.calculating)
        let activity = ChargingActivity.sample()
        #expect(activity.accessibilityValue?.contains("82") == true)
    }

    @Test func pluggedInNotChargingDiffersByShapeNotOnlyColour() {
        // DESIGN.md §16 (Differentiate Without Color): the band glyph itself tells charging from not charging.
        #expect(ChargingContent.Phase.charging.bandSymbol == "bolt.fill")
        #expect(ChargingContent.Phase.charged.bandSymbol == "bolt.fill")
        #expect(ChargingContent.Phase.notCharging.bandSymbol == "powerplug.fill")
    }

    @Test func lowBatteryActionOpensBatterySettings() throws {
        var opened = 0
        let activity = LowBatteryActivity { opened += 1 }
        activity.alert(LowBatteryContent(level: .critical, percent: 9, minutesToEmpty: 20), for: nil)
        #expect(activity.isPersistent)
        #expect(activity.palette == .lowBattery)
        let action = try #require(activity.actions.first)
        #expect(!action.title.isEmpty)
        action.perform()
        #expect(opened == 1)
        #expect(activity.accessibilityValue?.contains("9") == true)
    }

    @Test func lowBatterySubtitleNamesLowPowerMode() {
        let content = LowBatteryContent(level: .warning, percent: 20, minutesToEmpty: 60, isLowPowerMode: true)
        #expect(LowBatteryActivity.subtitle(content).contains(SystemCopy.lowPowerModeIsOn))
        #expect(LowBatteryContent.Level.critical.symbol == "battery.0percent")
        #expect(LowBatteryContent.Level.warning.symbol == "battery.25percent")
    }

    @Test func lowBatteryColourAndGlyphFollowTheWarningsRole() {
        // DESIGN.md §2.1 / §9.2: `warning` + battery.25percent at the first warning, `danger` + battery.0percent at
        // the final one, in every palette; the glyphs differ too, so colour is never the only cue (§16).
        for variant in CrannyPalette.Variant.allCases {
            let palette = CrannyPalette.make(variant)
            #expect(LowBatteryContent.Level.warning.color(palette) == palette.warning, "\(variant)")
            #expect(LowBatteryContent.Level.critical.color(palette) == palette.danger, "\(variant)")
        }
        #expect(LowBatteryContent.Level.warning.symbol != LowBatteryContent.Level.critical.symbol)
        #expect(LowBatteryActivity(openBatterySettings: {}).slot == .short)
    }

    @Test func bluetoothUpdatesOnlyTheDeviceOnScreen() {
        let activity = BluetoothActivity()
        let airPods = BluetoothActivity.SampleDevice.airPods.accessory
        activity.present(airPods, for: 2.6)
        #expect(activity.slot == .medium)
        var other = BluetoothActivity.SampleDevice.trackpad.accessory
        activity.update(other)
        #expect(activity.accessory?.id == airPods.id)
        var drained = airPods
        drained.batteries.left = BatteryLevel(percent: 50)
        activity.update(drained)
        #expect(activity.accessory?.batteries.left?.percent == 50)
        #expect(activity.revision == 1)
        other.batteries = .unknown
        activity.present(other, for: nil)
        #expect(activity.revision == 2)
        #expect(activity.accessibilityValue == SystemCopy.batteryUnknown)
    }

    @Test func bluetoothGlyphBouncesOncePerConnection() {
        let activity = BluetoothActivity()
        activity.present(BluetoothActivity.SampleDevice.airPods.accessory, for: 2.6)
        #expect(activity.claimBounce(for: activity.revision))               // the compact glyph appears: bounce
        #expect(!activity.claimBounce(for: activity.revision))              // the peek re-creates it: no replay
        activity.end()
        activity.present(BluetoothActivity.SampleDevice.trackpad.accessory, for: 2.6)
        #expect(activity.claimBounce(for: activity.revision))               // the next connection bounces again
        #expect(!activity.claimBounce(for: activity.revision - 1))          // a stale view never does
    }

    @Test func bluetoothVoiceOverListsTheParts() {
        let activity = BluetoothActivity.sample(.airPods)
        let value = activity.accessibilityValue ?? ""
        #expect(value.contains("84") && value.contains("82") && value.contains("45"))
        #expect(activity.accessibilityLabel.contains("AirPods Pro"))
    }

    @Test func formattingUsesFormatStyles() {
        #expect(SystemCopy.percent(82).contains("82"))
        #expect(SystemCopy.duration(minutes: 80).contains("20"))
        #expect(SystemCopy.duration(minutes: 0).contains("1"))               // never "0 min"
    }
}

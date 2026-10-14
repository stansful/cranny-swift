import CrannyCore
import Foundation
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct SystemActivitiesModuleTests {
    @Test func registersWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(SystemActivitiesModule.self)
        #expect(SystemActivitiesModule.id == .system)
        #expect(registry.registeringModule == nil)
        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
    }

    @Test func contributesThreeAlertActivitiesWithSamples() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(SystemActivitiesModule.self)
        #expect(registry.activities.map(\.id) == [.charging, .lowBattery, .bluetoothDevice])
        for registered in registry.activities {
            #expect(registered.kind.module == .system)
            #expect(registered.kind.defaultPriority == .alert)
            #expect(registered.kind.isEnabledByDefault)
            #expect(!registered.kind.title.isEmpty)
            #expect(!registered.activity.isActive)        // nothing shows before launch
            let sample = try #require(registered.makeSample?())
            #expect(sample.isActive)
            #expect(sample.id == registered.id)
            #expect(sample.expiresAt == nil)              // samples never expire
            #expect(!sample.accessibilityLabel.isEmpty)
        }
        // Option rows under Low battery and Bluetooth devices (there is no System pane).
        #expect(registry.activity(.charging)?.makeOptions == nil)
        #expect(registry.activity(.lowBattery)?.makeOptions != nil)
        #expect(registry.activity(.bluetoothDevice)?.makeOptions != nil)
        #expect(registry.settingsPages.isEmpty)
        #expect(registry.widgets.isEmpty)
    }

    @Test func declaresTheOptionalBluetoothPermission() {
        let registry = ModuleRegistry(services: .preview())
        registry.register(SystemActivitiesModule.self)
        #expect(registry.permissionUses.map(\.kind) == [.bluetooth])
        #expect(registry.permissionUses.first?.module == .system)
        #expect(registry.permissionUses.first?.reason.isEmpty == false)
        #expect(registry.permissionUses.first?.optIn == SystemSettings.showsAllBluetoothDevices)   // onboarding asks only while on
    }

    @Test func settingsDefaultsMatchTheArchitecture() {
        #expect(SystemSettings.lowBatteryThresholds.id == "system.lowBatteryThresholds")
        #expect(SystemSettings.lowBatteryThresholds.defaultValue == [20, 10])
        #expect(SystemSettings.showsAllBluetoothDevices.id == "system.showsAllBluetoothDevices")
        #expect(SystemSettings.showsAllBluetoothDevices.defaultValue == false)
    }

    @Test func batterySettingsLinkParses() {
        #expect(SystemActivitiesModule.batterySettingsURL?.scheme == "x-apple.systempreferences")
    }
}

// Registration contributes the activity (+ sample, + options row), Settings ▸ HUD and the Accessibility use,
// without side effects; the settings keys keep their documented defaults.
import CrannyCore
import Foundation
import Testing
@testable import CrannyHUD

@MainActor @Suite struct HUDModuleTests {
    @Test func registersWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(HUDModule.self)
        #expect(HUDModule.id == .hud)
        #expect(registry.registeringModule == nil)
        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
    }

    @Test func contributesTheHUDActivity() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(HUDModule.self)
        let registered = try #require(registry.activity(.hud))
        #expect(registered.kind.module == .hud)
        #expect(registered.kind.defaultPriority == .hud)
        #expect(!registered.kind.canPeekOnChange)
        #expect(registered.activity.priority == .hud)
        #expect(registered.activity.slot == .wide)
        #expect(!registered.activity.isActive)             // nothing shows until a key is pressed
        #expect(registered.makeOptions != nil)
        let sample = try #require(registered.makeSample?())
        #expect(sample.isActive)
        #expect(sample.expiresAt == nil)                   // the Settings stage keeps it
        #expect(sample.actions.isEmpty)                    // samples never touch a device
        #expect(sample.accessibilityValue?.contains("62") == true)
    }

    @Test func contributesSettingsHUD() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(HUDModule.self)
        let page = try #require(registry.settingsPages.first { $0.id == .hud })
        #expect(page.group == .notch)
        #expect(page.tint == .teal)
        #expect(page.symbol == "speaker.wave.2.fill")
        #expect(page.previewState == .hud)
        #expect(page.namespaces == [.hud])                 // "Reset HUD…" resets the module's keys
        #expect(page.keywords.contains(HUDKind.volume.title))
        #expect(page.keywords.contains(PermissionKind.accessibility.title))
        #expect(page.keywords.count >= 12)
        #expect(page.keywords.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) })
    }

    @Test func declaresAccessibility() {
        let registry = ModuleRegistry(services: .preview())
        registry.register(HUDModule.self)
        let uses = registry.permissionUses.filter { $0.module == .hud }
        #expect(uses.map(\.kind) == [.accessibility])
        #expect(uses.allSatisfy { !$0.reason.isEmpty })
    }

    @Test func settingsDefaults() {
        let settings = CrannyServices.preview().settings
        #expect(settings[HUDSettings.replaceSystemHUD] == false)   // never asks for Accessibility by itself
        #expect(settings[HUDSettings.volume])
        #expect(!settings[HUDSettings.brightness])                 // until the hardware checklist (§10.10)
        #expect(!settings[HUDSettings.keyboardBacklight])          // until the hardware checklist (unverified write)
        #expect(settings[HUDSettings.colors] == .mono)
        #expect(!settings[HUDSettings.showsValue])
        #expect(settings[HUDSettings.showsOutputDevice])
        #expect(settings[HUDSettings.duration] == 1.5)
        let ids = [HUDSettings.replaceSystemHUD.id, HUDSettings.volume.id, HUDSettings.brightness.id,
                   HUDSettings.keyboardBacklight.id, HUDSettings.showsValue.id, HUDSettings.showsOutputDevice.id]
        #expect(ids == ["hud.replaceSystemHUD", "hud.volume", "hud.brightness", "hud.keyboardBacklight", "hud.showsValue",
                        "hud.showsOutputDevice"])
        #expect(HUDSettings.colors.id == "hud.colors")
        #expect(HUDSettings.duration.id == "hud.duration")
    }

    @Test func durationIsClamped() {
        #expect(HUDSettings.clampedDuration(0.1) == 0.8)
        #expect(HUDSettings.clampedDuration(9) == 3)
        #expect(HUDSettings.clampedDuration(1.5) == 1.5)
    }

    @Test func durationText() {
        #expect(HUDSettingsPane.durationText(1.5).contains("1"))
        #expect(HUDSettingsPane.durationText(1.5).contains("5"))
    }

    @Test func colorsPersistAsStrings() throws {
        let data = try JSONEncoder().encode(HUDColors.semantic)
        #expect(String(data: data, encoding: .utf8) == "\"semantic\"")
    }
}

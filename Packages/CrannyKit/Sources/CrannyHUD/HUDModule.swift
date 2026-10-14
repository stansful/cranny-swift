// CrannyHUD/HUDModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §7.1, §10.10).
// `register(in:)` only creates objects and contributes: the HUD activity (+ sample), Settings ▸ HUD and the
// Accessibility declaration. Nothing touches a device, installs a tap or asks for a permission until
// `onLaunch`, and even then only with "Replace the system HUD" on and Accessibility already granted.
import CrannyCore
import Foundation
import SwiftUI

/// HUD: volume, brightness and keyboard backlight levels in the notch, replacing the system HUD
/// (never alongside it, ARCHITECTURE.md D10). Registered by the shell's `CompositionRoot`.
public enum HUDModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.hud`).
    public static var id: ModuleID { .hud }

    /// Registers the HUD activity, Settings ▸ HUD and the Accessibility use; work starts in `onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let activity = HUDActivity(settings: services.settings)
        let controller = HUDController(services: services, activity: activity, hardware: .live)

        registry.add(activity: activity, kind: HUDActivity.kind,
                     sample: { HUDActivity.sample(settings: services.settings) },
                     options: { AnyView(HUDActivityOptions(app: services.app)) })
        registry.add(settingsPage: settingsPage(services: services, controller: controller))
        registry.declare(.accessibility, reason: String(
            localized: "Replace the system volume and brightness HUD. Cranny uses it only to handle those keys.",
            bundle: .module, comment: "Permissions pane and onboarding: why the HUD needs Accessibility"))

        registry.onLaunch {
            controller.start()
            #if DEBUG
            if let display = HUDQAHook.display(arguments: CommandLine.arguments) {
                try? await Task.sleep(for: .milliseconds(600))          // let the panel appear first
                controller.presentForQA(display)
            }
            #endif
        }
        registry.onTerminate { controller.stop() }
    }

    /// Settings ▸ HUD: group Notch, teal, after Live Activities (DESIGN.md §11.1); the stage shows the HUD.
    static func settingsPage(services: CrannyServices, controller: HUDController?) -> SettingsPage {
        SettingsPage(id: .hud,
                     title: String(localized: "HUD", bundle: .module, comment: "Settings sidebar: pane name (the volume and brightness heads-up display)"),
                     symbol: "speaker.wave.2.fill", tint: .teal, group: .notch, order: 2,
                     keywords: searchKeywords, previewState: .hud) {
            AnyView(HUDSettingsPane(settings: services.settings, permissions: services.permissions, app: services.app,
                                    controller: controller))
        }
    }

    /// The pane's row labels plus a few synonyms: a module pane is opaque to Settings search (§3.7).
    static var searchKeywords: [String] {
        let rows = [HUDKind.volume.title, HUDKind.brightness.title, HUDKind.keyboardBacklight.title,
                    PermissionKind.accessibility.title,
                    String(localized: "Replace the system HUD", bundle: .module, comment: "Settings ▸ HUD: main toggle"),
                    String(localized: "Keyboard backlight", bundle: .module, comment: "Settings ▸ HUD: toggle for the keyboard backlight keys"),
                    String(localized: "Colors", bundle: .module, comment: "Settings ▸ HUD: picker for the level bar's colour"),
                    String(localized: "Show value", bundle: .module, comment: "Settings ▸ HUD: toggle that shows the level as a number"),
                    String(localized: "Show output device", bundle: .module, comment: "Settings ▸ HUD: toggle"),
                    String(localized: "Duration", bundle: .module, comment: "Settings ▸ HUD: how long the HUD stays")]
        let synonyms = String(localized: "sound, mute, speaker, display, keys, OSD", bundle: .module,
                              comment: "Settings search: extra comma-separated search terms for the HUD pane (translate each term)")
        return rows + synonyms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// The HUD's row in Settings ▸ Live Activities: its options live in their own pane.
struct HUDActivityOptions: View {
    let app: any AppControl

    var body: some View {
        Button {
            app.openSettings(.hud)
        } label: {
            Text("HUD Settings…", bundle: .module, comment: "Live Activities pane: button under the HUD row that opens Settings ▸ HUD")
        }
    }
}

#Preview("Live Activities option row") {
    HUDActivityOptions(app: PreviewAppControl())
        .padding()
}

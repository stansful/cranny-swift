// CrannySettingsUI/Panes/AppearancePane.swift — Settings ▸ Appearance (DESIGN.md §11.1): accent, text size, motion,
// the light layer (DESIGN.md §5.1), surfaces (translucency, glass island, buttons, widgets, density, padding), Notch fit
// and the style on displays without a notch. The stage above shows the open Nook, so every change is visible.
import CrannyCore
import Foundation
import SwiftUI

struct AppearancePane: View {
    let registry: ModuleRegistry
    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        let ambience = settings[CoreSettings.ambience]
        SettingsForm(.appearance) {
            Section {
                AccentPicker(settings: settings)
                ChoiceRow(AppearanceRows.textSize, settings: settings, key: CoreSettings.textSize, choices: [
                    Choice(value: .small, label: String(localized: "Small", bundle: .module, comment: "Settings ▸ Appearance ▸ Text size: option")),
                    Choice(value: .standard, label: String(localized: "Medium", bundle: .module, comment: "Settings ▸ Appearance ▸ Text size: option (the default)")),
                    Choice(value: .large, label: String(localized: "Large", bundle: .module, comment: "Settings ▸ Appearance ▸ Text size: option")),
                    Choice(value: .extraLarge, label: String(localized: "Extra large", bundle: .module, comment: "Settings ▸ Appearance ▸ Text size: option")),
                ], footnote: String(localized: "Larger text also makes the widgets larger, so nothing is cut off.", bundle: .module,
                                    comment: "Settings ▸ Appearance: footnote of Text size"))
                ChoiceRow(AppearanceRows.motion, settings: settings, key: CoreSettings.motion, choices: [
                    Choice(value: .calm, label: String(localized: "Calm", bundle: .module, comment: "Settings ▸ Appearance ▸ Motion: option (no bounce)")),
                    Choice(value: .standard, label: String(localized: "Standard", bundle: .module, comment: "Settings ▸ Appearance: the default option of a picker")),
                    Choice(value: .lively, label: String(localized: "Lively", bundle: .module, comment: "Settings ▸ Appearance ▸ Motion: option (more bounce)")),
                    Choice(value: .instant, label: String(localized: "Instant", bundle: .module, comment: "Settings: option with no delay or no animation (Hover delay, Motion)")),
                ], footnote: String(localized: "With Reduce Motion turned on in System Settings, shapes fade instead of moving.", bundle: .module,
                                    comment: "Settings ▸ Appearance: footnote of Motion"))
                ToggleRow(info: AppearanceRows.typingEffect, settings: settings, key: CoreSettings.typingEffect,
                          footnote: String(localized: "New characters in notes appear in the accent colour, then settle.", bundle: .module,
                                           comment: "Settings ▸ Appearance: footnote of Typing effect"))
            }
            Section {
                ChoiceRow(AppearanceRows.ambience, settings: settings, key: CoreSettings.ambience, choices: [
                    Choice(value: .off, label: String(localized: "Off", bundle: .module, comment: "Settings: option that turns something off (ambient light, a display style, a shortcut)")),
                    Choice(value: .subtle, label: String(localized: "Subtle", bundle: .module, comment: "Settings ▸ Appearance ▸ Ambient light: option")),
                    Choice(value: .vivid, label: String(localized: "Vivid", bundle: .module, comment: "Settings ▸ Appearance ▸ Ambient light: option")),
                ], footnote: String(localized: "Light in the colour of what is playing or happening, only while Cranny is open.", bundle: .module,
                                    comment: "Settings ▸ Appearance: footnote of Ambient light"))
                ChoiceRow(AppearanceRows.effect, settings: settings, key: CoreSettings.effect, choices: [
                    Choice(value: .aurora, label: String(localized: "Aurora", bundle: .module, comment: "Settings ▸ Appearance ▸ Effect: option")),
                    Choice(value: .motes, label: String(localized: "Motes", bundle: .module, comment: "Settings ▸ Appearance ▸ Effect: option (slow rising specks)")),
                    Choice(value: .tide, label: String(localized: "Tide", bundle: .module, comment: "Settings ▸ Appearance ▸ Effect: option (wave lines)")),
                ], footnote: String(localized: "In Low Power Mode the light becomes a still glow.", bundle: .module,
                                    comment: "Settings ▸ Appearance: footnote of Effect"))
                    .disabled(ambience == .off)
                ToggleRow(info: AppearanceRows.albumGlow, settings: settings, key: CoreSettings.albumGlow,
                          footnote: String(localized: "A soft halo in the album's colour behind the artwork.", bundle: .module,
                                           comment: "Settings ▸ Appearance: footnote of Album glow"))
                ToggleRow(info: AppearanceRows.underglow, settings: settings, key: CoreSettings.underglow,
                          footnote: String(localized: "With Vivid light, a glow spills onto the desktop under Cranny.", bundle: .module,
                                           comment: "Settings ▸ Appearance: footnote of Underglow"))
                    .disabled(ambience != .vivid)
                ToggleRow(info: AppearanceRows.progressRim, settings: settings, key: CoreSettings.progressRim,
                          footnote: String(localized: "Playback progress as a thin line along the lower edge of the notch.", bundle: .module,
                                           comment: "Settings ▸ Appearance: footnote of Progress rim"))
            } header: {
                Text("Light", bundle: .module, comment: "Settings ▸ Appearance: section header (the ambient light layer)")
            }
            SurfaceSection(settings: settings)
            NotchFitControls(settings: settings, notch: registry.services.notch, haptics: registry.services.haptics)
            Section {
                ChoiceRow(AppearanceRows.noNotchStyle, settings: settings, key: CoreSettings.noNotchStyle, choices: [
                    Choice(value: .floatingIsland, label: String(localized: "Floating island", bundle: .module, comment: "Settings: no-notch style")),
                    Choice(value: .attached, label: String(localized: "Attached", bundle: .module, comment: "Settings: no-notch style")),
                    Choice(value: .off, label: String(localized: "Off", bundle: .module, comment: "Settings: option that turns something off (ambient light, a display style, a shortcut)")),
                ], footnote: String(localized: "A floating island does not pretend to be hardware. Each display can override this in General.",
                                    bundle: .module, comment: "Settings ▸ Appearance: footnote of On displays without a notch"))
                ChoiceRow(AppearanceRows.handle, settings: settings, key: CoreSettings.handleVisibility, choices: [
                    Choice(value: .visible, label: String(localized: "Visible", bundle: .module, comment: "Settings ▸ Appearance ▸ Handle: option")),
                    Choice(value: .hiddenUntilHover, label: String(localized: "Hidden until hover", bundle: .module, comment: "Settings ▸ Appearance ▸ Handle: option")),
                ])
                    .disabled(settings[CoreSettings.noNotchStyle] == .off)
            } header: {
                Text("Displays without a notch", bundle: .module, comment: "Settings ▸ Appearance: section header")
            }
        }
    }
}

/// Translucency, glass island, buttons, widgets, density and panel padding.
private struct SurfaceSection: View {
    let settings: SettingsStore

    var body: some View {
        Section {
            ToggleRow(info: AppearanceRows.translucent, settings: settings, key: CoreSettings.translucentBackground,
                      footnote: String(localized: "The open panel lets the desktop show through below the menu bar. Off with Reduce Transparency.",
                                       bundle: .module, comment: "Settings ▸ Appearance: footnote of Translucent background"))
            if AppearanceRows.hasGlassIsland {
                ToggleRow(info: AppearanceRows.glassIsland, settings: settings, key: CoreSettings.glassIsland,
                          footnote: String(localized: "Liquid Glass for the floating island on displays without a notch.", bundle: .module,
                                           comment: "Settings ▸ Appearance: footnote of Glass island"))
            }
            ChoiceRow(AppearanceRows.buttons, settings: settings, key: CoreSettings.buttonShape, choices: [
                Choice(value: .capsule, label: String(localized: "Capsule", bundle: .module, comment: "Settings ▸ Appearance ▸ Buttons: option")),
                Choice(value: .rounded, label: String(localized: "Rounded", bundle: .module, comment: "Settings ▸ Appearance ▸ Buttons: option")),
            ])
            ChoiceRow(AppearanceRows.widgets, settings: settings, key: CoreSettings.widgetStyle, choices: [
                Choice(value: .cards, label: String(localized: "Cards", bundle: .module, comment: "Settings ▸ Appearance ▸ Widgets: option")),
                Choice(value: .flat, label: String(localized: "Flat with dividers", bundle: .module, comment: "Settings ▸ Appearance ▸ Widgets: option")),
            ])
            ChoiceRow(AppearanceRows.density, settings: settings, key: CoreSettings.density, choices: [
                Choice(value: .compact, label: String(localized: "Compact", bundle: .module, comment: "Settings ▸ Appearance ▸ Density: option")),
                Choice(value: .standard, label: String(localized: "Standard", bundle: .module, comment: "Settings ▸ Appearance: the default option of a picker")),
                Choice(value: .roomy, label: String(localized: "Roomy", bundle: .module, comment: "Settings ▸ Appearance ▸ Density: option")),
            ])
            SliderRow(AppearanceRows.panelPadding, settings: settings, key: CoreSettings.panelPaddingTune, range: -4...4, step: 1,
                      footnote: String(localized: "Fine-tunes the space around the widgets. Corners stay concentric.", bundle: .module,
                                       comment: "Settings ▸ Appearance: footnote of Panel padding")) { SettingsFormat.points($0) }
        } header: {
            Text("Panel", bundle: .module, comment: "Settings ▸ Appearance: section header (the open panel's surface)")
        }
    }
}

#Preview("Appearance") {
    AppearancePane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 900)
}

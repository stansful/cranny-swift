// CrannySettingsUI/Stage/StageController+Appearance.swift — the stage's display, theme, layout, wallpaper and samples.
// Theme and layout come from `ThemeResolver` with the same inputs the shell's panel uses (one implementation,
// three callers, ARCHITECTURE D21), measured on the display the stage imitates: the built-in display when there
// is one, else the main display.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// Everything the stage's look depends on; observed as one value.
struct StageAppearance: Equatable {
    var layout: NotchLayout
    var theme: CrannyTheme
    var isOff: Bool
}

/// The settings that change which samples the stage shows and the open page's width.
struct StageCastInputs: Equatable {
    var preferences: [ActivityID: ActivityPreference]
    var order: [ActivityID]
    var satellite: Bool
    var pages: [NookPage]
}

extension StageController {
    /// The stage's look from the live settings (reads are tracked by `observe`).
    func appearanceInputs() -> StageAppearance {
        let settings = registry.services.settings
        let metrics = currentScreen.map(NotchMetrics.measure) ?? .reference
        let key = currentScreen.flatMap(ThemeResolver.displayKey)
        let preferences = key.flatMap { settings[CoreSettings.perDisplay][$0] }
        let noNotchStyle = settings[CoreSettings.noNotchStyle]
        let style = preferences?.style ?? noNotchStyle
        // The same rule as the shell's panels: the no-notch style never turns off a notched display.
        let shows = DisplayPreferences.showsCranny(preferences, noNotchStyle: noNotchStyle, hasNotch: metrics.hasNotch)
        let layout = ThemeResolver.layout(metrics: metrics, displayModel: currentScreen.flatMap(ThemeResolver.displayModelKey),
                                          style: style == .off ? .floatingIsland : style, settings: settings,
                                          textSize: settings[CoreSettings.textSize], density: settings[CoreSettings.density],
                                          widgetStyle: settings[CoreSettings.widgetStyle])
        let theme = ThemeResolver.theme(settings: settings, albumAccent: registry.services.nowPlaying?.palette?.accent,
                                        notchUnit: metrics.unit, isFloatingDisplay: layout.isFloating)
        return StageAppearance(layout: layout, theme: theme, isOff: !shows)
    }

    func castInputs() -> StageCastInputs {
        let settings = registry.services.settings
        return StageCastInputs(preferences: settings[CoreSettings.activityPreferences], order: settings[CoreSettings.activityOrder],
                               satellite: settings[CoreSettings.satellite], pages: settings[CoreSettings.pages])
    }

    /// Applies theme and layout; a change animates the shape with the `resize` token of the NEW theme. `given` is the
    /// value an observation just computed (each computation measures the display and resolves the theme), so it is
    /// not computed twice; nil computes it.
    func applyAppearance(_ given: StageAppearance? = nil, animated: Bool) {
        let appearance = given ?? appearanceInputs()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation = animated ? CrannyMotion.animation(.resize, personality: appearance.theme.motion, reduceMotion: reduceMotion) : nil
        withAnimation(animation) {
            if model.theme != appearance.theme { model.theme = appearance.theme }
            if model.layout != appearance.layout {
                model.layout = appearance.layout
                model.context.layout = appearance.layout
            }
        }
        if isOffOnDisplay != appearance.isOff { isOffOnDisplay = appearance.isOff }
        refreshScene(animated: animated)
    }

    /// Picks the display to imitate: built-in first, then the main display.
    func chooseScreen() {
        let screens = NSScreen.screens
        let builtIn = screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        currentScreen = builtIn ?? NSScreen.main ?? screens.first
        displayName = currentScreen?.localizedName
    }

    func loadWallpaper() async {
        guard let screen = currentScreen else { return }
        let miniature = await WallpaperSource.miniature(for: screen)
        guard !Task.isCancelled else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(CrannyMotion.animation(.contentSwap, personality: model.theme.motion, reduceMotion: reduceMotion)) {
            wallpaper = miniature
        }
    }

    /// One sample per activity: the module's `makeSample()`, else the stage's stand-in for well-known activities.
    static func makeSamples(registry: ModuleRegistry) -> [ActivityID: any LiveActivity] {
        var samples: [ActivityID: any LiveActivity] = [:]
        for registered in registry.activities {
            if let make = registered.makeSample { samples[registered.id] = make() }
        }
        for sample in StageSampleActivity.Sample.allCases where samples[sample.id] == nil {
            samples[sample.id] = StageSampleActivity(sample)
        }
        return samples
    }
}

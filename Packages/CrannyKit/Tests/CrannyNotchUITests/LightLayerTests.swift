// The light behind the open panel draws what Settings ▸ Appearance asks for: CoreSettings.effect and .ambience go
// through ThemeResolver into the theme, and NookLightLayer hands them to CrannyEffects' AmbientLayer. Measured on
// rendered pixels (snapshots draw the light in SwiftUI on its resting frame, so the pixels are deterministic).
import CoreGraphics
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

@MainActor @Suite("Light layer (DESIGN.md §5)") struct LightLayerTests {
    private let size = CGSize(width: 656, height: 170)

    /// The open panel's light for these settings, as luminance samples (12 × 8 grid over the lower 60 %).
    private func light(effect: AmbientEffect, ambience: AmbienceLevel = .vivid) throws -> [Double] {
        let (model, registry) = previewScene(.open)
        let settings = registry.services.settings
        settings[CoreSettings.effect] = effect
        settings[CoreSettings.ambience] = ambience
        model.theme = ThemeResolver.theme(settings: settings, albumAccent: nil, notchUnit: model.layout.metrics.unit,
                                          isFloatingDisplay: false)
        #expect(model.theme.effect == effect)
        let view = NookLightLayer(model: model, registry: registry)
            .environment(\.notchRendersFinalState, true)
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .crannyThemeRoot(model.theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let probe = try #require(ShapeProbe(image, scale: 2))
        var samples: [Double] = []
        for row in 0..<8 {
            let y = Int((0.42 + 0.56 * Double(row) / 7) * Double(probe.height - 1))
            for column in 0..<12 {
                let x = Int((0.04 + 0.92 * Double(column) / 11) * Double(probe.width - 1))
                samples.append(probe.luminance(x: x, y: y))
            }
        }
        return samples
    }

    private func difference(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(max(a.count, 1))
    }

    @Test func theEffectSettingChangesTheLight() throws {
        let aurora = try light(effect: .aurora), motes = try light(effect: .motes), tide = try light(effect: .tide)
        for (name, samples) in [("aurora", aurora), ("motes", motes), ("tide", tide)] {
            #expect((samples.max() ?? 0) > 0.03, "\(name) draws no light")
        }
        // Each choice of Appearance ▸ Effect draws a different light (before, every choice drew the aurora).
        #expect(difference(aurora, motes) > 0.005, "motes draws the aurora")
        #expect(difference(aurora, tide) > 0.005, "tide draws the aurora")
        #expect(difference(motes, tide) > 0.005, "motes and tide draw the same light")
        // The same settings draw the same pixels (the resting frame).
        #expect(difference(aurora, try light(effect: .aurora)) < 0.001)
    }
}

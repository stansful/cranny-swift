// Opt-in visual QA: renders every sample (compact, satellite, peek) to PNGs with ImageRenderer.
//   CRANNY_SNAPSHOTS=/tmp/out [CRANNY_SNAPSHOT_LANGUAGE=ru] swift test --scratch-path .build-test --filter SnapshotRenderTests
// Skipped unless CRANNY_SNAPSHOTS is set (never in CI). Nothing is asserted beyond "it renders". The language
// switch (`SystemCopy.useLanguage`) exists in Debug builds only.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct SnapshotRenderTests {
    nonisolated static let directory = ProcessInfo.processInfo.environment["CRANNY_SNAPSHOTS"]

    struct Variant {
        let name: String
        let metrics: NotchMetrics
        let theme: CrannyTheme
    }

    static var variants: [Variant] {
        var highContrast = CrannyTheme()
        highContrast.increaseContrast = true
        var large = CrannyTheme()
        large.textSize = .extraLarge
        var island = CrannyTheme()
        island.notchUnit = 0.94
        let external = NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)
        return [Variant(name: "notch", metrics: .reference, theme: CrannyTheme()),
                Variant(name: "notch-contrast", metrics: .reference, theme: highContrast),
                Variant(name: "notch-xl", metrics: .reference, theme: large),
                Variant(name: "island", metrics: external, theme: island)]
    }

    static var samples: [(String, any LiveActivity)] {
        [("charging", ChargingActivity.sample(.charging)), ("charged", ChargingActivity.sample(.charged)),
         ("plugged", ChargingActivity.sample(.notCharging)), ("unplugged", ChargingActivity.sample(.onBattery)),
         ("low-warning", LowBatteryActivity.sample(.warning)), ("low-critical", LowBatteryActivity.sample(.critical)),
         ("low-lpm", LowBatteryActivity.sample(.critical, lowPowerMode: true)),
         ("bt-airpods", BluetoothActivity.sample(.airPods)), ("bt-trackpad", BluetoothActivity.sample(.trackpad)),
         ("bt-unknown", BluetoothActivity.sample(.headphones))]
    }

    @Test(.enabled(if: directory != nil)) func renderEverySample() throws {
        let directory = try #require(Self.directory)
        let language = ProcessInfo.processInfo.environment["CRANNY_SNAPSHOT_LANGUAGE"]
        SystemCopy.useLanguage(language)
        defer { SystemCopy.useLanguage(nil) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for variant in Self.variants {
            for (name, activity) in Self.samples {
                let view = ActivityPreviewBoard(activity: activity, metrics: variant.metrics, theme: variant.theme)
                    .environment(\.colorScheme, .dark)
                    .environment(\.locale, language.map(Locale.init(identifier:)) ?? .current)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage, "\(name) did not render")
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let suffix = language.map { "-\($0)" } ?? ""
                try data.write(to: URL(fileURLWithPath: directory).appending(path: "\(variant.name)-\(name)\(suffix).png"))
            }
        }
    }
}

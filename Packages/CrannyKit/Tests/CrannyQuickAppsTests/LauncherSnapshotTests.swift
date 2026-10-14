// Opt-in visual QA: renders the launcher card in its states to PNGs for a human to look at.
//   CRANNY_SNAPSHOT_DIR=/some/dir swift test --scratch-path .build-test --filter LauncherSnapshot
// Skipped otherwise (and never in CI). Uses real app icons (read-only); launches and runs nothing.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyQuickApps

nonisolated private let snapshotDirectory = ProcessInfo.processInfo.environment["CRANNY_SNAPSHOT_DIR"]

@Suite(.enabled(if: snapshotDirectory != nil, "set CRANNY_SNAPSHOT_DIR to render"))
struct LauncherSnapshot {
    private let states: [String: ShortcutRunState] = [
        QuickAppsPreview.sampleShortcuts[0].id: .running(since: Date().addingTimeInterval(-3)),
        QuickAppsPreview.sampleShortcuts[1].id: .succeeded,
        QuickAppsPreview.sampleShortcuts[2].id: .failed(.shortcutFailed),
    ]
    private let many = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music", "com.apple.Notes",
                        "com.apple.iCal", "com.apple.Terminal", "com.apple.systempreferences", "com.apple.AppStore"]

    @Test func renderStates() async throws {
        let directory = try #require(snapshotDirectory)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var hints = NotchContext()
        hints.showsCommandHints = true
        var xl = CrannyTheme()
        xl.textSize = .extraLarge
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        var flat = CrannyTheme()
        flat.widgetStyle = .flat
        var roomy = CrannyTheme()
        roomy.density = .roomy

        let variants: [(String, QuickAppsModel, Int, CrannyTheme, NotchContext)] = [
            ("1-default-2cells", QuickAppsPreview.model(), 2, CrannyTheme(), NotchContext()),
            ("2-one-cell", QuickAppsPreview.model(), 1, CrannyTheme(), NotchContext()),
            ("3-four-cells-labels", QuickAppsPreview.model(showsLabels: true), 4, CrannyTheme(), NotchContext()),
            ("4-three-cells-editing", QuickAppsPreview.model(editing: true), 3, CrannyTheme(), NotchContext()),
            ("5-overflow", QuickAppsPreview.model(apps: many), 2, CrannyTheme(), NotchContext()),
            ("6-shortcut-states", QuickAppsPreview.model(apps: ["com.apple.Safari"], states: states), 2, CrannyTheme(), NotchContext()),
            ("7-empty", QuickAppsPreview.model(apps: [], shortcuts: []), 2, CrannyTheme(), NotchContext()),
            ("8-hints", QuickAppsPreview.model(apps: many), 3, CrannyTheme(), hints),
            ("9-xl-text", QuickAppsPreview.model(), 3, xl, NotchContext()),
            ("10-increase-contrast", QuickAppsPreview.model(), 3, contrast, NotchContext()),
            ("11-flat", QuickAppsPreview.model(), 3, flat, NotchContext()),
            ("12-roomy-6cells", QuickAppsPreview.model(apps: many), 6, roomy, NotchContext()),
            ("13-one-cell-editing-empty", QuickAppsPreview.model(apps: [], shortcuts: [], editing: true), 1, CrannyTheme(), NotchContext()),
        ]
        for (name, model, cells, theme, context) in variants {
            await warmIcons(model, theme: theme)
            let view = QuickAppsPreview.card(model: model, cells: cells, theme: theme, context: context)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
        }
    }

    /// The renderer takes one frame: put the icons in the cache first.
    private func warmIcons(_ model: QuickAppsModel, theme: CrannyTheme) async {
        let tile = TileMetrics(tile: theme.grid.cell, showsLabels: model.showsLabels)
        for case .app(let app) in model.tiles {
            _ = await model.catalog.icon(at: app.url, pixelSize: Int(tile.icon * 2))
            _ = await model.catalog.icon(at: app.url, pixelSize: 32)
        }
    }
}

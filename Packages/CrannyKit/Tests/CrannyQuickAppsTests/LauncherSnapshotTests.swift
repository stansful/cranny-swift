// Opt-in visual QA: renders the launcher card in its states to PNGs for a human to look at.
//   CRANNY_SNAPSHOT_DIR=/some/dir swift test --scratch-path .build-test --filter LauncherSnapshot
// writes into /some/dir/QuickApps. Skipped otherwise (and never in CI). Uses real app icons (read-only); launches
// and runs nothing.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyQuickApps

nonisolated private let snapshotDirectory = SnapshotOutput.directory("QuickApps")

@Suite(.enabled(if: snapshotDirectory != nil, "set CRANNY_SNAPSHOT_DIR to render"), .serialized)
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            // Shortcuts in "+N" still show their run state there (the default 2-cell launcher with shortcuts added).
            ("14-overflow-running", QuickAppsPreview.model(states: states), 2, CrannyTheme(), NotchContext()),
            ("15-overflow-failed", QuickAppsPreview.model(states: [QuickAppsPreview.sampleShortcuts[2].id: .failed(.shortcutFailed)]),
             2, CrannyTheme(), NotchContext()),
        ]
        for (name, model, cells, theme, context) in variants {
            await warmIcons(model, theme: theme)
            let view = QuickAppsPreview.card(model: model, cells: cells, theme: theme, context: context)
                .environment(\.quickAppsMenuAnchors, false)       // AppKit anchors render as placeholders here
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appending(path: "\(name).png"))
        }
    }

    /// Settings views hold AppKit-backed controls (lists, fields, switches) that `ImageRenderer` cannot draw:
    /// host them in an off-screen window (never ordered front) and cache its display.
    @Test func renderSettings() async throws {
        let directory = try #require(snapshotDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = QuickAppsPreview.model(apps: AppEntry.defaults.map(\.bundleID) + ["com.example.not-installed"])
        await model.shortcutsCatalog.refresh()
        await warmIcons(model, theme: CrannyTheme())
        for tile in model.tiles { if case .app(let app) = tile { _ = await model.catalog.icon(at: app.url, pixelSize: 48) } }
        let views: [(String, AnyView, CGSize)] = [
            ("20-settings-pane", AnyView(ShortcutsSettingsPane(model: model)), CGSize(width: 640, height: 640)),
            ("21-shortcut-picker", AnyView(ShortcutPicker(model: model)), CGSize(width: 320, height: 352)),
            ("22-appearance-editor", AnyView(ShortcutAppearanceEditor(model: model, id: QuickAppsPreview.sampleShortcuts[1].id)), CGSize(width: 330, height: 330)),
            ("23-widget-options", AnyView(LauncherOptions(model: model)), CGSize(width: 240, height: 130)),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view, size) in views {
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
                host.frame = CGRect(origin: .zero, size: size)
                window.contentView = host
                try await Task.sleep(for: .milliseconds(300))       // let `.task`s and layout settle
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                let suffix = appearance == .darkAqua ? "dark" : "light"
                try png.write(to: directory.appending(path: "\(name)-\(suffix).png"))
                window.close()
            }
        }
    }

    /// The launcher in a real `NSHostingView` (off-screen window, never ordered front), so the AppKit menu anchors
    /// behind "+" and "+N" are attached as in the app: they must draw nothing.
    @Test func renderHostedLauncher() async throws {
        let directory = try #require(snapshotDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let variants: [(String, QuickAppsModel, Int)] = [
            ("16-hosted-editing-overflow", QuickAppsPreview.model(editing: true, states: states), 2),
            ("17-hosted-overflow-failed",
             QuickAppsPreview.model(states: [QuickAppsPreview.sampleShortcuts[2].id: .failed(.shortcutFailed)]), 3),
        ]
        for (name, model, cells) in variants {
            await warmIcons(model, theme: CrannyTheme())
            let card = QuickAppsPreview.card(model: model, cells: cells)
            let size = CGSize(width: CrannyTheme().grid.width(cells: cells) + 2 * Space.xl, height: CrannyTheme().grid.height + 2 * Space.xl)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: card.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appending(path: "\(name).png"))
            window.close()
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

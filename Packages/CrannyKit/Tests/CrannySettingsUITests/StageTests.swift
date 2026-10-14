import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannySettingsUI

private let cast = StageCast(ongoing: [.nowPlaying, .timerRunning], available: [.nowPlaying, .timerRunning, .meetingSoon, .hud])

// MARK: - Scenes (DESIGN.md §11.2)

@Test func everyPickerStateHasItsScene() {
    let closed = StageScript.scene(for: .closed, cast: cast, page: .nook, showsSatellite: true)
    #expect(closed.phase == .idle && closed.primary == nil)
    let activity = StageScript.scene(for: .activity, cast: cast, page: .nook, showsSatellite: true)
    #expect(activity.phase == .compact && activity.primary == .nowPlaying && activity.satellite == .timerRunning)
    #expect(StageScript.scene(for: .activity, cast: cast, page: .nook, showsSatellite: false).satellite == nil)
    let peek = StageScript.scene(for: .peek, cast: cast, page: .nook, showsSatellite: false)
    #expect(peek.phase == .peek && peek.peekRows == [.nowPlaying])
    let open = StageScript.scene(for: .open, cast: cast, page: "page.focus", showsSatellite: true)
    #expect(open.phase == .open && open.open?.page == "page.focus" && open.motion == .open)
    let hud = StageScript.scene(for: .hud, cast: cast, page: .nook, showsSatellite: true)
    #expect(hud.phase == .compact && hud.primary == .hud && hud.motion == .hudIn)
}

@Test func statesWithoutSamplesFallBackToClosed() {
    let empty = StageCast(ongoing: [], available: [])
    for state in [PreviewStageState.activity, .peek, .hud] {
        #expect(StageScript.scene(for: state, cast: empty, page: .nook, showsSatellite: true).phase == .idle)
    }
}

@Test func chipsPlayOnceAndSettleOnThePickerState() throws {
    let base = StageScript.scene(for: .open, cast: cast, page: .nook, showsSatellite: true)
    let song = StageScript.steps(for: .songChange, base: base, cast: cast, page: .nook, peekDuration: 2.6, showsSatellite: true)
    #expect(song.map(\.scene.phase) == [.compact, .peek, .compact, .open])
    #expect(song[1].delay == .milliseconds(600) && song[2].delay == .milliseconds(2600))
    #expect(song[1].scene.delight == .songRipple)
    #expect(song[0].scene.satellite == .timerRunning)                       // the other ongoing activity
    let last = try #require(song.last)
    #expect(last.scene.phase == base.phase && last.scene.delight == nil && last.scene.motion == .resize)

    let volume = StageScript.steps(for: .volume, base: base, cast: cast, page: .nook, peekDuration: 2.6, showsSatellite: true)
    #expect(volume.map(\.scene.primary) == [.hud, nil])
    #expect(volume[1].delay == .milliseconds(1500) && volume[1].scene.motion == .hudOut)

    let drop = StageScript.steps(for: .dropFile, base: base, cast: cast, page: .nook, peekDuration: 2.6, showsSatellite: true)
    #expect(drop.first?.scene.open?.mode == .catchFiles([.fileURL]))
    #expect(drop[1].scene.delight == .gulp)
}

@Test func chipsWithoutASampleDoNothing() {
    let base = StageScript.scene(for: .closed, cast: cast, page: .nook, showsSatellite: true)
    let noHUD = StageCast(ongoing: [.nowPlaying], available: [.nowPlaying])
    #expect(StageScript.steps(for: .volume, base: base, cast: noHUD, page: .nook, peekDuration: 2.6, showsSatellite: true).isEmpty)
    #expect(StageScript.steps(for: .meeting, base: base, cast: noHUD, page: .nook, peekDuration: 2.6, showsSatellite: true).isEmpty)
}

@Test func openWidthSumsClampedWidgets() {
    let items = [NookItem(.media, cells: 9), NookItem(.timer, cells: 2), NookItem("unknown.widget", cells: 0)]
    let sizes: (WidgetID) -> WidgetSizes? = { $0 == .media ? WidgetSizes(minimum: 4, preferred: 5, maximum: 6) : nil }
    #expect(StageScript.openColumns(items: items, sizes: sizes, maxColumns: 20) == 6 + 2 + 1)
    #expect(StageScript.openColumns(items: items, sizes: sizes, maxColumns: 8) == 8)
    #expect(StageScript.openColumns(items: [], sizes: sizes, maxColumns: 8) == 1)
}

// MARK: - The stage controller

@Test func stageUsesStandInsAndRespectsTheUsersToggles() {
    let registry = ModuleRegistry(services: .preview())
    let stage = StageController(registry: registry, state: .activity)
    #expect(stage.model.context.isPreview)
    #expect(Set(stage.model.sampleActivities.keys) == [.nowPlaying, .timerRunning, .meetingSoon, .hud])
    #expect(stage.model.phase == .compact && stage.model.primary == .nowPlaying && stage.model.primarySlot == .short)
    #expect(stage.availableChips == SimulateChip.allCases)

    registry.services.settings[CoreSettings.activityPreferences] = [.nowPlaying: ActivityPreference(isEnabled: false, peeksOnChange: false)]
    stage.refreshScene(animated: false)
    #expect(stage.model.primary == .timerRunning && stage.model.satellite == nil)

    stage.select(.closed)
    #expect(stage.model.phase == .idle && stage.state == .closed)
    stage.select(.hud)
    #expect(stage.model.primary == .hud && stage.model.primarySlot == .wide)
}

@Test func stageFollowsTheUsersActivityOrder() {
    let registry = ModuleRegistry(services: .preview())
    registry.services.settings[CoreSettings.activityOrder] = [.timerRunning, .nowPlaying]
    let stage = StageController(registry: registry, state: .activity)
    #expect(stage.cast.ongoing == [.timerRunning, .nowPlaying])
    #expect(stage.model.primary == .timerRunning && stage.model.satellite == .nowPlaying)
}

@Test func openStageShowsTheEditedPageAtItsWidth() {
    let registry = ModuleRegistry(services: .preview())
    let focus = NookPage(id: "page.focus", title: "Focus", symbol: "note.text", items: [NookItem(.notes, cells: 4), NookItem(.timer, cells: 2)])
    registry.services.settings[CoreSettings.pages] = [NookPreset.listener.page, focus]
    let stage = StageController(registry: registry, state: .open)
    #expect(stage.model.open?.page == .nook && stage.model.openColumns == 10)
    stage.show(page: "page.focus")
    #expect(stage.model.open?.page == "page.focus" && stage.model.openColumns == 6)
}

@Test func stageThemeComesFromTheLiveSettings() {
    let registry = ModuleRegistry(services: .preview())
    let stage = StageController(registry: registry, state: .open)
    registry.services.settings[CoreSettings.density] = .roomy
    registry.services.settings[CoreSettings.motion] = .lively
    stage.applyAppearance(animated: false)
    #expect(stage.model.theme.density == .roomy && stage.model.theme.motion == .lively)
    #expect(stage.model.layout.grid.density == .roomy)
}

// MARK: - Wallpaper

@Test func wallpapersInProtectedFoldersAreNeverRead() {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
    func safe(_ path: String) -> Bool { ProtectedLocations.isSafeToRead(URL(fileURLWithPath: path), home: home) }
    #expect(safe("/System/Library/Desktop Pictures/Sequoia.heic"))
    #expect(safe("/Users/me/Pictures/Wallpapers/lake.jpg"))
    #expect(safe("/Users/me/Library/Application Support/com.apple.mobileAssetDesktop/x.heic"))
    #expect(!safe("/Users/me/Desktop/wall.png"))
    #expect(!safe("/Users/me/Documents/a/b.jpg"))
    #expect(!safe("/Users/me/Downloads/b.jpg"))
    #expect(!safe("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/w.jpg"))
    #expect(!safe("/Users/me/Library/CloudStorage/Dropbox/w.jpg"))
    #expect(!safe("/Volumes/USB/w.jpg"))
    #expect(!safe("/Users/me/Desktop/../Desktop/w.png"))
    #expect(safe("/Users/me/DesktopPictures/w.png"))                          // a prefix of a name is not the folder
    #expect(!ProtectedLocations.isSafeToRead(URL(string: "https://example.com/w.jpg")!))
}

@Test func menuBarInkFollowsTheWallpapersTop() throws {
    func image(white: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: white, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return try #require(context.makeImage())
    }
    #expect(WallpaperSource.topLuminance(of: try image(white: 1)) > 0.9)
    #expect(WallpaperSource.topLuminance(of: try image(white: 0)) < 0.1)
}

// CrannyTray/TraySettings.swift — the module's settings keys (namespace `tray.`, ARCHITECTURE.md §10.9) and the
// public value types they use. Every key is surfaced in Settings ▸ Tray (DESIGN.md §11.1).
import CrannyCore
import Foundation

/// The Tray's settings. Defaults match ARCHITECTURE.md §10.9; never rename a key (§3.11).
public nonisolated enum TraySettings {
    /// How long items stay in the Tray.
    public static let retention = SettingKey<TrayRetention>(.tray, "retention", default: .untilRemoved)
    /// The oldest items leave when the Tray holds more than this.
    public static let maxItems = SettingKey<Int>(.tray, "maxItems", default: 50)
    /// Keep a copy of every dropped file (default) or a link to the original.
    public static let storageMode = SettingKey<TrayStorageMode>(.tray, "storageMode", default: .copy)
    /// After files are kept, open Cranny on the Tray page so they can be seen.
    public static let opensTrayOnDrop = SettingKey<Bool>(.tray, "opensTrayOnDrop", default: true)
    /// AirDrop zone in the drag catch state and on the Tray page.
    public static let showsAirDropZone = SettingKey<Bool>(.tray, "showsAirDropZone", default: true)
    /// Up to three pipelines (by `PipelineDefinition.id`) offered as drop zones while dragging.
    public static let pinnedPipelines = SettingKey<[String]>(.tray, "pinnedPipelines", default: ["builtin.compress", "builtin.zip"])
    /// Chains built in Settings ▸ Tray.
    public static let userPipelines = SettingKey<[PipelineDefinition]>(.tray, "userPipelines", default: [])
    /// Lossy quality for Compress and JPEG/HEIC conversions (0.1…1).
    public static let jpegQuality = SettingKey<Double>(.tray, "jpegQuality", default: 0.8)
    /// "Resize ▸ Max N px" (pixels on the longer side).
    public static let maxDimension = SettingKey<Int>(.tray, "maxDimension", default: 1600)
    /// Where pipeline results are written.
    public static let outputLocation = SettingKey<TrayOutputLocation>(.tray, "outputLocation", default: .nextToSource)
    /// How Zip names its archive.
    public static let zipNaming = SettingKey<TrayZipNaming>(.tray, "zipNaming", default: .firstItem)

    /// The largest number of pinned pipelines shown as drop zones (DESIGN.md §8.3).
    public static let maxPinnedPipelines = 3
    /// Choices offered for `maxItems` in Settings.
    public static let maxItemsChoices = [10, 25, 50, 100, 200]
    /// Choices offered for `maxDimension` in Settings and the pipeline editor.
    public static let maxDimensionChoices = [1024, 1600, 2048, 2560, 3840]
}

/// Settings ▸ Tray ▸ Keep items (DESIGN.md §8.1 "Retention").
public nonisolated enum TrayRetention: String, Codable, CaseIterable, Sendable {
    /// Until the user removes them (default).
    case untilRemoved
    /// The Tray is emptied when Cranny quits (and on the next launch if it did not quit cleanly).
    case clearOnQuit
    /// Each item leaves 24 hours after it was added.
    case afterOneDay
}

/// Settings ▸ Tray ▸ Store dropped files as (ARCHITECTURE.md §7.8).
public nonisolated enum TrayStorageMode: String, Codable, CaseIterable, Sendable {
    /// A copy in Cranny's own folder: safe if the original is temporary, moved or deleted (default).
    case copy
    /// A bookmark to the original file. Temporary files (screenshots, promised files) are still copied.
    case link
}

/// Settings ▸ Tray ▸ Save results (DESIGN.md §8.2 "Result").
public nonisolated enum TrayOutputLocation: String, Codable, CaseIterable, Sendable {
    /// Next to the original file; files the Tray owns (and temporary files) go to Downloads instead.
    case nextToSource
    /// Always in the Downloads folder.
    case downloads
}

/// Settings ▸ Tray ▸ Zip naming (DESIGN.md §11.1).
public nonisolated enum TrayZipNaming: String, Codable, CaseIterable, Sendable {
    /// The first item's name: "Brief.zip".
    case firstItem
    /// "Archive 2026-10-14.zip" (the word is localized).
    case dated
}

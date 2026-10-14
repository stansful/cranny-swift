// CrannyTray/UI/TrayPreview.swift — sample data for this target's #Previews and tests (ARCHITECTURE.md §9.4): a store
// on throw-away folders with a recording `TraySystem`, and sample items that need no files on disk.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor enum TrayPreview {
    /// A store with `items` sample items (and `selected` of them selected), on temporary folders.
    static func store(items count: Int, selected: Int = 0, services: CrannyServices = .preview()) -> TrayStore {
        let store = TrayStore(settings: services.settings, notch: services.notch, haptics: services.haptics,
                              system: RecordingTraySystem(), directories: .temporary())
        let samples = Array(sampleItems.prefix(count))
        var urls: [UUID: URL] = [:]
        for item in samples { urls[item.id] = URL(filePath: "/tmp/cranny-preview/\(item.name)") }
        store.setContent(samples, urls: urls)
        store.selection.set(Array(samples.prefix(selected).map(\.id)))
        return store
    }

    /// The Tray page's context at `cells` columns (standard density).
    static func pageContext(cells: Int) -> WidgetContext {
        let grid = NookGrid()
        return WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells), height: grid.height))
    }

    /// A widget's content context at `cells` (card padding removed).
    static func widgetContext(cells: Int) -> WidgetContext {
        let grid = NookGrid()
        let inset = grid.density.cardPadding
        return WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset))
    }

    static let sampleItems: [TrayItem] = [
        ("Brief.pdf", UTType.pdf, 1_240_000), ("hero@2x.png", .png, 2_830_000), ("notch.heic", .heic, 980_000),
        ("assets.zip", .zip, 14_200_000), ("IMG_2041.jpg", .jpeg, 3_400_000), ("Screen Recording.mov", .quickTimeMovie, 26_100_000),
        ("Release notes.txt", .plainText, 4_300), ("Design review.key", UTType("com.apple.keynote.key") ?? .data, 8_900_000),
    ].enumerated().map { index, entry in
        TrayItem(id: UUID(), name: entry.0, location: .owned(path: "sample/\(entry.0)"), size: Int64(entry.2),
                 addedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(index) * 600), typeIdentifier: entry.1.identifier,
                 originalPath: nil)
    }
}

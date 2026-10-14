// Opt-in visual QA: renders the Tray's surfaces to PNGs with ImageRenderer so they can be looked at without the app.
//   CRANNY_TRAY_SNAPSHOTS=/some/folder swift test --scratch-path .build-test --filter CrannyTrayTests.SnapshotTests
// Always-on part: every surface renders (non-empty) in standard, high-contrast and Russian-length conditions.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@MainActor @Suite struct SnapshotTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["CRANNY_TRAY_SNAPSHOTS"]

    struct Surface {
        let name: String
        let view: AnyView
    }

    var surfaces: [Surface] {
        let grid = NookGrid()
        let states = TrayPreview.store(items: 6, selected: 2)
        if let ids = Optional(states.order), ids.count >= 4 {
            states.jobs.append(TrayJob(id: UUID(), pipelineID: "builtin.compress", title: "Compress", sourceIDs: [ids[3]],
                                       placeholderName: nil, progress: 0.4))
            states.failures[ids[4]] = TrayError.notSmaller.errorDescription
            states.freshItems.insert(ids[2])
            states.undoOffer = TrayUndoOffer(id: UUID(), title: "Compress", itemIDs: [ids[2]], files: [])
        }
        let page = { (store: TrayStore, cells: Int) in
            AnyView(TrayPage(store: store, context: TrayPreview.pageContext(cells: cells)).frame(width: grid.width(cells: cells)))
        }
        return [
            Surface(name: "page-items", view: page(TrayPreview.store(items: 8), 10)),
            Surface(name: "page-selected-states", view: page(states, 10)),
            Surface(name: "page-empty", view: page(TrayPreview.store(items: 0), 10)),
            Surface(name: "catch-images", view: AnyView(CatchView(store: TrayPreview.store(items: 1), types: [.png]).frame(width: grid.width(cells: 10)))),
            Surface(name: "catch-pdf-narrow", view: AnyView(CatchView(store: TrayPreview.store(items: 1), types: [.pdf]).frame(width: grid.width(cells: 7)))),
            Surface(name: "widgets", view: AnyView(HStack(alignment: .top, spacing: grid.gutter) {
                AirDropWidget(store: TrayPreview.store(items: 0)).makeBody(context: TrayPreview.widgetContext(cells: 2)).crannyCard(cells: 2)
                AirDropWidget(store: TrayPreview.store(items: 0)).makeBody(context: TrayPreview.widgetContext(cells: 1)).crannyCard(cells: 1)
                FilesShelfWidget(store: TrayPreview.store(items: 8, selected: 1)).makeBody(context: TrayPreview.widgetContext(cells: 4)).crannyCard(cells: 4)
                FilesShelfWidget(store: TrayPreview.store(items: 0)).makeBody(context: TrayPreview.widgetContext(cells: 3)).crannyCard(cells: 3)
            })),
            Surface(name: "files-6-cells", view: AnyView(
                FilesShelfWidget(store: TrayPreview.store(items: 8)).makeBody(context: TrayPreview.widgetContext(cells: 6)).crannyCard(cells: 6))),
        ]
    }

    func render(_ surface: Surface, theme: CrannyTheme, locale: Locale) -> NSImage? {
        let content = surface.view
            .padding(Space.l)
            .background(Color.black)
            .environment(\.locale, locale)
            .environment(\.trayRendersStatically, true)
            .crannyThemeRoot(theme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.nsImage
    }

    @Test func everySurfaceRenders() throws {
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        for surface in surfaces {
            for theme in [CrannyTheme(), contrast] {
                let image = try #require(render(surface, theme: theme, locale: Locale(identifier: "en")), "\(surface.name)")
                #expect(image.size.width > 100 && image.size.height > 50)
            }
        }
    }

    @Test(.enabled(if: SnapshotTests.folder != nil)) func writeSnapshots() throws {
        let folder = URL(filePath: try #require(Self.folder), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for surface in surfaces {
            for (suffix, locale) in [("en", Locale(identifier: "en")), ("ru", Locale(identifier: "ru"))] {
                guard let image = render(surface, theme: CrannyTheme(), locale: locale),
                      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: folder.appending(path: "\(surface.name)-\(suffix).png"))
            }
        }
    }
}

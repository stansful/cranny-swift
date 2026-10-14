// Visual QA of the Tray's surfaces with ImageRenderer.
// Always on: every surface renders at Standard, Increase Contrast, Extra Large text and Compact density, and the page
// keeps its final size (the tile geometry itself is checked numerically in `tilesGrowWithTextSizeAndNeverClip`).
// Opt-in PNGs (look at them):
//   CRANNY_TRAY_SNAPSHOTS=/some/folder swift test --scratch-path .build-test --filter CrannyTrayTests.SnapshotTests
//   CRANNY_TRAY_SNAPSHOT_LANGUAGE=ru CRANNY_TRAY_SNAPSHOTS=/some/folder swift test … (same filter): Russian renders.
// Why the language needs its own run: the test runner is an English-only tool, so `String(localized:bundle:)` resolves
// in English whatever the system language or `.environment(\.locale)` says (only `Text(_:bundle:)` follows the
// environment). The Russian run switches the process to Russian before the first string is read, so it must run
// alone (the filter above), one language per process. 1.4× pseudo-localisation is WP-Final's (ARCHITECTURE.md §8.7).
import AppKit
import CoreFoundation
import CrannyCore
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@MainActor @Suite(.serialized) struct SnapshotTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["CRANNY_TRAY_SNAPSHOTS"]
    nonisolated static let language = ProcessInfo.processInfo.environment["CRANNY_TRAY_SNAPSHOT_LANGUAGE"] ?? "en"

    /// Switches this test process to `language` once, before any string is resolved (opt-in runs only).
    private static let processLanguage: Void = {
        guard folder != nil, language != "en" else { return }
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        // Module bundles otherwise follow the runner's own (English) localization.
        if let info = CFBundleGetInfoDictionary(CFBundleGetMainBundle()) {
            (info as NSDictionary as? NSMutableDictionary)?["CFBundleAllowMixedLocalizations"] = true
        }
    }()

    init() { _ = Self.processLanguage }

    struct Surface {
        let name: String
        let view: AnyView
        /// The exact size a page must keep (nil: free-sized).
        var size: CGSize?
    }

    struct Variant {
        let name: String
        let theme: CrannyTheme
    }

    static var variants: [Variant] {
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        var large = CrannyTheme()
        large.textSize = .extraLarge
        var compact = CrannyTheme()
        compact.density = .compact
        return [Variant(name: "standard", theme: CrannyTheme()), Variant(name: "contrast", theme: contrast),
                Variant(name: "xl", theme: large), Variant(name: "compact", theme: compact)]
    }

    func surfaces(_ grid: NookGrid) -> [Surface] {
        let states = TrayPreview.store(items: 6, selected: 2)
        let ids = states.order
        states.jobs.append(TrayJob(id: UUID(), pipelineID: "builtin.compress", title: "Compress", sourceIDs: [ids[3]],
                                   placeholderName: nil, progress: 0.4))
        states.jobs.append(TrayJob(id: UUID(), pipelineID: TrayStore.keepJobID, title: "Keep", sourceIDs: [],
                                   placeholderName: "Gone.pdf", failure: TrayError.cannotRead("Gone.pdf").errorDescription))
        states.failures[ids[4]] = TrayError.notSmaller.errorDescription
        states.freshItems.insert(ids[2])
        states.undoOffer = TrayUndoOffer(id: UUID(), title: "Compress", itemIDs: [ids[2]], files: [])
        let pageSize = CGSize(width: grid.width(cells: 10), height: grid.height)
        let page = { (store: TrayStore) in
            AnyView(TrayPage(store: store, context: WidgetContext(cells: 10, contentSize: pageSize)).frame(width: pageSize.width))
        }
        let widget = { (cells: Int) in
            WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * grid.density.cardPadding,
                                                            height: grid.height - 2 * grid.density.cardPadding))
        }
        return [
            Surface(name: "page-items", view: page(TrayPreview.store(items: 8)), size: pageSize),
            Surface(name: "page-selected-states", view: page(states), size: pageSize),
            Surface(name: "page-empty", view: page(TrayPreview.store(items: 0)), size: pageSize),
            Surface(name: "catch-images", view: AnyView(CatchView(store: TrayPreview.store(items: 1), types: [.png])
                .frame(width: grid.width(cells: 10)))),
            Surface(name: "catch-pdf-narrow", view: AnyView(CatchView(store: TrayPreview.store(items: 1), types: [.pdf])
                .frame(width: grid.width(cells: 7)))),
            Surface(name: "widgets", view: AnyView(HStack(alignment: .top, spacing: grid.gutter) {
                AirDropWidget(store: TrayPreview.store(items: 0)).makeBody(context: widget(2)).crannyCard(cells: 2)
                AirDropWidget(store: TrayPreview.store(items: 0)).makeBody(context: widget(1)).crannyCard(cells: 1)
                FilesShelfWidget(store: TrayPreview.store(items: 8, selected: 1)).makeBody(context: widget(4)).crannyCard(cells: 4)
                FilesShelfWidget(store: TrayPreview.store(items: 0)).makeBody(context: widget(3)).crannyCard(cells: 3)
            })),
            Surface(name: "files-6-cells", view: AnyView(
                FilesShelfWidget(store: TrayPreview.store(items: 8)).makeBody(context: widget(6)).crannyCard(cells: 6))),
        ]
    }

    func render(_ surface: Surface, theme: CrannyTheme, padding: CGFloat = Space.l) -> NSImage? {
        let content = surface.view
            .padding(padding)
            .background(Color.black)
            .environment(\.locale, Locale(identifier: Self.language))
            .environment(\.trayRendersStatically, true)
            .crannyThemeRoot(theme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.nsImage
    }

    @Test func everySurfaceRendersAtItsSize() throws {
        for variant in Self.variants {
            for surface in surfaces(variant.theme.grid) {
                let image = try #require(render(surface, theme: variant.theme, padding: 0), "\(surface.name) \(variant.name)")
                #expect(image.size.width > 100 && image.size.height > 50, "\(surface.name) \(variant.name)")
                if let size = surface.size {
                    // The page is laid out at its final size: nothing inside pushes it taller or wider.
                    #expect(image.size == size, "\(surface.name) \(variant.name): \(image.size) ≠ \(size)")
                }
            }
        }
    }

    @Test(.enabled(if: SnapshotTests.folder != nil)) func writeSnapshots() throws {
        let folder = URL(filePath: try #require(Self.folder), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(Bundle.module.preferredLocalizations.first == Self.language,
                "strings resolve in \(Bundle.module.preferredLocalizations); run this suite alone (see the header)")
        for variant in Self.variants {
            for surface in surfaces(variant.theme.grid) {
                guard let image = render(surface, theme: variant.theme),
                      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: folder.appending(path: "\(surface.name)-\(variant.name)-\(Self.language).png"))
            }
        }
    }
}

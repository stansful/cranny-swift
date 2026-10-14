// CrannyQuickApps/UI/AppIconView.swift — an app's icon (`NSWorkspace.icon(forFile:)`), rendered off the main
// actor at the exact pixel size and cached by `AppCatalog`. Until it arrives, a quiet rounded placeholder.
import AppKit
import CoreGraphics
import CrannyCore
import SwiftUI

struct AppIconView: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL
    let catalog: AppCatalog
    let size: CGFloat
    @State private var image: CGImage?

    private struct Request: Hashable { let url: URL; let pixels: Int }

    var body: some View {
        let scale = max(displayScale, 2)
        let pixels = Int((size * scale).rounded())
        Group {
            if let icon = image ?? catalog.cachedIcon(at: url, pixelSize: pixels) {
                Image(decorative: icon, scale: scale)
                    .resizable()
                    .interpolation(.high)
            } else {
                // macOS icons sit on a squircle-ish grid: a soft square of the same footprint, never a spinner.
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(.quaternary)
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .task(id: Request(url: url, pixels: pixels)) {
            image = await catalog.icon(at: url, pixelSize: pixels)
        }
        .accessibilityHidden(true)
    }

    /// Pixel size of an NSMenu row's 16-pt icon (2×). `OverflowTile` renders these off the main actor in advance.
    static let menuPixels = 32

    /// The icon as an NSImage for an NSMenu row, from the cache only (no I/O on the main actor): the menu size, else
    /// any size already rendered (the tile's), else none.
    @MainActor static func menuImage(for app: ResolvedApp, catalog: AppCatalog, size: CGFloat = 16) -> NSImage? {
        guard let icon = catalog.cachedIcon(at: app.url, pixelSize: menuPixels) ?? catalog.anyCachedIcon(at: app.url) else {
            return nil
        }
        return NSImage(cgImage: icon, size: NSSize(width: size, height: size))
    }
}

#Preview("App icons") {
    let model = QuickAppsPreview.model()
    HStack(spacing: Space.l) {
        ForEach(model.tiles) { tile in
            if case .app(let app) = tile { AppIconView(url: app.url, catalog: model.catalog, size: 36) }
        }
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

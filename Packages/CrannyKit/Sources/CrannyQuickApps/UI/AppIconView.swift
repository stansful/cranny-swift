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

    /// The icon as an NSImage for an NSMenu row (cached icon, else LaunchServices' own).
    @MainActor static func menuImage(for app: ResolvedApp, catalog: AppCatalog, size: CGFloat = 16) -> NSImage {
        let pixels = Int(size * 2)
        if let cached = catalog.cachedIcon(at: app.url, pixelSize: pixels) {
            return NSImage(cgImage: cached, size: NSSize(width: size, height: size))
        }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: size, height: size)
        return image
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

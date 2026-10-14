// CrannyQuickApps/Apps/AppResolver.swift — bundle id ↔ app on disk, and app icons (R3 §6).
//
// Lookup, naming and the protected-folder rule are CrannyCore's (`AppIdentityResolver.locate`, `AppIdentity.name(of:)`,
// `ProtectedLocations`), shared with Settings and Media (§10.20 #11): Finder's name, or the file name for an app in a
// protected folder, never the bundle identifier; and no icon is read from a protected folder (an app left in Downloads
// gets macOS's generic app icon, so the launcher never raises a Files & Folders prompt). What Quick Apps adds: icons
// rendered at an exact pixel size, and reading a bundle the user dropped or chose (their own action).
//
// Threading: LaunchServices lookups, Info.plist reads and icon rendering are I/O, so the live resolver does them
// in `@concurrent` functions off the main actor and hands back Sendable values (`ResolvedApp`, `CGImage`).
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import UniformTypeIdentifiers

/// An installed app.
nonisolated struct ResolvedApp: Hashable, Sendable, Identifiable {
    let bundleID: String
    let url: URL
    /// Finder's name ("System Settings" / «Системные настройки»; `AppIdentity.name(of:)`), never the bundle identifier.
    let name: String
    var id: String { bundleID }
}

/// Looks apps up. The app uses `WorkspaceAppResolver`; tests inject fakes.
nonisolated protocol AppResolving: Sendable {
    /// The installed app with this bundle identifier, nil if there is none.
    func resolve(_ bundleID: String) async -> ResolvedApp?
    /// The app at `url` if it is an application bundle with a bundle identifier (drops, the open panel).
    func app(at url: URL) async -> ResolvedApp?
    /// The app's icon rendered at `pixelSize` × `pixelSize`.
    func icon(at url: URL, pixelSize: Int) async -> CGImage?
}

nonisolated struct WorkspaceAppResolver: AppResolving {
    /// What an app's icon is drawn from.
    enum IconSource: Equatable {
        /// The bundle's own icon (Icon Services reads the bundle).
        case bundle(URL)
        /// macOS's generic app icon: the bundle sits where reading it could raise a privacy prompt.
        case genericApp
    }

    /// CrannyCore's lookup (off the main actor): Launch Services, then Finder's name.
    func resolve(_ bundleID: String) async -> ResolvedApp? {
        await AppIdentityResolver.locate(bundleID).map { ResolvedApp(bundleID: bundleID, url: $0.url, name: $0.name) }
    }

    func app(at url: URL) async -> ResolvedApp? { await Self.appOffMain(at: url) }
    func icon(at url: URL, pixelSize: Int) async -> CGImage? { await Self.iconOffMain(at: url, pixelSize: pixelSize) }

    /// The bundle's own icon where reading it cannot raise a privacy prompt (`ProtectedLocations`), else the generic
    /// app icon. Tests inject `isSafeToRead`.
    static func iconSource(for url: URL, isSafeToRead: (URL) -> Bool = { ProtectedLocations.isSafeToRead($0) }) -> IconSource {
        isSafeToRead(url) ? .bundle(url) : .genericApp
    }

    /// A bundle the user dropped or chose in the open panel (their own action, so reading it is theirs to ask for).
    @concurrent private static func appOffMain(at url: URL) async -> ResolvedApp? {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let isApp = values?.contentType?.conforms(to: .application) ?? (url.pathExtension.lowercased() == "app")
        guard isApp, let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return ResolvedApp(bundleID: bundleID, url: url.standardizedFileURL, name: AppIdentity.name(of: url))
    }

    /// Draws the icon into a bitmap of exactly `pixelSize` (NSImage picks its best representation for it).
    @concurrent private static func iconOffMain(at url: URL, pixelSize: Int) async -> CGImage? {
        guard pixelSize > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let image = switch iconSource(for: url) {
        case .bundle(let bundle): NSWorkspace.shared.icon(forFile: bundle.path)
        case .genericApp: NSWorkspace.shared.icon(for: .applicationBundle)
        }
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

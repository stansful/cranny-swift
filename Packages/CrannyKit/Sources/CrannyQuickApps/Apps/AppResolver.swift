// CrannyQuickApps/Apps/AppResolver.swift — bundle id ↔ app on disk, and app icons (R3 §6).
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
    /// Localized display name ("System Settings" / «Системные настройки»), without ".app".
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
    func resolve(_ bundleID: String) async -> ResolvedApp? { await Self.resolveOffMain(bundleID) }
    func app(at url: URL) async -> ResolvedApp? { await Self.appOffMain(at: url) }
    func icon(at url: URL, pixelSize: Int) async -> CGImage? { await Self.iconOffMain(at: url, pixelSize: pixelSize) }

    @concurrent private static func resolveOffMain(_ bundleID: String) async -> ResolvedApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return ResolvedApp(bundleID: bundleID, url: url, name: displayName(of: url))
    }

    @concurrent private static func appOffMain(at url: URL) async -> ResolvedApp? {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let isApp = values?.contentType?.conforms(to: .application) ?? (url.pathExtension.lowercased() == "app")
        guard isApp, let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return ResolvedApp(bundleID: bundleID, url: url.standardizedFileURL, name: displayName(of: url))
    }

    /// Draws the icon into a bitmap of exactly `pixelSize` (NSImage picks its best representation for it).
    @concurrent private static func iconOffMain(at url: URL, pixelSize: Int) async -> CGImage? {
        guard pixelSize > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Finder's name: CrannyCore's one naming rule (`AppIdentity.name(of:)`, shared with Settings and Media): the
    /// localized display name, or the file name for a bundle in a protected folder (an app left in Downloads, which
    /// is not read) or one that names nothing; never the bundle identifier.
    private static func displayName(of url: URL) -> String { AppIdentity.name(of: url) }
}

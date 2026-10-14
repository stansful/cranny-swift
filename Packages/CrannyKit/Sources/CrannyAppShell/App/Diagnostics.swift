// CrannyAppShell/App/Diagnostics.swift — `Cranny --diagnostics <file.json>`: CI/launch smoke test, no UI.
// Keys read by scripts/smoke.sh: resourceBundles, bridge, mainMenu, shaders. Also effectsRenderer and media (QA).
import AppKit
import CrannyCore
import CrannyEffects
import Foundation

enum Diagnostics {
    static func argument(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func write(to path: String, registry: ModuleRegistry) async {
        var r: [String: Any] = [:]
        let info = AppInfo.current()
        r["app"] = ["id": info.bundleIdentifier, "version": info.version, "build": info.build]
        r["preferredLanguages"] = Locale.preferredLanguages
        r["mainPreferredLocalizations"] = Bundle.main.preferredLocalizations
        r["resourceBundles"] = ((try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.resourcePath ?? "")) ?? [])
            .filter { $0.hasSuffix(".bundle") }.sorted()
        r["registry"] = ["widgets": registry.widgets.map(\.id.rawValue), "activities": registry.activities.map(\.id.rawValue),
                         "pages": registry.pages.map(\.id.rawValue), "shortcuts": registry.shortcuts.map(\.id.rawValue),
                         "permissions": registry.permissionUses.map { "\($0.kind)" }]
        r["permissionTitle.ru"] = Bundle(path: Bundle.main.path(forResource: "CrannyKit_CrannyCore", ofType: "bundle") ?? "")
            .flatMap { b in b.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:)) }?
            .localizedString(forKey: "Accessibility", value: "(missing)", table: nil) ?? "(no bundle)"
        r["mainMenu"] = NSApp.mainMenu?.items.map { item in
            [item.title: item.submenu?.items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) ⌘\($0.keyEquivalent)" } ?? []]
        } ?? []
        let bridge = Bundle.main.privateFrameworksURL?.appending(path: "libCrannyMediaBridge.dylib").path ?? ""
        r["bridge"] = FileManager.default.fileExists(atPath: bridge) ? bridge : "(missing)"
        // Metal effects: the CrannyEffects bundle's default.metallib, loaded the way the app loads it (Bundle.module).
        r["shaders"] = EffectsDiagnostics.shaderStatus
        // How the ambient light is drawn: "metal-layer", "swiftui-shader" or "fallback" (WP11).
        r["effectsRenderer"] = EffectsDiagnostics.ambientRenderer
        // The media source's health facts (WP1: provider, state, elected player as unknown/none/some; no names).
        if let media = registry.services.nowPlaying as? any NowPlayingDiagnostics { r["media"] = media.diagnostics }
        // Which display(s) get a panel under the current settings, in AppKit screen coordinates (visual QA).
        r["panelScreens"] = OverlayCoordinator.panelScreens(settings: registry.services.settings).map { entry in
            ["key": entry.key.rawValue, "name": entry.screen.localizedName, "style": entry.style.rawValue,
             "frame": [entry.screen.frame.minX, entry.screen.frame.minY, entry.screen.frame.width, entry.screen.frame.height],
             "notch": entry.screen.safeAreaInsets.top > 0] as [String: Any]
        }
        r["screens"] = NSScreen.screens.map { screen in
            [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height]
        }
        if let data = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

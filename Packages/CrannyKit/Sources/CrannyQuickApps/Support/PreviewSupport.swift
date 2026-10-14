// CrannyQuickApps/Support/PreviewSupport.swift — sample data for #Previews, snapshot tests and QA: a model on
// `CrannyServices.preview()` whose apps are real installed apps (read-only lookups), whose running set and
// Shortcuts list are fixed, and which never launches or runs anything.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

@MainActor enum QuickAppsPreview {
    static let sampleShortcuts: [ShortcutEntry] = [
        ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine", symbol: "sun.max.fill", tint: .orange),
        ShortcutEntry(id: "5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02", name: "Resize (50%) images"),
        ShortcutEntry(id: "9E3F7A21-0C4D-4B8E-A5F6-1D2C3B4A5E03", name: "Отправить отчёт"),
    ]

    /// What `shortcuts list --show-identifiers` would print (the three samples plus two more).
    static let sampleList = """
        Morning routine (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)
        Resize (50%) images (5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02)
        Отправить отчёт (9E3F7A21-0C4D-4B8E-A5F6-1D2C3B4A5E03)
        Clean Desktop 🧹 (2A4B6C8D-1E3F-4A5B-8C7D-9E0F1A2B3C04)
        Start focus timer (7F6E5D4C-3B2A-4190-8F7E-6D5C4B3A2905)

        """

    static func model(apps: [String] = AppEntry.defaults.map(\.bundleID),
                      shortcuts: [ShortcutEntry] = sampleShortcuts,
                      running: [String] = ["com.apple.finder", "com.apple.Safari"],
                      showsLabels: Bool = false, editing: Bool = false,
                      states: [String: ShortcutRunState] = [:]) -> QuickAppsModel {
        let services = CrannyServices.preview()
        services.settings[QuickAppsSettings.apps] = apps.map(AppEntry.init(bundleID:))
        services.settings[QuickAppsSettings.shortcuts] = shortcuts
        services.settings[QuickAppsSettings.showsLabels] = showsLabels
        let list = Data(sampleList.utf8)
        let model = QuickAppsModel(services: services, resolver: PreviewAppResolver(), launcher: PreviewLauncher(),
                                   cli: ShortcutsCLI(runner: { _, _ in CLIOutput(stdout: list) }),
                                   running: RunningAppsObserver(center: NotificationCenter(), snapshot: { running }))
        model.catalog.seed(apps.compactMap(PreviewAppResolver.app(for:)))
        model.running.start()
        model.isEditing = editing
        for (id, state) in states { model.runs.show(state, for: id) }
        return model
    }

    /// The launcher on a card, as the open panel draws it.
    static func widget(cells: Int, showsLabels: Bool = false, editing: Bool = false,
                       apps: [String] = AppEntry.defaults.map(\.bundleID), shortcuts: [ShortcutEntry] = sampleShortcuts,
                       states: [String: ShortcutRunState] = [:], theme: CrannyTheme = CrannyTheme()) -> some View {
        let model = model(apps: apps, shortcuts: shortcuts, showsLabels: showsLabels, editing: editing, states: states)
        return card(model: model, cells: cells, theme: theme)
    }

    static func card(model: QuickAppsModel, cells: Int, theme: CrannyTheme = CrannyTheme(),
                     context: NotchContext = NotchContext()) -> some View {
        let grid = theme.grid
        let inset = grid.density.cardPadding
        let content = CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset)
        return LauncherView(model: model, context: WidgetContext(cells: cells, contentSize: content))
            .crannyCard(cells: cells)
            .padding(Space.xl)
            .background(Color.black)
            .environment(\.notchContext, context)
            .crannyThemeRoot(theme)
    }
}

/// Looks real apps up synchronously (previews only).
nonisolated struct PreviewAppResolver: AppResolving {
    static func app(for bundleID: String) -> ResolvedApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return ResolvedApp(bundleID: bundleID, url: url, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }
    func resolve(_ bundleID: String) async -> ResolvedApp? { Self.app(for: bundleID) }
    func app(at url: URL) async -> ResolvedApp? { await WorkspaceAppResolver().app(at: url) }
    func icon(at url: URL, pixelSize: Int) async -> CGImage? { await WorkspaceAppResolver().icon(at: url, pixelSize: pixelSize) }
}

/// Launches nothing.
@MainActor final class PreviewLauncher: AppLaunching {
    private(set) var opened: [URL] = []
    private(set) var revealed: [URL] = []
    private(set) var shortcutsAppOpened = 0
    func open(_ url: URL) async throws { opened.append(url) }
    func reveal(_ url: URL) { revealed.append(url) }
    func openShortcutsApp() { shortcutsAppOpened += 1 }
}

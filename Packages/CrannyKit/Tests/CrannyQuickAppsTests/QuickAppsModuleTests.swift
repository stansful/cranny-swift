// Registration contributes the widget, Settings ▸ Shortcuts and ⌘K, without side effects; settings keep their contract.
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(QuickAppsModule.self)
    #expect(QuickAppsModule.id == .quickApps)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

@Test func contributesTheLauncherWidget() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(QuickAppsModule.self)
    let widget = try #require(registry.widget(.quickApps))
    #expect(widget.sizes == WidgetSizes(minimum: 1, preferred: 2, maximum: 6))
    #expect(widget.symbol == "square.2.layers.3d.fill")     // the feature's glyph, as on its Settings pane
    #expect(widget.symbol != "app.dashed")                  // DESIGN.md §14.1: the placeholder (missing app, unknown widget)
    #expect(!widget.isFrameless)
    #expect(widget.hasOptions)
    #expect(!widget.title.isEmpty && !widget.summary.isEmpty)
}

@Test func contributesSettingsPaneAndCommands() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(QuickAppsModule.self)
    let page = try #require(registry.settingsPages.first { $0.id == .shortcuts })
    #expect(page.group == .features)
    #expect(page.tint == .indigo)
    #expect(page.symbol == "square.2.layers.3d.fill")
    #expect(page.symbol == registry.widget(.quickApps)?.symbol)
    #expect(page.namespaces == [.quickApps])
    #expect(page.previewState == .open)
    #expect(page.keywords.count >= 5)
    #expect(registry.commandProviders.count == 1)
    #expect(registry.permissionUses.isEmpty)           // the Shortcuts CLI needs no permission
    #expect(registry.shortcuts.isEmpty)
}

@Test func settingsDefaults() {
    #expect(QuickAppsSettings.apps.id == "quickapps.apps")
    #expect(QuickAppsSettings.apps.defaultValue.map(\.bundleID) == ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music"])
    #expect(QuickAppsSettings.shortcuts.id == "quickapps.shortcuts")
    #expect(QuickAppsSettings.shortcuts.defaultValue.isEmpty)
    #expect(QuickAppsSettings.showsLabels.id == "quickapps.showsLabels")
    #expect(QuickAppsSettings.showsLabels.defaultValue == false)
    #expect(QuickAppsSettings.order.id == "quickapps.order")
    #expect(QuickAppsSettings.order.defaultValue.isEmpty)
}

@Test func entriesRoundTripAndTolerateMissingFields() throws {
    let entries = [ShortcutEntry(id: "A", name: "Ünïcödé (x)", symbol: "bolt.fill", tint: .mint), ShortcutEntry(id: "B", name: "Plain")]
    let data = try JSONEncoder().encode(entries)
    #expect(try JSONDecoder().decode([ShortcutEntry].self, from: data) == entries)
    let minimal = try JSONDecoder().decode(ShortcutEntry.self, from: Data(#"{"id":"C","name":"Old"}"#.utf8))
    #expect(minimal.symbol == nil && minimal.tint == nil)
    let app = try JSONDecoder().decode(AppEntry.self, from: Data(#"{"bundleID":"com.apple.Safari"}"#.utf8))
    #expect(app == AppEntry(bundleID: "com.apple.Safari"))
}

@Test func settingsPersistThroughTheStore() {
    let services = CrannyServices.preview()
    services.settings[QuickAppsSettings.shortcuts] = [ShortcutEntry(id: "A", name: "One", tint: .red)]
    services.settings[QuickAppsSettings.apps] = []
    #expect(services.settings[QuickAppsSettings.shortcuts].first?.tint == .red)
    #expect(services.settings[QuickAppsSettings.apps].isEmpty)
    services.settings.reset(module: .quickApps)
    #expect(services.settings[QuickAppsSettings.apps] == AppEntry.defaults)
    #expect(services.settings[QuickAppsSettings.shortcuts].isEmpty)
}

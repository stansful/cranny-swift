import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyTray

@Test func registersEveryContributionWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(TrayModule.self)
    #expect(TrayModule.id == .tray)
    #expect(registry.registeringModule == nil)
    #expect(registry.services.tray != nil)
    #expect(registry.pages.map(\.id) == [.tray])
    #expect(registry.pages.first?.badge() == nil)                     // nothing loaded at registration
    #expect(registry.widget(.airDrop)?.sizes == WidgetSizes(minimum: 1, preferred: 2, maximum: 2))
    #expect(registry.widget(.files)?.sizes == WidgetSizes(minimum: 3, preferred: 4, maximum: 8))
    let pane = try #require(registry.settingsPages.first)
    #expect(pane.id == .tray && pane.group == .features && pane.tint == .green && pane.namespaces == [.tray])
    #expect(!pane.keywords.isEmpty)
    #expect(registry.shortcuts.map(\.id) == [.openTray])
    #expect(registry.shortcuts.first?.defaultCombo == nil)            // off until the user sets one (DESIGN.md §11.1)
    #expect(registry.commandProviders.count == 1)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                                       // registering never opens, flashes or peeks
}

@Test func theShortcutAndCommandOpenTheTrayPage() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(TrayModule.self)
    registry.shortcuts.first?.perform()
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls == ["open(tray,-,keyboard)"])
}

@Test func everySymbolExistsOnMacOS14() throws {
    let availability = URL(filePath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
    let plist = try #require(NSDictionary(contentsOf: availability))
    let symbols = try #require(plist["symbols"] as? [String: String])
    let releases = try #require(plist["year_to_release"] as? [String: [String: String]])
    for name in TraySymbols.all {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name) does not resolve")
        let year = try #require(symbols[name], "\(name) is not in the availability table")
        let macOS = releases[year]?["macOS"].flatMap { SemanticVersion($0) }
        #expect(macOS.map { $0 <= SemanticVersion("14.0")! } == true, "\(name) needs macOS \(releases[year]?["macOS"] ?? "?")")
    }
}

@Test func errorsHaveOneLineDescriptions() {
    let errors: [TrayError] = [.cannotRead("a"), .cannotWrite, .unsupportedFile("a"), .formatUnavailable("AVIF"), .notSmaller,
                               .archiveFailed, .unarchiveFailed, .noSubject, .noText, .pdfFailed, .videoFailed, .fileMissing]
    for error in errors {
        let text = error.errorDescription ?? ""
        #expect(!text.isEmpty && !text.contains("\n"))
    }
}

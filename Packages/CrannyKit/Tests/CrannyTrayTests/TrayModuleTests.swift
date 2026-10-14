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
                               .archiveFailed, .unarchiveFailed, .noSubject, .noText, .pdfFailed, .videoFailed, .fileMissing,
                               .cannotKeep("a")]
    for error in errors {
        let text = error.errorDescription ?? ""
        #expect(!text.isEmpty && !text.contains("\n"))
    }
    #expect(Set(errors.map(\.caseName)).count == errors.count)
}

@Test func publicLogTextNeverNamesTheUsersFiles() {
    let name = "Medical report.pdf"
    #expect(TrayLogCode.of(TrayError.unsupportedFile(name)) == "TrayError.unsupportedFile")
    let missing = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/someone/Desktop/\(name)"])
    #expect(missing.localizedDescription.contains("Medical"))             // what used to be logged publicly
    #expect(TrayLogCode.of(missing) == "NSCocoaErrorDomain 260")
    #expect(TrayError.keeping(name, failedWith: missing) == .cannotRead(name))
    #expect(TrayError.keeping(name, failedWith: CocoaError(.fileWriteOutOfSpace)) == .cannotKeep(name))
}

@Test func tilesGrowWithTextSizeAndNeverClip() {
    let standard = TrayTileLayout(textSize: .standard, grid: NookGrid())
    #expect(standard.width == 64 && standard.height == 66)                // DESIGN.md §8.1 at Standard
    for density in NookDensity.allCases {
        var previous: TrayTileLayout?
        for textSize in CrannyTextSize.allCases {
            let grid = NookGrid(density: density, textSize: textSize)
            let layout = TrayTileLayout(textSize: textSize, grid: grid)
            let label = "\(density) \(textSize)"
            // The caption's line box sits inside the well with room to spare below it for the 1.5-pt selection ring.
            let caption = CrannyTextStyle.caption.pointSize(textSize: textSize, notchUnit: 1)
            #expect(layout.captionHeight >= caption * 1.2, "\(label)")
            #expect(layout.height - Space.xs - TrayMetrics.thumbnail - layout.captionHeight >= StrokeWidth.emphasis + 2, "\(label)")
            // Tile row, gap and chips fit the page card.
            let content = grid.height - 2 * density.cardPadding
            #expect(layout.height + layout.rowSpacing + TrayTileLayout.chipRowHeight(textSize: textSize) <= content, "\(label)")
            if let previous { #expect(layout.height >= previous.height && layout.width >= previous.width, "\(label)") }
            previous = layout
        }
    }
    #expect(TrayTileLayout(textSize: .extraLarge, grid: NookGrid(textSize: .extraLarge)).width > 64)
}

@Test func quickLookOpensCentredOnThePointersScreen() {
    let frame = QuickLookPresenter.frame(for: NSEvent.mouseLocation)
    #expect((480...1101).contains(frame.width))           // `.integral` may add a point
    #expect((360...821).contains(frame.height))
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    if let visible = screen?.visibleFrame { #expect(visible.intersects(frame)) }
}

@Test func tileAccessibilityValueSaysStateThenFailure() {
    let job = TrayJob(id: UUID(), pipelineID: "builtin.compress", title: "Compress", sourceIDs: [], placeholderName: nil, progress: 0.4)
    let value = TrayTileAccessibility.value(selected: true, job: job, failure: "Nope")
    #expect(value.hasPrefix(TrayTileAccessibility.value(selected: true, job: nil, failure: nil)))
    #expect(value.contains("Compress") && value.hasSuffix("Nope"))
    #expect(TrayTileAccessibility.value(selected: false, job: nil, failure: nil).isEmpty)
}

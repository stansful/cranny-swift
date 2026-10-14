// The "+" and "+N" menus and what they show without main-actor I/O: live submenus, lazily drawn shortcut glyphs,
// cached app icons; the overflow tile's combined run state; the running ring's energy budget; announcement limits.
import AppKit
import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannyQuickApps

@MainActor @Observable private final class Items {
    var titles = ["Loading…"]
}

@Test @MainActor func liveSubmenusFollowTheirContentWhileOpen() async throws {
    let items = Items()
    let menu = NSMenu()
    PopUpMenu.fill(menu, with: [MenuEntry("Add Shortcut", liveSubmenu: { items.titles.map { MenuEntry(disabled: $0) } })])
    let submenu = try #require(menu.items.first?.submenu)
    #expect(submenu.items.map(\.title) == ["Loading…"])
    items.titles = ["Morning routine", "Resize images"]                   // the list finished reading
    #expect(await waitUntil { submenu.items.map(\.title) == ["Morning routine", "Resize images"] })
    #expect(submenu.delegate != nil)                                       // rebuilt again when it opens
}

@Test @MainActor func addMenuListsShortcutsNotOnTheLauncherAndHidesNamesInDemoMode() async {
    let morning = ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine")
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture))
    #expect(AddMenu.shortcutEntries(model: h.model).map(\.title) == ["Loading…"])    // not read yet
    await h.model.shortcutsCatalog.refresh()
    let titles = AddMenu.shortcutEntries(model: h.model).map(\.title)
    #expect(titles.count == 8 && !titles.contains("Morning routine") && titles.contains("Resize (50%) images"))
    h.environment.isDemoMode = true
    #expect(Set(AddMenu.shortcutEntries(model: h.model).map(\.title)) == [QuickAppsModel.neutralShortcutName])
}

@Test @MainActor func shortcutMenuImagesAreDrawnLazilyAndShared() throws {
    let entry = ShortcutEntry(id: "A", name: "т-банк", tint: .teal)
    let glyph = ShortcutMenuImage.glyph(for: entry, redacted: false, size: 16)
    #expect(glyph.initial == "Т" && glyph.symbol == nil && glyph.tint == .teal)
    #expect(ShortcutMenuImage.glyph(for: entry, redacted: true, size: 16).symbol == ShortcutAppearance.fallbackSymbol)
    let symbol = ShortcutEntry(id: "B", name: "Sun", symbol: "sun.max.fill")
    #expect(ShortcutMenuImage.glyph(for: symbol, redacted: false, size: 16).symbol == "sun.max.fill")

    let image = ShortcutMenuImage.image(for: entry)
    #expect(image.size == NSSize(width: 16, height: 16))
    #expect(ShortcutMenuImage.image(for: ShortcutEntry(id: "C", name: "Тест", tint: .teal)) === image)   // same glyph
    // It draws: the squircle's middle is the tint or the white letter, the corner stays clear.
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
    NSGraphicsContext.restoreGraphicsState()
    #expect((rep.colorAt(x: 16, y: 6)?.alphaComponent ?? 0) > 0.9)
    #expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
}

@Test @MainActor func appMenuIconsComeFromTheCacheOnly() async {
    let catalog = AppCatalog(resolver: IconResolver())
    let app = FakeResolver.app("a")
    #expect(AppIconView.menuImage(for: app, catalog: catalog) == nil)     // nothing rendered yet: no image, no I/O
    _ = await catalog.icon(at: app.url, pixelSize: 72)                      // the tile's size
    #expect(AppIconView.menuImage(for: app, catalog: catalog)?.size == NSSize(width: 16, height: 16))
    #expect(catalog.anyCachedIcon(at: app.url)?.width == 72)
    _ = await catalog.icon(at: app.url, pixelSize: AppIconView.menuPixels)
    #expect(catalog.cachedIcon(at: app.url, pixelSize: AppIconView.menuPixels) != nil)
}

@Test @MainActor func catalogSortsDroppedFilesIntoAppsAndOthers() async {
    let catalog = AppCatalog(resolver: FakeResolver([]))
    let urls = ["/x/a.app", "/x/readme.txt", "/y/a.app", "/x/b.app"].map { URL(fileURLWithPath: $0) }
    let sorted = await catalog.sort(urls)
    #expect(sorted.apps.map(\.bundleID) == ["a", "b"])
    #expect(sorted.others == [URL(fileURLWithPath: "/x/readme.txt")])
}

@Test func overflowShowsTheMostUrgentStateOfItsShortcuts() {
    let started = Date(timeIntervalSince1970: 100)
    #expect(ShortcutRunState.combined([]) == .idle)
    #expect(ShortcutRunState.combined([.idle, .succeeded]) == .succeeded)
    #expect(ShortcutRunState.combined([.succeeded, .failed(.shortcutFailed)]) == .failed(.shortcutFailed))
    #expect(ShortcutRunState.combined([.failed(.shortcutFailed), .running(since: started)]) == .running(since: started))
}

@Test @MainActor func runningRingTicksOnlyWithinTheEffectBudget() {
    let environment = PreviewSystemEnvironment()
    func interval() -> Double? {
        RunningRing.frameInterval(environment.effectBudget(isOpen: true, isOnScreen: true, reduceMotion: false))
    }
    #expect(interval() == 1.0 / 8)                                         // capped at 8 fps on AC (budget 30)
    environment.isOnBattery = true
    #expect(interval() == 1.0 / 8)
    environment.thermalState = .serious
    #expect(interval() == nil)                                             // thermal: still
    environment.thermalState = .nominal
    environment.isLowPowerMode = true
    #expect(interval() == nil)
    environment.isLowPowerMode = false
    environment.isFullScreenInFront = true
    #expect(interval() == nil)
    environment.isFullScreenInFront = false
    #expect(RunningRing.frameInterval(environment.effectBudget(isOpen: true, isOnScreen: true, reduceMotion: true)) == nil)
}

@Test func announcementsAreLimitedToOnePer10Seconds() {
    var limiter = AnnouncementLimiter()
    let start = Date(timeIntervalSince1970: 1000)
    let answers = [0, 9.9, 10, 12].map { limiter.allows(at: start.addingTimeInterval($0)) }
    #expect(answers == [true, false, true, false])
}

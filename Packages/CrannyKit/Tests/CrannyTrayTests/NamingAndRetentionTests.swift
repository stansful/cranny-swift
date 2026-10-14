// Pure logic: result names, output folders, the editor's name preview, retention, selection, dedup, LRU.
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@Suite struct NamingTests {
    let naming = OutputNaming.english

    @Test func namesDeriveFromTheInput() {
        #expect(naming.compressed("photo") == "photo (compressed)")
        #expect(naming.resized("hero", width: 1600, height: 900) == "hero 1600×900")
        #expect(naming.withoutBackground("cat") == "cat (no background)")
        #expect(naming.withoutMetadata("cat") == "cat (no metadata)")
    }

    @Test func zipNaming() {
        let date = Date(timeIntervalSince1970: 1_791_936_000)   // 2026-10-14 00:00 UTC
        let utc = TimeZone(identifier: "UTC") ?? .current
        #expect(naming.zipBaseName(firstItem: "Brief", naming: .firstItem, date: date) == "Brief")
        #expect(naming.zipBaseName(firstItem: "", naming: .firstItem, date: date) == "Archive")
        #expect(naming.zipBaseName(firstItem: "Brief", naming: .dated, date: date, timeZone: utc) == "Archive 2026-10-14")
    }

    @Test func uniqueNamesFollowFinder() {
        #expect(OutputNaming.unique(base: "a", ext: "png", taken: []) == "a.png")
        #expect(OutputNaming.unique(base: "a", ext: "png", taken: ["a.png"]) == "a 2.png")
        #expect(OutputNaming.unique(base: "a", ext: "png", taken: ["A.PNG", "a 2.png"]) == "a 3.png")
        #expect(OutputNaming.unique(base: "Folder", ext: "", taken: ["Folder"]) == "Folder 2")
        let folder = Fixtures.folder("unique")
        Fixtures.text("x.txt", in: folder)
        #expect(OutputNaming.uniqueURL(base: "x", ext: "txt", in: folder).lastPathComponent == "x 2.txt")
    }

    @Test func resultsGoNextToTheSourceUnlessTheTrayOwnsIt() {
        let base = Fixtures.folder("placement")
        let user = base.appending(path: "Desktop", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let placement = OutputPlacement(trayRoot: base.appending(path: "Tray"), temporaryRoots: [base.appending(path: "Incoming")],
                                        downloads: base.appending(path: "Downloads"))
        let source = user.appending(path: "photo.png")
        #expect(placement.directory(for: source, location: .nextToSource).path == user.path)
        #expect(placement.directory(for: source, location: .downloads) == placement.downloads)
        #expect(placement.directory(for: base.appending(path: "Tray/123/photo.png"), location: .nextToSource) == placement.downloads)
        #expect(placement.directory(for: base.appending(path: "Incoming/x/photo.png"), location: .nextToSource) == placement.downloads)
        #expect(placement.directory(for: nil, location: .nextToSource) == placement.downloads)
        #expect(OutputPlacement.isInside(base.appending(path: "Tray"), base.appending(path: "Tray")))
        #expect(!OutputPlacement.isInside(base.appending(path: "Trays/x"), base.appending(path: "Tray")))
    }

    @Test func editorPreviewUsesTheRunsNamingRules() {
        var options = PipelineOptions()
        options.maxDimension = 1600
        let sample = PipelinePreview.sample(for: .images)
        #expect(PipelinePreview.outputName(of: [.resize(to: .maxDimension(pixels: 0)), .convert(format: .jpeg), .copyPaths],
                                           sample: sample, options: options) == "IMG_2041 1600×1200.jpg")
        #expect(PipelinePreview.outputName(of: [.resize(to: .scale(percent: 50))], sample: sample, options: options)
                == "IMG_2041 2016×1512.heic")
        #expect(PipelinePreview.outputName(of: [.removeBackground], sample: sample, options: options) == "IMG_2041 (no background).png")
        #expect(PipelinePreview.outputName(of: [.convert(format: .png), .zip], sample: sample, options: options) == "IMG_2041.zip")
        #expect(PipelinePreview.outputName(of: [.unzip], sample: PipelinePreview.sample(for: .archives), options: options) == "Assets")
        #expect(PipelinePreview.outputName(of: [.copyPaths], sample: PipelinePreview.sample(for: .any), options: options) == "Brief.pdf")
        #expect(PipelinePreview.outputName(of: [], sample: sample, options: options) == nil)
    }
}

@Suite struct RetentionTests {
    func item(_ age: TimeInterval, now: Date) -> TrayItem {
        TrayItem(id: UUID(), name: "f", location: .owned(path: "x/f"), size: 1, addedAt: now.addingTimeInterval(-age),
                 typeIdentifier: nil, originalPath: nil)
    }

    @Test func afterOneDayExpiresOldItems() {
        let now = Date()
        let fresh = item(60, now: now), old = item(Retention.oneDay + 1, now: now)
        #expect(Retention.expired([fresh, old], policy: .afterOneDay, now: now) == [old.id])
        #expect(Retention.expired([fresh, old], policy: .untilRemoved, now: now).isEmpty)
        #expect(Retention.expired([fresh, old], policy: .clearOnQuit, now: now).isEmpty)
        #expect(Retention.nextExpiry([fresh, old], policy: .afterOneDay) == old.addedAt.addingTimeInterval(Retention.oneDay))
        #expect(Retention.nextExpiry([fresh], policy: .untilRemoved) == nil)
        #expect(Retention.clearsOnQuit(.clearOnQuit) && !Retention.clearsOnQuit(.afterOneDay))
    }

    @Test func capRemovesTheOldestButNeverTheNewcomers() {
        let now = Date()
        let items = (0..<5).map { item(Double($0) * 10, now: now) }        // items[4] is the oldest
        #expect(Retention.overflow(items, maxItems: 3) == [items[3].id, items[4].id])
        #expect(Retention.overflow(items, maxItems: 10).isEmpty)
        #expect(Retention.overflow(items, maxItems: 3, keeping: [items[4].id]) == [items[2].id, items[3].id])
        #expect(Retention.overflow(items, maxItems: 0).count == 4)          // at least one item stays
    }
}

@Suite struct SelectionTests {
    let order = (0..<5).map { _ in UUID() }

    @Test func clickCommandClickShiftClick() {
        var s = TraySelection()
        s.click(order[1], modifiers: [], order: order)
        #expect(s.selected == [order[1]] && s.cursor == order[1])
        s.click(order[3], modifiers: .command, order: order)
        #expect(s.selected == [order[1], order[3]])
        s.click(order[1], modifiers: .command, order: order)
        #expect(s.selected == [order[3]])
        s.click(order[0], modifiers: .shift, order: order)                 // anchor is order[1] (last ⌘-click)
        #expect(s.selected == Set(order[0...1]))
        s.click(order[4], modifiers: [], order: order)
        s.click(order[2], modifiers: .shift, order: order)
        #expect(s.selected == Set(order[2...4]))
        #expect(s.ordered(in: order) == Array(order[2...4]))
    }

    @Test func keyboardMovesAndExtends() {
        var s = TraySelection()
        s.move(forward: true, extend: false, order: order)
        #expect(s.selected == [order[0]])
        s.move(forward: true, extend: true, order: order)
        s.move(forward: true, extend: true, order: order)
        #expect(s.selected == Set(order[0...2]) && s.cursor == order[2])
        s.move(forward: false, extend: false, order: order)
        #expect(s.selected == [order[1]])
        s.move(forward: false, extend: false, order: order)
        s.move(forward: false, extend: false, order: order)                // stays at the first tile
        #expect(s.selected == [order[0]])
        var back = TraySelection()
        back.move(forward: false, extend: false, order: order)
        #expect(back.selected == [order[4]])
        s.selectAll(order)
        #expect(s.selected == Set(order))
    }

    @Test func pruneForgetsRemovedItems() {
        var s = TraySelection()
        s.selectAll(order)
        s.click(order[2], modifiers: .command, order: order)
        s.prune(to: Array(order.prefix(2)))
        #expect(s.selected == Set(order.prefix(2)))
        #expect(s.cursor == nil)
        s.clear()
        #expect(s.isEmpty && s.anchor == nil)
    }
}

@Suite struct DedupAndCacheTests {
    @Test func aFileAlreadyInTheTrayIsFound() {
        let url = URL(filePath: "/Users/someone/Desktop/a.png")
        let copy = TrayItem(id: UUID(), name: "a.png", location: .owned(path: "x/a.png"), size: 1, addedAt: Date(),
                            typeIdentifier: nil, originalPath: url.path)
        let link = TrayItem(id: UUID(), name: "b.png", location: .linked(bookmark: Data(), path: "/Users/someone/b.png"), size: 1,
                            addedAt: Date(), typeIdentifier: nil, originalPath: nil)
        #expect(TrayDedup.match(url, in: [copy, link])?.id == copy.id)
        #expect(TrayDedup.match(URL(filePath: "/Users/someone/b.png"), in: [copy, link])?.id == link.id)
        #expect(TrayDedup.match(URL(filePath: "/Users/someone/c.png"), in: [copy, link]) == nil)
    }

    @Test func lruEvictsTheLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        #expect(cache.value(for: "a") == 1)       // a is now the most recent
        cache.insert(3, for: "c")
        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "a") == 1 && cache.value(for: "c") == 3)
        #expect(cache.count == 2)
        cache.removeAll()
        #expect(cache.count == 0)
    }
}

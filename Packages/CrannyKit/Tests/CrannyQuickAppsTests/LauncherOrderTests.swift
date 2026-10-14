// One tile order across the apps and shortcuts keys, and moves that keep hidden (not installed) apps in place.
import Testing
@testable import CrannyQuickApps

private let apps = ["a", "b", "c"].map(AppEntry.init(bundleID:))
private let shortcuts = [ShortcutEntry(id: "S1", name: "One"), ShortcutEntry(id: "S2", name: "Two")]

@Test func tileIDRawValuesRoundTrip() {
    #expect(TileID.app("com.apple.Safari").rawValue == "app:com.apple.Safari")
    #expect(TileID.shortcut("S1").rawValue == "shortcut:S1")
    #expect(TileID(rawValue: "app:com.apple.Safari") == .app("com.apple.Safari"))
    #expect(TileID(rawValue: "shortcut:S1") == .shortcut("S1"))
    #expect(TileID(rawValue: "app:") == nil)
    #expect(TileID(rawValue: "bogus") == nil)
}

@Test func withoutAnOrderAppsComeFirst() {
    #expect(LauncherOrder.arrange(apps: apps, shortcuts: shortcuts, order: []) ==
            [.app("a"), .app("b"), .app("c"), .shortcut("S1"), .shortcut("S2")])
}

@Test func theOrderWinsAndUnlistedTilesFollow() {
    let order = ["shortcut:S2", "app:c", "app:gone", "shortcut:S2", "junk"]
    #expect(LauncherOrder.arrange(apps: apps, shortcuts: shortcuts, order: order) ==
            [.shortcut("S2"), .app("c"), .app("a"), .app("b"), .shortcut("S1")])
}

@Test func repeatedEntriesAppearOnce() {
    let doubled = apps + [AppEntry(bundleID: "a")]
    #expect(LauncherOrder.arrange(apps: doubled, shortcuts: [], order: []) == [.app("a"), .app("b"), .app("c")])
}

@Test func moveAmongVisibleTilesKeepsHiddenOnesInPlace() {
    // "b" is not installed (hidden): moving "c" to the front must not move "b".
    let arrangement: [TileID] = [.app("a"), .app("b"), .app("c"), .shortcut("S1")]
    let visible: (TileID) -> Bool = { $0 != .app("b") }
    #expect(LauncherOrder.move(.app("c"), toVisibleIndex: 0, in: arrangement, isVisible: visible) ==
            [.app("c"), .app("b"), .app("a"), .shortcut("S1")])
    #expect(LauncherOrder.move(.app("a"), toVisibleIndex: 99, in: arrangement, isVisible: visible) ==
            [.app("c"), .app("b"), .shortcut("S1"), .app("a")])
    #expect(LauncherOrder.move(.app("b"), toVisibleIndex: 0, in: arrangement, isVisible: visible) == arrangement)
}

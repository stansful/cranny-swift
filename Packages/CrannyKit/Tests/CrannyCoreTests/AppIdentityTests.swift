import AppKit
import Foundation
import Testing
@testable import CrannyCore

// MARK: - One naming rule (§10.20 #11)

/// Finder's name where the bundle may be read; the file name elsewhere and when the bundle names nothing; never the
/// bundle identifier.
@Test func appsAreNamedLikeFinderNamesThem() {
    let spotify = URL(fileURLWithPath: "/Applications/Spotify.app")
    #expect(AppIdentity.name(of: spotify, isSafeToRead: { _ in true }, displayName: { _ in "Spotify" }) == "Spotify")
    // In a protected folder the bundle is not read: its file name stands in.
    let downloaded = URL(fileURLWithPath: "/Users/me/Downloads/Spotify.app")
    #expect(AppIdentity.name(of: downloaded, isSafeToRead: { _ in false },
                             displayName: { _ in Issue.record("read a protected bundle"); return "" }) == "Spotify")
    // The real protected-folder rule decides by default: the user's Downloads is never read.
    let userDownloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Spotify.app")
    #expect(AppIdentity.name(of: userDownloads, displayName: { _ in Issue.record("read a protected bundle"); return "" }) == "Spotify")
    // A bundle that names nothing never falls back to its identifier.
    #expect(AppIdentity.name(of: spotify, isSafeToRead: { _ in true }, displayName: { _ in "  " }) == "Spotify")
    #expect(AppIdentity.displayName(of: URL(fileURLWithPath: "/System/Applications/Music.app")).hasSuffix(".app") == false)
}

/// The real lookup (Launch Services, off the main actor): an installed app has its name, an unknown one none.
@Test func theLookupFindsInstalledAppsOnly() async {
    let finder = await AppIdentityResolver.locate("com.apple.finder")
    #expect(finder.map { !$0.name.isEmpty && $0.name != "com.apple.finder" && !$0.name.hasSuffix(".app") && $0.isSafeToRead } == true)
    #expect(await AppIdentityResolver.locate("com.example.cranny.not-installed") == nil)
    #expect(await AppIdentityResolver.applicationURL(for: "com.example.cranny.not-installed") == nil)
}

// MARK: - The resolver

/// Pending first (no name, never the identifier), then the lookup's answer: installed with Finder's name and an icon,
/// or not installed; one lookup per app at a time.
@MainActor @Test func identitiesArePendingThenInstalledOrNotInstalled() async {
    let lookups = LookupLog()
    let resolver = AppIdentityResolver(locate: { id in
        await lookups.add(id)
        return id == "com.apple.Music" ? AppIdentity.Location(url: URL(fileURLWithPath: "/System/Applications/Music.app"),
                                                              name: "Music", isSafeToRead: true) : nil
    }, icon: { _ in NSImage(size: CGSize(width: 16, height: 16)) })
    let pending = resolver.identity(of: "com.apple.Music")
    #expect(pending.isPending && pending.name == nil && pending.icon == nil && pending.url == nil)
    #expect(resolver.identity(of: "com.apple.Music").isPending && resolver.isLookingUp)
    _ = resolver.identity(of: "com.example.gone")
    await waitUntil { !resolver.isLookingUp }

    let music = resolver.identity(of: "com.apple.Music")
    #expect(music.isInstalled && music.name == "Music" && music.icon != nil && music.url?.lastPathComponent == "Music.app")
    let gone = resolver.identity(of: "com.example.gone")
    #expect(gone.isNotInstalled && gone.name == nil && gone.icon == nil && gone.name(or: "fallback") == "fallback")
    #expect(await lookups.ids.sorted() == ["com.apple.Music", "com.example.gone"])     // one lookup each
    #expect(resolver.revision == 2)
}

/// An app in a protected folder is named after its file and gets no icon (reading it could prompt).
@MainActor @Test func protectedAppsHaveANameButNoIcon() async {
    let resolver = AppIdentityResolver(locate: { _ in
        AppIdentity.Location(url: URL(fileURLWithPath: "/Users/me/Downloads/Spotify.app"), name: "Spotify", isSafeToRead: false)
    }, icon: { _ in Issue.record("read a protected bundle's icon"); return nil })
    _ = resolver.identity(of: "com.spotify.client")
    await waitUntil { !resolver.isLookingUp }
    let spotify = resolver.identity(of: "com.spotify.client")
    #expect(spotify.isInstalled && spotify.name == "Spotify" && spotify.icon == nil && spotify.url != nil)
}

/// `refresh()` picks up an app installed or removed meanwhile; an identity keeps what it shows until the answer
/// differs, and the revision moves only then.
@MainActor @Test func refreshPicksUpInstallsAndRemovals() async {
    let installed = Locked(false)
    let resolver = AppIdentityResolver(locate: { _ in
        installed.value ? AppIdentity.Location(url: URL(fileURLWithPath: "/Applications/Spotify.app"), name: "Spotify",
                                               isSafeToRead: true) : nil
    }, icon: { _ in nil })
    _ = resolver.identity(of: "com.spotify.client")
    await waitUntil { !resolver.isLookingUp }
    #expect(resolver.identity(of: "com.spotify.client").isNotInstalled)
    let revision = resolver.revision

    resolver.refresh()                                                                // nothing changed
    #expect(resolver.isLookingUp && resolver.identity(of: "com.spotify.client").isNotInstalled)   // kept meanwhile
    await waitUntil { !resolver.isLookingUp }
    #expect(resolver.revision == revision)

    installed.value = true
    resolver.refresh()
    await waitUntil { !resolver.isLookingUp }
    #expect(resolver.identity(of: "com.spotify.client").name == "Spotify" && resolver.revision == revision + 1)

    installed.value = false
    resolver.refresh()
    await waitUntil { !resolver.isLookingUp }
    #expect(resolver.identity(of: "com.spotify.client").isNotInstalled && resolver.revision == revision + 2)
}

/// The icon is made off the main actor (Icon Services' first call is slow), once per answer: a refresh that finds the
/// same app makes none, one that finds it moved makes a new one.
@MainActor @Test func iconsAreMadeOffTheMainActorOncePerAnswer() async {
    let moved = Locked(false)
    let iconCalls = Locked<[Bool]>([])                                                // on the main thread, per call
    let resolver = AppIdentityResolver(locate: { _ in
        AppIdentity.Location(url: URL(fileURLWithPath: moved.value ? "/Applications/Utilities/Spotify.app" : "/Applications/Spotify.app"),
                             name: "Spotify", isSafeToRead: true)
    }, icon: { _ in
        iconCalls.value += [Thread.isMainThread]
        return NSImage(size: CGSize(width: 16, height: 16))
    })
    _ = resolver.identity(of: "com.spotify.client")
    await waitUntil { !resolver.isLookingUp }
    #expect(resolver.identity(of: "com.spotify.client").icon != nil)
    #expect(iconCalls.value == [false])

    resolver.refresh()                                                                // the same answer: no icon
    await waitUntil { !resolver.isLookingUp }
    #expect(iconCalls.value == [false])

    moved.value = true
    resolver.refresh()                                                                // a new answer: a new icon
    await waitUntil { !resolver.isLookingUp }
    #expect(iconCalls.value == [false, false])
    #expect(resolver.identity(of: "com.spotify.client").url?.path == "/Applications/Utilities/Spotify.app")
}

/// The real resolver: Finder has a name and an icon, an unknown identifier is not installed.
@MainActor @Test func theSharedLookupResolvesRealApps() async {
    let resolver = AppIdentityResolver()
    _ = resolver.identity(of: "com.apple.finder")
    _ = resolver.identity(of: "com.example.cranny.not-installed")
    await waitUntil { !resolver.isLookingUp }
    let finder = resolver.identity(of: "com.apple.finder")
    #expect(finder.isInstalled && finder.name.map { $0 != "com.apple.finder" && !$0.hasSuffix(".app") } == true && finder.icon != nil)
    #expect(resolver.identity(of: "com.example.cranny.not-installed").isNotInstalled)
}

/// An app in a protected folder is never read (no Files & Folders prompt), whatever lists it.
@Test func protectedFoldersAreNeverRead() {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    #expect(!ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Users/someone/Downloads/Player.app"), home: home))
    #expect(!ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Volumes/USB/Player.app"), home: home))
    #expect(ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Applications/Player.app"), home: home))
    #expect(ProtectedLocations.normalized("/a/./b/../c//d") == "/a/c/d")
}

/// A QA run's isolated home (`CFFIXED_USER_HOME` moves `homeDirectoryForCurrentUser`) does not unguard the account's
/// own folders: those are what macOS protects. String checks only; nothing in the real home is read.
@Test func theAccountsOwnFoldersStayProtectedUnderAnIsolatedHome() throws {
    let account = try #require(ProtectedLocations.accountHome)
    #expect(account.hasPrefix("/") && account != "/")
    let isolated = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appending(path: "qa-home-\(UUID())")
    for folder in ["Desktop", "Documents", "Downloads", "Library/Containers/com.example.other"] {
        #expect(!ProtectedLocations.isSafeToRead(URL(fileURLWithPath: account + "/" + folder + "/wall.jpg"),
                                                 home: isolated, ownBundleID: nil), "\(folder)")
        #expect(!ProtectedLocations.isSafeToRead(isolated.appending(path: folder + "/wall.jpg"), home: isolated,
                                                 ownBundleID: nil), "\(folder)")
    }
    #expect(ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                            home: isolated, ownBundleID: nil))
}

// MARK: - Helpers

/// The bundle identifiers a lookup was asked for (from the lookups' isolation domain).
private actor LookupLog {
    private(set) var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}

/// A value the injected lookups read from another isolation domain.
private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Waits for `condition`, letting the lookups land (a generous bound: never a short real-time wait, §9.6).
@MainActor private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<3000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

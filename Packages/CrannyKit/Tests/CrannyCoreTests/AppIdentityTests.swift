import AppKit
import Foundation
import Testing
@testable import CrannyCore

/// App names and icons are looked up off the main actor, once per app; until then views show the identifier.
@MainActor @Test func appIdentitiesResolveOffTheMainActorOnce() async {
    let resolver = AppIdentityResolver()
    let placeholder = resolver.identity(of: "com.apple.finder")
    #expect(placeholder.name == "com.apple.finder" && placeholder.icon == nil && !placeholder.isResolved)
    for _ in 0..<200 where resolver.resolvedCount == 0 { try? await Task.sleep(for: .milliseconds(10)) }
    let finder = resolver.identity(of: "com.apple.finder")
    #expect(finder.isResolved && finder.name != "com.apple.finder" && finder.icon != nil)
    #expect(finder.name.hasSuffix(".app") == false)
    let unknown = resolver.identity(of: "com.example.not-installed")
    for _ in 0..<200 where resolver.resolvedCount < 2 { try? await Task.sleep(for: .milliseconds(10)) }
    let missing = resolver.identity(of: "com.example.not-installed")
    #expect(unknown.name == "com.example.not-installed" && !missing.isResolved && missing.icon == nil)
    #expect(await AppIdentityResolver.applicationURL(for: "com.example.not-installed") == nil)
}

/// An app in a protected folder is never read (no Files & Folders prompt), whatever lists it.
@Test func protectedFoldersAreNeverRead() {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    #expect(!ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Users/someone/Downloads/Player.app"), home: home))
    #expect(!ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Volumes/USB/Player.app"), home: home))
    #expect(ProtectedLocations.isSafeToRead(URL(fileURLWithPath: "/Applications/Player.app"), home: home))
    #expect(ProtectedLocations.normalized("/a/./b/../c//d") == "/a/c/d")
    #expect(AppIdentity.displayName(of: URL(fileURLWithPath: "/System/Applications/Music.app")).hasSuffix(".app") == false)
}

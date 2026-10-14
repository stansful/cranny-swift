// Locator order and the quarantine copy (ARCHITECTURE.md §6.3): temp files + setxattr, nothing outside a temp dir.
import CrannyCore
import Darwin
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Bridge locator") struct BridgeLocatorTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cranny-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setQuarantine(_ url: URL) {
        let value = "0083;00000000;Safari;"
        _ = url.withUnsafeFileSystemRepresentation { path in
            value.withCString { setxattr(path!, BridgeLocator.quarantineAttribute, $0, strlen($0), 0, 0) }
        }
    }

    @Test func candidatesInOrder() {
        let frameworks = URL(fileURLWithPath: "/Applications/Cranny.app/Contents/Frameworks")
        let executable = URL(fileURLWithPath: "/tmp/build/debug/tool")
        let all = BridgeLocator.candidates(environment: ["CRANNY_MEDIA_BRIDGE": "/custom/lib.dylib"],
                                           privateFrameworks: frameworks, executable: executable)
        #expect(all.map(\.path) == ["/custom/lib.dylib",
                                    "/Applications/Cranny.app/Contents/Frameworks/libCrannyMediaBridge.dylib",
                                    "/tmp/build/debug/libCrannyMediaBridge.dylib"])
        #expect(BridgeLocator.candidates(environment: ["CRANNY_MEDIA_BRIDGE": ""], privateFrameworks: nil, executable: executable).count == 1)
        #expect(BridgeLocator.candidates(environment: [:], privateFrameworks: nil, executable: nil).isEmpty)
    }

    @Test func picksTheFirstExistingCandidate() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appending(path: "missing.dylib"), present = dir.appending(path: "present.dylib")
        try Data("bridge".utf8).write(to: present)
        #expect(BridgeLocator.locate(candidates: [missing, present], copyDirectory: { dir }) == present)
        #expect(BridgeLocator.locate(candidates: [missing], copyDirectory: { dir }) == nil)
    }

    @Test func quarantinedLibraryIsReplacedByACleanCopy() throws {
        let dir = try tempDirectory(), copies = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: copies) }
        let original = dir.appending(path: BridgeLocator.fileName)
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        try bytes.write(to: original)
        setQuarantine(original)
        #expect(BridgeLocator.isQuarantined(original))

        let located = try #require(BridgeLocator.locate(candidates: [original], copyDirectory: { copies }))
        #expect(located == copies.appending(path: BridgeLocator.fileName))
        #expect(!BridgeLocator.isQuarantined(located))
        #expect(try Data(contentsOf: located) == bytes)
        #expect(BridgeLocator.isQuarantined(original))                    // the app bundle is never modified

        // A second launch reuses the identical copy; a changed library (app update) is copied again.
        #expect(BridgeLocator.locate(candidates: [original], copyDirectory: { copies }) == located)
        try Data("new build".utf8).write(to: original)
        setQuarantine(original)
        _ = BridgeLocator.locate(candidates: [original], copyDirectory: { copies })
        #expect(try Data(contentsOf: located) == Data("new build".utf8))
    }

    @Test func unquarantinedLibraryIsUsedInPlace() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appending(path: BridgeLocator.fileName)
        try Data("bridge".utf8).write(to: original)
        #expect(BridgeLocator.locate(candidates: [original], copyDirectory: { throw CocoaError(.fileWriteNoPermission) }) == original)
    }

    @Test func interpretersArePlatformBinaries() {
        // The two hosts the chain relies on (R2: still shipped on macOS 27).
        #expect(BridgeConnection.Host.perl.rawValue == "/usr/bin/perl")
        #expect(BridgeConnection.Host.ruby.rawValue == "/usr/bin/ruby")
        #expect(BridgeConnection.Host.perl.arguments(dylib: "/x.dylib").last == "/x.dylib")
        #expect(BridgeConnection.Host.ruby.arguments(dylib: "/x.dylib").first == "-e")
    }
}

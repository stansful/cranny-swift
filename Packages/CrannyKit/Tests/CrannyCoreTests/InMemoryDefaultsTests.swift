import Foundation
import Testing
@testable import CrannyCore

@Suite("In-memory defaults") struct InMemoryDefaultsTests {
    @Test func storesAndConvertsLikeUserDefaults() {
        let defaults = InMemoryDefaults()
        let key = "cranny.inMemoryTest.\(UUID().uuidString)"
        #expect(defaults.object(forKey: key) == nil && !defaults.bool(forKey: key) && defaults.integer(forKey: key) == 0)
        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key) && defaults.integer(forKey: key) == 1)
        defaults.set(2.5, forKey: key)
        #expect(defaults.double(forKey: key) == 2.5 && defaults.integer(forKey: key) == 2)
        defaults.set("YES", forKey: key)
        #expect(defaults.bool(forKey: key) && defaults.string(forKey: key) == "YES")
        defaults.set("42", forKey: key)
        #expect(defaults.integer(forKey: key) == 42)
        defaults.set(Data([1, 2]), forKey: key)
        #expect(defaults.data(forKey: key) == Data([1, 2]) && defaults.string(forKey: key) == nil)
        defaults.set(["a", "b"], forKey: key)
        #expect(defaults.stringArray(forKey: key) == ["a", "b"] && defaults.array(forKey: key)?.count == 2)
        defaults.set(URL(fileURLWithPath: "/tmp/x"), forKey: key)
        #expect(defaults.url(forKey: key)?.path == "/tmp/x")
        #expect(defaults.dictionaryRepresentation()[key] != nil)
        defaults.removeObject(forKey: key)
        #expect(defaults.object(forKey: key) == nil && defaults.dictionaryRepresentation()[key] == nil)
        #expect(UserDefaults.standard.object(forKey: key) == nil)           // nothing reached the real domain
    }

    @Test func registeredDefaultsShowThroughUntilSet() {
        let defaults = InMemoryDefaults()
        defaults.register(defaults: ["volume": 3])
        #expect(defaults.integer(forKey: "volume") == 3)
        defaults.set(7, forKey: "volume")
        #expect(defaults.integer(forKey: "volume") == 7 && defaults.dictionaryRepresentation()["volume"] as? Int == 7)
        defaults.removeObject(forKey: "volume")
        #expect(defaults.integer(forKey: "volume") == 3)
    }

    @MainActor @Test func previewServicesKeepSettingsInMemoryAndApart() {
        let a = CrannyServices.preview(), b = CrannyServices.preview()
        a.settings[CoreSettings.openMode] = .click
        #expect(a.settings[CoreSettings.openMode] == .click)
        #expect(b.settings[CoreSettings.openMode] == .hover)                 // independent stores
        #expect(UserDefaults.standard.data(forKey: "cranny.general.openMode") == nil)
        a.settings.resetAll()
        #expect(a.settings[CoreSettings.openMode] == .hover)
    }

    /// `UserDefaults(suiteName:)` leaves `~/Library/Preferences/<suite>.plist` behind on every run (thousands of files
    /// on contributors' Macs and CI runners). Tests, previews and samples use `InMemoryDefaults` instead; only reads
    /// of a system domain are allowed.
    @Test func noCodeCreatesAPreferencesSuite() throws {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let allowed = ["UserDefaults(suiteName: \"com.apple."]                // reading a system domain
        var hits: [String] = []
        var scanned = 0
        for folder in ["Sources", "Tests"] {
            let root = package.appending(path: folder)
            let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            for file in files where file.lastPathComponent != "InMemoryDefaultsTests.swift" {
                scanned += 1
                for (number, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated() {
                    let code = line.trimmingCharacters(in: .whitespaces)
                    guard !code.hasPrefix("//"), code.contains("UserDefaults(suiteName:"),
                          !allowed.contains(where: code.contains) else { continue }
                    hits.append("\(folder)/\(file.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(scanned > 100)
        #expect(hits.isEmpty, "use InMemoryDefaults(): \(hits)")
    }
}

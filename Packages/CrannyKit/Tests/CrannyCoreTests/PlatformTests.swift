import Foundation
import SwiftUI
import Testing
@testable import CrannyCore

// MARK: - Files

private struct Document: Codable, Equatable, Sendable {
    var title: String
    var items: [Int]
}

@Test func jsonFileStoreRoundTripsAndSetsCorruptFilesAside() async throws {
    let paths = AppPaths.temporary()
    let directory = try paths.directory(for: .notes)
    #expect(directory.path.hasSuffix("/notes"))
    let url = directory.appending(path: "index.json")
    let store = JSONFileStore(url: url, defaultValue: Document(title: "default", items: []))

    #expect(await store.load() == Document(title: "default", items: []))     // missing file → default
    try await store.save(Document(title: "Groceries", items: [1, 2, 3]))
    #expect(await store.load() == Document(title: "Groceries", items: [1, 2, 3]))

    try Data("{ not json".utf8).write(to: url)
    #expect(await store.load() == Document(title: "default", items: []))     // corrupt → default …
    let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(!siblings.contains("index.json"))                                   // … and the file is moved aside,
    #expect(siblings.contains { $0.hasPrefix("index.json.corrupt-") })         // never silently overwritten
    try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent())
}

// MARK: - Processes

@Test func processRunnerCapturesOutput() async throws {
    let out = try await ProcessRunner.run("/bin/echo", ["hello", "Cranny"])
    #expect(out.succeeded)
    #expect(String(decoding: out.stdout, as: UTF8.self) == "hello Cranny\n")
    #expect(out.stderr.isEmpty)
    let failing = try await ProcessRunner.run("/bin/sh", ["-c", "echo oops >&2; exit 3"])
    #expect(failing.status == 3 && String(decoding: failing.stderr, as: UTF8.self) == "oops\n")
    await #expect(throws: ProcessRunError.self) { try await ProcessRunner.run("/nonexistent/tool", []) }
}

@Test func processRunnerTerminatesOnCancellation() async throws {
    let start = Date()
    let task = Task { try await ProcessRunner.run("/bin/sleep", ["30"]) }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    let result = try await task.value
    #expect(!result.succeeded)                                                  // SIGTERM, not a clean exit
    #expect(Date().timeIntervalSince(start) < 10)
}

// MARK: - Registry

@MainActor private enum ProbeModule: FeatureModule {
    static var id: ModuleID { "probe" }
    static func register(in registry: ModuleRegistry) {
        registry.add(settingsPage: SettingsPage(id: "probe", title: "Probe", symbol: "gearshape.fill", tint: .gray,
                                                group: .features, order: 0) { AnyView(EmptyView()) })
        registry.add(settingsPage: SettingsPage(id: "probe.shared", title: "Shared", symbol: "gearshape.fill", tint: .gray,
                                                group: .features, order: 1, namespaces: [.general]) { AnyView(EmptyView()) })
        registry.declare(.camera, reason: "Show a preview.")
        registry.onLaunch { launched.append("probe") }
    }
    static var launched: [String] = []
}

@MainActor @Test func registryAttributesContributionsToTheRegisteringModule() async {
    let registry = ModuleRegistry(services: .preview())
    registry.register(ProbeModule.self)
    #expect(registry.registeringModule == nil)
    #expect(registry.settingsPages.map(\.namespaces) == [["probe"], [.general]])  // empty = the module itself
    #expect(registry.permissionUses == [PermissionUse(kind: .camera, module: "probe", reason: "Show a preview.")])
    #expect(ProbeModule.launched.isEmpty)                                         // nothing runs in register
    await registry.runLaunchHooks()
    #expect(ProbeModule.launched == ["probe"])
}

// MARK: - Settings value types

@MainActor @Test func settingsRoundTripNestedKeyedValues() throws {
    let defaults = InMemoryDefaults()
    let a = SettingsStore(defaults: defaults)
    a[CoreSettings.shortcuts] = [.openNook: KeyCombo.openNookDefault, .togglePin: nil]   // nil = explicitly off
    a[CoreSettings.displaySelection] = .custom(["37D8832A-2D66-02CA-B9F7-8F30A301B230"])
    a[CoreSettings.notchFit] = ["1552-41001": NotchFit(widthTune: -1.5, radiusTune: 0.5)]
    a[CoreSettings.pages] = [NookPreset.maker.page]
    let b = SettingsStore(defaults: defaults)                                         // a fresh store reads the same JSON
    #expect(b[CoreSettings.shortcuts] == [.openNook: KeyCombo.openNookDefault, .togglePin: nil])
    #expect(b[CoreSettings.displaySelection] == .custom(["37D8832A-2D66-02CA-B9F7-8F30A301B230"]))
    #expect(b[CoreSettings.notchFit]["1552-41001"]?.widthTune == -1.5)
    #expect(b[CoreSettings.pages].first?.items.map(\.widget) == [.notes, .todos, .timer, .quickApps])
    defaults.set(Data("garbage".utf8), forKey: "cranny.appearance.density")           // undecodable → default
    #expect(SettingsStore(defaults: defaults)[CoreSettings.density] == .standard)
}

@Test func semanticVersionsParseAndOrder() throws {
    #expect(SemanticVersion("v0.1.0")?.description == "0.1.0")
    #expect(SemanticVersion("1.2.3-rc.1")?.prerelease == "rc.1")
    #expect(SemanticVersion("") == nil && SemanticVersion("one.two") == nil && SemanticVersion("1.2.3.4") == nil)
    #expect(try #require(SemanticVersion("1.0.0-beta.2")) < #require(SemanticVersion("1.0.0-beta.10")))
    #expect(try #require(SemanticVersion("0.9.9")) < #require(SemanticVersion("0.10.0")))
    #expect(!(try #require(SemanticVersion("1.0.0")) < #require(SemanticVersion("1.0.0"))))
}

// MARK: - Effect clock

@Test func effectClockKeepsItsCadenceAndNeverBursts() {
    let clock = ContinuousClock()
    let start = clock.now
    let next = EffectClock<EmptyView>.nextDeadline(after: start, now: start.advanced(by: .milliseconds(5)), interval: 1.0 / 30)
    #expect(next == start.advanced(by: .seconds(1.0 / 30)))                          // on time: one interval later
    let late = start.advanced(by: .seconds(2))                                         // woke from sleep 2 s late
    #expect(EffectClock<EmptyView>.nextDeadline(after: start, now: late, interval: 0.05) == late.advanced(by: .seconds(0.05)))
}

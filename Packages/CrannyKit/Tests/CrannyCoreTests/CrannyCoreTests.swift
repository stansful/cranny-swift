import Foundation
import SwiftUI
import Testing
@testable import CrannyCore

@MainActor @Test func settingsPersistResetAndNamespace() throws {
    let defaults = InMemoryDefaults()
    let key = SettingKey<[Int]>(.timer, "presets", default: [1, 5])
    let a = SettingsStore(defaults: defaults)
    #expect(a[key] == [1, 5] && a.isDefault(key))
    a[key] = [25]
    #expect(SettingsStore(defaults: defaults)[key] == [25])          // persisted (JSON under cranny.timer.presets)
    #expect(defaults.data(forKey: "cranny.timer.presets") != nil)
    a.reset(module: .timer)
    #expect(a[key] == [1, 5])                                          // live box reset
    #expect(defaults.data(forKey: "cranny.timer.presets") == nil)
    a[CoreSettings.activityPreferences] = [.nowPlaying: ActivityPreference(isEnabled: false, peeksOnChange: true)]
    let json = try #require(defaults.data(forKey: "cranny.activities.preferences"))
    #expect(String(decoding: json, as: UTF8.self).contains("\"media.nowPlaying\""))  // dictionary keyed by raw id
    a.resetAll()
    #expect(a[CoreSettings.activityPreferences].isEmpty)
}

/// A key's id is built once from its namespace and name (it is stored, not recomputed per read); keys are equal and
/// hash alike exactly when their ids are, whatever their defaults.
@Test func settingKeysAreIdentifiedByTheirID() {
    let key = SettingKey<Int>(.timer, "presets", default: 1)
    #expect(key.id == "timer.presets")
    #expect(key == SettingKey<Int>(.timer, "presets", default: 2))
    #expect(key != SettingKey<Int>(.timer, "preset", default: 1))
    #expect(Set([key, SettingKey<Int>(.timer, "presets", default: 3)]).count == 1)
}

@Test func swipeCommitsOncePerSequence() {
    var t = SwipeTracker(axis: .horizontal)
    func s(_ p: SwipePhase, _ dx: CGFloat, _ ts: TimeInterval) -> ScrollSample {
        ScrollSample(phase: p, isMomentum: false, deltaX: dx, deltaY: 0, isPrecise: true, isInvertedFromDevice: true, timestamp: ts)
    }
    #expect(t.handle(s(.began, 0, 0)) == nil)
    var updates: [SwipeUpdate] = []
    for i in 1...10 { if let u = t.handle(s(.changed, 6, Double(i) * 0.016)) { updates.append(u) } }
    #expect(updates.contains { if case .committed(.right, _) = $0 { true } else { false } })
    #expect(updates.filter { if case .committed = $0 { true } else { false } }.count == 1)
    #expect(t.handle(s(.ended, 0, 0.2)) == nil)
}

@Test func versions() throws {
    #expect(try #require(SemanticVersion("v1.2")) < #require(SemanticVersion("1.10.0")))
    #expect(try #require(SemanticVersion("1.0.0-beta.2")) < #require(SemanticVersion("1.0.0")))
}

@MainActor @Test func registryFillsPageNamespacesAndActivityOptions() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(settingsPage: SettingsPage(id: "x", title: "X", symbol: "gearshape.fill", tint: .gray, group: .features, order: 0) { AnyView(EmptyView()) })
    #expect(registry.settingsPages.first?.namespaces == [])           // registered outside a module: stays empty (shell)
    let notch = PreviewNotchControl()
    notch.flash(symbol: "hand.wave.fill", label: "Hi")
    #expect(notch.calls == ["flash(hand.wave.fill)"])
    #expect(DelightMoment.allCases.count == 5)
}

@MainActor @Test func resetAllCanBeUndone() throws {
    let defaults = InMemoryDefaults()
    let s = SettingsStore(defaults: defaults)
    s[CoreSettings.openMode] = .click
    s[CoreSettings.panelPaddingTune] = 3
    let snap = s.snapshot()
    s.resetAll()
    #expect(s[CoreSettings.openMode] == .hover)
    s.restore(snap)
    #expect(s[CoreSettings.openMode] == .click && s[CoreSettings.panelPaddingTune] == 3)
    #expect(SettingsStore(defaults: defaults)[CoreSettings.openMode] == .click)
    let g = NookGrid(paddingTune: 3)
    #expect(g.padding == 15 && g.cardRadius == Radius.card && g.panelRadius == 35)
}

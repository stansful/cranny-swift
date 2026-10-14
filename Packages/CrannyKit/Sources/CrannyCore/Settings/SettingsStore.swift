// CrannyCore/Settings/SettingsStore.swift
// Typed, module-namespaced, observable settings persisted in UserDefaults.
import Foundation
import Observation
import os
import SwiftUI

/// A typed settings key. Declare keys as `static let` in the owning module's `<Module>Settings` enum.
/// Stored under "cranny.<module>.<name>" as JSON data. Never rename a key; add a new one and migrate.
public nonisolated struct SettingKey<Value: Codable & Sendable & Equatable>: Sendable, Hashable {
    public let module: ModuleID
    public let name: String
    public let defaultValue: Value
    public init(_ module: ModuleID, _ name: String, default defaultValue: Value) {
        self.module = module; self.name = name; self.defaultValue = defaultValue
    }
    /// "timer.presets"
    public var id: String { "\(module.rawValue).\(name)" }
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// One observable box per key, so a view reading `settings[TimerSettings.presets]` is invalidated
/// only by that key (fine-grained Observation; no global "settings changed" storms).
@MainActor @Observable final class SettingBox<Value: Codable & Sendable & Equatable> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor public final class SettingsStore {
    public static let keyPrefix = "cranny."
    private let defaults: UserDefaults
    private var boxes: [String: AnyObject] = [:]
    private var reloadHandlers: [String: @MainActor () -> Void] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The app uses `.standard` (domain = bundle id). Tests and previews pass `InMemoryDefaults()`, never a
    /// `UserDefaults(suiteName:)`, which would leave a plist in ~/Library/Preferences.
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public subscript<V>(key: SettingKey<V>) -> V {
        get { box(key).value }
        set {
            let b = box(key)
            guard b.value != newValue else { return }
            b.value = newValue
            if newValue == key.defaultValue {
                defaults.removeObject(forKey: Self.keyPrefix + key.id)
            } else if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Self.keyPrefix + key.id)
            }
        }
    }

    /// For SwiftUI controls: `Toggle(isOn: settings.binding(HUDSettings.showValue)) { … }`.
    public func binding<V>(_ key: SettingKey<V>) -> Binding<V> {
        Binding(get: { self[key] }, set: { self[key] = $0 })
    }

    /// Drives the "changed from default" dot and per-row "Reset to Default" (DESIGN.md §11.3).
    public func isDefault<V>(_ key: SettingKey<V>) -> Bool { self[key] == key.defaultValue }
    public func reset<V>(_ key: SettingKey<V>) { self[key] = key.defaultValue }

    /// "Reset ‹Pane›…": every key of a namespace (only keys already read in this session are live-updated;
    /// the others are removed from disk and read back as defaults).
    public func reset(module: ModuleID) { reset(prefix: Self.keyPrefix + module.rawValue + ".") }
    /// "Reset All Settings…". Content (notes, to-dos, tray files) is NOT settings and is kept.
    public func resetAll() { reset(prefix: Self.keyPrefix) }

    /// Opaque copy of every persisted Cranny key: take one before "Reset All" so the 10-s Undo can restore it.
    public nonisolated struct Snapshot: Sendable { fileprivate let values: [String: Data] }
    public func snapshot() -> Snapshot {
        var values: [String: Data] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.keyPrefix) {
            if let data = value as? Data { values[key] = data }
        }
        return Snapshot(values: values)
    }
    /// Replaces every Cranny key with `snapshot` and updates the live values (Undo of "Reset All").
    public func restore(_ snapshot: Snapshot) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        for (key, data) in snapshot.values { defaults.set(data, forKey: key) }
        for handler in reloadHandlers.values { handler() }
    }

    private func reset(prefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        for (id, handler) in reloadHandlers where (Self.keyPrefix + id).hasPrefix(prefix) { handler() }
    }

    private func box<V>(_ key: SettingKey<V>) -> SettingBox<V> {
        if let b = boxes[key.id] as? SettingBox<V> { return b }
        let b = SettingBox(load(key))
        boxes[key.id] = b
        reloadHandlers[key.id] = { [weak self, weak b] in
            guard let self, let b else { return }
            let v = self.load(key)
            if b.value != v { b.value = v }
        }
        return b
    }

    /// The persisted value, or the default (undecodable data is logged and ignored).
    private func load<V>(_ key: SettingKey<V>) -> V {
        guard let data = defaults.data(forKey: Self.keyPrefix + key.id) else { return key.defaultValue }
        if let v = try? decoder.decode(V.self, from: data) { return v }
        Log.logger(.settings).error("undecodable value for \(key.id, privacy: .public); using default")
        return key.defaultValue
    }
}

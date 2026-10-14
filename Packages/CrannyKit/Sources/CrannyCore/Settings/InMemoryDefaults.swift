// CrannyCore/Settings/InMemoryDefaults.swift
// Settings that live in memory only: `CrannyServices.preview()`, unit tests and sample models.
import Foundation
import os

/// A `UserDefaults` that keeps every value in memory and never reads or writes a preferences file.
///
/// `UserDefaults(suiteName:)` is not a substitute: a suite becomes `~/Library/Preferences/<suite>.plist` as soon as
/// one value is written, and `removePersistentDomain(forName:)` still leaves an empty file behind. Pass an
/// `InMemoryDefaults()` to `SettingsStore(defaults:)` (or any API that takes a `UserDefaults`) wherever the values
/// must not outlive the process: previews, tests, sample models.
///
/// Every accessor `SettingsStore` and the typed getters use is overridden, so nothing reaches the standard domain.
/// Unlike a real suite it never falls back to the global domain: a test sets every value it reads.
/// `@unchecked Sendable`: the values are behind a lock.
public nonisolated final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private struct Storage {
        var values: [String: Any] = [:]
        var registered: [String: Any] = [:]
    }

    private let storage = OSAllocatedUnfairLock<Storage>(uncheckedState: Storage())

    // MARK: Objects

    /// The value set for `defaultName`, else its registered default, else nil.
    public override func object(forKey defaultName: String) -> Any? {
        storage.withLockUnchecked { $0.values[defaultName] ?? $0.registered[defaultName] }
    }

    /// Stores `value` (nil removes it). Kept as given: no property-list validation, no copy to disk.
    public override func set(_ value: Any?, forKey defaultName: String) {
        storage.withLockUnchecked { $0.values[defaultName] = value }
    }

    /// Removes the value set for `defaultName`; a registered default shows through again.
    public override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }

    /// Fallback values, as `UserDefaults.register(defaults:)` (in memory there as well).
    public override func register(defaults registrationDictionary: [String: Any]) {
        storage.withLockUnchecked { $0.registered.merge(registrationDictionary) { _, new in new } }
    }

    /// Registered defaults overlaid with the values set.
    public override func dictionaryRepresentation() -> [String: Any] {
        storage.withLockUnchecked { $0.registered.merging($0.values) { _, set in set } }
    }

    // MARK: Typed getters (the semantics of `UserDefaults`: numbers and strings convert, anything else is 0/false/nil)

    /// The value if it is a string; a number is converted to its description.
    public override func string(forKey defaultName: String) -> String? {
        switch object(forKey: defaultName) {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
    /// The value if it is an array.
    public override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    /// The value if it is a dictionary with string keys.
    public override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }
    /// The value if it is data.
    public override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    /// The value if it is an array of strings.
    public override func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }
    /// The value as an integer (a number, or a string that parses as one), else 0.
    public override func integer(forKey defaultName: String) -> Int { number(forKey: defaultName)?.intValue ?? 0 }
    /// The value as a float, else 0.
    public override func float(forKey defaultName: String) -> Float { number(forKey: defaultName)?.floatValue ?? 0 }
    /// The value as a double, else 0.
    public override func double(forKey defaultName: String) -> Double { number(forKey: defaultName)?.doubleValue ?? 0 }
    /// The value as a Boolean: a non-zero number, or "YES"/"true"/"1" (any case), else false.
    public override func bool(forKey defaultName: String) -> Bool {
        if let string = object(forKey: defaultName) as? String {
            return ["yes", "true", "1"].contains(string.lowercased())
        }
        return number(forKey: defaultName)?.boolValue ?? false
    }
    /// The value if it is a URL, or a string that is a file path or URL.
    public override func url(forKey defaultName: String) -> URL? {
        switch object(forKey: defaultName) {
        case let url as URL: url
        case let string as String where string.hasPrefix("/"): URL(fileURLWithPath: (string as NSString).expandingTildeInPath)
        case let string as String: URL(string: string)
        default: nil
        }
    }

    // MARK: Typed setters

    /// Stores an integer.
    public override func set(_ value: Int, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    /// Stores a float.
    public override func set(_ value: Float, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    /// Stores a double.
    public override func set(_ value: Double, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    /// Stores a Boolean.
    public override func set(_ value: Bool, forKey defaultName: String) { set(NSNumber(value: value), forKey: defaultName) }
    /// Stores a URL (nil removes the value).
    public override func set(_ url: URL?, forKey defaultName: String) { set(url as Any?, forKey: defaultName) }

    private func number(forKey defaultName: String) -> NSNumber? {
        switch object(forKey: defaultName) {
        case let number as NSNumber: number
        case let string as String: Double(string.trimmingCharacters(in: .whitespaces)).map { NSNumber(value: $0) }
        default: nil
        }
    }
}

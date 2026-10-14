import CrannyCore
import Foundation
import os
import Testing
@testable import CrannyTodos

/// Settings kept in memory only. `CrannyServices.preview()` backs its settings with
/// `UserDefaults(suiteName: "cranny.preview.<UUID>")`, which leaves a plist in ~/Library/Preferences as soon as a
/// test writes a setting (reported to WP0). These tests write settings, so they use this instead: nothing outside
/// the temporary directories is touched.
///
/// Overrides exactly what `SettingsStore` calls. `@unchecked Sendable`: the values are behind a lock.
nonisolated final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let values = OSAllocatedUnfairLock<[String: Any]>(uncheckedState: [:])

    override func object(forKey defaultName: String) -> Any? { values.withLockUnchecked { $0[defaultName] } }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values.withLockUnchecked { $0[defaultName] = value } }
    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
    override func dictionaryRepresentation() -> [String: Any] { values.withLockUnchecked { $0 } }
}

extension CrannyServices {
    /// `preview(environment:)` with in-memory settings: recording doubles, temporary paths, no haptics.
    @MainActor static func testing(environment: PreviewSystemEnvironment = PreviewSystemEnvironment()) -> CrannyServices {
        CrannyServices(settings: SettingsStore(defaults: InMemoryDefaults()), permissions: PermissionsCenter(),
                       haptics: Haptics(isEnabled: { false }), paths: .temporary(),
                       notch: PreviewNotchControl(), environment: environment, app: PreviewAppControl())
    }
}

extension TodosModel {
    /// `preview(_:)` on `CrannyServices.testing()`.
    static func testing(_ items: [Todo], services: CrannyServices = .testing()) -> TodosModel {
        preview(items, services: services)
    }
}

/// The double behaves like the defaults `SettingsStore` expects.
@MainActor
struct InMemoryDefaultsTests {
    @Test func settingsRoundTripInMemory() {
        let services = CrannyServices.testing()
        #expect(services.settings[TodosSettings.hidesCompleted])
        services.settings[TodosSettings.hidesCompleted] = false
        #expect(!services.settings[TodosSettings.hidesCompleted])
        #expect(!services.settings.isDefault(TodosSettings.hidesCompleted))
        services.settings.reset(module: .todos)
        #expect(services.settings[TodosSettings.hidesCompleted])
    }
}

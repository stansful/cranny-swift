import CrannyCore
import Foundation
import Testing
@testable import CrannyTodos

extension CrannyServices {
    /// `preview(environment:)`: in-memory settings (Core's `InMemoryDefaults`), recording doubles, temporary paths,
    /// no haptics.
    @MainActor static func testing(environment: PreviewSystemEnvironment = PreviewSystemEnvironment()) -> CrannyServices {
        .preview(environment: environment)
    }
}

extension TodosModel {
    /// `preview(_:)` on `CrannyServices.testing()`.
    static func testing(_ items: [Todo], services: CrannyServices = .testing()) -> TodosModel {
        preview(items, services: services)
    }
}

/// A store in a temporary directory whose saves fail until `repair()`: the parent of `todos.json` is a plain file.
@MainActor
struct SaveFailure {
    let paths = AppPaths.temporary()
    let store: TodoStore

    /// Loads an empty list, then saves `items` once, which fails.
    init(_ items: [Todo]) async throws {
        store = TodoStore(storage: TodoStorage(paths: paths), saveDelay: .seconds(60))     // tests save explicitly
        await store.load()
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data().write(to: paths.root.appending(path: "todos"))
        store.update { list in for todo in items { list.insert(todo, after: nil) } }
        await store.save()
    }

    func repair() throws { try FileManager.default.removeItem(at: paths.root.appending(path: "todos")) }

    /// Waits for the retry's save (it runs in a task) to clear the failure.
    func waitUntilSaved() async throws {
        for _ in 0..<100 where store.saveFailed { try await Task.sleep(for: .milliseconds(10)) }
    }

    func model(_ services: CrannyServices) -> TodosModel {
        TodosModel(store: store, settings: services.settings, environment: services.environment,
                   notch: services.notch, feedback: .silent)
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

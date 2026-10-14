// CrannyTodos/UI/TodosPreviewData.swift — sample to-dos for `#Preview`s and for the Settings / onboarding
// stages (`WidgetContext.isPreview`) when the user has none yet. In memory only; never written.
import CrannyCore
import Foundation

extension TodosModel {
    /// Sample to-dos with localized titles (cycled when `count` exceeds the samples); `completed` are checked.
    static func sampleTodos(count: Int = 3, completed: Set<Int> = []) -> [Todo] {
        let titles = TodosStrings.sampleTitles
        let base = Date(timeIntervalSinceReferenceDate: 0)
        return (0..<count).map { i in
            // Stable ids, so previews and stages do not re-identify rows on every render.
            let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x7D, UInt8(truncatingIfNeeded: i)))
            return Todo(id: id, title: titles[i % titles.count], isDone: completed.contains(i),
                        created: base, completed: completed.contains(i) ? base : nil)
        }
    }

    /// A model on `CrannyServices.preview()` holding `items` in memory: no files, no haptics, no sounds.
    static func preview(_ items: [Todo] = sampleTodos(), services: CrannyServices = .preview()) -> TodosModel {
        TodosModel(store: .inMemory(items), settings: services.settings, environment: services.environment,
                   notch: services.notch, feedback: .silent)
    }
}

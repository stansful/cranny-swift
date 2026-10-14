import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

@MainActor
struct TodosModuleTests {
    @Test func registersWithoutSideEffects() throws {
        let registry = ModuleRegistry(services: .testing())
        registry.register(TodosModule.self)
        #expect(TodosModule.id == .todos)
        #expect(registry.registeringModule == nil)
        let notch = try #require(registry.services.notch as? PreviewNotchControl)
        #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
        #expect(registry.permissionUses.isEmpty)          // To-dos needs no permission
        #expect(registry.activities.isEmpty)
    }

    @Test func contributesTheWidgetCommandsAndCaptureTarget() throws {
        let registry = ModuleRegistry(services: .testing())
        registry.register(TodosModule.self)
        let widget = try #require(registry.widget(.todos))
        #expect(widget.title == TodosStrings.title)
        #expect(widget.symbol == "checklist")
        #expect(widget.sizes == WidgetSizes(minimum: 2, preferred: 3, maximum: 6))   // DESIGN.md §6.7
        #expect(!widget.isFrameless)
        #expect(widget.hasOptions)
        #expect(registry.commandProviders.count == 1)
        let capture = try #require(registry.captureTargets.first)
        #expect(capture.id == "todos" && capture.id == TodosModule.captureTargetID)
        #expect(capture.symbol == "checklist")
    }

    @Test func captureCreatesAToDo() throws {
        let registry = ModuleRegistry(services: .testing())
        registry.register(TodosModule.self)
        let capture = try #require(registry.captureTargets.first)
        #expect(capture.capture("h") == .todos)
    }

    @Test func settingsDefaults() {
        #expect(TodosSettings.hidesCompleted.id == "todos.hidesCompleted")
        #expect(TodosSettings.hidesCompleted.defaultValue == true)
    }

    @Test func liveStorageIsTheModuleFile() {
        let services = CrannyServices.testing()
        let model = TodosModel(services: services)
        #expect(model.store.phase == .loading)            // nothing read during registration
        #expect(TodoStorage(paths: services.paths).url.path.hasSuffix("/todos/todos.json"))
    }

    @Test func everySymbolIsFromTheDesignList() {
        // DESIGN.md §14.1 (Notes, to-dos · Header · HUD rows) and all resolve on this macOS.
        for name in ["checklist", "circle", "checkmark.circle.fill", "plus", "exclamationmark"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test func everyStringIsLocalizedInRussian() throws {
        let path = try #require(TodosStrings.bundle.path(forResource: "ru", ofType: "lproj"))
        let russian = try #require(Bundle(path: path))
        for key in ["To-dos", "New to-do", "All done", "No to-dos yet", "Hide completed", "Delete completed",
                    "%lld left", "Couldn’t load your to-dos", "Couldn’t save your to-dos", "Try again", "Edit",
                    "Mark as done", "Mark as not done", "Move up", "Move down", "Delete", "todo task add",
                    "A short list of things to do", "Water the plants", "Reply to Sam", "Book train tickets",
                    "Back up the laptop", "Space checks it, Return edits it, Command-Up and Command-Down move it."] {
            let value = russian.localizedString(forKey: key, value: "\u{0}", table: "Localizable")
            #expect(value != "\u{0}" && value != key, "missing ru for \(key)")
        }
    }
}

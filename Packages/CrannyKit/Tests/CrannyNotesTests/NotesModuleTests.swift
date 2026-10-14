// Registration (contributions, no side effects), ⌘K commands and the editor's key map.
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(NotesModule.self)
    #expect(NotesModule.id == .notes)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
    #expect(!FileManager.default.fileExists(atPath: registry.services.paths.root.path(percentEncoded: false)))   // no I/O
}

@Test func contributesWidgetCaptureShortcutAndCommands() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(NotesModule.self)
    let widget = try #require(registry.widget(.notes))
    #expect(widget.sizes == WidgetSizes(minimum: 3, preferred: 4, maximum: 8))   // DESIGN.md §6.7
    #expect(widget.symbol == "note.text")
    #expect(widget.title == NotesStrings.notes)
    #expect(widget.hasOptions)
    #expect(registry.captureTargets.map(\.id) == ["notes"])
    let shortcut = try #require(registry.shortcuts.first { $0.id == .newNote })
    #expect(shortcut.defaultCombo == nil)                                       // off until the user sets one
    #expect(registry.commandProviders.count == 1)
    #expect(registry.pages.isEmpty && registry.activities.isEmpty && registry.permissionUses.isEmpty)
}

@Test func theShortcutCreatesANoteAndOpensCranny() async throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(NotesModule.self)
    await registry.runLaunchHooks()
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    registry.shortcuts.first { $0.id == .newNote }?.perform()
    #expect(notch.calls.last == "open(-,notes.editor,keyboard)")
    let commands = registry.commandProviders[0].commands(matching: "")
    #expect(commands.count == 2)                                                // New note + the new note
    registry.runTerminateHooks()
    try? FileManager.default.removeItem(at: registry.services.paths.root.deletingLastPathComponent())
}

@Suite("Command palette") struct NotesCommandsTests {
    @Test func listsNewAndEveryNoteAndFilters() {
        let services = CrannyServices.preview()
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        model.adoptLoadedNotes([Note(title: "deploy.md", mode: .code), Note(title: "Groceries", mode: .plain)])
        let commands = NotesCommands(model: model)
        let all = commands.commands(matching: "")
        #expect(all.map(\.title) == [NotesStrings.newNote, NotesStrings.open("deploy.md"), NotesStrings.open("Groceries")])
        #expect(Set(all.map(\.kind)) == [NotesStrings.notes])
        #expect(commands.commands(matching: "groc").map(\.title) == [NotesStrings.open("Groceries")])
        #expect(commands.commands(matching: "DEPLOY").count == 1)
        #expect(commands.commands(matching: "zzz").isEmpty)
        commands.commands(matching: "Groceries").first?.perform()
        #expect(model.selectedEntry?.title == "Groceries")
        let notch = services.notch as? PreviewNotchControl
        #expect(notch?.calls.last == "open(-,notes.editor,keyboard)")
    }
}

@Suite("Editor keys") struct NoteKeyCommandTests {
    private func command(_ characters: String, _ keyCode: UInt16, shift: Bool = false, option: Bool = false,
                         control: Bool = false, command: Bool = true) -> NoteKeyCommand? {
        NoteKeyCommand(characters: characters, keyCode: keyCode, command: command, shift: shift, option: option, control: control)
    }

    @Test func latinLayout() {
        #expect(command("n", 45) == .newNote)
        #expect(command("r", 15) == .rename)
        #expect(command("[", 33) == .previousNote)
        #expect(command("]", 30) == .nextNote)
        #expect(command("/", 44) == .toggleCodeMode)
        #expect(command("\r", 36) == .toggleFocus)
        #expect(command("\u{3}", 76) == .toggleFocus)                            // keypad Enter
        #expect(command("a", 0) == .selectAll)
        #expect(command("c", 8) == .copy)
        #expect(command("x", 7) == .cut)
        #expect(command("v", 9) == .paste)
        #expect(command("z", 6) == .undo)
        #expect(command("Z", 6, shift: true) == .redo)
    }

    @Test func russianLayoutMatchesByKey() {
        #expect(command("с", 8) == .copy)                                       // ⌘C on ЙЦУКЕН
        #expect(command("м", 9) == .paste)
        #expect(command("я", 6) == .undo)
        #expect(command("т", 45) == .newNote)
        #expect(command("х", 33) == .previousNote)
    }

    @Test func otherModifiersDoNotMatch() {
        #expect(command("n", 45, command: false) == nil)
        #expect(command("n", 45, option: true) == nil)
        #expect(command("n", 45, control: true) == nil)
        #expect(command("{", 33, shift: true) == nil)                           // ⇧⌘[ stays the system's
        #expect(command("\r", 36, shift: true) == nil)
        #expect(command("q", 12) == nil)
        #expect(NoteKeyCommand.copy.isTextCommand && !NoteKeyCommand.rename.isTextCommand)
    }
}

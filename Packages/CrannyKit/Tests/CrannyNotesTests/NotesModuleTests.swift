// Registration (contributions, no side effects), ⌘K commands and the editor's key map.
import CrannyCore
import Foundation
import Observation
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
    #expect(registry.captureTargets.first?.widget == .notes)                    // typing goes there only while it is shown
    let shortcut = try #require(registry.shortcuts.first { $0.id == .newNote })
    #expect(shortcut.defaultCombo == nil)                                       // off until the user sets one
    #expect(registry.commandProviders.count == 1)
    #expect(registry.pages.isEmpty && registry.activities.isEmpty && registry.permissionUses.isEmpty)
}

/// Records the Settings panes the module opens (the preview double ignores them).
@MainActor @Observable private final class SettingsRecorder: AppControl {
    private(set) var opened: [SettingsPageID?] = []
    var loginItem: LoginItemState = .disabled
    var update: UpdateState = .idle
    func setLaunchAtLogin(_ enabled: Bool) {}
    func checkForUpdates() {}
    func shortcutState(_ id: ShortcutID) -> ShortcutState { .off }
    func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { .off }
    func openSettings(_ page: SettingsPageID?) { opened.append(page) }
    func showWelcome() {}
    func startTutorial() {}
    func showOnNotch(_ state: PreviewStageState) {}
    func resetAllSettings() {}
    func quit() {}
}

@Test func theShortcutCreatesANoteAndOpensCranny() async throws {
    let preview = CrannyServices.preview()
    let app = SettingsRecorder()
    let services = CrannyServices(settings: preview.settings, permissions: preview.permissions, haptics: preview.haptics,
                                  paths: preview.paths, notch: preview.notch, environment: preview.environment, app: app)
    let registry = ModuleRegistry(services: services)
    registry.register(NotesModule.self)
    await registry.runLaunchHooks()
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    let shortcut = try #require(registry.shortcuts.first { $0.id == .newNote })
    // The default Home has no Notes: no hidden note, no panel without the widget; Layout & Widgets opens instead.
    shortcut.perform()
    #expect(notch.calls.isEmpty && app.opened == [.nookAndWidgets])
    #expect(registry.commandProviders[0].commands(matching: "").isEmpty)
    services.settings[CoreSettings.pages] = [NookPreset.maker.page]
    shortcut.perform()
    #expect(notch.calls.last == "open(nook,notes.editor,keyboard)" && app.opened.count == 1)
    let commands = registry.commandProviders[0].commands(matching: "")
    #expect(commands.count == 2)                                                // New note + the new note
    registry.runTerminateHooks()
    try? FileManager.default.removeItem(at: registry.services.paths.root.deletingLastPathComponent())
}

@Suite("Command palette") struct NotesCommandsTests {
    @Test func listsNewAndEveryNoteAndFilters() {
        let services = CrannyServices.preview()
        services.settings[CoreSettings.pages] = [NookPreset.listener.page,
                                                 NookPage(id: "page.notes", symbol: "note.text", items: [.init(.notes, cells: 4)])]
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
        #expect(notch?.calls.last == "open(page.notes,notes.editor,keyboard)")
    }

    /// Both commands show the note in the widget: while it is on no page (the default Home) none is offered.
    @Test func offersNothingWhileNotesIsOnNoPage() {
        let services = CrannyServices.preview()
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        model.adoptLoadedNotes([Note(title: "Groceries", mode: .plain)])
        let commands = NotesCommands(model: model)
        #expect(commands.commands(matching: "").isEmpty && commands.commands(matching: "groc").isEmpty)
        services.settings[CoreSettings.pages] = [NookPreset.maker.page]
        #expect(commands.commands(matching: "").count == 2)
    }
}

/// A switch the palette's `redactsTitles` closure reads (a captured `var` is not Sendable).
@MainActor private final class Flag {
    var isOn: Bool
    init(_ isOn: Bool) { self.isOn = isOn }
}

@Test func demoRedactionKeepsNoteTitlesOutOfThePalette() {
    let services = CrannyServices.preview()
    services.settings[CoreSettings.pages] = [NookPreset.maker.page]
    let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
    model.adoptLoadedNotes([Note(title: "Salary review", mode: .plain)])
    let redacts = Flag(true)
    let commands = NotesCommands(model: model) { redacts.isOn }
    #expect(commands.commands(matching: "").map(\.title) == [NotesStrings.newNote])
    #expect(commands.commands(matching: "salary").isEmpty)
    redacts.isOn = false
    #expect(commands.commands(matching: "salary").count == 1)
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

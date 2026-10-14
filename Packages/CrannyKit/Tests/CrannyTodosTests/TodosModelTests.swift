import CrannyCore
import Foundation
import Testing
@testable import CrannyTodos

/// Edit flows, completion, linger and feedback, driven through the model with Core's test doubles.
/// No sounds or haptics reach the system: feedback is recorded.
@MainActor
struct TodosModelTests {
    final class FeedbackLog {
        var haptics = 0
        var sounds: [String] = []
    }

    let services: CrannyServices
    let environment: PreviewSystemEnvironment
    let feedback = FeedbackLog()

    init() {
        environment = PreviewSystemEnvironment()
        services = .testing(environment: environment)
    }

    private func model(_ titles: [String] = ["a", "b", "c"], linger: Duration = .milliseconds(10)) -> TodosModel {
        let log = feedback
        return TodosModel(store: .inMemory(titles.map { Todo(title: $0) }), settings: services.settings,
                          environment: environment, notch: services.notch,
                          feedback: TodoFeedback(haptic: { log.haptics += 1 }, sound: { log.sounds.append($0) }),
                          lingerDelay: linger)
    }

    private var notchCalls: [String] { (services.notch as? PreviewNotchControl)?.calls ?? [] }
    private func titles(_ model: TodosModel) -> [String] { model.items.map(\.title) }
    private func visibleTitles(_ model: TodosModel) -> [String] { model.visibleItems.map(\.title) }

    // MARK: Completing

    @Test func completingPlaysAHapticButNoSoundByDefault() {
        let model = model()
        model.toggle(model.items[0].id)
        #expect(model.items[0].isDone)
        #expect(feedback.haptics == 1)
        #expect(feedback.sounds.isEmpty)
        model.toggle(model.items[0].id)                  // unchecking is silent
        #expect(feedback.haptics == 1)
    }

    @Test func tinkPlaysOnlyWithUISoundsAndNeverInDemoMode() {
        let model = model()
        services.settings[CoreSettings.uiSounds] = true
        model.toggle(model.items[0].id)
        #expect(feedback.sounds == ["Tink"])
        environment.isDemoMode = true
        model.toggle(model.items[1].id)
        #expect(feedback.sounds == ["Tink"])
        #expect(TodoFeedback.playsSound(uiSounds: true, isDemoMode: false))
        #expect(!TodoFeedback.playsSound(uiSounds: false, isDemoMode: false))
        #expect(!TodoFeedback.playsSound(uiSounds: true, isDemoMode: true))
    }

    @Test func aCheckedToDoLingersThenCollapses() async throws {
        let model = model()
        let id = model.items[1].id
        model.toggle(id)
        #expect(model.lingering == [id])
        #expect(visibleTitles(model) == ["a", "b", "c"])          // still visible, struck through
        #expect(model.remainingCount == 2)
        let task = try #require(model.lingerTasks[id])
        await task.value
        #expect(model.lingering.isEmpty)
        #expect(visibleTitles(model) == ["a", "c"])
        #expect(titles(model) == ["a", "b", "c"])                 // hidden, not deleted
    }

    @Test func uncheckingWhileLingeringCancelsTheCollapse() async throws {
        let model = model(linger: .seconds(30))
        let id = model.items[0].id
        model.toggle(id)
        let task = try #require(model.lingerTasks[id])
        model.toggle(id)
        await task.value
        #expect(model.lingering.isEmpty && model.lingerTasks.isEmpty)
        #expect(visibleTitles(model) == ["a", "b", "c"])
    }

    @Test func withHideCompletedOffCheckedToDosStay() {
        let model = model()
        services.settings[TodosSettings.hidesCompleted] = false
        model.toggle(model.items[0].id)
        #expect(model.lingering.isEmpty)
        #expect(visibleTitles(model) == ["a", "b", "c"])
        services.settings[TodosSettings.hidesCompleted] = true
        #expect(visibleTitles(model) == ["b", "c"])
    }

    @Test func blankDraftsCannotBeChecked() {
        let model = model([])
        let id = model.beginNew(after: nil)
        model.toggle(id)
        #expect(model.item(id)?.isDone == false)
        #expect(feedback.haptics == 0)
    }

    @Test func checkingTheRowBeingEditedEndsEditing() {
        let model = model()
        model.beginEditing(model.items[0].id)
        model.toggle(model.items[0].id)
        #expect(model.editingID == nil)
        #expect(model.items[0].isDone)
    }

    // MARK: Editing

    @Test func returnKeepsTheTitleAndStartsTheNextRowBelow() throws {
        let model = model(["a", "b"])
        let a = model.items[0].id
        model.beginEditing(a)
        #expect(model.handle(.commit))
        let draft = try #require(model.editingID)
        #expect(draft != a)
        #expect(titles(model) == ["a", "", "b"])
        model.setTitle("a2", for: draft)
        #expect(model.handle(.commit))
        #expect(titles(model) == ["a", "a2", "", "b"])
    }

    @Test func returnOnABlankRowStopsEditingAndDropsIt() {
        let model = model(["a"])
        model.beginNew(after: nil)
        #expect(model.handle(.commit))
        #expect(model.editingID == nil)
        #expect(titles(model) == ["a"])
    }

    @Test func deleteBackwardOnAnEmptyRowDeletesItAndEditsTheRowAbove() throws {
        let model = model(["a", "b"])
        let a = model.items[0].id
        model.beginNew(after: a)
        #expect(model.handle(.deleteBackward))
        #expect(titles(model) == ["a", "b"])
        #expect(model.editingID == a)
    }

    @Test func deleteBackwardWithTextIsOrdinaryEditing() {
        let model = model(["a"])
        model.beginEditing(model.items[0].id)
        #expect(!model.handle(.deleteBackward))
        #expect(titles(model) == ["a"])
    }

    @Test func deleteBackwardOnTheOnlyRowSelectsNewToDo() {
        let model = model([])
        model.beginNew(after: nil)
        #expect(model.handle(.deleteBackward))
        #expect(model.items.isEmpty && model.editingID == nil)
        #expect(model.selectionRequest?.selection == .newRow)
    }

    @Test func escapeTrimsTheTitleAndAsksForTheRowToBeSelected() {
        let model = model(["a"])
        let id = model.items[0].id
        model.beginEditing(id)
        model.setTitle("  walk the dog  ", for: id)
        #expect(model.handle(.cancel))
        #expect(model.editingID == nil)
        #expect(titles(model) == ["walk the dog"])
        #expect(model.selectionRequest?.selection == .item(id))
        model.clearSelectionRequest()
        #expect(model.selectionRequest == nil)
    }

    @Test func escapeOnABlankDraftSelectsTheRowAbove() {
        let model = model(["a"])
        let a = model.items[0].id
        model.beginNew(after: a)
        #expect(model.handle(.cancel))
        #expect(titles(model) == ["a"])
        #expect(model.selectionRequest?.selection == .item(a))
    }

    @Test func arrowsInTheEditorMoveToTheNeighbour() {
        let model = model(["a", "b"])
        let (a, b) = (model.items[0].id, model.items[1].id)
        model.beginEditing(a)
        #expect(!model.handle(.previous))                   // first row: the field keeps the key
        #expect(model.handle(.next))
        #expect(model.editingID == b)
        #expect(!model.handle(.next))
        #expect(model.handle(.previous))
        #expect(model.editingID == a)
    }

    @Test func commandArrowsInTheEditorReorderAndKeepEditing() {
        let model = model(["a", "b"])
        let a = model.items[0].id
        model.beginEditing(a)
        #expect(model.handle(.moveDown))
        #expect(titles(model) == ["b", "a"])
        #expect(model.editingID == a)
        #expect(model.handle(.moveUp))
        #expect(titles(model) == ["a", "b"])
    }

    @Test func editorKeysAreIgnoredWhenNothingIsEdited() {
        let model = model()
        #expect(!model.handle(.commit))
        #expect(!model.handle(.cancel))
    }

    @Test func newNeverStacksTwoDrafts() {
        let model = model(["a"])
        let first = model.beginNew(after: nil)
        let second = model.beginNew(after: nil)
        #expect(first == second)
        #expect(titles(model) == ["a", ""])
        // Starting one elsewhere drops the blank draft.
        model.beginNew(after: model.items[0].id)
        #expect(titles(model) == ["a", ""])
        #expect(model.items[1].id != first)
    }

    @Test func focusLeavingTheEditorEndsEditingOnlyForThatRow() {
        let model = model(["a", "b"])
        let (a, b) = (model.items[0].id, model.items[1].id)
        model.beginEditing(b)
        model.editorDidEnd(a)                               // a stale field going away
        #expect(model.editingID == b)
        model.editorDidEnd(b)
        #expect(model.editingID == nil)
    }

    @Test func theEditorAsksForKeyboardFocus() {
        let model = model()
        model.editorDidBegin()
        #expect(notchCalls == ["key"])
    }

    @Test func closingTheNookEndsEditing() async {
        let model = model(["a"])
        await model.start()
        model.beginNew(after: nil)
        (services.notch as? PreviewNotchControl)?.emit(.closed)
        #expect(model.editingID == nil)
        #expect(titles(model) == ["a"])
    }

    @Test func changingThePageEndsEditing() async {
        let model = model(["a"])
        await model.start()
        model.beginEditing(model.items[0].id)
        (services.notch as? PreviewNotchControl)?.emit(.pageChanged(.tray))
        #expect(model.editingID == nil)
        (services.notch as? PreviewNotchControl)?.emit(.pinned(true))      // other events leave it alone
        model.beginEditing(model.items[0].id)
        (services.notch as? PreviewNotchControl)?.emit(.pinned(false))
        #expect(model.editingID == model.items[0].id)
    }

    @Test func titlesTypedIntoTheEditorAreSanitized() {
        let model = model(["a"])
        model.setTitle("x\ny", for: model.items[0].id)
        #expect(titles(model) == ["x y"])
    }

    // MARK: Ordering, deleting, Undo

    @Test func moveSkipsHiddenCompletedToDos() async throws {
        let model = model(["a", "b", "c"])
        let (b, c) = (model.items[1].id, model.items[2].id)
        model.toggle(b)
        await model.lingerTasks[b]?.value
        #expect(model.canMove(c, .up) && !model.canMove(c, .down))
        #expect(model.move(c, .up))
        #expect(visibleTitles(model) == ["c", "a"])
        #expect(!model.move(c, .up))
    }

    @Test func deleteAndUndoPutsItBack() throws {
        let model = model(["a", "b", "c"])
        let removal = try #require(model.delete(model.items[1].id))
        #expect(titles(model) == ["a", "c"])
        model.restore([removal])
        #expect(titles(model) == ["a", "b", "c"])
    }

    @Test func deletingTheEditedRowStopsEditing() {
        let model = model(["a"])
        model.beginEditing(model.items[0].id)
        model.delete(model.items[0].id)
        #expect(model.editingID == nil && model.items.isEmpty)
    }

    @Test func undoManagerRestoresAndRedoesDeletions() throws {
        let model = model(["a", "b", "c", "d"])
        model.toggle(model.items[0].id)
        model.toggle(model.items[2].id)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        TodoUndo.registerRestore(model.deleteCompleted(), model: model, undoManager: undo, actionName: "Delete completed")
        undo.endUndoGrouping()
        #expect(titles(model) == ["b", "d"])
        #expect(undo.undoActionName == "Delete completed")
        undo.undo()
        #expect(titles(model) == ["a", "b", "c", "d"])
        #expect(model.items[0].isDone && model.items[2].isDone)
        undo.redo()
        #expect(titles(model) == ["b", "d"])
        undo.undo()
        #expect(titles(model) == ["a", "b", "c", "d"])
    }

    // MARK: Capture, selection, check style

    @Test func typeToCaptureStartsAToDoWithTheTypedText() throws {
        let model = model(["a"])
        #expect(model.capture("b") == .todos)
        let id = try #require(model.editingID)
        #expect(model.item(id)?.title == "b")
        #expect(titles(model) == ["a", "b"])
    }

    @Test func selectionRequestsAreSerialised() {
        let model = model()
        model.requestSelection(.newRow)
        let first = model.selectionRequest
        model.requestSelection(.newRow)
        #expect(first != model.selectionRequest)
    }

    @Test func checkStyleFollowsTheEnvironment() {
        let model = model()
        #expect(model.checkStyle(personality: .lively, reduceMotion: false) == .drawWithMotes)
        environment.isFullScreenInFront = true
        #expect(model.checkStyle(personality: .lively, reduceMotion: false) == .instant)
        environment.isFullScreenInFront = false
        environment.areLiveActivitiesPaused = true
        #expect(model.checkStyle(personality: .standard, reduceMotion: false) == .instant)
    }

    @Test func flushEndsEditing() {
        let model = model(["a"])
        model.beginNew(after: nil)
        model.flush()
        #expect(model.editingID == nil)
        #expect(titles(model) == ["a"])
    }
}

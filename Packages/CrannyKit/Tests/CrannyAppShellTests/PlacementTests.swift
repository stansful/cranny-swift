// Where things land on the open panel (DESIGN.md §7.5, ARCHITECTURE.md §3.9, §4.12): type-to-capture only reaches a
// widget that is on a page, and `NotchControl.open(focus:)` opens the page that shows the widget. No windows are
// shown: key events go straight to the router of a panel never ordered in.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
@testable import CrannyAppShell

@MainActor private struct Fixture {
    let registry = ModuleRegistry(services: .preview())
    let viewModel: NotchViewModel
    var settings: SettingsStore { registry.services.settings }
    var scene: NotchSceneModel { viewModel.scene }

    init() {
        viewModel = NotchViewModel(scene: NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme()),
                                   registry: registry)
        viewModel.pointerKeys = { (false, false) }                              // never the real mouse or keyboard
    }
}

/// A capture target like Notes' that records what it was given.
@MainActor private final class CaptureLog {
    var typed: [String] = []
}

private func keyEvent(_ characters: String, keyCode: UInt16, in window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                     context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                     keyCode: keyCode)
}

/// C-SHELL-1: the default Home has no Notes. Typing after ⌃⌥N must not create a note nobody sees; the key stays with
/// the panel. With Notes on a page the first key starts the note there and that page shows.
@Test func typeToCaptureNeedsItsWidgetOnAPage() throws {
    _ = NSApplication.shared
    let f = Fixture()
    let log = CaptureLog()
    f.registry.add(captureTarget: CaptureTarget(id: "notes", title: "Notes", symbol: "note.text", widget: .notes) { text in
        log.typed.append(text)
        return .notes
    })
    let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    defer { panel.close() }
    panel.contentView = NSView(frame: panel.frame)
    let router = KeyboardRouter(panel: panel, viewModel: f.viewModel, registry: f.registry)
    #expect(f.settings[CoreSettings.typeToCapture] == "notes")                // the default target

    f.viewModel.send(.hotKey)                                                   // the default Listener Home: no Notes
    #expect(router.captureTarget() == nil)
    let h = try #require(keyEvent("h", keyCode: 4, in: panel))
    #expect(router.handleKeyDown(h) === h)                                      // passed on, not consumed
    #expect(log.typed.isEmpty && f.viewModel.state.openState?.focus == nil)
    f.viewModel.send(.close)
    router.panelClosed()

    f.settings[CoreSettings.pages] = [NookPreset.listener.page,
                                      NookPage(id: "page.notes", symbol: "note.text", items: [.init(.notes, cells: 4)])]
    f.viewModel.send(.hotKey)
    #expect(router.handleKeyDown(try #require(keyEvent("h", keyCode: 4, in: panel))) == nil)
    #expect(log.typed == ["h"])
    #expect(f.scene.open?.page == "page.notes" && f.scene.context.focusedWidget == .notes)
}

/// A target that names no widget (a third-party one) is always captured, as before.
@Test func aCaptureTargetWithoutAWidgetIsAlwaysOffered() {
    _ = NSApplication.shared
    let f = Fixture()
    f.registry.add(captureTarget: CaptureTarget(id: "journal", title: "Journal", symbol: "book") { _ in .notes })
    f.settings[CoreSettings.typeToCapture] = "journal"
    let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    defer { panel.close() }
    let router = KeyboardRouter(panel: panel, viewModel: f.viewModel, registry: f.registry)
    #expect(router.captureTarget()?.id == "journal")
}

/// C-SHELL-10: "Show today's events" and the Start timer shortcut ask for Home; the widget may be on another page
/// (it opens there) or on none (the panel opens without a focus nobody could see).
@Test func openingAtAWidgetShowsThePageThatHoldsIt() {
    let f = Fixture()
    f.settings[CoreSettings.pages] = [NookPreset.minimal.page,
                                      NookPage(id: "page.work", symbol: "calendar", items: [.init(.calendar, cells: 4)])]
    f.viewModel.send(.open(page: .nook, focus: .calendar, reason: .keyboard))
    #expect(f.scene.open?.page == "page.work" && f.scene.context.focusedWidget == .calendar)
    f.viewModel.send(.close)
    f.viewModel.send(.open(page: nil, focus: .calendar, reason: .programmatic))
    #expect(f.scene.open?.page == "page.work")
    f.viewModel.send(.close)
    f.viewModel.send(.open(page: .nook, focus: .timer, reason: .keyboard))     // on no page
    #expect(f.scene.open?.page == .nook && f.scene.open?.focus == nil)
    f.viewModel.send(.close)
    f.viewModel.send(.open(page: .nook, focus: .media, reason: .keyboard))     // already there: unchanged
    #expect(f.scene.open == OpenState(page: .nook, focus: .media, reason: .keyboard))
}

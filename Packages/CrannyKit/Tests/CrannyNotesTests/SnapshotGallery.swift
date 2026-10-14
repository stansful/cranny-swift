// Opt-in visual QA without a display: renders Notes cards (real AppKit editor included) in an offscreen window
// and writes PNGs. Run with
//   CRANNY_SNAPSHOT_DIR=/path/to/dir swift test --scratch-path .build-test --filter CrannyNotesTests.SnapshotGallery
// (into /path/to/dir/Notes).
// Nothing is shown on screen and nothing outside the given folder and temporary paths is written.
// Debug builds only: the typing-effect case uses the DEBUG-only `NotesQAHooks`.
#if DEBUG
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotes

@Suite("Snapshot gallery", .enabled(if: SnapshotOutput.directory("Notes") != nil))
struct SnapshotGallery {
    private let folder = SnapshotOutput.directory("Notes") ?? URL(filePath: "/dev/null")

    private struct Case {
        var name: String
        var cells = 4
        var rows = 2
        var select = 0
        var notes = true
        /// Notes after the standard five (`select` counts them too).
        var extra: [Note] = []
        var theme = CrannyTheme()
        var context: (inout WidgetContext) -> Void = { _ in }
        var prepare: (NotesModel) -> Void = { _ in }
    }

    private static let notes: [Note] = [
        Note(title: "deploy.md", text: "## Release\nlet build = \"1.4.2\"\nretry(3) // flaky CI\n- [ ] tag `v1.4.2` and **ship** it\n> see https://cranny.app/notes\n", mode: .code),
        Note(title: "Weekend", text: "Oat milk, lemons, basil\nCall the bike shop before noon\nReturn the library books\nBook a table for Saturday", mode: .plain),
        Note(title: "build.swift", text: "import SwiftUI\n\n@MainActor struct Card: View {\n    let title: String // shown on top\n    var body: some View {\n        Text(title).padding(12)\n    }\n}\n/* TODO: dark mode */\nlet retries = 0x1F\n", mode: .code),
        Note(title: "Список дел", text: "Позвонить в сервис до обеда\nКупить лимоны и базилик\nВернуть книги в библиотеку", mode: .plain),
        Note(title: "Untitled", text: "", mode: .plain),
    ]

    private static let longNote = Note(title: "long.md", text: String(repeating: "## Section\nSome *emphasis* and "
        + "**strong** text with `code` and [a link](https://example.com).\n```swift\nlet retries = 3 // flaky CI\n```\n> quote\n\n",
        count: 1_300), mode: .code)

    @Test func renderGallery() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var highContrast = CrannyTheme(); highContrast.increaseContrast = true
        var large = CrannyTheme(); large.textSize = .extraLarge
        let cases: [Case] = [
            Case(name: "01-code-4"),
            Case(name: "02-plain-4", select: 1),
            Case(name: "03-wide-8", cells: 8, select: 2),
            Case(name: "04-wide-6", cells: 6, select: 2),
            Case(name: "05-russian-3", cells: 3, select: 3),
            Case(name: "06-placeholder", select: 4),
            Case(name: "07-delete", select: 1, prepare: { $0.requestDelete() }),
            Case(name: "08-rename-savefailed", prepare: { $0.renamingID = $0.selectedID; $0.saveFailed = true }),
            Case(name: "09-empty-state", notes: false),
            Case(name: "10-preview-stage", context: { $0.isPreview = true }),
            Case(name: "11-redacted", context: { $0.redactsPersonalData = true }),
            Case(name: "12-focus-3-rows", cells: 12, rows: 3, select: 2),
            Case(name: "13-high-contrast", select: 2, theme: highContrast),
            Case(name: "14-xl-text", select: 1, theme: large),
            Case(name: "15-typing-effect", select: 1, prepare: { _ in NotesQAHooks.actions = ["typing"] }),
            // About 100 000 units: tokenized off the main actor and coloured in slices; the top must end up coloured.
            Case(name: "16-long-note-8", cells: 8, select: 5, extra: [Self.longNote]),
        ]
        for item in cases {
            NotesQAHooks.actions = []
            try await render(item)
        }
        NotesQAHooks.actions = []
    }

    private func render(_ item: Case) async throws {
        let services = CrannyServices.preview()
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        model.adoptLoadedNotes(item.notes ? Self.notes + item.extra : [])
        if item.notes { model.select(model.entries[item.select].id) }
        item.prepare(model)
        var grid = item.theme.grid
        grid.rows = item.rows
        let inset = grid.density.cardPadding
        var context = WidgetContext(cells: item.cells, rows: item.rows,
                                    contentSize: CGSize(width: grid.width(cells: item.cells) - 2 * inset, height: grid.height - 2 * inset))
        item.context(&context)
        let card = NotesWidgetView(model: model, settings: services.settings, context: context)
            .padding(inset)
            .frame(width: grid.width(cells: item.cells), height: grid.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: grid.cardRadius, style: .continuous).fill(item.theme.palette.card))
            .clipShape(RoundedRectangle(cornerRadius: grid.cardRadius, style: .continuous))
            .padding(Space.l)
            .background(Color.black)
            .crannyThemeRoot(item.theme)
        let size = CGSize(width: grid.width(cells: item.cells) + 2 * Space.l, height: grid.height + 2 * Space.l)
        let host = NSHostingView(rootView: card)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        for _ in 0..<6 {                                                        // let SwiftUI and the editor settle
            host.layoutSubtreeIfNeeded()
            host.display()
            try await Task.sleep(for: .milliseconds(60))
        }
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appending(path: "\(item.name).png"))
        window.contentView = nil
        try? FileManager.default.removeItem(at: services.paths.root.deletingLastPathComponent())
    }
}
#endif

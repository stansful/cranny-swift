// CrannyNotchUI/Nook/CommandPaletteView.swift — ⌘K (DESIGN.md §6.4). It replaces the grid area at the same
// height, so the shape does not move: a 28-pt search field in a `well` (r 8), then up to 4 rows of 22 pt —
// icon 16 · title (`body`) · kind (`caption`, tertiary) · shortcut as a `KeyCap`. ↑ ↓ choose, ↩ runs the
// command and returns to the grid, Esc returns to the grid. Commands come from `registry.commandProviders`, searched
// once per evaluation (a keystroke evaluates it once; the selection is written only when it changes).
import CrannyCore
import Foundation
import SwiftUI

struct CommandPaletteView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext.isPreview) private var isPreview
    @FocusState private var fieldFocused: Bool
    @State private var query = ""
    @State private var selection = PaletteSelection()
    let registry: ModuleRegistry
    let height: CGFloat
    let setMode: @MainActor (NookMode) -> Void

    var body: some View {
        let results = self.results
        let visible = PaletteSelection.visibleRows(height: height)
        VStack(alignment: .leading, spacing: PaletteMetrics.gap) {
            field(results: results, visible: visible)
            if results.isEmpty {
                Text("No matching commands", bundle: .module, comment: "Command palette: empty result list")
                    .crannyFont(.caption)
                    .foregroundStyle(theme.palette.tertiaryLabel)
                    .padding(.horizontal, Space.m)
                    .frame(height: PaletteRow.height)
            } else {
                VStack(spacing: 0) {
                    let window = Array(results.enumerated()).dropFirst(selection.firstVisible).prefix(visible)
                    ForEach(window, id: \.element.id) { index, command in
                        PaletteRow(command: command, isSelected: index == selection.index)
                            .onTapGesture { run(command) }
                            .onHover { if $0, selection.index != index { selection.index = index } }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Results", bundle: .module, comment: "Command palette: VoiceOver name of the result list"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: PaletteQuery(text: query, results: results.count)) { _, new in
            var next = PaletteSelection()
            next.clamp(count: new.results, visible: visible)
            if next != selection { selection = next }
        }
        .onAppear {
            // Typing goes to the panel: make it key first (without activating the app), then focus the field on the
            // next turn of the run loop, once the window can hold a first responder.
            if !isPreview { registry.services.notch.requestKeyboardFocus() }
            Task { @MainActor in fieldFocused = true }
        }
    }

    private func field(results: [PaletteCommand], visible: Int) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .notchGlyph(.field)
                .foregroundStyle(theme.palette.tertiaryLabel)
                .accessibilityHidden(true)
            TextField(text: $query) {
                Text("Search commands", bundle: .module, comment: "Command palette: search field placeholder")
            }
            .textFieldStyle(.plain)
            .crannyFont(.body)
            .focused($fieldFocused)
            .onSubmit { if results.indices.contains(selection.index) { run(results[selection.index]) } }
            .onKeyPress(.downArrow) { selection.move(by: 1, count: results.count, visible: visible); return .handled }
            .onKeyPress(.upArrow) { selection.move(by: -1, count: results.count, visible: visible); return .handled }
            .onExitCommand { setMode(.grid) }
            KeyCap("esc")
        }
        .padding(.horizontal, Space.m)
        .frame(height: PaletteMetrics.fieldHeight)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(theme.palette.well))
    }

    /// Every provider's matches, best first (`PaletteSearch`).
    private var results: [PaletteCommand] {
        let all = registry.commandProviders.flatMap { $0.commands(matching: query) }
        return PaletteSearch.order(all.map { ($0.title, $0.keywords) }, query: query).map { all[$0] }
    }

    private func run(_ command: PaletteCommand) {
        setMode(.grid)
        command.perform()
    }
}

/// The query with the number of results the evaluation that saw it found. Equal when the text is, so the palette
/// resets its selection when the query changes (not when a provider's list does), and clamps it to the count that
/// came with the new text, without searching again.
private nonisolated struct PaletteQuery: Equatable, Sendable {
    let text: String
    let results: Int

    static func == (a: PaletteQuery, b: PaletteQuery) -> Bool { a.text == b.text }
}

/// One 22-pt result row.
private struct PaletteRow: View {
    @Environment(\.cranny) private var theme
    let command: PaletteCommand
    let isSelected: Bool

    static let height = PaletteMetrics.rowHeight

    var body: some View {
        let p = theme.palette
        HStack(spacing: Space.m) {
            Image(systemName: command.symbol)
                .notchGlyph(.paletteRow)
                .frame(width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize)
                .foregroundStyle(p.secondaryLabel)
                .accessibilityHidden(true)
            Text(verbatim: command.title).crannyFont(.body).foregroundStyle(p.label).lineLimit(1)
            Text(verbatim: command.kind).crannyFont(.caption).foregroundStyle(p.tertiaryLabel).lineLimit(1)
            Spacer(minLength: Space.s)
            if let shortcut = command.shortcut { KeyCap(shortcut.display) }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(isSelected ? p.controlPressed : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: command.title))
        .accessibilityValue(Text(verbatim: command.kind))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text(verbatim: command.shortcut?.display ?? ""))
    }
}

#Preview("Palette") {
    let (model, registry) = previewScene(.open, palette: true)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}

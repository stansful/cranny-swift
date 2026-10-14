// CrannyNotchUI/Nook/CardOverflowMenu.swift — a card's ⋯ menu (DESIGN.md §6.8): Options…, Resize ▸, Remove,
// Edit Layout…. Three ways in, one set of commands: the 20-pt `ellipsis` button on hover (an `NSMenu`, which
// holds the panel open while it tracks), ⌘. on a focused card (a keyboard-navigable list), and VoiceOver
// actions on the card.
import CrannyCore
import Foundation
import SwiftUI

/// The hover button and its menu.
struct CardOverflowMenu: View {
    @Environment(\.cranny) private var theme
    let widget: WidgetID
    let hasOptions: Bool
    let cells: Int
    let commands: CardCommands
    let showOptions: @MainActor () -> Void

    var body: some View {
        Menu {
            if hasOptions {
                Button(action: showOptions) { CardStrings.options }
            }
            let sizes = commands.allowedSizes(widget)
            if sizes.count > 1 {
                Menu {
                    ForEach(sizes, id: \.self) { n in
                        Toggle(isOn: Binding(get: { n == cells }, set: { if $0 { commands.resize(widget, n) } })) {
                            CardStrings.cells(n)
                        }
                    }
                } label: { CardStrings.resize }
            }
            Button(role: .destructive) { commands.remove(widget) } label: { CardStrings.remove }
            Divider()
            Button(action: commands.editLayout) { CardStrings.editLayout }
        } label: {
            Image(systemName: "ellipsis")
                .notchGlyph(.overflow)
                .foregroundStyle(theme.palette.tertiaryLabel)
                .frame(width: CardOverflowMenu.size, height: CardOverflowMenu.size)
                .background(Circle().fill(theme.palette.control))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: HitTarget.nook.width, height: HitTarget.nook.height, alignment: .topTrailing)
        .contentShape(Rectangle())
        .help(String(localized: "More", bundle: .module, comment: "Widget card: the ⋯ button that opens the card's menu"))
        .accessibilityLabel(Text("More", bundle: .module, comment: "Widget card: the ⋯ button that opens the card's menu"))
    }

    /// The visible glyph (DESIGN.md §6.8); the hit area is 28 × 24.
    static let size: CGFloat = 20
}

/// The same commands as a list, for ⌘. on a focused card (↑ ↓ and ↩ work; Esc closes the popover).
struct CardActionsList: View {
    let widget: WidgetID
    let hasOptions: Bool
    let cells: Int
    let commands: CardCommands
    let showOptions: @MainActor () -> Void
    let done: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if hasOptions {
                Button { showOptions() } label: { CardStrings.options }
            }
            let sizes = commands.allowedSizes(widget)
            if sizes.count > 1 {
                ForEach(sizes, id: \.self) { n in
                    Button { commands.resize(widget, n); done() } label: {
                        Label { CardStrings.cells(n) } icon: { Image(systemName: n == cells ? "checkmark" : "square.resize") }
                    }
                }
            }
            Button(role: .destructive) { commands.remove(widget); done() } label: { CardStrings.remove }
            Button { commands.editLayout(); done() } label: { CardStrings.editLayout }
        }
        .buttonStyle(.borderless)
        .padding(Space.m)
        .frame(minWidth: Self.minimumWidth, alignment: .leading)
    }

    /// Wide enough for "Edit layout…" in Russian without wrapping.
    static let minimumWidth: CGFloat = 180
}

/// VoiceOver actions of a card (DESIGN.md §6.8: the menu is also a VoiceOver action): Options…, Wider and
/// Narrower (the Resize submenu, one allowed width at a time), Remove, Edit Layout… (not while editing).
struct CardAccessibilityActions: View {
    let widget: WidgetID
    let hasOptions: Bool
    /// The width the card is drawn at.
    let cells: Int
    let isEditing: Bool
    let commands: CardCommands
    let showOptions: @MainActor () -> Void

    var body: some View {
        if hasOptions {
            Button(action: showOptions) { CardStrings.options }
        }
        let step = CardAccessibilityActions.resizeSteps(cells: cells, allowed: commands.allowedSizes(widget))
        if let wider = step.wider {
            Button { commands.resize(widget, wider) } label: { CardStrings.wider }
        }
        if let narrower = step.narrower {
            Button { commands.resize(widget, narrower) } label: { CardStrings.narrower }
        }
        Button { commands.remove(widget) } label: { CardStrings.remove }
        if !isEditing {
            Button(action: commands.editLayout) { CardStrings.editLayout }
        }
    }

    /// The next allowed width up and down from `cells` (nil = none). Pure.
    nonisolated static func resizeSteps(cells: Int, allowed: [Int]) -> (wider: Int?, narrower: Int?) {
        (allowed.filter { $0 > cells }.min(), allowed.filter { $0 < cells }.max())
    }
}

/// The card menu's titles (sentence case, DESIGN.md §17).
enum CardStrings {
    static var options: Text { Text("Options…", bundle: .module, comment: "Widget card menu: the widget's options popover") }
    static var resize: Text { Text("Resize", bundle: .module, comment: "Widget card menu: submenu of widths in cells") }
    static var remove: Text { Text("Remove", bundle: .module, comment: "Widget card menu: removes the widget from the page") }
    static var editLayout: Text { Text("Edit layout…", bundle: .module, comment: "Widget card menu: enters the layout editor (⌘E)") }
    static var wider: Text { Text("Wider", bundle: .module, comment: "Widget card: VoiceOver action, one allowed width wider") }
    static var narrower: Text { Text("Narrower", bundle: .module, comment: "Widget card: VoiceOver action, one allowed width narrower") }
    static func cells(_ n: Int) -> Text {
        Text("\(n) cells", bundle: .module, comment: "Widget card menu and layout editor: a widget's width in grid cells")
    }
}

#Preview("Overflow button") {
    CardOverflowMenu(widget: .media, hasOptions: true, cells: 5, commands: CardCommands(), showOptions: {})
        .padding()
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

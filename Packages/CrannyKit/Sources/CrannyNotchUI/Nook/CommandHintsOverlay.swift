// CrannyNotchUI/Nook/CommandHintsOverlay.swift — hold ⌘ for hints (DESIGN.md §6.5): while
// `notchShowsCommandHints` is on (the shell sets it after ⌘ is held 0.5 s), every tab and header
// action shows its shortcut as a `KeyCap` in place of its glyph; on release the glyph comes back. VoiceOver
// gets the same shortcuts as accessibility hints instead (key caps are hidden from it).
import CrannyCore
import SwiftUI

/// Shows `content`, or the key cap of `shortcut` while hints are visible.
struct HintSwap<Content: View>: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchShowsCommandHints) private var showsCommandHints
    let shortcut: NookShortcut?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let showsHint = showsCommandHints && shortcut != nil
        ZStack {
            content().opacity(showsHint ? 0 : 1)
            if showsHint, let shortcut {
                KeyCap(shortcut.display)
                    .transition(.opacity)
            }
        }
        .animation(theme.animation(.contentSwap), value: showsHint)
    }
}

extension View {
    /// The shortcut as a VoiceOver hint ("⌘K"), so it is never pointer-only (DESIGN.md §6.5).
    func shortcutHint(_ shortcut: NookShortcut?) -> some View {
        modifier(ShortcutHint(shortcut: shortcut))
    }
}

/// Always applied (an empty hint reads nothing), so the control keeps its identity.
struct ShortcutHint: ViewModifier {
    let shortcut: NookShortcut?
    func body(content: Content) -> some View {
        content.accessibilityHint(Text(verbatim: shortcut?.display ?? ""))
    }
}

#Preview("Hints · on") {
    HStack(spacing: Space.m) {
        HintSwap(shortcut: NookKeyMap.palette) { Image(systemName: "magnifyingglass") }
        HintSwap(shortcut: NookKeyMap.pin) { Image(systemName: "pin") }
        HintSwap(shortcut: NookKeyMap.page(0)) { Image(systemName: "square.grid.2x2.fill") }
    }
    .foregroundStyle(.white)
    .padding()
    .background(.black)
    .environment(\.notchShowsCommandHints, true)
    .crannyThemeRoot(CrannyTheme())
}

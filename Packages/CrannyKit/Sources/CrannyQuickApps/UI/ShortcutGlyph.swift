// CrannyQuickApps/UI/ShortcutGlyph.swift — the shortcut squircle (DESIGN.md §7.3): a continuous squircle in the
// shortcut's colour with its SF Symbol or first letter in white. `size` is an ICON canvas, like an app icon's: the
// squircle sits on the macOS icon grid inside it (`IconGrid`), so shortcuts and apps line up. Used by the launcher,
// Settings and menus, so it reads no notch tokens: the glyph on a content colour is always white.
import AppKit
import CrannyCore
import SwiftUI

struct ShortcutGlyph<Overlay: View>: View {
    let entry: ShortcutEntry
    let size: CGFloat
    /// Demo-mode redaction: a neutral glyph instead of the shortcut's letter (its name may be personal).
    var redacted = false
    private let overlay: Overlay?

    init(entry: ShortcutEntry, size: CGFloat, redacted: Bool = false) where Overlay == EmptyView {
        self.entry = entry; self.size = size; self.redacted = redacted; self.overlay = nil
    }

    /// `overlay` replaces the glyph (the running ring, the success check).
    init(entry: ShortcutEntry, size: CGFloat, redacted: Bool = false, @ViewBuilder replacingGlyph overlay: () -> Overlay) {
        self.entry = entry; self.size = size; self.redacted = redacted; self.overlay = overlay()
    }

    var body: some View {
        let tint = ShortcutAppearance.tint(for: entry)
        let body = IconGrid.body(size)
        RoundedRectangle(cornerRadius: IconGrid.radius(body), style: .continuous)
            .fill(tint.rgb.color.gradient)
            .overlay {
                if let overlay { overlay } else { ShortcutMark(entry: entry, size: size, redacted: redacted) }
            }
            .frame(width: body, height: body)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The symbol or first letter of a shortcut, white, sized for the squircle of an icon canvas of `size`.
struct ShortcutMark: View {
    let entry: ShortcutEntry
    let size: CGFloat
    var redacted = false

    var body: some View {
        let points = IconGrid.glyph(IconGrid.body(size))
        if let symbol = entry.symbol, !redacted {
            Image(systemName: symbol)
                .font(.system(size: points, weight: .semibold))
                .foregroundStyle(Color.white)
        } else if !redacted, let initial = ShortcutAppearance.initial(of: entry.name) {
            Text(verbatim: initial)
                .font(.system(size: points, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.5)
        } else {
            Image(systemName: ShortcutAppearance.fallbackSymbol)
                .font(.system(size: (points * 0.9).rounded(), weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }
}

extension ShortcutGlyph where Overlay == EmptyView {
    /// The squircle as an image for an NSMenu row.
    @MainActor static func menuImage(for entry: ShortcutEntry, size: CGFloat = 16) -> NSImage? {
        let renderer = ImageRenderer(content: ShortcutGlyph(entry: entry, size: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}

#Preview("Shortcut squircles") {
    HStack(spacing: Space.l) {
        ShortcutGlyph(entry: ShortcutEntry(id: "1", name: "Morning routine"), size: 36)
        ShortcutGlyph(entry: ShortcutEntry(id: "2", name: "т-банк"), size: 36)
        ShortcutGlyph(entry: ShortcutEntry(id: "3", name: "Resize (50%)", symbol: "photo.fill", tint: .teal), size: 36)
        ShortcutGlyph(entry: ShortcutEntry(id: "4", name: "☀️ Sunrise"), size: 36)
        ShortcutGlyph(entry: ShortcutEntry(id: "5", name: "Private", tint: .gray), size: 36, redacted: true)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

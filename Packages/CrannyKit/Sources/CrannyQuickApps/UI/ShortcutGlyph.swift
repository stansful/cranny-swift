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

/// The squircle as a small image for an NSMenu row. AppKit draws it only when the menu shows the row (a lazy
/// drawing handler, no SwiftUI render per shortcut), so a submenu of hundreds of shortcuts opens at once. The
/// images are shared per colour and glyph.
@MainActor enum ShortcutMenuImage {
    /// What one image shows (Sendable: the drawing handler captures it).
    struct Glyph: Hashable, Sendable {
        let tint: ShortcutTint
        let symbol: String?
        let initial: String?
        let size: CGFloat
    }

    private static var cache: [Glyph: NSImage] = [:]
    private static let cacheLimit = 256

    /// `redacted` (Demo mode): the neutral glyph, as on the tile.
    static func image(for entry: ShortcutEntry, redacted: Bool = false, size: CGFloat = 16) -> NSImage {
        let glyph = glyph(for: entry, redacted: redacted, size: size)
        if let cached = cache[glyph] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(glyph, in: rect)
            return true
        }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[glyph] = image
        return image
    }

    nonisolated static func glyph(for entry: ShortcutEntry, redacted: Bool, size: CGFloat) -> Glyph {
        let tint = ShortcutAppearance.tint(for: entry)
        if !redacted, let symbol = entry.symbol { return Glyph(tint: tint, symbol: symbol, initial: nil, size: size) }
        if !redacted, let initial = ShortcutAppearance.initial(of: entry.name) {
            return Glyph(tint: tint, symbol: nil, initial: initial, size: size)
        }
        return Glyph(tint: tint, symbol: ShortcutAppearance.fallbackSymbol, initial: nil, size: size)
    }

    /// Same geometry as `ShortcutGlyph`: the squircle on the icon grid of the canvas, a white glyph in its middle.
    nonisolated private static func draw(_ glyph: Glyph, in rect: NSRect) {
        let body = IconGrid.body(rect.width)
        let square = NSRect(x: rect.midX - body / 2, y: rect.midY - body / 2, width: body, height: body)
        let radius = IconGrid.radius(body)
        glyph.tint.rgb.nsColor.setFill()
        NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius).fill()
        let points = IconGrid.glyph(body)
        if let symbol = glyph.symbol {
            let configuration = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            let size = image.size
            image.draw(in: NSRect(x: square.midX - size.width / 2, y: square.midY - size.height / 2,
                                  width: size.width, height: size.height))
        } else if let initial = glyph.initial {
            let system = NSFont.systemFont(ofSize: points, weight: .semibold)
            let font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: points) } ?? system
            let text = NSAttributedString(string: initial, attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2))
        }
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

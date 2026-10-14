// CrannyQuickApps/UI/ShortcutAppearanceEditor.swift — a shortcut's colour and glyph (Settings ▸ Shortcuts ▸
// "Customize…"). Shortcuts.app exposes neither (R3 §6), so the user picks: Automatic (a hue hashed from the name)
// or one of twelve colours; the first letter or one of the curated symbols. Changes apply instantly (D14).
import CrannyCore
import SwiftUI

struct ShortcutAppearanceEditor: View {
    let model: QuickAppsModel
    let id: String

    var body: some View {
        if let entry = model.shortcutEntries.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ShortcutGlyph(entry: entry, size: 44)
                    Text(verbatim: entry.displayName).font(.headline).lineLimit(2)
                }
                Text("Color", bundle: .module, comment: "Settings ▸ Shortcuts: colour (popover section, search keyword)")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                    swatch(nil, entry: entry)
                    ForEach(ShortcutTint.allCases, id: \.self) { swatch($0, entry: entry) }
                }
                Text("Symbol", bundle: .module, comment: "Settings ▸ Shortcuts: symbol (popover section, search keyword)")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9), alignment: .leading, spacing: 4) {
                        symbolButton(nil, entry: entry)
                        ForEach(ShortcutAppearance.symbols, id: \.self) { symbolButton($0, entry: entry) }
                    }
                }
                .frame(height: 30 * 4 + 4 * 3)
            }
            .padding(16)
            .frame(width: 330)
        }
    }

    // MARK: Colour

    private func swatch(_ tint: ShortcutTint?, entry: ShortcutEntry) -> some View {
        let isSelected = entry.tint == tint
        let fill = tint ?? ShortcutAppearance.automaticTint(forName: entry.name)
        let title = tint?.title ?? String(localized: "Automatic", bundle: .module, comment: "Settings ▸ Shortcuts: automatic colour / symbol option")
        return Button {
            model.setAppearance(of: entry.id, symbol: entry.symbol, tint: tint)
        } label: {
            Circle()
                .fill(fill.rgb.color.gradient)
                .overlay {
                    if tint == nil {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(2)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Symbol

    private func symbolButton(_ symbol: String?, entry: ShortcutEntry) -> some View {
        let isSelected = entry.symbol == symbol
        return Button {
            model.setAppearance(of: entry.id, symbol: symbol, tint: entry.tint)
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                } else {
                    Text(verbatim: ShortcutAppearance.initial(of: entry.name) ?? "A")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .accessibilityLabel(Text("First letter", bundle: .module, comment: "Settings ▸ Shortcuts: glyph option, the name's first letter"))
                        .help(String(localized: "First letter", bundle: .module, comment: "Settings ▸ Shortcuts: glyph option, the name's first letter"))
                }
            }
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Appearance editor") {
    let model = QuickAppsPreview.model()
    ShortcutAppearanceEditor(model: model, id: QuickAppsPreview.sampleShortcuts[1].id)
}

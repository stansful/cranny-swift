// CrannyCore/Contracts/PreviewWidgets.swift
// Stand-ins for the well-known widgets, for #Previews and tests of the layers that cannot import feature modules
// (CrannyNotchUI, CrannySettingsUI, CrannyOnboarding). The app registers every real widget, so it never shows these;
// there, an ID nobody registered (a widget removed from a saved layout) shows its raw identifier and a placeholder
// glyph. One table here replaces the three copies those layers used to keep.
import SwiftUI

public extension ModuleRegistry {
    /// Registers a stand-in for each well-known widget that is not registered yet: its English name, its DESIGN.md
    /// §14.1 glyph and §6.7 sizes, drawn as glyph + name. For #Previews and tests only.
    func addPreviewStandIns() {
        for standIn in PreviewStandInWidget.all() where widget(standIn.id) == nil { add(widget: standIn) }
    }
}

/// A well-known widget's name, glyph and sizes without its module.
@MainActor final class PreviewStandInWidget: NookWidget {
    let id: WidgetID
    let title: String
    let symbol: String
    let sizes: WidgetSizes
    var summary: String { title }

    init(_ id: WidgetID, _ title: String, _ symbol: String, _ sizes: WidgetSizes) {
        self.id = id; self.title = title; self.symbol = symbol; self.sizes = sizes
    }

    func makeBody(context: WidgetContext) -> some View { PreviewStandInBody(title: title, symbol: symbol) }

    /// DESIGN.md §6.7 sizes and §14.1 glyphs (English names: previews and tests are not localized).
    static func all() -> [PreviewStandInWidget] {
        [
            .init(.media, "Media", "music.note", WidgetSizes(minimum: 4, preferred: 5, maximum: 6)),
            .init(.calendar, "Calendar", "calendar", WidgetSizes(minimum: 2, preferred: 3, maximum: 5)),
            .init(.quickApps, "Quick Apps", "app.dashed", WidgetSizes(minimum: 1, preferred: 2, maximum: 6)),
            .init(.mirror, "Mirror", "web.camera", WidgetSizes(minimum: 2, preferred: 2, maximum: 3)),
            .init(.notes, "Notes", "note.text", WidgetSizes(minimum: 3, preferred: 4, maximum: 8)),
            .init(.todos, "To-dos", "checklist", WidgetSizes(minimum: 2, preferred: 3, maximum: 6)),
            .init(.timer, "Timer", "timer", WidgetSizes(minimum: 2, preferred: 2, maximum: 3)),
            .init(.airDrop, "AirDrop", "dot.radiowaves.up.forward", WidgetSizes(minimum: 1, preferred: 2, maximum: 2)),
            .init(.files, "Files", "folder", WidgetSizes(minimum: 3, preferred: 4, maximum: 8)),
        ]
    }
}

struct PreviewStandInBody: View {
    @Environment(\.cranny) private var theme
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).crannySymbol(.widgetState)
            Text(verbatim: title).crannyFont(.caption).lineLimit(2).multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.palette.tertiaryLabel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stand-in widgets") {
    let registry = ModuleRegistry(services: .preview())
    registry.addPreviewStandIns()
    return HStack(spacing: Space.m) {
        ForEach(registry.widgets) { widget in
            widget.makeBody(context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96)))
                .frame(width: 96, height: 96)
        }
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

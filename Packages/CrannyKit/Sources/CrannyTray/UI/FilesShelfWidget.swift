// CrannyTray/UI/FilesShelfWidget.swift — the Files mini shelf (DESIGN.md §7.9, 3–8 cells): the 6 most recent tray
// items as 44-pt thumbnails, also a drop target, with "Open Tray" (⌘2) to jump to the Tray page. Up to 5 cells the
// thumbnails sit in two rows; from 6 cells they get captions, like the Tray page. Tiles behave as in §8.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class FilesShelfWidget: NookWidget {
    let store: TrayStore
    init(store: TrayStore) { self.store = store }

    let id: WidgetID = .files
    var title: String { String(localized: "Files", bundle: .module, comment: "Tray page: VoiceOver label of the row of files; also the Files widget's name") }
    let symbol = "folder"
    var summary: String {
        String(localized: "Your latest Tray files, ready to drag", bundle: .module, comment: "Widget library: Files description")
    }
    let sizes = WidgetSizes(minimum: 3, preferred: 4, maximum: 8)

    func makeBody(context: WidgetContext) -> some View { FilesShelfView(store: store, context: context) }
}

struct FilesShelfView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchZones) private var zones
    let store: TrayStore
    let context: WidgetContext

    /// DESIGN.md §7.9: the 6 most recent items.
    static let recentCount = 6

    var body: some View {
        let armed = zones?.armedDropZone == TrayDropZones.shelf
        let interactive = !context.isPreview && !context.isEditingLayout
        Group {
            if store.items.isEmpty {
                WidgetStateView(.empty, symbol: "tray.and.arrow.down.fill",
                                message: String(localized: "Drop files here to keep them", bundle: .module, comment: "Files widget: empty state"),
                                actionTitle: openTrayTitle, action: openTray)
            } else if context.cells >= 6 {
                captioned(interactive: interactive)
            } else {
                thumbnails(interactive: interactive)
            }
        }
        .frame(width: context.contentSize.width, height: context.contentSize.height)
        .overlay { if armed { TrayArmedOverlay() } }
        .crannyDropZone(TrayDropZones.shelf, accepts: [.item]) { payload in await store.keep(payload.fileURLs, opensTray: false) }
        .onChange(of: armed) { _, isArmed in if isArmed { store.haptics.play(.alignment) } }
        .animation(theme.animation(.commit), value: armed)
        .animation(theme.animation(.listReorder), value: store.order)
    }

    // MARK: Layouts

    /// Two rows of thumbnails; the last slot opens the Tray.
    private func thumbnails(interactive: Bool) -> some View {
        let side = TrayMetrics.thumbnail
        let columns = max(Int((context.contentSize.width + Space.m) / (side + Space.m)), 1)
        let shown = Array(store.items.prefix(min(Self.recentCount, 2 * columns - 1)))
        let spacing = columns > 1 ? (context.contentSize.width - CGFloat(columns) * side) / CGFloat(columns - 1) : 0
        let rows = [Array(shown.prefix(columns)), Array(shown.dropFirst(columns))]
        return VStack(alignment: .leading, spacing: context.contentSize.height - 2 * side) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(rows[row]) { item in
                        TrayTile(item: item, store: store, showsCaption: false, isInteractive: interactive)
                    }
                    if row == (rows[0].count < columns ? 0 : 1) { openTile }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One row of captioned tiles and a footer.
    private func captioned(interactive: Bool) -> some View {
        let columns = max(Int((context.contentSize.width + Space.m) / (TrayTileLayout(theme: theme).width + Space.m)), 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                ForEach(store.items.prefix(min(Self.recentCount, columns))) { item in
                    TrayTile(item: item, store: store, isInteractive: interactive)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: String(localized: "\(store.items.count) items · \(store.totalSize.formatted(.byteCount(style: .file)))",
                                      bundle: .module, comment: "Tray chip row with nothing selected: number of items and their total size"))
                    .crannyFont(.caption)
                    .foregroundStyle(theme.palette.tertiaryLabel)
                    .lineLimit(1)
                Spacer(minLength: Space.m)
                ChipButton(title: openTrayTitle, symbol: "tray.full.fill", action: openTray)
            }
            .frame(height: TrayTileLayout.chipRowHeight(textSize: theme.textSize))
        }
    }

    private var openTile: some View {
        Button(action: openTray) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.grid.innerRadius, style: .continuous).fill(theme.palette.control)
                VStack(spacing: Space.xxs) {
                    Image(systemName: "tray.full.fill").font(.system(size: TrayMetrics.thumbnail * 0.32, weight: .medium))
                    if store.items.count > Self.recentCount {
                        Text(verbatim: (store.items.count - Self.recentCount).formatted(.number.sign(strategy: .always())))
                            .crannyFont(.micro)
                    }
                }
                .foregroundStyle(theme.palette.secondaryLabel)
            }
            .frame(width: TrayMetrics.thumbnail, height: TrayMetrics.thumbnail)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(openTrayTitle)
        .accessibilityLabel(Text(verbatim: openTrayTitle))
    }

    private var openTrayTitle: String {
        String(localized: "Open Tray", bundle: .module, comment: "Files widget button, ⌘K command and Settings ▸ Keyboard shortcut: show the Tray page")
    }

    private func openTray() { store.notch.open(page: .tray, focus: nil, reason: .click) }
}

#Preview("Files widget · 4 and 6 cells") {
    let store = TrayPreview.store(items: 8, selected: 1)
    VStack(spacing: Space.m) {
        FilesShelfWidget(store: store).makeBody(context: TrayPreview.widgetContext(cells: 4))
            .crannyCard(cells: 4)
        FilesShelfWidget(store: store).makeBody(context: TrayPreview.widgetContext(cells: 6))
            .crannyCard(cells: 6)
        FilesShelfWidget(store: TrayPreview.store(items: 0)).makeBody(context: TrayPreview.widgetContext(cells: 3))
            .crannyCard(cells: 3)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

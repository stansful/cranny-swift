// CrannyTray/UI/PipelineChips.swift — the 22-pt chip row under the tiles (DESIGN.md §8.1–§8.2). Nothing selected:
// "5 items · 48 MB" and Clear. A selection: "2 selected" and the actions valid for every selected item
// (`PipelineChipSet`): Compress · Convert ▾ · Resize ▾ · Unzip · Zip · Copy paths · AirDrop · ✦ user pipelines · ….
// After a run that wrote files, an Undo chip leads the row for 5 s. While pipelines run, a Stop chip (⌘.) leads it.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PipelineChips: View {
    @Environment(\.cranny) private var theme
    let store: TrayStore

    var body: some View {
        let p = theme.palette
        HStack(spacing: Space.m) {
            if !store.stopChipJobs.isEmpty {
                ChipButton(title: TrayItemCommand.stopTitle, symbol: "xmark") { store.stopRunning() }
                    .help(String(localized: "Stop (⌘.)", bundle: .module, comment: "Tray chip: tooltip of Stop, which cancels running pipelines"))
                    .transition(.opacity)
            }
            if let offer = store.undoOffer {
                Button(action: store.undo) {
                    Label { Text("Undo", bundle: .module, comment: "Tray chip: undo the last pipeline for 5 seconds") }
                        icon: { Image(systemName: "arrow.uturn.backward").imageScale(.small) }
                }
                .buttonStyle(CrannyChipButtonStyle(tint: theme.accentColor))
                .accessibilityLabel(Text("Undo \(offer.title)", bundle: .module, comment: "Tray chip: VoiceOver label of Undo; the argument is the pipeline name"))
                .transition(.opacity)
                .fixedSize()
            }
            if store.selection.isEmpty {
                Text(verbatim: summary)
                    .crannyFont(.caption)
                    .foregroundStyle(p.tertiaryLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !store.items.isEmpty {
                    Button(action: store.clear) {
                        Label { Text("Clear", bundle: .module, comment: "Tray chip: remove every item from the Tray (⌥⌘⌫)") }
                            icon: { Image(systemName: "trash").imageScale(.small) }
                    }
                    .buttonStyle(CrannyChipButtonStyle())
                    .help(String(localized: "Clear the Tray (⌥⌘⌫)", bundle: .module, comment: "Tray chip: tooltip of Clear"))
                    .fixedSize()
                }
            } else {
                Text(verbatim: String(localized: "\(store.selectedItems.count) selected", bundle: .module,
                                      comment: "Tray chip row: number of selected files"))
                    .crannyFont(.caption)
                    .foregroundStyle(p.secondaryLabel)
                    .lineLimit(1)
                    .fixedSize()
                TrayScrollRow { HStack(spacing: Space.s) { chips } }
            }
        }
        .frame(height: TrayTileLayout.chipRowHeight(textSize: theme.textSize))
        .animation(theme.animation(.contentSwap), value: store.undoOffer)
        .animation(theme.animation(.contentSwap), value: store.stopChipJobs.map(\.id))
    }

    private var summary: String {
        let size = store.totalSize.formatted(.byteCount(style: .file))
        return String(localized: "\(store.items.count) items · \(size)", bundle: .module,
                      comment: "Tray chip row with nothing selected: number of items and their total size")
    }

    // MARK: Chips

    @ViewBuilder private var chips: some View {
        let selected = store.selectedItems
        let ids = selected.map(\.id)
        let maxDimension = store.settings[TraySettings.maxDimension]
        let set = PipelineChipSet.make(types: selected.map(\.contentType), userPipelines: store.settings[TraySettings.userPipelines],
                                       maxDimension: maxDimension)
        if set.compress { chip(BuiltinPipelines.compress, ids: ids) }
        if !set.convertFormats.isEmpty {
            ChipMenu(title: PipelineTitles.kind(.convert(format: .png), maxDimension: maxDimension), symbol: "arrow.triangle.2.circlepath") {
                ForEach(set.convertFormats, id: \.self) { format in
                    Button { store.run(BuiltinPipelines.convert(format), on: ids) } label: { Text(verbatim: format.displayName) }
                }
            }
        }
        if !set.resizeOptions.isEmpty {
            ChipMenu(title: PipelineTitles.kind(.resize(to: .scale(percent: 50)), maxDimension: maxDimension), symbol: "square.resize") {
                ForEach(set.resizeOptions, id: \.self) { option in
                    Button { store.run(PipelineDefinition(id: "builtin.resize", name: nil, symbol: "square.resize",
                                                          steps: [.resize(to: option)]), on: ids) } label: {
                        Text(verbatim: PipelineTitles.step(.resize(to: option), maxDimension: maxDimension))
                    }
                }
            }
        }
        if set.unzip { chip(BuiltinPipelines.unzip, ids: ids) }
        if set.zip { chip(BuiltinPipelines.zip, ids: ids) }
        if set.copyPaths {
            ChipButton(title: PipelineTitles.step(.copyPaths, maxDimension: maxDimension), symbol: "link") { store.copyPaths() }
        }
        if set.airDrop {
            ChipButton(title: "AirDrop", symbol: "dot.radiowaves.up.forward") { store.airDrop() }
        }
        ForEach(set.user) { pipeline in chip(pipeline, ids: ids) }
        ChipMenu(title: nil, symbol: "ellipsis") {
            ForEach(set.more) { pipeline in
                Button { store.run(pipeline, on: ids) } label: {
                    Label { Text(verbatim: store.title(of: pipeline)) } icon: { Image(systemName: pipeline.symbol) }
                }
            }
            if !set.more.isEmpty { Divider() }
            Button { store.share() } label: {
                Label { Text(verbatim: TrayItemCommand.share.title) } icon: { Image(systemName: "square.and.arrow.up") }
            }
            Button { store.reveal() } label: {
                Label { Text(verbatim: TrayItemCommand.reveal.title) } icon: { Image(systemName: "folder") }
            }
            Divider()
            Button(role: .destructive) { store.removeTargets() } label: {
                Label { Text(verbatim: TrayItemCommand.remove.title) } icon: { Image(systemName: "trash") }
            }
        }
        .accessibilityLabel(Text("More actions", bundle: .module, comment: "Tray chip: the … menu (VoiceOver label, tooltip)"))
        .help(String(localized: "More actions", bundle: .module, comment: "Tray chip: the … menu (VoiceOver label, tooltip)"))
    }

    private func chip(_ pipeline: PipelineDefinition, ids: [UUID]) -> some View {
        ChipButton(title: store.title(of: pipeline), symbol: pipeline.isUserPipeline ? "wand.and.stars" : pipeline.symbol) {
            store.run(pipeline, on: ids)
        }
    }
}

/// A 22-pt capsule with a glyph and a caption-semibold title (`CrannyChipButtonStyle`).
struct ChipButton: View {
    let title: String
    let symbol: String
    let action: @MainActor () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol).imageScale(.small) }
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(CrannyChipButtonStyle())
        .fixedSize()
    }
}

/// A chip that opens a menu ("Convert ▾", "Resize ▾", "…"). `title == nil` = glyph only.
struct ChipMenu<Items: View>: View {
    @Environment(\.cranny) private var theme
    let title: String?
    let symbol: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).imageScale(.small)
                if let title { Text(verbatim: title) }
                if title != nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.palette.secondaryLabel)
                }
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(CrannyChipButtonStyle())
        .fixedSize()
    }
}

/// A row that scrolls horizontally with faded ends (DESIGN.md §8.1). `trayRendersStatically` lays it out as a plain
/// clipped row instead: ImageRenderer (snapshot tests) cannot draw AppKit-backed scroll views.
struct TrayScrollRow<Content: View>: View {
    @Environment(\.trayRendersStatically) private var renderStatically
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if renderStatically {
                Color.clear
                    .overlay(alignment: .leading) { content().padding(.horizontal, TrayMetrics.fade).fixedSize() }
                    .clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) { content().padding(.horizontal, TrayMetrics.fade) }
            }
        }
        // Mask first, then reach into the card padding: the fade falls on the padding, not on the first tile.
        .mask(HorizontalFade())
        .padding(.horizontal, -TrayMetrics.fade)
    }
}

extension EnvironmentValues {
    /// Snapshot tests only: rows render without `ScrollView`.
    @Entry var trayRendersStatically = false
}

/// Fades the ends of a horizontally scrolling row (DESIGN.md §8.1 "scrolls horizontally with a fade mask").
struct HorizontalFade: View {
    var body: some View {
        GeometryReader { proxy in
            let stop = min(TrayMetrics.fade / max(proxy.size.width, 1), 0.5)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: stop),
                                   .init(color: .black, location: 1 - stop), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}

#Preview("Chips · nothing selected / images selected") {
    let width = NookGrid().width(cells: 8) - 2 * NookGrid().density.cardPadding
    let images = TrayPreview.store(items: 3)
    images.selection.set(images.items.filter { $0.contentType.conforms(to: .image) }.map(\.id))
    return VStack(spacing: Space.l) {
        PipelineChips(store: TrayPreview.store(items: 5)).frame(width: width)
        PipelineChips(store: images).frame(width: width)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

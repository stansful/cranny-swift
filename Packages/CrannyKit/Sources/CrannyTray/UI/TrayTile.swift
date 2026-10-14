// CrannyTray/UI/TrayTile.swift — one file in the Tray (DESIGN.md §8.1–§8.2): 64 × 66, a 44-pt thumbnail and a
// middle-truncated caption. Selected: `controlPressed` well (r 8) with a 1.5-pt accent ring and a 14-pt check badge
// (not colour-only). Hover: a 16-pt remove ✕. Running: dimmed behind a 22-pt accent ring (✕ cancels). Failed: a
// `danger` "!" badge whose tooltip and accessibility value say what failed. New result: a 6-pt accent dot. Stop is
// also in the context menu, the VoiceOver actions, the Stop chip and on ⌘. (nothing hover-only, §16).
// The AppKit layer underneath (`FileDragSource`) takes clicks, double-clicks, the context menu and drag-out.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct TrayTile: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.trayRendersStatically) private var renderStatically
    let item: TrayItem
    let store: TrayStore
    var showsCaption = true
    var isFocused = false
    var isInteractive = true
    /// Called after a click selects (the row takes keyboard focus).
    var onSelect: @MainActor () -> Void = {}
    @State private var hovered = false

    var body: some View {
        let selected = store.selection.contains(item.id)
        let job = store.job(for: item.id)
        // The live fraction (`TrayJobProgress`): only a running tile follows the ticks.
        let progress = job.map { store.progress(of: $0) }
        let missing = store.isLoaded && store.url(item.id) == nil
        let failure = store.failures[item.id] ?? (missing ? TrayError.fileMissing.errorDescription : nil)
        let layout = TrayTileLayout(theme: theme)
        ZStack(alignment: .top) {
            if isInteractive && !renderStatically { FileDragSource(handlers: handlers) }
            visuals(selected: selected, job: job, progress: progress, failure: failure, missing: missing, layout: layout)
                .allowsHitTesting(false)
            controls(job: job)
        }
        .frame(width: showsCaption ? layout.width : TrayMetrics.thumbnail,
               height: showsCaption ? layout.height : TrayMetrics.thumbnail)
        .help(failure ?? item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: TrayTileAccessibility.value(selected: selected, job: job, progress: progress,
                                                                       failure: failure)))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.click(item.id, modifiers: []) }
        .modifier(TrayItemActions(store: store, id: item.id))
    }

    // MARK: Visuals

    private func visuals(selected: Bool, job: TrayJob?, progress: Double?, failure: String?, missing: Bool,
                         layout: TrayTileLayout) -> some View {
        let p = theme.palette
        let radius = theme.grid.innerRadius
        let well = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(spacing: 0) {
            TrayThumbnailView(url: store.url(item.id), type: item.contentType, cache: store.thumbnails)
                .opacity(job != nil ? 0.5 : missing ? 0.4 : 1)
                .overlay { if let progress { TrayProgressRing(progress: progress) } }
                .overlay(alignment: .topTrailing) { badge(failure: failure) }
                .overlay(alignment: .bottomTrailing) {
                    if selected { TrayCheckBadge().offset(x: Space.xs, y: Space.xs) }
                }
            if showsCaption {
                Text(verbatim: item.name)
                    .crannyFont(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(selected ? p.label : p.secondaryLabel)
                    .frame(width: layout.width - Space.xs, height: layout.captionHeight)
            }
        }
        .padding(.top, showsCaption ? Space.xs : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // Captioned tiles get a well around thumbnail and name; bare thumbnails (Files widget) only the ring.
            if showsCaption { well.fill(selected ? p.controlPressed : hovered ? p.control : .clear) }
        }
        .overlay { if selected { well.strokeBorder(theme.accentColor, lineWidth: StrokeWidth.emphasis) } }
        .crannyFocusRing(isFocused, radius: radius)
        .animation(theme.animation(.hover), value: hovered)
        .animation(theme.animation(.commit), value: selected)
    }

    @ViewBuilder private func badge(failure: String?) -> some View {
        if failure != nil {
            TrayErrorBadge().offset(x: Space.xs, y: -Space.xs)
        } else if store.freshItems.contains(item.id) {
            Circle().fill(theme.accentColor)
                .frame(width: TrayMetrics.newDot, height: TrayMetrics.newDot)
                .offset(x: Space.xxs, y: -Space.xxs)
                .transition(.opacity)
        }
    }

    // MARK: Hover controls (also in the context menu, on keys and as VoiceOver actions)

    @ViewBuilder private func controls(job: TrayJob?) -> some View {
        if let job, hovered, isInteractive {
            TrayRoundButton(symbol: "xmark", label: TrayItemCommand.stopTitle) {
                store.cancel(job.id)
            }
            .padding(.top, Space.xs + (TrayMetrics.thumbnail - TrayMetrics.removeBadge) / 2)
        } else if hovered, isInteractive {
            TrayRoundButton(symbol: "xmark", label: TrayItemCommand.remove.title) {
                store.remove([item.id])
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .offset(x: -Space.xxs, y: -Space.xxs)
            .transition(.opacity)
        }
    }

    // MARK: AppKit layer

    private var handlers: FileDragHandlers {
        let id = item.id
        let store = store
        let scale = displayScale
        return FileDragHandlers(
            payload: {
                store.targets(for: id).compactMap { item in store.url(item.id).map { (id: item.id, url: $0) } }
            },
            image: {
                guard let url = store.url(id), let cached = store.thumbnails.cached(for: url, pointSize: TrayMetrics.thumbnail, scale: scale)
                else { return nil }
                return NSImage(cgImage: cached.image, size: NSSize(width: TrayMetrics.thumbnail, height: TrayMetrics.thumbnail))
            },
            click: { [onSelect] modifiers in
                store.click(id, modifiers: modifiers)
                onSelect()
            },
            doubleClick: { store.open(id) },
            hover: { inside in hovered = inside },
            menu: { TrayContextMenu.make(for: id, store: store) },
            dragBegan: { store.dragOutBegan() },
            dragEnded: { ids, gone in store.dragOutEnded(ids, movedOrDeleted: gone) },
            allowsMove: { store.targets(for: id).allSatisfy(\.isOwned) })
    }
}

/// VoiceOver value of a tile: state first, then what failed.
enum TrayTileAccessibility {
    /// `progress`: the job's live fraction (`TrayStore.progress(of:)`); nil = the value the job was made with.
    static func value(selected: Bool, job: TrayJob?, progress: Double? = nil, failure: String?) -> String {
        var parts: [String] = []
        if selected { parts.append(selectedValue) }
        if let job {
            let percent = (progress ?? job.progress).formatted(.percent.precision(.fractionLength(0)))
            parts.append(String(localized: "\(job.title), \(percent)", bundle: .module,
                                comment: "Tray tile: VoiceOver value while a pipeline runs; pipeline name and percent done"))
        }
        if let failure { parts.append(failure) }
        return parts.joined(separator: ", ")
    }

    /// Looked up once per session (every tile body asks; the UI language only changes with a relaunch).
    private static let selectedValue = String(localized: "Selected", bundle: .module, comment: "Tray tile: VoiceOver value")
}

// MARK: - Small pieces

/// 22-pt accent ring over a dimmed thumbnail (DESIGN.md §8.2 "Running").
struct TrayProgressRing: View {
    @Environment(\.cranny) private var theme
    let progress: Double
    var body: some View {
        ProgressRing(progress: max(progress, 0.04), color: theme.accentColor, lineWidth: StrokeWidth.ringCompact)
            .frame(width: TrayMetrics.progressRing, height: TrayMetrics.progressRing)
            .animation(theme.animation(.commit), value: progress)
            .accessibilityHidden(true)
    }
}

/// 14-pt check badge of a selected tile: accent disc, black check (carries selection without colour).
struct TrayCheckBadge: View {
    @Environment(\.cranny) private var theme
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: TrayMetrics.checkBadge * 0.55, weight: .bold))
            .foregroundStyle(theme.accent.onColor.color)
            .frame(width: TrayMetrics.checkBadge, height: TrayMetrics.checkBadge)
            .background(Circle().fill(theme.accentColor))
            .overlay(Circle().strokeBorder(theme.palette.surface, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// `danger` "!" badge (DESIGN.md §8.2 "Error"; "!" carries it without colour, §16).
struct TrayErrorBadge: View {
    @Environment(\.cranny) private var theme
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: TrayMetrics.checkBadge * 0.6, weight: .heavy))
            .foregroundStyle(theme.palette.label)
            .frame(width: TrayMetrics.checkBadge, height: TrayMetrics.checkBadge)
            .background(Circle().fill(theme.palette.danger))
            .overlay(Circle().strokeBorder(theme.palette.surface, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A 16-pt circle (remove, cancel) with a ≥ 28 × 24 hit area (DESIGN.md §2.3).
struct TrayRoundButton: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let label: String
    let action: @MainActor () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: TrayMetrics.removeBadge * 0.5, weight: .bold))
                .foregroundStyle(theme.palette.label)
                .frame(width: TrayMetrics.removeBadge, height: TrayMetrics.removeBadge)
                .background(Circle().fill(hovered ? theme.palette.controlPressed : theme.palette.surface.opacity(0.85)))
                .overlay(Circle().strokeBorder(theme.palette.stroke, lineWidth: 1))
                .padding((HitTarget.preferred - TrayMetrics.removeBadge) / 2)
                .contentShape(Rectangle())
                .padding(-(HitTarget.preferred - TrayMetrics.removeBadge) / 2)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
    }
}

#Preview("Tiles · states") {
    let store = TrayPreview.store(items: 5, selected: 1)
    let ids = store.order
    store.jobs.append(TrayJob(id: UUID(), pipelineID: "builtin.compress", title: "Compress", sourceIDs: [ids[1]],
                              placeholderName: nil, progress: 0.4))
    store.failures[ids[2]] = TrayError.notSmaller.errorDescription
    store.freshItems.insert(ids[3])
    return HStack(spacing: Space.m) {
        ForEach(store.items) { TrayTile(item: $0, store: store, isInteractive: false) }
        TrayTile(item: store.items[0], store: store, showsCaption: false, isInteractive: false)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

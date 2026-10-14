// CrannyTray/UI/AirDropWidget.swift — the AirDrop widget (DESIGN.md §7.8, 1–2 cells) and the AirDrop card of the Tray
// page. Idle: a dashed zone with `dot.radiowaves.up.forward` and "AirDrop". Drag over: `info` stroke (solid under
// Differentiate Without Color), `info` at 15 %, scale 1.03, bounce, `.alignment` haptic. Drop: the AirDrop sheet
// (`NotchControl.presentAirDrop`, anchored by the shell). Click: sends the Tray's selection, else explains itself.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class AirDropWidget: NookWidget {
    let store: TrayStore
    init(store: TrayStore) { self.store = store }

    let id: WidgetID = .airDrop
    /// A product name: not translated.
    var title: String { "AirDrop" }
    let symbol = "dot.radiowaves.up.forward"
    var summary: String {
        String(localized: "Drop files to send them to devices nearby", bundle: .module, comment: "Widget library: AirDrop description")
    }
    let sizes = WidgetSizes(minimum: 1, preferred: 2, maximum: 2)

    func makeBody(context: WidgetContext) -> some View {
        AirDropZoneView(store: store, cells: context.cells, zone: .airDrop, isInteractive: !context.isPreview && !context.isEditingLayout)
    }
}

struct AirDropZoneView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchZones) private var zones
    let store: TrayStore
    let cells: Int
    let zone: DropZoneID
    var isInteractive = true
    @State private var showsHint = false
    @State private var hintTask: Task<Void, Never>?

    private var hint: String {
        String(localized: "Drop files here to send them with AirDrop", bundle: .module, comment: "AirDrop widget: shown on click with nothing to send, and as tooltip")
    }

    var body: some View {
        let armed = zones?.armedDropZone == zone
        Button(action: clicked) {
            if cells >= 2 {
                DropZone(symbol: "dot.radiowaves.up.forward", title: showsHint ? hint : "AirDrop", targeted: armed,
                         tint: theme.palette.info)
            } else {
                CompactDropTarget(symbol: "dot.radiowaves.up.forward", targeted: armed, tint: theme.palette.info)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .crannyDropZone(zone, accepts: [.item]) { payload in await store.airDrop(dropped: payload.fileURLs) }
        .onChange(of: armed) { _, isArmed in if isArmed { store.haptics.play(.alignment) } }
        .help(hint)
        .accessibilityLabel(Text(verbatim: "AirDrop"))
        .accessibilityHint(Text(verbatim: hint))
        .animation(theme.animation(.contentSwap), value: showsHint)
    }

    private func clicked() {
        if !store.selection.isEmpty { return store.airDrop() }
        showsHint = true
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(HoverIntent.peekAutoDismiss))   // as long as a peek
            if !Task.isCancelled { showsHint = false }
        }
    }
}

/// `DropZone` without a title, for a 1-cell card (DESIGN.md §6.7: "1: icon only").
struct CompactDropTarget: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let targeted: Bool
    let tint: Color
    var body: some View {
        let p = theme.palette
        let shape = RoundedRectangle(cornerRadius: theme.grid.innerRadius, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: TrayMetrics.thumbnail / 2, weight: .medium))
            .crannySymbolBounce(value: targeted)        // none under Reduce Motion or Instant (DESIGN.md §14.1, §4.2)
            .foregroundStyle(targeted ? p.label : p.secondaryLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(targeted ? tint.opacity(0.15) : .clear))
            .overlay(shape.strokeBorder(targeted ? tint : p.stroke,
                                        style: StrokeStyle(lineWidth: StrokeWidth.emphasis,
                                                           dash: targeted && theme.differentiateWithoutColor ? [] : StrokeWidth.dash)))
            .scaleEffect(targeted && !theme.reduceMotion ? 1.03 : 1)
            .animation(theme.animation(.commit), value: targeted)
    }
}

#Preview("AirDrop widget · 2 cells / 1 cell") {
    let store = TrayPreview.store(items: 0)
    HStack(spacing: Space.m) {
        AirDropWidget(store: store).makeBody(context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96)))
            .crannyCard(cells: 2)
        AirDropWidget(store: store).makeBody(context: WidgetContext(cells: 1, contentSize: CGSize(width: 32, height: 96)))
            .crannyCard(cells: 1)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

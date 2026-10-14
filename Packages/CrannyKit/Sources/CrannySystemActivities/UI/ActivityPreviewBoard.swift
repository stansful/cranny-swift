// CrannySystemActivities/UI/ActivityPreviewBoard.swift — a stand-in for CrannyNotchUI's compact and peek hosts
// (this layer cannot import it): one activity drawn in the band, as the satellite and as a peek row, with the
// Core `NotchSurface`/`CompactSlots` and DESIGN.md §3.3 geometry. Used by `#Preview`s and the opt-in
// snapshot test (`CRANNY_SNAPSHOT_DIR=<dir>`).
import CrannyCore
import SwiftUI

struct ActivityPreviewBoard: View {
    let activity: any LiveActivity
    var metrics = NotchMetrics.reference
    var theme = CrannyTheme()

    var body: some View {
        let layout = NotchLayout(metrics: metrics)
        VStack(spacing: Space.xxxl) {
            HStack(alignment: .top, spacing: Space.l) {
                compact(layout)
                satellite(layout)
            }
            peek(layout)
        }
        .padding(Space.huge)
        .background(LinearGradient(colors: [RGB(hex: 0x2B3A55).color, RGB(hex: 0x6D7FA3).color],
                                   startPoint: .top, endPoint: .bottom))
        .crannyThemeRoot(theme)
    }

    private func compact(_ layout: NotchLayout) -> some View {
        let geometry = layout.compact(activity.slot)
        return NotchSurface(geometry: geometry, band: layout.band, openness: 0) {
            CompactSlots(layout: layout, slot: activity.slot,
                         leading: { activity.view(for: .compactLeading) },
                         center: { EmptyView() },
                         trailing: { activity.view(for: .compactTrailing) })
        }
        .frame(width: geometry.outerWidth, height: geometry.bottom)
    }

    private func satellite(_ layout: NotchLayout) -> some View {
        let d = NotchLayout.satelliteDiameter * layout.u
        return Circle().fill(Color.black)
            .overlay { activity.view(for: .minimal) }
            .frame(width: d, height: d)
            .padding(.top, layout.rowInset + (layout.rowHeight - d) / 2)
    }

    private func peek(_ layout: NotchLayout) -> some View {
        let geometry = layout.peek(rows: 1)
        return NotchSurface(geometry: geometry, band: layout.band, openness: 1, elevation: Elevation.peek) {
            VStack(spacing: 0) {
                CompactSlots(layout: layout, slot: activity.slot,
                             leading: { activity.view(for: .compactLeading) },
                             center: { EmptyView() },
                             trailing: { activity.view(for: .compactTrailing) })
                activity.view(for: .peekRow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: NotchLayout.peekRow)
                    .padding(.horizontal, Space.l)
            }
            .frame(width: geometry.bodyWidth, height: geometry.bottom, alignment: .top)
        }
        .frame(width: geometry.outerWidth, height: geometry.bottom)
    }
}

#Preview("Preview board · floating island") {
    ActivityPreviewBoard(activity: BluetoothActivity.sample(.trackpad),
                         metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920))
}

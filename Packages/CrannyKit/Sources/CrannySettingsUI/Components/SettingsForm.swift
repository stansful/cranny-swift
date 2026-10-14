// CrannySettingsUI/Components/SettingsForm.swift — the body of every shell pane: `Form { … }.formStyle(.grouped)`
// (DESIGN.md §11.3) inside a `ScrollViewReader`, so a search result or deep link scrolls its row into view.
import CrannyCore
import Foundation
import SwiftUI

struct SettingsForm<Content: View>: View {
    @Environment(SettingsNavigator.self) private var navigator: SettingsNavigator?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pane: SettingsPageID
    private let content: Content

    /// `pane` is the pane these rows belong to: only its rows are scrolled to.
    init(_ pane: SettingsPageID, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form { content }
                .formStyle(.grouped)
                .onAppear { scrollToPendingRow(proxy) }
                .onChange(of: navigator?.highlightSerial) { scrollToPendingRow(proxy) }
        }
    }

    /// Waits one layout pass (the rows of a pane that just appeared do not exist yet), then centres the row.
    private func scrollToPendingRow(_ proxy: ScrollViewProxy) {
        guard let navigator, let row = navigator.takePendingRow(in: pane) else { return }
        Task { @MainActor in
            await Task.yield()
            if reduceMotion {
                proxy.scrollTo(row, anchor: .center)
            } else {
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(row, anchor: .center) }
            }
        }
    }
}

#Preview("Settings form") {
    SettingsForm(.general) {
        Section { Text(verbatim: "Row") }
    }
    .frame(width: 500, height: 200)
}

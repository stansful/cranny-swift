// CrannySettingsUI/Components/SettingRow.swift — the conventions every Settings row shares (DESIGN.md §11.3):
// a 6-pt accent dot before the label marks a changed value, the row's context menu (and a VoiceOver action)
// has "Reset to Default", a one-line footnote in `.secondary` explains non-obvious rows, and a search result
// or deep link washes the row with the accent for 1 s.
import CrannyCore
import Foundation
import SwiftUI

/// A row's label: the title, the changed-value dot before it and an optional one-line footnote.
struct RowLabel: View {
    let title: String
    var footnote: String?
    var isChanged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .overlay(alignment: .leading) {
                    ChangedDot()
                        .opacity(isChanged ? 1 : 0)
                        .offset(x: -(SettingsMetrics.changedDot + 4))
                }
            if let footnote {
                Text(verbatim: footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The 6-pt accent dot of a changed value. Decorative: the row says "Changed" to VoiceOver instead.
struct ChangedDot: View {
    var body: some View {
        Circle()
            .fill(.tint)
            .frame(width: SettingsMetrics.changedDot, height: SettingsMetrics.changedDot)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Row conventions for a row backed by one settings key.
    func settingRow<V>(_ info: SettingsRowInfo, settings: SettingsStore, key: SettingKey<V>) -> some View {
        settingRow(info, isDefault: settings.isDefault(key), reset: { settings.reset(key) })
    }

    /// Row conventions with explicit "is default" and "reset" (rows backed by several keys or a dictionary entry).
    func settingRow(_ info: SettingsRowInfo, isDefault: Bool, reset: @escaping @MainActor () -> Void) -> some View {
        modifier(SettingRowModifier(info: info, isDefault: isDefault, reset: reset))
    }
}

/// Context menu and VoiceOver action "Reset to Default", plus the search target.
struct SettingRowModifier: ViewModifier {
    let info: SettingsRowInfo
    let isDefault: Bool
    let reset: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .searchTarget(info)
            .contextMenu {
                Button(action: reset) {
                    Text("Reset to Default", bundle: .module, comment: "Settings: row context menu and VoiceOver action")
                }
                .disabled(isDefault)
            }
            .accessibilityAction(named: Text("Reset to Default", bundle: .module, comment: "Settings: row context menu and VoiceOver action")) {
                reset()
            }
            .accessibilityHint(isDefault ? Text(verbatim: "")
                               : Text("Changed from the default.", bundle: .module, comment: "Settings: VoiceOver hint of a row whose value differs from its default"))
    }
}

extension View {
    /// Makes the row a scroll target of search results and deep links, and washes it with the accent when it is
    /// the result (read-only rows use this alone).
    func searchTarget(_ info: SettingsRowInfo) -> some View { modifier(SearchTargetModifier(info: info)) }
}

/// Scroll target and search highlight of one row.
struct SearchTargetModifier: ViewModifier {
    @Environment(SettingsNavigator.self) private var navigator: SettingsNavigator?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wash = 0.0
    let info: SettingsRowInfo

    func body(content: Content) -> some View {
        content
            .id(info.id)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(wash))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
                    .allowsHitTesting(false)
            }
            .onAppear(perform: flashIfRequested)
            .onChange(of: navigator?.highlightSerial) { flashIfRequested() }
    }

    /// Washes the row when a search result or deep link points at it (also when the row appears later).
    private func flashIfRequested() {
        guard let navigator, navigator.highlightedRow == info.id, navigator.isHighlightFresh else { return }
        wash = SettingsMetrics.highlightOpacity
        withAnimation(.easeOut(duration: SettingsMetrics.highlightFade).delay(reduceMotion ? 0 : 0.25)) { wash = 0 }
    }
}

extension SettingsNavigator {
    /// A highlight is shown only shortly after it was requested, so rows that scroll in later stay calm.
    var isHighlightFresh: Bool { Date().timeIntervalSince(highlightDate) < 2 }
}

#Preview("Row label · changed") {
    Form {
        Toggle(isOn: .constant(true)) {
            RowLabel(title: "Close when the pointer leaves", footnote: "Waits 300 ms before closing.", isChanged: true)
        }
        Toggle(isOn: .constant(false)) { RowLabel(title: "Hold ⌥ to pass over") }
    }
    .formStyle(.grouped)
    .toggleStyle(.switch)
    .controlSize(.small)
    .frame(width: 520, height: 200)
}

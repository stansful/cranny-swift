// CrannyOnboarding/Steps/DoneStep.swift — step 6 (DESIGN.md §12.1): Launch at login (on) and Check for updates
// (on), plus a cheat sheet of six keys. Launch at login applies when setup finishes (`AppControl`); updates are
// a setting and apply at once.
import CrannyCore
import Foundation
import SwiftUI

struct DoneStep: View {
    @Bindable var flow: WelcomeFlow

    private static let switchesWidth: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "You're set", bundle: .module, comment: "Welcome step 6: headline"),
                       message: String(localized: "Cranny waits at the top of your screen. A few keys worth knowing:",
                                       bundle: .module, comment: "Welcome step 6: sentence under the headline, before the cheat sheet"))
            HStack(alignment: .top, spacing: Space.xxl) {
                CheatSheet(entries: flow.cheatSheet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.m) {
                    Toggle(isOn: $flow.launchesAtLogin) {
                        Text("Open at login", bundle: .module, comment: "Welcome step 6: launch at login switch")
                    }
                    .disabled(!flow.canChangeLoginItem)
                    Toggle(isOn: $flow.checksForUpdates) {
                        Text("Check for updates", bundle: .module, comment: "Welcome step 6: daily update check switch")
                    }
                    Text("Only the update check uses the network.", bundle: .module,
                         comment: "Welcome step 6: footnote under the update switch")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(width: Self.switchesWidth, alignment: .leading)
            }
        }
    }
}

/// Six keys in two columns: key cap, then what it does.
private struct CheatSheet: View {
    let entries: [CheatSheetEntry]

    var body: some View {
        let half = (entries.count + 1) / 2
        HStack(alignment: .top, spacing: Space.xl) {
            column(Array(entries.prefix(half)))
            column(Array(entries.dropFirst(half)))
        }
    }

    private func column(_ entries: [CheatSheetEntry]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(entries) { entry in
                HStack(spacing: Space.m) {
                    WindowKeyCap(entry.keys)
                    Text(verbatim: entry.action.title).font(.callout).lineLimit(1).minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(entry.action.title), \(entry.keys)"))
            }
        }
    }
}

extension CheatSheetEntry.Action {
    var title: String {
        switch self {
        case .open: String(localized: "Open or close Cranny", bundle: .module, comment: "Welcome step 6 cheat sheet: ⌃⌥N")
        case .hints: String(localized: "Hold to see shortcuts", bundle: .module, comment: "Welcome step 6 cheat sheet: hold ⌘")
        case .palette: String(localized: "Find any command", bundle: .module, comment: "Welcome step 6 cheat sheet: ⌘K command palette")
        case .pin: String(localized: "Keep Cranny open", bundle: .module, comment: "Welcome step 6 cheat sheet: ⌘P pin")
        case .edit: String(localized: "Edit the layout", bundle: .module, comment: "Welcome step 6 cheat sheet: ⌘E")
        case .close: String(localized: "Close Cranny", bundle: .module, comment: "Welcome step 6 cheat sheet: Esc")
        }
    }
}

#Preview("Step 6 · You're set") {
    WelcomePreview(step: .done)
}

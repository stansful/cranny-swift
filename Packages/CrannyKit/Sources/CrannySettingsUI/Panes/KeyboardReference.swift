// CrannySettingsUI/Panes/KeyboardReference.swift — the read-only "In Cranny" key reference of Settings ▸ Keyboard
// (DESIGN.md §11.1): the same data as the hold-⌘ overlay and the keyboard map of DESIGN.md §16. Each row is
// searchable ("palette" finds ⌘K).
import CrannyCore
import Foundation
import SwiftUI

struct KeyboardReference: View {
    var body: some View {
        Section {
            ForEach(Self.entries, id: \.row.id) { entry in
                LabeledContent {
                    Text(verbatim: entry.keys)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Text(verbatim: entry.row.title)
                }
                .searchTarget(entry.row)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Inside Cranny", bundle: .module, comment: "Settings ▸ Keyboard: section header of the key reference")
        } footer: {
            Text("Hold ⌘ in Cranny to see these next to each control.", bundle: .module,
                 comment: "Settings ▸ Keyboard: footer of the key reference")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    struct Entry {
        let row: SettingsRowInfo
        let keys: String
    }

    private static func entry(_ name: String, _ title: String, _ keys: String) -> Entry {
        Entry(row: SettingsRowInfo(.keyboard, "reference.\(name)", title: title), keys: keys)
    }

    static var entries: [Entry] {
        [
            entry("widgets", String(localized: "Move between widgets", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⇥  ⇧⇥"),
            entry("activate", String(localized: "Activate", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action (press the focused control)"), "↩  " + KeyComboFormatter.keyName(keyCode: 49, character: nil)),
            entry("pages", String(localized: "Go to page 1–5", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⌘1 … ⌘5"),
            entry("nextPage", String(localized: "Next page", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⌃⇥"),
            entry("palette", String(localized: "Command palette", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⌘K"),
            entry("hints", String(localized: "Show shortcuts", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action (hold ⌘)"), "⌘ …"),
            entry("pin", String(localized: "Keep open", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action (pin; glossary: Закрепить)"), "⌘P"),
            entry("edit", String(localized: "Edit layout", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⌘E"),
            entry("settings", String(localized: "Open Settings", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⌘,"),
            entry("close", String(localized: "Close", bundle: .module, comment: "Settings ▸ Keyboard ▸ Inside Cranny: action"), "⎋"),
        ]
    }

    static var rows: [SettingsRowInfo] { entries.map(\.row) }
}

#Preview("Key reference") {
    Form { KeyboardReference() }
        .formStyle(.grouped)
        .frame(width: 600, height: 480)
}

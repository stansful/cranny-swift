// CrannySettingsUI/Panes/AccentPicker.swift — Appearance ▸ Accent (DESIGN.md §2.1, §11.1): Automatic (album art while
// music plays, else the system accent) · System · eight curated swatches · Monochrome, as a row of colour wells like
// the system's own accent picker. Each well has a tooltip and a VoiceOver label; the selected one carries a ring
// and the `.isSelected` trait (colour is never the only cue).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct AccentPicker: View {
    let settings: SettingsStore

    var body: some View {
        let current = settings[CoreSettings.accent]
        LabeledContent {
            HStack(spacing: 7) {
                ForEach(Self.options, id: \.self) { option in
                    AccentWell(option: option, isSelected: option == current) {
                        settings[CoreSettings.accent] = option
                    }
                }
            }
        } label: {
            RowLabel(title: AppearanceRows.accent.title, footnote: Self.footnote(current),
                     isChanged: !settings.isDefault(CoreSettings.accent))
        }
        .settingRow(AppearanceRows.accent, settings: settings, key: CoreSettings.accent)
    }

    static var options: [AccentSource] {
        [.automatic, .system] + AccentSwatch.allCases.map { .swatch($0) } + [.monochrome]
    }

    static func footnote(_ source: AccentSource) -> String {
        switch source {
        case .automatic: String(localized: "The album's colour while music plays, otherwise the system accent.", bundle: .module,
                                comment: "Settings ▸ Appearance ▸ Accent: footnote for Automatic")
        case .system: String(localized: "The accent colour chosen in System Settings.", bundle: .module,
                             comment: "Settings ▸ Appearance ▸ Accent: footnote for System")
        case .swatch: String(localized: "Used for progress, rings and toggles. Alerts keep their own colours.", bundle: .module,
                             comment: "Settings ▸ Appearance ▸ Accent: footnote for a swatch")
        case .monochrome: String(localized: "White only. Alerts keep their own colours.", bundle: .module,
                                 comment: "Settings ▸ Appearance ▸ Accent: footnote for Monochrome")
        }
    }

    static func title(_ source: AccentSource) -> String {
        switch source {
        case .automatic: String(localized: "Automatic", bundle: .module, comment: "Settings: option chosen automatically (a display style, the accent)")
        case .system: String(localized: "System", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: the system accent colour")
        case .monochrome: String(localized: "Monochrome", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: white only")
        case .swatch(let swatch):
            switch swatch {
            case .blue: String(localized: "Blue", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .teal: String(localized: "Teal", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .green: String(localized: "Green", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .yellow: String(localized: "Yellow", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .orange: String(localized: "Orange", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .pink: String(localized: "Pink", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .purple: String(localized: "Purple", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            case .graphite: String(localized: "Graphite", bundle: .module, comment: "Settings ▸ Appearance ▸ Accent: swatch name")
            }
        }
    }
}

/// One 16-pt colour well. Automatic shows a split of the brand gradient and the system accent.
private struct AccentWell: View {
    let option: AccentSource
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            fill
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary.opacity(0.75) : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: AccentPicker.title(option)))
        .accessibilityLabel(Text(verbatim: AccentPicker.title(option)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var fill: some View {
        switch option {
        case .automatic:
            LinearGradient(colors: [BrandColor.rose.color, BrandColor.iris.color, BrandColor.lagoon.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .system: Color(nsColor: .controlAccentColor)
        case .swatch(let swatch): swatch.rgb.color
        case .monochrome: Color.white
        }
    }
}

#Preview("Accent") {
    Form { AccentPicker(settings: CrannyServices.preview().settings) }
        .formStyle(.grouped)
        .frame(width: 650, height: 140)
}

// CrannyOnboarding/Steps/PresetStep.swift — step 4 (DESIGN.md §12.1): four starting layouts, each drawn as a
// miniature open panel. Picking one rewrites Home at once (`CoreSettings.pages`, D14) and the stage above opens
// with it; a layout of one's own stays until a preset is picked.
import CrannyCore
import Foundation
import SwiftUI

struct PresetStep: View {
    let flow: WelcomeFlow

    static let cardHeight: CGFloat = 116
    private static let miniWidth: CGFloat = 112

    var body: some View {
        let selected = flow.selectedPreset
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "Pick a starting layout", bundle: .module, comment: "Welcome step 4: headline"),
                       message: selected == nil
                        ? String(localized: "Your own layout stays unless you pick one. You can change it any time in Settings ▸ Layout & Widgets.",
                                 bundle: .module, comment: "Welcome step 4: sentence when the person already arranged their own layout")
                        : String(localized: "You can change it any time in Settings ▸ Layout & Widgets.",
                                 bundle: .module, comment: "Welcome step 4: sentence under the headline"))
            HStack(spacing: Space.m) {
                ForEach(NookPreset.allCases, id: \.self) { preset in
                    PresetCard(preset: preset, isSelected: preset == selected, registry: flow.registry,
                               miniScale: MiniPanel.scale(forWidth: Self.miniWidth)) { flow.pick(preset) }
                }
            }
            .frame(height: Self.cardHeight)
        }
    }
}

private struct PresetCard: View {
    let preset: NookPreset
    let isSelected: Bool
    let registry: ModuleRegistry
    let miniScale: CGFloat
    let pick: () -> Void

    var body: some View {
        let widgets = preset.items.map { WidgetCatalog.info($0.widget, in: registry) }
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.xs) {
                MiniPanel(items: preset.items,
                          symbols: Dictionary(zip(preset.items.map(\.widget), widgets.map(\.symbol)), uniquingKeysWith: { first, _ in first }),
                          scale: miniScale)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Space.s)
                HStack(spacing: Space.xs) {
                    Text(verbatim: preset.title).font(.headline)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
                    }
                }
                Text(verbatim: preset.summary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m + Space.xxs)
        }
        .buttonStyle(SelectableCardStyle(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: preset.title))
        .accessibilityValue(Text(verbatim: widgets.map(\.title).formatted(.list(type: .and))))
        .accessibilityHint(Text(verbatim: preset.summary))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Step 4 · Layout") {
    WelcomePreview(step: .preset)
}

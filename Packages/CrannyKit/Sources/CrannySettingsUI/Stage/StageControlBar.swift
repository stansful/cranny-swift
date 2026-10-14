// CrannySettingsUI/Stage/StageControlBar.swift — the controls under the preview stage (DESIGN.md §11.2): a segmented
// picker Closed · Activity · Peek · Open · HUD (auto-selected per pane), the Simulate chips and Show on Notch.
// When the window or the language makes the row too narrow, the chips fold into a Simulate menu, then the picker
// into a pop-up.
import CrannyCore
import Foundation
import SwiftUI

struct StageControlBar: View {
    let controller: StageController

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(statePicker: .segmented, chipsInline: true, compactButton: false)
            row(statePicker: .segmented, chipsInline: false, compactButton: false)
            row(statePicker: .segmented, chipsInline: false, compactButton: true)
            row(statePicker: .menu, chipsInline: false, compactButton: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private enum PickerKind { case segmented, menu }

    private func row(statePicker kind: PickerKind, chipsInline: Bool, compactButton: Bool) -> some View {
        HStack(spacing: 12) {
            statePicker(kind)
            Spacer(minLength: 8)
            if chipsInline {
                SimulateChips(controller: controller)
            } else {
                SimulateMenu(controller: controller)
            }
            Button {
                controller.showOnNotch()
            } label: {
                if compactButton {
                    Image(systemName: "play.fill")
                        .accessibilityLabel(Text("Show on Notch", bundle: .module, comment: "Settings preview stage: plays the preview on the real notch for 5 s"))
                } else {
                    Text("Show on Notch", bundle: .module, comment: "Settings preview stage: plays the preview on the real notch for 5 s")
                }
            }
            .controlSize(.small)
            .help(Text("Plays this preview on your notch for 5 seconds.", bundle: .module,
                       comment: "Settings preview stage: tooltip of Show on Notch"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func statePicker(_ kind: PickerKind) -> some View {
        let picker = Picker(selection: Binding(get: { controller.state }, set: { controller.select($0) })) {
            ForEach(PreviewStageState.allCases, id: \.self) { state in
                Text(verbatim: Self.title(of: state)).tag(state)
            }
        } label: {
            Text("Preview", bundle: .module, comment: "Settings preview stage: label of the state picker (VoiceOver)")
        }
        .labelsHidden()
        .controlSize(.small)
        switch kind {
        case .segmented: picker.pickerStyle(.segmented).fixedSize()
        case .menu: picker.pickerStyle(.menu).fixedSize()
        }
    }

    /// Localized names of the picker states.
    static func title(of state: PreviewStageState) -> String {
        switch state {
        case .closed: String(localized: "Closed", bundle: .module, comment: "Settings preview stage: state picker segment")
        case .activity: String(localized: "Activity", bundle: .module, comment: "Settings preview stage: state picker segment (a live activity in compact)")
        case .peek: String(localized: "Peek", bundle: .module, comment: "Settings preview stage: state picker segment")
        case .open: String(localized: "Open", bundle: .module, comment: "Settings preview stage: state picker segment")
        case .hud: String(localized: "HUD", bundle: .module, comment: "Settings: the HUD (volume and brightness overlay) as a name or column header")
        }
    }
}

#Preview("Control bar") {
    let registry = ModuleRegistry(services: .preview())
    StageControlBar(controller: StageController(registry: registry, state: .closed))
        .frame(width: 650)
}

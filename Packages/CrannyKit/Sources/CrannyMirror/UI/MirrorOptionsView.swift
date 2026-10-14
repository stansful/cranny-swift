// CrannyMirror/UI/MirrorOptionsView.swift — the widget's options popover (Settings ▸ Layout & Widgets and the
// card's ⋯ menu, DESIGN.md §11.1): camera and mirroring. System controls, so it follows Light/Dark in Settings
// and the dark panel alike (§11.3). Listing cameras never prompts and never turns a camera on.
import CrannyCore
import SwiftUI

struct MirrorOptionsView: View {
    let model: MirrorModel

    var body: some View {
        Form {
            Section {
                Picker(selection: model.cameraSelection) {
                    CameraChoices(model: model)
                } label: {
                    Text(verbatim: MirrorCopy.camera)
                }
                .pickerStyle(.menu)
                Toggle(isOn: Binding(get: { model.isMirrored }, set: { model.isMirrored = $0 })) {
                    Text(verbatim: MirrorCopy.mirrorImage)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            } footer: {
                Text(verbatim: MirrorCopy.optionsFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.catalog.activate() }
        .onDisappear { model.catalog.release() }
    }
}

#Preview("Options · two cameras") {
    MirrorOptionsView(model: .preview())
        .padding()
}

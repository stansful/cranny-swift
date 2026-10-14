// CrannyMirror/UI/CameraChoices.swift — the camera list shared by the toolbar's camera menu and the options popover:
// Automatic (the system's preferred camera), every connected camera, and a row for a picked camera that is not
// connected, so a picker never shows a blank value. Selecting writes `MirrorSettings.cameraID`; a running Mirror
// switches cameras (MirrorMachine `.devicesChanged`).
import CrannyCore
import SwiftUI

struct CameraChoices: View {
    let model: MirrorModel
    var separatesAutomatic = false

    var body: some View {
        Text(verbatim: MirrorCopy.automatic).tag(String?.none)
        if separatesAutomatic { Divider() }
        ForEach(model.catalog.devices) { device in
            Text(verbatim: device.isSuspended ? MirrorCopy.unavailableCamera(device.name) : device.name)
                .tag(String?.some(device.id))
        }
        // The pick is unplugged: the Mirror uses the preferred camera meanwhile and returns to it when it is back.
        if let missing = missingSelection {
            Text(verbatim: MirrorCopy.disconnected).tag(String?.some(missing))
        }
    }

    /// The stored camera ID when that camera is not connected.
    private var missingSelection: String? {
        guard let id = model.selectedCameraID, model.catalog.isLoaded,
              !model.catalog.devices.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}

extension MirrorModel {
    /// The camera menu's and the options picker's selection.
    var cameraSelection: Binding<String?> {
        Binding(get: { self.selectedCameraID }, set: { self.selectedCameraID = $0 })
    }
}

#Preview("Camera choices") {
    let model = MirrorModel.preview()
    Picker(selection: model.cameraSelection) {
        CameraChoices(model: model)
    } label: {
        Text(verbatim: MirrorCopy.camera)
    }
    .pickerStyle(.inline)
    .padding()
}

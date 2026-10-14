// CrannyNotchUI/Nook/CatchHost.swift — the drag "catch" state (DESIGN.md §8.3): while a file drag is in
// progress the open shape shows the Tray's drop zones (Keep in Tray, AirDrop, pinned pipelines), filtered by the
// dragged types. CrannyTray draws them (`TrayIntake.catchView(for:)`, each a `.crannyDropZone`); this view
// hosts them in the grid area. Without a Tray (module not registered) a single neutral zone says so — the
// shell still keeps any drop through its `TrayIntake.accept` fallback.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CatchHost: View {
    @Environment(\.notchZones) private var zones
    let types: [UTType]
    let registry: ModuleRegistry

    var body: some View {
        if let tray = registry.services.tray {
            tray.catchView(for: types)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DropZone(symbol: "tray.and.arrow.down.fill",
                     title: String(localized: "Drop files on the notch to keep them here", bundle: .module,
                                   comment: "Catch state: the only drop zone while the Tray is unavailable"),
                     targeted: zones?.armedDropZone == .trayKeep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("Catch · no Tray") {
    let (model, registry) = previewScene(.open, mode: .catchFiles([.fileURL]))
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}

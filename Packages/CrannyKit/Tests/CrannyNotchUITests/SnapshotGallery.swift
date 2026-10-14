// Opt-in visual gallery: every presentation × {notch, floating island, attached} × {standard, lit, highContrast,
// opaque}, plus the palette, the layout editor, Notes focus, the catch state, the HUD in the header, the
// satellite and hold-⌘ hints. Writes PNGs for a human (or a design QA script) to look at:
//
//   CRANNY_SNAPSHOT_DIR=/tmp/snapshots swift test --scratch-path .build-test --filter CrannyNotchUITests.SnapshotGallery
//
// writes into /tmp/snapshots/NotchUI. Never runs in CI (no directory set). The renders are the final state of each
// presentation.
import CrannyCore
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyNotchUI

nonisolated private let directory = SnapshotOutput.directory("NotchUI")

@MainActor @Suite(.enabled(if: directory != nil, "set CRANNY_SNAPSHOT_DIR to write the gallery"))
struct SnapshotGallery {
    private let displays: [(name: String, metrics: NotchMetrics, style: NoNotchStyle)] = [
        ("notch", PreviewDisplays.notch, .floatingIsland),
        ("island", PreviewDisplays.external, .floatingIsland),
        ("attached", PreviewDisplays.external, .attached),
    ]
    private let phases: [NotchPhase] = [.idle, .breath, .compact, .peek, .open]

    @Test func everyStateDisplayAndVariant() throws {
        let dir = try #require(directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for display in displays {
            for phase in phases {
                for variant in PreviewVariant.allCases {
                    let (model, registry) = previewScene(phase, metrics: display.metrics, style: display.style, variant: variant)
                    try write(model, registry, name: "\(phase.rawValue)-\(display.name)-\(variant.rawValue)", in: dir)
                }
            }
        }
    }

    @Test func modesAndExtras() throws {
        let dir = try #require(directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let extras: [(String, (NotchSceneModel, ModuleRegistry))] = [
            ("open-palette", previewScene(.open, palette: true)),
            ("open-edit", previewScene(.open, mode: .editLayout)),
            ("open-focus", previewScene(.open, mode: .focus(.notes))),
            ("open-catch", previewScene(.open, mode: .catchFiles([.fileURL]))),
            ("open-hud", previewScene(.open, hudInHeader: true)),
            ("open-confirmation", previewScene(.open, headerMessage: PreviewConfirmation.sentence)),
            ("open-island-palette", previewScene(.open, metrics: PreviewDisplays.external, palette: true)),
            ("compact-satellite", previewScene(.compact, satellite: true)),
            ("compact-timer", previewScene(.compact, sample: .timer)),
            ("compact-hud", previewScene(.compact, sample: .hud)),
            ("compact-meeting", previewScene(.compact, sample: .meeting)),
            ("compact-island-label", previewScene(.compact, metrics: PreviewDisplays.external)),
            ("peek-three", previewScene(.peek, peekRowCount: 3)),
        ]
        for (name, scene) in extras { try write(scene.0, scene.1, name: name, in: dir) }

        let (hints, registry) = previewScene(.open)
        hints.context.showsCommandHints = true
        try write(hints, registry, name: "open-hints", in: dir)
        let (flat, flatRegistry) = previewScene(.open)
        flat.theme.widgetStyle = .flat
        flat.layout = NotchLayout(metrics: .reference, grid: flat.theme.grid)          // the flat gutter widens the panel
        try write(flat, flatRegistry, name: "open-flat", in: dir)
        let (pinned, pinnedRegistry) = previewScene(.open, metrics: PreviewDisplays.external)
        pinned.pinned = true
        try write(pinned, pinnedRegistry, name: "open-island-pinned", in: dir)
    }

    private func write(_ model: NotchSceneModel, _ registry: ModuleRegistry, name: String, in dir: URL) throws {
        let size = CGSize(width: model.layout.canvasSize.width, height: model.layout.canvasSize.height)
        let image = try #require(Snapshot.image(model, registry, size: size, background: Color(white: 0.32)))
        try Snapshot.write(image, to: dir.appending(path: "\(name).png"))
    }
}

// CrannyNotchUI/Keyboard/NotchUIQAHooks.swift — DEBUG-only visual QA arguments that complement the shell's
// `--qa-state` (CrannyAppShell/App/QAHooks.swift, docs/CONTRIBUTING.md). They only ask the owner through
// `NotchUIActions` (the scene stays owner-written) or decorate what is drawn. Release builds compile only three
// inert answers (no mode, no hints, nothing applied) for the call sites outside `#if DEBUG`.
//
//   --qa-mode palette|edit|focus|catch   with --qa-state open: switch the open panel to that mode once
//   --qa-hints                           show the hold-⌘ key caps as if ⌘ were held
//   --qa-snapshot <file.png>             3 s after launch, render the primary canvas offscreen (ImageRenderer,
//                                        final state, on mid-grey) to that PNG: QA while the displays sleep,
//                                        when the window server has no image of the panel to capture
import CrannyCore
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum NotchUIQAHooks {
    #if DEBUG
    static let arguments = LaunchArguments.current

    /// The mode `--qa-mode` asks for (nil = none).
    static var mode: NookMode? { mode(in: arguments.values) }

    /// `--qa-mode` is applied once per launch, on the first open.
    @MainActor static var didApplyMode = false

    /// `--qa-hints`.
    static var showsHints: Bool { arguments.contains("--qa-hints") }

    /// `--qa-snapshot <file.png>` (nil = none). Any other value is a directory for the shell's window snapshots
    /// (CrannyAppShell/App/QAHooks.swift); `LaunchArguments.qaPanelSnapshot` holds the rule.
    static var snapshotPath: String? { arguments.qaPanelSnapshot }

    /// One snapshot per launch (the first canvas that asks: the primary panel's).
    @MainActor static var didSnapshot = false

    /// Renders the canvas of `model` offscreen and writes it to `snapshotPath` (DEBUG visual QA only).
    @MainActor static func writeSnapshot(model: NotchSceneModel, registry: ModuleRegistry, actions: NotchUIActions) async {
        guard let path = snapshotPath, !didSnapshot, !model.context.isPreview else { return }
        do { try await Task.sleep(for: .seconds(3)) } catch { return }       // after --qa-state / --qa-mode settled
        guard !didSnapshot, model.phase != .hidden else { return }
        didSnapshot = true
        let size = model.layout.canvasSize
        let view = NotchCanvasView(model: model, registry: registry, actions: actions)
            .environment(\.notchRendersFinalState, true)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.25))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let file = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(file, image, nil)
        _ = CGImageDestinationFinalize(file)
    }

    static func mode(in arguments: [String]) -> NookMode? {
        switch LaunchArguments(arguments).value(after: "--qa-mode") {
        case "palette": .palette
        case "edit": .editLayout
        case "focus": .focus(.notes)
        case "catch": .catchFiles([.fileURL])
        default: nil
        }
    }
    #else
    // Release: inert answers for the two call sites outside `#if DEBUG`; nothing else is compiled.
    static var mode: NookMode? { nil }
    @MainActor static var didApplyMode = false
    static var showsHints: Bool { false }
    #endif
}

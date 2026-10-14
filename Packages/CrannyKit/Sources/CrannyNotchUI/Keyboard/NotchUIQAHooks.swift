// CrannyNotchUI/Keyboard/NotchUIQAHooks.swift — DEBUG-only visual QA arguments that complement the shell's
// `--qa-state` (CrannyAppShell/App/QAHooks.swift, docs/CONTRIBUTING.md). They only ask the owner through
// `NotchUIActions` (the scene stays owner-written) or decorate what is drawn; Release builds compile none of it.
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
    static let arguments = ProcessInfo.processInfo.arguments
    #else
    static let arguments: [String] = []
    #endif

    /// The mode `--qa-mode` asks for (nil = none, or a Release build).
    static var mode: NookMode? { mode(in: arguments) }

    /// `--qa-mode` is applied once per launch, on the first open.
    @MainActor static var didApplyMode = false

    /// `--qa-hints` (always false in Release builds).
    static var showsHints: Bool { arguments.contains("--qa-hints") }

    /// `--qa-snapshot <file.png>` (nil = none, or a Release build).
    static var snapshotPath: String? {
        guard let i = arguments.firstIndex(of: "--qa-snapshot"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

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
        guard let i = arguments.firstIndex(of: "--qa-mode"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "palette": return .palette
        case "edit": return .editLayout
        case "focus": return .focus(.notes)
        case "catch": return .catchFiles([.fileURL])
        default: return nil
        }
    }
}

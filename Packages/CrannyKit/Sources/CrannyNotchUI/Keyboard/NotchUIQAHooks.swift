// CrannyNotchUI/Keyboard/NotchUIQAHooks.swift — DEBUG-only visual QA arguments that complement the shell's
// `--qa-state` (CrannyAppShell/App/QAHooks.swift, docs/CONTRIBUTING.md). They only ask the owner through
// `NotchUIActions` (the scene stays owner-written) or decorate what is drawn; Release builds compile none of it.
//
//   --qa-mode palette|edit|focus|catch   with --qa-state open: switch the open panel to that mode once
//   --qa-hints                           show the hold-⌘ key caps as if ⌘ were held
import CrannyCore
import Foundation
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

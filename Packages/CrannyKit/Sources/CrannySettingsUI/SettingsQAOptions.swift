// CrannySettingsUI/SettingsQAOptions.swift — Debug-only visual QA options of the Settings window, read from launch
// arguments (the argument domain of `UserDefaults`), next to the shell's `--qa-settings <pane[#row]>`:
//
//   -CrannyQAStageState closed|activity|peek|open|hud   the preview stage starts in this state on every pane
//   -CrannyQASearch "<text>"                            the sidebar search field starts with this text
//   -CrannyQAKeepStageLive YES                          keep the live stage while the window is occluded (the
//                                                       screen is locked during scripted captures)
//
// No input is synthesized. Compiled out of Release builds (the options are always nil there).
import CrannyCore
import Foundation

enum SettingsQAOptions {
    /// Overrides the pane's own stage state.
    static var stageState: PreviewStageState? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CrannyQAStageState").flatMap(PreviewStageState.init(rawValue:))
        #else
        nil
        #endif
    }

    /// Keep rendering the stage while the window reports itself occluded.
    static var keepsStageLive: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CrannyQAKeepStageLive")
        #else
        false
        #endif
    }

    /// Initial text of the search field.
    static var search: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CrannyQASearch")
        #else
        nil
        #endif
    }
}

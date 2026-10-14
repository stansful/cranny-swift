// Every label the app hands to the flash (`NotchControl.flash`, `OverlayCoordinator.showFlash`/`presentFlash`), for
// `FlashLabelFitTests`. The modules' own accessors are read here, in a file that imports no other module's
// `Bundle.module`, so a renamed key or a new wording shows up as a mismatch. A new flash label belongs in this list.
import CrannyCore
import Foundation
@testable import CrannyOnboarding
@testable import CrannyQuickApps
@testable import CrannyTray

/// One flash label: the String Catalog it comes from, its key (the English text), the glyph it is shown with and the
/// source files that pass it to the flash.
struct FlashLabelSource: CustomStringConvertible, Sendable {
    /// The target whose String Catalog holds the key; nil for a name that is never translated.
    let module: String?
    let key: String
    let symbol: String
    /// Source files (relative to `Sources/`) that show it.
    let files: [String]
    /// What the code returns for it now (in the test process's language), when the code has an accessor.
    let current: String?

    var description: String { "\(module ?? "verbatim"): \(key)" }
}

enum FlashLabelCatalog {
    /// The modules' labels, read through their own accessors.
    @MainActor static var modules: [FlashLabelSource] {
        [
            FlashLabelSource(module: "CrannyOnboarding", key: "Hi", symbol: "hand.wave.fill",
                             files: ["CrannyOnboarding/Model/WelcomeFlow.swift"], current: WelcomeFlow.greeting),
            FlashLabelSource(module: "CrannyTray", key: "Copied", symbol: "link",
                             files: ["CrannyTray/Store/TrayStore+Actions.swift", "CrannyTray/Store/TrayStore+Pipelines.swift"],
                             current: TrayStore.copiedLabel),
            FlashLabelSource(module: "CrannyTray", key: "Copied", symbol: "doc.on.doc",
                             files: ["CrannyTray/Store/TrayStore+Pipelines.swift"], current: TrayStore.copiedLabel),
            FlashLabelSource(module: "CrannyQuickApps", key: "Done", symbol: "checkmark.circle.fill",
                             files: ["CrannyQuickApps/Model/QuickAppsModel.swift"], current: nil),
            FlashLabelSource(module: "CrannyQuickApps", key: "Failed", symbol: "exclamationmark",
                             files: ["CrannyQuickApps/Model/QuickAppsModel.swift"], current: QuickAppsModel.failedLabel),
        ]
    }
}

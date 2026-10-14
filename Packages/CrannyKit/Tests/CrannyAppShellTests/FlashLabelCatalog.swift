// Every label the app hands to the flash (`NotchControl.flash`, `OverlayCoordinator.showFlash`/`presentFlash`), for
// `FlashLabelFitTests`. The modules' own accessors are read here, in a file that imports no other module's
// `Bundle.module`, so a renamed key or a new wording shows up as a mismatch. Each label names the calls that show it,
// written as in the code; the tests scan the sources for every flash call, so a new call (a new label, or a known
// label with another glyph) must be listed here before it passes.
import CrannyCore
import Foundation
@testable import CrannyOnboarding
@testable import CrannyQuickApps
@testable import CrannyTray

/// One call that shows a flash: the source file (relative to `Sources/`) and its `symbol:` and `label:` arguments as
/// the code writes them.
struct FlashCallSite: Hashable, Sendable, CustomStringConvertible {
    let file: String
    let symbol: String
    let label: String

    var description: String { "\(file): symbol: \(symbol), label: \(label)" }
}

/// One flash label: the String Catalog it comes from, its key (the English text), the glyph it is shown with and the
/// calls that show it.
struct FlashLabelSource: CustomStringConvertible, Sendable {
    /// The target whose String Catalog holds the key; nil for a name that is never translated.
    let module: String?
    let key: String
    let symbol: String
    /// The calls that show it (a call may show several labels: the pause confirmation's word is "Paused" or "Resumed").
    let sites: [FlashCallSite]
    /// What the code returns for it now (in the test process's language); nil only for a name that is never translated.
    let current: String?
    /// The glyph the code returns now, for calls that name it in code rather than as a literal.
    let currentSymbol: String?

    init(module: String?, key: String, symbol: String, sites: [FlashCallSite], current: String?,
         currentSymbol: String? = nil) {
        self.module = module; self.key = key; self.symbol = symbol; self.sites = sites
        self.current = current; self.currentSymbol = currentSymbol
    }

    var description: String { "\(module ?? "verbatim"): \(key)" }
}

enum FlashLabelCatalog {
    /// The modules' labels, read through their own accessors.
    @MainActor static var modules: [FlashLabelSource] {
        let tray = ["CrannyTray/Store/TrayStore+Actions.swift", "CrannyTray/Store/TrayStore+Pipelines.swift"]
        let quickApps = "CrannyQuickApps/Model/QuickAppsModel.swift"
        return [
            FlashLabelSource(module: "CrannyOnboarding", key: "Hi", symbol: "hand.wave.fill",
                             sites: [FlashCallSite(file: "CrannyOnboarding/Model/WelcomeFlow.swift",
                                                   symbol: "StageGreeting.symbol", label: "Self.greeting")],
                             current: WelcomeFlow.greeting, currentSymbol: StageGreeting.symbol),
            FlashLabelSource(module: "CrannyTray", key: "Copied", symbol: "doc.on.doc",
                             sites: tray.map { FlashCallSite(file: $0, symbol: "\"doc.on.doc\"", label: "Self.copiedLabel") },
                             current: TrayStore.copiedLabel),
            FlashLabelSource(module: "CrannyQuickApps", key: "Done", symbol: "checkmark.circle.fill",
                             sites: [FlashCallSite(file: quickApps, symbol: "\"checkmark.circle.fill\"", label: "Self.doneLabel")],
                             current: QuickAppsModel.doneLabel),
            FlashLabelSource(module: "CrannyQuickApps", key: "Failed", symbol: "exclamationmark",
                             sites: [FlashCallSite(file: quickApps, symbol: "\"exclamationmark\"", label: "Self.failedLabel")],
                             current: QuickAppsModel.failedLabel),
        ]
    }
}

// Every flash label fits the compact wing (design ruling E4, ARCHITECTURE.md §10.20 #26): each label the modules and
// the shell show in the flash, in English and Russian, drawn by `FlashActivity` in its wing at the notch units of
// every whole-point band height from 0.8 to 1.25. The fit is measured, never counted in characters («Скопировано» has
// 11 characters and is 88 pt wide at 1u). A label that fits no wing leaves the glyph alone in the wings and stays in
// the peek row and for VoiceOver. No windows are shown.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI
import Testing
@testable import CrannyAppShell

/// The notch units of whole-point band heights (`NotchMetrics.unit`, 0.8–1.25). `WingTextMetrics` decides at a
/// finer grid; rendering every one of those would take too long.
private let bandUnits: [CGFloat] = [0.8] + (26...40).map { CGFloat($0) / 32 }

/// The shell's own labels (its `Bundle.module` is this file's).
@MainActor private var shellLabels: [FlashLabelSource] {
    [
        FlashLabelSource(module: "CrannyAppShell", key: "Paused", symbol: "pause.fill",
                         files: ["CrannyAppShell/Overlay/OverlayCoordinator+Control.swift"],
                         current: PauseConfirmation.paused(.oneHour).label),
        FlashLabelSource(module: "CrannyAppShell", key: "Resumed", symbol: "play.fill",
                         files: ["CrannyAppShell/Overlay/OverlayCoordinator+Control.swift"],
                         current: PauseConfirmation.resumed.label),
        // Show on Notch without a sample activity: the app's name, never translated.
        FlashLabelSource(module: nil, key: "Cranny", symbol: "sparkles",
                         files: ["CrannyAppShell/Overlay/OverlayCoordinator+Control.swift"], current: nil),
        // Visual QA's sample (Debug builds only).
        FlashLabelSource(module: "CrannyAppShell", key: "Hi", symbol: "hand.wave.fill",
                         files: ["CrannyAppShell/Overlay/OverlayCoordinator+Control.swift"], current: nil),
    ]
}

@MainActor private var allLabels: [FlashLabelSource] { shellLabels + FlashLabelCatalog.modules }

/// The label in `language` from its module's String Catalog, as the app bundles it.
@MainActor private func text(of source: FlashLabelSource, in language: String) throws -> String {
    guard let module = source.module else { return source.key }
    // SwiftPM puts every module's resource bundle beside the shell's.
    let url = Bundle.module.bundleURL.deletingLastPathComponent().appending(path: "CrannyKit_\(module).bundle")
    let bundle = try #require(Bundle(url: url), "no resource bundle for \(module)")
    let missing = "\u{0}"
    if language == "en" {
        let english = bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        return english?.localizedString(forKey: source.key, value: source.key, table: "Localizable") ?? source.key
    }
    let localized = try #require(bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                                 "\(module) has no \(language).lproj")
    let value = localized.localizedString(forKey: source.key, value: missing, table: "Localizable")
    try #require(value != missing && !value.isEmpty, "\(source) has no \(language) translation")
    return value
}

/// What the wings draw: the trailing wing's width, and the content width of the flash's slot.
@MainActor private func drawn(_ flash: FlashActivity, unit: CGFloat) -> (label: CGFloat, glyph: CGFloat, wing: CGFloat) {
    var theme = CrannyTheme()
    theme.notchUnit = unit
    let label = NSHostingView(rootView: flash.compactTrailing().fixedSize().crannyThemeRoot(theme)).fittingSize.width
    let glyph = NSHostingView(rootView: flash.compactLeading().fixedSize().crannyThemeRoot(theme)).fittingSize.width
    return (label, glyph, WingTextMetrics.contentWidth(flash.slot, notchUnit: unit))
}

@MainActor @Suite("Flash labels fit the wing (ruling E4)") struct FlashLabelFitTests {
    @Test(arguments: ["en", "ru"]) func everyFlashLabelFitsItsWing(language: String) throws {
        for source in allLabels {
            let label = try text(of: source, in: language)
            let flash = FlashActivity()
            flash.show(symbol: source.symbol, label: label, duration: 60)
            #expect(flash.showsLabelInWings && FlashActivity.labelSlots.contains(flash.slot), "\(source) «\(label)» fits no wing")
            for unit in bandUnits {
                let (width, glyph, wing) = drawn(flash, unit: unit)
                #expect(width > 0 && width <= wing, "«\(label)» at \(unit)u: \(width) pt in a \(wing)-pt wing")
                #expect(glyph <= wing, "\(source.symbol) at \(unit)u: \(glyph) pt in a \(wing)-pt wing")
            }
            flash.hide()
        }
    }

    /// The table names what the code shows: each accessor returns its key's English or Russian text.
    @Test func theTableMatchesTheCode() throws {
        for source in allLabels {
            guard let current = source.current else { continue }
            let texts = try ["en", "ru"].map { try text(of: source, in: $0) }
            #expect(texts.contains(current), "\(source): the code shows «\(current)», the table expects \(texts)")
        }
    }

    /// Every source file that shows a flash is in the table, so a new label cannot skip the test above.
    @Test func everyFileThatShowsAFlashIsListed() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        let calls = [".flash(symbol:", "showFlash(", "presentFlash(", "flashActivity.show("]
        // The port and its forwarding: they pass a caller's label on.
        let forwarding: Set<String> = ["CrannyAppShell/Services/ShellNotchControl.swift"]
        var showing = Set<String>()
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "#Preview(").first ?? ""
            let lines = code.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.contains(where: { line in
                !line.hasPrefix("//") && !line.contains("func ") && calls.contains { line.contains($0) }
            }) {
                showing.insert(file.standardizedFileURL.pathComponents
                    .dropFirst(sources.standardizedFileURL.pathComponents.count).joined(separator: "/"))
            }
        }
        #expect(showing.count >= 5)
        let listed = Set(allLabels.flatMap(\.files)).union(forwarding)
        #expect(showing.subtracting(listed).isEmpty, "add their labels to FlashLabelCatalog: \(showing.subtracting(listed).sorted())")
    }

    /// A label no wing holds (here a sentence) keeps the glyph alone in the wings, in the narrowest slot; the peek row and
    /// VoiceOver still say it. «Скопировано», the Tray's old word, is such a label although it has 11 characters.
    @Test(arguments: ["Copied to the clipboard", "Скопировано"]) func aLabelThatFitsNoWingLeavesTheGlyphAlone(label: String) {
        let flash = FlashActivity()
        flash.show(symbol: "doc.on.doc", label: label, duration: 60)
        #expect(!flash.showsLabelInWings && flash.slot == .glyph && flash.accessibilityLabel == label)
        for unit in bandUnits {
            let (width, glyph, wing) = drawn(flash, unit: unit)
            #expect(width == 0 && glyph <= wing, "\(label) at \(unit)u: label \(width), glyph \(glyph) in \(wing)")
        }
        flash.show(symbol: "doc.on.doc", label: "Hi", duration: 60)                // the next flash measures again
        #expect(flash.showsLabelInWings && flash.slot == .medium)
        flash.hide()
    }
}

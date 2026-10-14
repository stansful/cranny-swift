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
    let control = "CrannyAppShell/Overlay/OverlayCoordinator+Control.swift"
    // `confirmPause`: one call shows either word of the pause confirmation.
    let confirmation = FlashCallSite(file: control, symbol: "confirmation.symbol", label: "confirmation.label")
    return [
        FlashLabelSource(module: "CrannyAppShell", key: "Paused", symbol: "pause.fill", sites: [confirmation],
                         current: PauseConfirmation.paused(.oneHour).label,
                         currentSymbol: PauseConfirmation.paused(.oneHour).symbol),
        FlashLabelSource(module: "CrannyAppShell", key: "Resumed", symbol: "play.fill", sites: [confirmation],
                         current: PauseConfirmation.resumed.label, currentSymbol: PauseConfirmation.resumed.symbol),
        // Show on Notch without a sample activity: the app's name, never translated.
        FlashLabelSource(module: nil, key: "Cranny", symbol: "sparkles",
                         sites: [FlashCallSite(file: control, symbol: "\"sparkles\"", label: "\"Cranny\"")], current: nil),
        // Visual QA's sample (Debug builds only).
        FlashLabelSource(module: "CrannyAppShell", key: "Hi", symbol: "hand.wave.fill",
                         sites: [FlashCallSite(file: control, symbol: "\"hand.wave.fill\"", label: "QAHooks.sampleLabel")],
                         current: qaSampleLabel),
    ]
}

/// `QAHooks.sampleLabel`, which only Debug builds have.
@MainActor private var qaSampleLabel: String? {
    #if DEBUG
    QAHooks.sampleLabel
    #else
    nil
    #endif
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

    /// The table names what the code shows: each accessor returns its key's English or Russian text, each call's
    /// glyph is the one listed, and every word of the pause confirmation is in the table.
    @Test func theTableMatchesTheCode() throws {
        for source in allLabels {
            if source.module == nil {
                #expect(source.sites.allSatisfy { $0.label == "\"\(source.key)\"" }, "\(source): not shown verbatim")
            } else if let current = source.current {
                let texts = try ["en", "ru"].map { try text(of: source, in: $0) }
                #expect(texts.contains(current), "\(source): the code shows «\(current)», the table expects \(texts)")
            } else {
                #if DEBUG
                Issue.record("\(source): no accessor to compare with")
                #endif
            }
            for site in source.sites {
                if site.symbol.hasPrefix("\"") {
                    #expect(site.symbol == "\"\(source.symbol)\"", "\(site): the table expects \(source.symbol)")
                } else {
                    #expect(source.currentSymbol == source.symbol, "\(site): the code shows \(source.currentSymbol ?? "?")")
                }
            }
        }
        let confirmations = PauseDuration.allCases.map(PauseConfirmation.paused) + [.resumed]
        for confirmation in confirmations {
            #expect(allLabels.contains { $0.current == confirmation.label && $0.symbol == confirmation.symbol },
                    "\(confirmation): «\(confirmation.label)» with \(confirmation.symbol) is not in the table")
        }
    }

    /// Every call in `Sources/` that shows a flash is in the table as written, glyph and label, so a new label (also
    /// in a file that already shows one) or a known label with another glyph cannot skip the test above. A call that
    /// passes on its caller's label must sit in a function whose own calls are scanned.
    @Test func everyFlashCallIsListed() throws {
        let scan = try FlashCallScan.sources()
        for forward in scan.forwarding {
            #expect(FlashCallScan.forwarders.contains(forward.function),
                    "\(forward.site) passes on the label of \(forward.function)(…), whose calls are not scanned")
        }
        #expect(scan.forwarding.count >= 4 && scan.sites.count >= 8)
        let listed = Set(allLabels.flatMap(\.sites))
        #expect(scan.sites.subtracting(listed).isEmpty,
                "add to FlashLabelCatalog: \(scan.sites.subtracting(listed).map(\.description).sorted())")
        #expect(listed.subtracting(scan.sites).isEmpty,
                "no longer in the code: \(listed.subtracting(scan.sites).map(\.description).sorted())")
    }

    /// The scan reads calls across lines, skips declarations, comments and previews, and tells a forwarded label from
    /// a listed one.
    @Test func theScanReadsCallsAsWritten() {
        let code = """
        /// Shows `NotchControl.flash(symbol:label:)` once.
        func report(symbol: String, label: String) {
            notch.flash(symbol: symbol, label: label)   // passes it on
        }
        func reportInNotch(_ entry: Entry, symbol: String, label: String) {}
        func done() {
            reportInNotch(entry, symbol: "checkmark",
                          label: String(localized: "Done (\\(n), now)", comment: "a, b"),
                          announcement: x(1, 2))
            showFlash(symbol: s.glyph, label: [a, b].joined(separator: ", "), duration: 1)
        }
        #Preview("x") { notch.flash(symbol: "eye", label: "Preview") }
        """
        let scan = FlashCallScan.scan(code, file: "M/F.swift")
        #expect(scan.sites == [
            FlashCallSite(file: "M/F.swift", symbol: "\"checkmark\"", label: "String(localized: \"Done (\\(n), now)\", comment: \"a, b\")"),
            FlashCallSite(file: "M/F.swift", symbol: "s.glyph", label: "[a, b].joined(separator: \", \")"),
        ])
        #expect(scan.forwarding.map { $0.function } == ["report"])
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

/// Every call that shows a flash, read from the sources: its glyph and label arguments as written, and the calls that
/// pass their caller's label on (with the function they are in).
private struct FlashCallScan {
    var sites: Set<FlashCallSite> = []
    var forwarding: [(site: FlashCallSite, function: String)] = []

    /// The calls that show a flash: the port, the coordinator's two entry points, the activity itself and Quick Apps'
    /// helper that passes a label on.
    static let calls = [".flash(symbol:", "showFlash(", "presentFlash(", "flashActivity.show(", "reportInNotch("]
    /// The functions those calls reach, which may pass their own `label` on (the port's `flash`, the coordinator's,
    /// Quick Apps' `reportInNotch`).
    static let forwarders: Set<String> = ["flash", "showFlash", "presentFlash", "reportInNotch"]

    static func sources() throws -> FlashCallScan {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var all = FlashCallScan()
        for file in files {
            let path = file.standardizedFileURL.pathComponents
                .dropFirst(sources.standardizedFileURL.pathComponents.count).joined(separator: "/")
            let found = scan(try String(contentsOf: file, encoding: .utf8), file: path)
            all.sites.formUnion(found.sites)
            all.forwarding += found.forwarding
        }
        return all
    }

    /// The calls in one file's code, before its first `#Preview`, without comment lines and trailing comments.
    static func scan(_ source: String, file: String) -> FlashCallScan {
        let code = (source.components(separatedBy: "#Preview(").first ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .map { line in line.range(of: " //").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
        var result = FlashCallScan()
        for call in calls {
            var searchFrom = code.startIndex
            while let match = code.range(of: call, range: searchFrom..<code.endIndex) {
                searchFrom = match.upperBound
                guard !code[..<match.lowerBound].hasSuffix("func "),
                      let open = code[match].firstIndex(of: "(") else { continue }
                let arguments = labelledArguments(code, from: open)
                guard let symbol = arguments["symbol"], let label = arguments["label"] else { continue }
                let site = FlashCallSite(file: file, symbol: symbol, label: label)
                if label == "label" {
                    result.forwarding.append((site, enclosingFunction(code, before: match.lowerBound)))
                } else {
                    result.sites.insert(site)
                }
            }
        }
        return result
    }

    /// The labelled arguments of the call whose `(` is at `open`, as written (whitespace runs collapsed).
    private static func labelledArguments(_ code: String, from open: String.Index) -> [String: String] {
        var parts: [String] = [], current = "", depth = 0, inString = false, escaped = false
        for character in code[open...] {
            if inString {
                current.append(character)
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"":
                inString = true
                current.append(character)
            case "(", "[", "{":
                depth += 1
                if depth > 1 { current.append(character) }
            case ")", "]", "}":
                depth -= 1
                if depth == 0 {
                    parts.append(current)
                    return Dictionary(parts.compactMap(labelled), uniquingKeysWith: { first, _ in first })
                }
                current.append(character)
            case "," where depth == 1:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        return [:]
    }

    private static func labelled(_ argument: String) -> (String, String)? {
        let words = argument.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let colon = words.firstIndex(of: ":") else { return nil }
        let name = String(words[..<colon])
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter }) else { return nil }
        return (name, words[words.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    /// The name of the last function declared before `index`.
    private static func enclosingFunction(_ code: String, before index: String.Index) -> String {
        guard let declaration = code.range(of: "func ", options: .backwards, range: code.startIndex..<index) else { return "" }
        return String(code[declaration.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
    }
}

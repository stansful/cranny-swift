// Symbols resolve, every catalog key is translated into Russian, and the views render.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyMirror

@MainActor struct MirrorResourceTests {
    @Test(arguments: MirrorSymbol.all)
    func symbolExists(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    @Test func symbolsAvoidRestrictedOnes() {
        // `video*` glyphs may only refer to FaceTime (DESIGN.md §14.1).
        #expect(MirrorSymbol.all.allSatisfy { !$0.hasPrefix("video") })
    }

    /// The source catalog, read from disk (the tests see every key and its Russian value whatever the locale).
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/CrannyMirror/Resources/Localizable.xcstrings")

    private func catalogStrings() throws -> [String: Any] {
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Self.catalogURL)) as? [String: Any])
        return try #require(catalog["strings"] as? [String: Any])
    }

    /// Reads the source catalog: every key needs a "Surface: purpose" comment and a translated Russian value.
    @Test func everyKeyIsTranslatedIntoRussian() throws {
        let strings = try catalogStrings()
        #expect(strings.count >= 25)
        for (key, value) in strings {
            let entry = try #require(value as? [String: Any], "\(key)")
            let comment = entry["comment"] as? String ?? ""
            #expect(comment.contains(": "), "comment of \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "localizations of \(key)")
            let ru = try #require(localizations["ru"] as? [String: Any], "ru for \(key)")
            let unit = try #require(ru["stringUnit"] as? [String: Any], "ru unit for \(key)")
            let state = unit["state"] as? String
            let value = unit["value"] as? String ?? ""
            #expect(state == "translated", "ru state for \(key)")
            #expect(!value.isEmpty, "ru value for \(key)")
        }
    }

    @Test func noCompetitorTermsInCopy() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        for term in ["nook", "boring.notch", "alcove", "atoll"] { #expect(!text.contains(term), "\(term)") }
    }

    // MARK: Chips

    /// Every chip title of the catalog (comment "Mirror widget: chip …") in English and Russian.
    private func chipTitles() throws -> [(en: String, ru: String)] {
        try catalogStrings().compactMap { key, value in
            let entry = try #require(value as? [String: Any], "\(key)")
            guard (entry["comment"] as? String ?? "").hasPrefix("Mirror widget: chip") else { return nil }
            let localizations = entry["localizations"] as? [String: Any]
            let unit = (localizations?["ru"] as? [String: Any])?["stringUnit"] as? [String: Any]
            return (en: key, ru: try #require(unit?["value"] as? String, "ru for \(key)"))
        }
    }

    /// A chip title is one line with no room to wrap: every title, in both languages, fits the card at its minimum
    /// size at every density and text size, without the view's safety scale-down. "Open System Settings" would not
    /// fit, and "Open Settings" was clipped in compact density.
    @Test func chipTitlesFitTheNarrowestCard() throws {
        let chips = try chipTitles()
        // Both chips the widget draws are covered (in whichever language the tests run).
        for title in [MirrorCopy.allowCamera, MirrorCopy.tryAgain] {
            #expect(chips.contains { $0.en == title || $0.ru == title }, "\(title)")
        }
        let cells = MirrorWidget(model: .preview()).sizes.minimum
        let caption = CrannyTextStyle.caption
        for density in NookDensity.allCases {
            for textSize in CrannyTextSize.allCases {
                let grid = NookGrid(density: density, textSize: textSize)        // cards: the narrower gutter
                let room = grid.width(cells: cells) - 2 * density.cardPadding - 2 * MirrorMetrics.chipPadding
                let font = NSFont.systemFont(ofSize: caption.pointSize(textSize: textSize, notchUnit: 1), weight: .semibold)
                for title in chips.flatMap({ [$0.en, $0.ru] }) {
                    let width = NSAttributedString(string: title, attributes: [.font: font, .kern: caption.spec.tracking])
                        .size().width
                    #expect(width <= room, "\(title): \(width) pt > \(room) pt (\(density), \(textSize))")
                }
            }
        }
    }

    /// In Cranny, "Settings" (the panel's gear, ⌘,) is Cranny's own Settings. A chip that leads to System Settings
    /// says what it is for ("Allow…") or names System Settings in full, in both languages.
    @Test func chipsNeverSayJustSettings() throws {
        let chips = try chipTitles()
        #expect(!chips.isEmpty)
        for chip in chips {
            #expect(!chip.en.contains("Settings") || chip.en.contains("System Settings"), "\(chip.en)")
            let ru = chip.ru.lowercased()
            #expect(!ru.contains("настройк") || ru.contains("системн"), "\(chip.ru)")
        }
    }

    @Test(arguments: [2, 3])
    func widgetRendersEveryState(cells: Int) throws {
        let grid = CrannyTheme().grid
        let size = CGSize(width: grid.width(cells: cells), height: grid.height)
        let context = WidgetContext(cells: cells, contentSize: size)
        let models: [(String, MirrorModel)] = [
            ("off", .preview()),
            ("running", .preview(phase: .running(deviceID: "sample.builtIn"))),
            ("denied", .preview(authorization: .denied)),
            ("failed", .preview(phase: .problem(.sessionFailed))),
            ("lid", .preview(phase: .problem(.suspended), cameras: SampleCameraDiscovery.lidClosed)),
        ]
        for (name, model) in models {
            let view = MirrorWidgetView(model: model, context: context)
                .crannyCard(cells: cells, frameless: true)
                .background(.black)
                .crannyThemeRoot(CrannyTheme())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "\(name)")
            #expect(image.width == Int(size.width * 2) && image.height == Int(size.height * 2), "\(name)")
            if let dir = ProcessInfo.processInfo.environment["CRANNY_MIRROR_SNAPSHOTS"] {
                try writePNG(image, to: URL(fileURLWithPath: dir).appending(path: "mirror-\(name)-\(cells).png"))
            }
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}

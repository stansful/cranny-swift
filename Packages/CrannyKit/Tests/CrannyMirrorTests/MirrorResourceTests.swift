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

    /// Reads the source catalog: every key needs a "Surface: purpose" comment and a translated Russian value.
    @Test func everyKeyIsTranslatedIntoRussian() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CrannyMirror/Resources/Localizable.xcstrings")
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
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
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CrannyMirror/Resources/Localizable.xcstrings")
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()
        for term in ["nook", "boring.notch", "alcove", "atoll"] { #expect(!text.contains(term), "\(term)") }
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

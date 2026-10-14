import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CrannyCore

@MainActor @Suite("Design system components") struct DesignSystemTests {
    // MARK: Hit targets (DESIGN.md §2.3, §16: at least 28 × 24 inside the Nook)

    private func fittingSize(_ view: some View) -> CGSize {
        NSHostingView(rootView: view.crannyThemeRoot(CrannyTheme())).fittingSize
    }

    /// A button's hit area is its own frame, so a chip or link is clickable over 28 × 24 only if the style makes the
    /// button that large (a frame added outside the `Button` does not widen it; see `chipTakesClicksOutsideItsCapsule`).
    @Test func chipsAndLinksAreAtLeastTheNookHitTarget() {
        for title in ["+1", "Clear", "Show your events"] {
            for style in [CrannyChipButtonStyle(), CrannyChipButtonStyle(tint: .red, prominent: true)] {
                let size = fittingSize(Button {} label: { Text(verbatim: title) }.buttonStyle(style))
                #expect(size.width >= HitTarget.nook.width && size.height >= HitTarget.nook.height, "\(title): \(size)")
            }
            let link = fittingSize(Button {} label: { Text(verbatim: title) }.buttonStyle(CrannyLinkButtonStyle()))
            #expect(link.width >= HitTarget.nook.width && link.height >= HitTarget.nook.height, "\(title): \(link)")
        }
        #expect(CrannyChipButtonStyle.height < HitTarget.nook.height)       // the drawn capsule stays 22 pt
    }

    /// Clicks a chip 11.5 pt above its centre: outside the 22-pt capsule, inside the 24-pt button. In-process only
    /// (`NSWindow.sendEvent` on an offscreen window, no system input), but it orders a window in, so it is opt-in.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"))
    func chipTakesClicksOutsideItsCapsule() throws {
        final class Clicks { var count = 0 }
        let clicks = Clicks()
        let root = Button { clicks.count += 1 } label: { Text(verbatim: "Clear") }
            .buttonStyle(CrannyChipButtonStyle())
            .frame(width: 200, height: 40)
            .crannyThemeRoot(CrannyTheme())
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 200, height: 40), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func click(_ point: NSPoint) throws -> Int {
            clicks.count = 0
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            return clicks.count
        }
        #expect(try click(NSPoint(x: 100, y: 20)) == 1)                    // the capsule
        #expect(try click(NSPoint(x: 100, y: 31.5)) == 1)                  // 0.5 pt beyond the capsule's edge
        #expect(try click(NSPoint(x: 100, y: 34)) == 0)                    // beyond the 24-pt button
    }

    // MARK: Symbols (DESIGN.md §14.1)

    @Test func symbolStylesScaleLikeTheirTextStyles() {
        #expect(CrannySymbolStyle.band.pointSize(textSize: .extraLarge, notchUnit: 1) == 13)       // band: notch unit only
        #expect(CrannySymbolStyle.band.pointSize(textSize: .standard, notchUnit: 1.2) == 16)
        #expect(CrannySymbolStyle.widgetState.pointSize(textSize: .standard, notchUnit: 2) == 20)  // Nook: Text Size only
        #expect(CrannySymbolStyle.widgetState.pointSize(textSize: .large, notchUnit: 1) == 22)
        #expect(CrannySymbolStyle.allCases.allSatisfy { $0.pointSize(textSize: .small, notchUnit: 0.5) >= 10 })
        #expect(CrannySymbolStyle.band.spec.weight == .semibold && CrannySymbolStyle.nook.spec.weight == .medium)
    }

    @Test func symbolsMoveOnlyWhenMotionAllowsIt() {
        var theme = CrannyTheme()
        #expect(theme.animatesSymbols && theme.symbolReplace == .symbolEffect(.replace))
        theme.motion = .instant
        #expect(!theme.animatesSymbols && theme.symbolReplace == .identity)
        theme.motion = .calm
        theme.reduceMotion = true
        #expect(!theme.animatesSymbols && theme.symbolReplace == .identity)
    }

    // MARK: Marquee (DESIGN.md §2.2: one pass, never under Reduce Motion or Instant)

    @Test func marqueeNeverMovesUnderReduceMotionOrInstant() {
        var theme = CrannyTheme()
        #expect(MarqueeText.moves(theme))
        theme.motion = .instant
        #expect(!MarqueeText.moves(theme))
        theme.motion = .lively
        theme.reduceMotion = true
        #expect(!MarqueeText.moves(theme))
        #expect(MarqueeText.speed == 30 && MarqueeText.leadIn > 0 && MarqueeText.dwell > 0)
    }

    // MARK: Colour

    @Test func prominentControlsAreWhiteWithBlackContent() {
        for variant in CrannyPalette.Variant.allCases {
            let p = CrannyPalette.make(variant)
            #expect(p.prominentFill == .white && p.onProminent == .black)
        }
    }

    @Test func delightCurvesKeepTheGulpAQuarterSecond() {
        let d = CrannyMotion.Delight.self
        #expect(d.gulpSwallowDuration + d.gulpRecoverDuration == 0.25 && d.gulpDepth == 3)
    }
}

// The Bluetooth glyph's bounce in a real (never shown) SwiftUI host: it is claimed when the glyph appears, so
// `symbolEffect(.bounce, value:)` changes while the glyph is on screen, once per connection, and never under
// Reduce Motion. The window is never ordered front.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct GlyphBounceTests {
    private func host(_ activity: BluetoothActivity, reduceMotion: Bool = false) -> NSWindow {
        var theme = CrannyTheme()
        theme.reduceMotion = reduceMotion
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Leading(activity: activity).environment(\.cranny, theme))
        return window
    }

    /// Asks the activity for its view inside a body, as NotchUI's `CompactRow` does, so changes re-render it.
    private struct Leading: View {
        let activity: BluetoothActivity
        var body: some View { activity.compactLeading() }
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func theGlyphBouncesWhenItAppearsAndOncePerConnection() async {
        let activity = BluetoothActivity()
        activity.present(BluetoothActivity.SampleDevice.airPods.accessory, for: nil)
        let compact = host(activity)
        defer { compact.close() }
        await settle { activity.bouncedRevision == activity.revision }
        #expect(activity.bouncedRevision == 1)                              // claimed on appearance
        let peek = host(activity)                                           // the peek's copy of the row
        defer { peek.close() }
        await settle { false }
        #expect(!activity.claimBounce(for: 1))                              // nothing left to replay
        activity.present(BluetoothActivity.SampleDevice.trackpad.accessory, for: nil)
        await settle { activity.bouncedRevision == activity.revision }
        #expect(activity.bouncedRevision == 2)                              // the visible glyph bounces again
    }

    @Test func noBounceUnderReduceMotion() async {
        let activity = BluetoothActivity()
        activity.present(BluetoothActivity.SampleDevice.airPods.accessory, for: nil)
        let window = host(activity, reduceMotion: true)
        defer { window.close() }
        await settle { false }
        #expect(activity.bouncedRevision == 0)
    }
}

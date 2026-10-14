// CrannyAppShell/MenuBar/MenuBarIcon.swift — the 18 × 14 template icon (DESIGN.md §13): a rounded screen
// outline (1.5 pt) with a filled NotchShape tab at its top centre, drawn in code (no asset in Bundle.main).
// In Demo mode a 4-pt dot marks its top-right corner, cut free from the outline by a 1-pt gap.
import AppKit
import CrannyCore
import Foundation
import Observation
import SwiftUI

enum MenuBarIcon {
    static let size = CGSize(width: 18, height: 14)

    /// The icon for the current state. Reading it inside a SwiftUI body (the menu bar extra's label) observes
    /// the demo badge, so the label redraws when Demo mode changes.
    static var image: NSImage { BadgeState.shared.showsDemoBadge ? badged : plain }

    /// Set by `DemoMode` (the app's instance) from `CoreSettings.demoMode`.
    static var showsDemoBadge: Bool {
        get { BadgeState.shared.showsDemoBadge }
        set { if BadgeState.shared.showsDemoBadge != newValue { BadgeState.shared.showsDemoBadge = newValue } }
    }

    static let plain = make(badged: false)
    static let badged = make(badged: true)

    /// Draws the template image; `badged` adds the Demo mode dot.
    static func make(badged: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let screen = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3, yRadius: 3)
            screen.lineWidth = 1.5
            NSColor.black.setStroke()
            screen.stroke()
            // The same shape as the app: a notch hanging from the top edge, with ears.
            let notch = NotchShape(NotchGeometry(bodyWidth: 7, height: 4.5, bottomRadius: 2, earRadius: 1)).path(in: rect)
            NSColor.black.setFill()
            NSBezierPath(cgPath: notch.cgPath).fill()
            if badged { drawBadge(in: rect) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badged ? accessibilityLabelInDemoMode : "Cranny"
        return image
    }

    /// "Cranny" — a name, never translated; in Demo mode the state follows it.
    static var accessibilityLabel: String { BadgeState.shared.showsDemoBadge ? accessibilityLabelInDemoMode : "Cranny" }

    // MARK: Private

    private static var accessibilityLabelInDemoMode: String {
        String(localized: "Cranny, demo mode", bundle: .module, comment: "Menu bar icon: VoiceOver label while Demo mode is on")
    }

    /// A 4-pt dot centred on the outline's top-right corner, with a 1-pt transparent ring around it.
    private static func drawBadge(in rect: CGRect) {
        let center = CGPoint(x: rect.maxX - 2, y: rect.minY + 2)
        let gap = NSBezierPath(ovalIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
        NSGraphicsContext.current?.compositingOperation = .clear
        gap.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSBezierPath(ovalIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
    }
}

/// The icon's observable state, so the menu bar extra's label redraws when Demo mode changes.
@MainActor @Observable private final class BadgeState {
    static let shared = BadgeState()
    var showsDemoBadge = false
}

/// The menu bar extra's label: the icon and its VoiceOver label, both following Demo mode.
struct MenuBarLabel: View {
    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .accessibilityLabel(Text(verbatim: MenuBarIcon.accessibilityLabel))
    }
}

#Preview("Menu bar icon · plain and Demo mode") {
    HStack(spacing: 24) {
        Image(nsImage: MenuBarIcon.plain)
        Image(nsImage: MenuBarIcon.badged)
    }
    .scaleEffect(4)
    .frame(width: 320, height: 120)
    .foregroundStyle(.white)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

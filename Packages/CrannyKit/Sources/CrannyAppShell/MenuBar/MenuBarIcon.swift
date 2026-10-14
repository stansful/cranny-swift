// CrannyAppShell/MenuBar/MenuBarIcon.swift — the 18 × 14 template icon (DESIGN.md §13): a rounded screen
// outline (1.5 pt) with a filled NotchShape tab at its top centre, drawn in code (no asset in Bundle.main).
import AppKit
import CrannyCore
import SwiftUI

enum MenuBarIcon {
    static let size = CGSize(width: 18, height: 14)

    static let image: NSImage = {
        let image = NSImage(size: size, flipped: true) { rect in
            let screen = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3, yRadius: 3)
            screen.lineWidth = 1.5
            NSColor.black.setStroke()
            screen.stroke()
            // The same shape as the app: a notch hanging from the top edge, with ears.
            let notch = NotchShape(NotchGeometry(bodyWidth: 7, height: 4.5, bottomRadius: 2, earRadius: 1)).path(in: rect)
            NSColor.black.setFill()
            NSBezierPath(cgPath: notch.cgPath).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cranny"
        return image
    }()
}

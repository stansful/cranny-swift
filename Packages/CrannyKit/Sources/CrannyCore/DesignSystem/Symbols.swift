// CrannyCore/DesignSystem/Symbols.swift
// The SF Symbols Cranny may draw: DESIGN.md §14.1, one set per role. Code spells the names as literals
// (`Image(systemName: "pin.fill")`); a name it uses must be in these sets, and the Core test checks every name
// against the system's symbol catalogue (available on macOS 14, not a restricted symbol except the product glyphs).
import Foundation

/// The allow-list of SF Symbols (DESIGN.md §14.1). Add a name here and to §14.1 before using it anywhere.
public nonisolated enum CrannySymbol {
    /// The Nook header, pages and card chrome.
    public static let header: Set<String> = [
        "square.grid.2x2.fill", "tray.full.fill", "note.text", "magnifyingglass", "pin", "pin.fill", "gearshape.fill",
        "ellipsis", "plus", "minus", "xmark", "chevron.down", "checkmark", "square.resize",
    ]
    /// Media.
    public static let media: Set<String> = [
        "play.fill", "pause.fill", "backward.fill", "forward.fill", "shuffle", "repeat", "airplayaudio", "music.note",
        "music.note.list", "waveform",
    ]
    /// Calendar and meetings (the day header pages with the chevrons).
    public static let calendar: Set<String> = [
        "calendar", "person.2.wave.2.fill", "clock", "mappin.and.ellipse", "chevron.backward", "chevron.forward",
    ]
    /// Quick Apps placeholders and the Shortcuts pane.
    public static let launcher: Set<String> = ["app.dashed", "square.2.layers.3d.fill"]
    /// Mirror.
    public static let mirror: Set<String> = ["web.camera", "camera.fill", "flip.horizontal"]
    /// Notes and To-dos.
    public static let notesAndTodos: Set<String> = [
        "chevron.left.forwardslash.chevron.right", "arrow.up.left.and.arrow.down.right",
        "arrow.down.right.and.arrow.up.left", "checklist", "circle", "checkmark.circle.fill",
    ]
    /// Timer.
    public static let timer: Set<String> = ["timer", "pause.fill", "stop.fill", "arrow.counterclockwise"]
    /// AirDrop, the Tray and its pipeline steps.
    public static let tray: Set<String> = [
        "dot.radiowaves.up.forward", "tray.and.arrow.down.fill", "doc.zipper", "photo.badge.arrow.down",
        "arrow.triangle.2.circlepath", "square.resize", "link", "doc.on.doc", "square.and.arrow.up", "folder", "eye",
        "trash", "archivebox", "wand.and.stars", "arrow.uturn.backward", "arrow.up.forward.app", "checkmark", "doc",
        "doc.richtext", "eye.slash", "film", "scissors", "text.viewfinder", "xmark", "exclamationmark",
    ]
    /// The HUD and power activities.
    public static let hudAndPower: Set<String> = [
        "speaker.wave.3.fill", "speaker.slash.fill", "sun.max.fill", "sun.min.fill", "light.max", "light.min",
        "bolt.fill", "battery.100percent.bolt", "battery.25percent", "battery.0percent", "exclamationmark",
        "powerplug.fill",
    ]
    /// Connected devices (HUD output glyph, Bluetooth activity).
    public static let devices: Set<String> = [
        "airpodspro", "airpodsmax", "airpods", "airpods.gen3", "beats.headphones", "earbuds", "headphones",
        "computermouse", "magicmouse", "keyboard", "hifispeaker", "gamecontroller",
        "rectangle.and.hand.point.up.left.filled", "dot.radiowaves.left.and.right", "display",
    ]
    /// Settings, onboarding and the tutorial.
    public static let settingsAndOnboarding: Set<String> = [
        "gearshape.fill", "paintbrush.fill", "keyboard", "capsule.tophalf.filled", "speaker.wave.2.fill",
        "hand.draw.fill", "hand.raised.fill", "info.circle.fill", "hand.wave.fill", "cursorarrow.motionlines",
        "cursorarrow.click", "sparkles", "accessibility", "laptopcomputer", "display", "exclamationmark.triangle.fill",
        "minus.circle.fill",
    ]
    /// The menu bar extra's fallback icon.
    public static let menuBar: Set<String> = ["rectangle.topthird.inset.filled"]

    /// Restricted symbols (`symbol_restrictions.strings`) Cranny uses, each only for that product or feature:
    /// AirPods, Beats headphones, a Magic Mouse, Apple's Accessibility settings.
    public static let restrictedProductGlyphs: Set<String> = [
        "airpods", "airpods.gen3", "beats.headphones", "magicmouse", "accessibility",
    ]

    /// Every allowed name.
    public static var all: Set<String> {
        header.union(media).union(calendar).union(launcher).union(mirror).union(notesAndTodos).union(timer)
            .union(tray).union(hudAndPower).union(devices).union(settingsAndOnboarding).union(menuBar)
    }
}

// CrannyNotchUI/PreviewSupport.swift — sample data for this target's #Preview blocks and snapshot tests
// (ARCHITECTURE.md §9.4): scenes in any phase, display style and palette variant on `CrannyServices.preview()`,
// with sample activities (Now Playing, timer, HUD, charging, meeting) and sample ⌘K commands. Not used by the
// app; preview copy is verbatim (never localized, never shipped in a catalog).
import CrannyCore
import Foundation
import Observation
import SwiftUI

/// A static live activity for previews and tests, drawn with tokens only.
@MainActor @Observable final class PreviewActivity: LiveActivity {
    enum Sample: String, CaseIterable { case nowPlaying, timer, hud, charging, meeting, greeting }

    let sample: Sample
    let id: ActivityID
    let isActive = true
    let revision = 1
    init(_ sample: Sample) {
        self.sample = sample
        id = switch sample {
        case .nowPlaying: .nowPlaying
        case .timer: .timerRunning
        case .hud: .hud
        case .charging: .charging
        case .meeting: .meetingSoon
        case .greeting: "preview.sample"
        }
    }

    var priority: ActivityPriority {
        switch sample {
        case .hud: .hud
        case .charging, .meeting, .greeting: .alert
        case .nowPlaying, .timer: .ongoing
        }
    }
    var slot: SlotWidth {
        switch sample {
        case .nowPlaying, .charging: .short
        case .timer, .meeting, .greeting: .medium
        case .hud: .wide
        }
    }
    var middleLabel: String? { sample == .nowPlaying ? "Midnight Window" : nil }
    var accessibilityLabel: String {
        switch sample {
        case .nowPlaying: "Now playing: Midnight Window by The Example Band"
        case .timer: "Timer running"
        case .hud: "Volume"
        case .charging: "Charging"
        case .meeting: "Design review in 4 minutes"
        case .greeting: "Sample activity"
        }
    }
    var accessibilityValue: String? {
        switch sample {
        case .nowPlaying: "2 minutes 11 seconds left"
        case .timer: "4 minutes 59 seconds left"
        case .hud: "62 percent"
        case .charging: "82 percent"
        default: nil
        }
    }

    func compactLeading() -> some View { PreviewGlyph(sample: sample, size: 20) }
    func compactTrailing() -> some View { PreviewValue(sample: sample) }
    func minimal() -> some View { PreviewGlyph(sample: sample, size: 14) }
    func peekRow() -> some View { PreviewPeekRow(sample: sample) }
}

private struct PreviewGlyph: View {
    @Environment(\.cranny) private var theme
    let sample: PreviewActivity.Sample
    let size: CGFloat
    var body: some View {
        let u = theme.notchUnit, p = theme.palette
        switch sample {
        case .nowPlaying:
            RoundedRectangle(cornerRadius: Radius.artCompact * u, style: .continuous)
                .fill(LinearGradient(colors: [BrandColor.iris.color, BrandColor.rose.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * u, height: size * u)
        case .timer:
            ProgressRing(progress: 0.7, color: p.warning, lineWidth: StrokeWidth.ringCompact).frame(width: 16 * u, height: 16 * u)
        case .hud:
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13 * u, weight: .semibold))
        case .charging:
            Image(systemName: "bolt.fill").font(.system(size: 13 * u, weight: .semibold)).foregroundStyle(p.success)
        case .meeting:
            if size >= 20 {
                HStack(spacing: Space.xs) {
                    Circle().fill(SemanticColor.info.rgb(false).color).frame(width: 7, height: 7)
                    Text(verbatim: "in 4m").crannyFont(.compactLabel).fixedSize()
                }
            } else {
                Circle().fill(SemanticColor.info.rgb(false).color).frame(width: 7, height: 7)
            }
        case .greeting:
            Image(systemName: "hand.wave.fill").font(.system(size: 13 * u, weight: .semibold))
        }
    }
}

private struct PreviewValue: View {
    @Environment(\.cranny) private var theme
    let sample: PreviewActivity.Sample
    var body: some View {
        let u = theme.notchUnit, p = theme.palette
        switch sample {
        case .nowPlaying:
            HStack(alignment: .center, spacing: 2) {
                ForEach([8.0, 14, 10, 16, 6], id: \.self) { h in
                    Capsule().fill(theme.accentColor).frame(width: 3, height: h * u)
                }
            }
        case .timer: Text(verbatim: "4:59").crannyFont(.compact)
        case .hud: LevelBar(value: 0.62).frame(width: 64 * u)
        case .charging: Text(verbatim: "82%").crannyFont(.compact)
        case .meeting:
            HStack(spacing: 3) {
                Image(systemName: "person.2.wave.2.fill").font(.system(size: 9, weight: .semibold))
                Text(verbatim: "Join").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(width: 34 * u + 12, height: 20 * u)
            .background(Capsule().fill(p.success))
        case .greeting: Text(verbatim: "Hi").crannyFont(.compact)
        }
    }
}

private struct PreviewPeekRow: View {
    @Environment(\.cranny) private var theme
    let sample: PreviewActivity.Sample
    var body: some View {
        let p = theme.palette
        HStack(spacing: Space.l) {
            Group {
                if sample == .nowPlaying {
                    RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous)
                        .fill(LinearGradient(colors: [BrandColor.iris.color, BrandColor.rose.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(p.control)
                        .overlay { PreviewGlyph(sample: sample, size: 14) }
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).crannyFont(.headline).lineLimit(1)
                Text(verbatim: subtitle).crannyFont(.callout).foregroundStyle(p.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: Space.m)
            if sample == .nowPlaying {
                HStack(spacing: 0) {
                    ForEach(["backward.fill", "pause.fill", "forward.fill"], id: \.self) { symbol in
                        Button {} label: { Image(systemName: symbol) }.buttonStyle(CrannyIconButtonStyle())
                    }
                }
            }
        }
    }
    private var title: String {
        switch sample {
        case .nowPlaying: "Midnight Window"
        case .timer: "Tea"
        case .hud: "Volume"
        case .charging: "82%"
        case .meeting: "Design review"
        case .greeting: "Hi"
        }
    }
    private var subtitle: String {
        switch sample {
        case .nowPlaying: "The Example Band"
        case .timer: "4:59 left"
        case .hud: "MacBook Pro Speakers"
        case .charging: "1 h 20 m to full"
        case .meeting: "10:30–11:00 · Room 4"
        case .greeting: "A sample activity"
        }
    }
}

/// The shell's pause confirmation as previews see it: a glyph and a short word in the wings, a sentence for the open
/// header (`OpenHeaderActivity`).
@MainActor @Observable final class PreviewConfirmation: OpenHeaderActivity {
    static let sentence = "Live Activities paused for 1 hour"
    let id: ActivityID = "preview.confirmation"
    let isActive = true
    let revision = 1
    let priority: ActivityPriority = .alert
    let slot: SlotWidth = .wide
    var headerMessage: String?
    var accessibilityLabel: String { headerMessage ?? "Paused" }
    init(_ message: String?) { headerMessage = message }

    func compactLeading() -> some View { Image(systemName: "pause.fill").crannySymbol(.band) }
    func compactTrailing() -> some View { Text(verbatim: "Paused").crannyFont(.compact) }
    func minimal() -> some View { Image(systemName: "pause.fill").crannySymbol(.band) }
    func peekRow() -> some View { Text(verbatim: headerMessage ?? "Paused").crannyFont(.title) }
}

/// Sample ⌘K commands.
@MainActor final class PreviewCommands: PaletteCommandProvider {
    func commands(matching query: String) -> [PaletteCommand] {
        [PaletteCommand(id: "preview.timer", title: "Start 25-minute timer", kind: "Timer", symbol: "timer") {},
         PaletteCommand(id: "preview.note", title: "New note", kind: "Notes", symbol: "note.text",
                        shortcut: KeyCombo(keyCode: 45, modifiers: [.command], display: "⌘N")) {},
         PaletteCommand(id: "preview.pause", title: "Pause live activities for 1 hour", kind: "Cranny", symbol: "pause.fill") {},
         PaletteCommand(id: "preview.demo", title: "Demo mode", kind: "Cranny", symbol: "sparkles") {},
         PaletteCommand(id: "preview.tray", title: "Clear tray", kind: "Tray", symbol: "tray.full.fill") {}]
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
}

/// Displays of DESIGN.md §3.3.
enum PreviewDisplays {
    /// 14″ MacBook Pro: notch 185 × 32, 1512 pt.
    static let notch = NotchMetrics.reference
    /// External display with a 30-pt menu bar (floating island or attached).
    static let external = NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)
}

/// The four palette situations of DESIGN.md §2.1.
enum PreviewVariant: String, CaseIterable {
    case standard, lit, highContrast, opaque
    func apply(to theme: inout CrannyTheme) {
        switch self {
        case .standard: break
        case .lit: theme.ambience = .vivid
        case .highContrast: theme.increaseContrast = true
        case .opaque: theme.reduceTransparency = true
        }
    }
}

/// A scene in `phase` with sample data. Compact and peek show Now Playing (+ a timer satellite or more rows);
/// open shows Home with placeholder cards (or the palette, the editor, focus or the catch state via `mode`).
@MainActor func previewScene(_ phase: NotchPhase, metrics: NotchMetrics = .reference, style: NoNotchStyle = .floatingIsland,
                             variant: PreviewVariant = .standard, sample: PreviewActivity.Sample = .nowPlaying,
                             satellite: Bool = false, peekRowCount: Int = 1, hudInHeader: Bool = false,
                             headerMessage: String? = nil, palette: Bool = false,
                             mode: NookMode = .grid) -> (NotchSceneModel, ModuleRegistry) {
    let registry = ModuleRegistry(services: .preview())
    registry.add(commands: PreviewCommands())
    registry.addPreviewStandIns()                                    // named cards without the feature modules
    var theme = CrannyTheme()
    theme.notchUnit = metrics.unit
    theme.glassIsland = false
    variant.apply(to: &theme)
    let layout = NotchLayout(metrics: metrics, noNotchStyle: style, grid: theme.grid)
    let model = NotchSceneModel(layout: layout, theme: theme)
    model.context.isPreview = true
    for kind in PreviewActivity.Sample.allCases {
        let activity = PreviewActivity(kind)
        model.sampleActivities[activity.id] = activity
    }
    let primary = PreviewActivity(hudInHeader ? .hud : sample)
    model.phase = phase
    switch phase {
    case .compact:
        model.primary = primary.id
        model.primarySlot = primary.slot
        model.middleLabelWidth = MiddleLabelMetrics.width(of: primary.middleLabel, layout: layout)
        if satellite { model.satellite = ActivityID.timerRunning }
    case .peek:
        model.primary = primary.id
        model.primarySlot = primary.slot
        let rows: [ActivityID] = [primary.id, .timerRunning, .meetingSoon, .charging]
        model.peekRows = Array(rows.prefix(max(peekRowCount, 1)))
    case .open:
        model.open = OpenState(page: .nook, mode: palette ? .palette : mode, reason: .click)
        model.openColumns = NookPreset.listener.items.reduce(0) { $0 + $1.cells }
        if hudInHeader { model.primary = primary.id; model.primarySlot = .wide }
        if let headerMessage {                                      // behind Now Playing in the lineup
            let confirmation = PreviewConfirmation(headerMessage)
            model.sampleActivities[confirmation.id] = confirmation
            model.primary = primary.id
            model.headerActivity = confirmation.id
        }
    default:
        break
    }
    return (model, registry)
}

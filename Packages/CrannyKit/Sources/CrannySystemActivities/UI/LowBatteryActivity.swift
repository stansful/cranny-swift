// CrannySystemActivities/UI/LowBatteryActivity.swift — "Low battery" (DESIGN.md §9.2): P1 at each threshold
// (20 % and 10 % by default). A first warning shows for the peek duration; at the final threshold the activity
// stays until power is connected.
//   compact   battery.25percent / battery.0percent + "!" | "10%"   (`warning` for a first warning, `danger` at the final one)
//   peek      battery tile · "Low battery" / "10% · 35m left" · [Low Power Mode…] (opens Battery settings, D18)
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class LowBatteryActivity: LiveActivity {
    let id: ActivityID = .lowBattery
    let priority: ActivityPriority = .alert
    let slot: SlotWidth = .short
    private(set) var content: LowBatteryContent?
    private(set) var revision = 0
    private(set) var expiresAt: Date?
    @ObservationIgnored private let expiry = ActivityExpiry()
    /// Opens System Settings ▸ Battery: apps cannot switch Low Power Mode (ARCHITECTURE.md D18).
    @ObservationIgnored let openBatterySettings: @MainActor () -> Void

    init(openBatterySettings: @escaping @MainActor () -> Void) {
        self.openBatterySettings = openBatterySettings
    }

    var isActive: Bool { content != nil }
    /// Shown until power is connected (the final warning), not for a fixed time.
    var isPersistent: Bool { isActive && expiresAt == nil }
    var palette: AmbientPalette? { isActive ? .lowBattery : nil }

    var accessibilityLabel: String { SystemCopy.lowBattery }
    var accessibilityValue: String? {
        guard let content else { return nil }
        let parts = [SystemCopy.percent(content.percent), Self.timeStatus(content, spoken: true)]
            + (content.isLowPowerMode ? [SystemCopy.lowPowerModeIsOn] : [])
        return SystemCopy.list(parts)
    }
    var actions: [ActivityAction] {
        [ActivityAction(id: "batterySettings", title: SystemCopy.batterySettings, symbol: "battery.25percent") { [openBatterySettings] in
            openBatterySettings()
        }]
    }

    // MARK: Driving (PowerModel, samples)

    /// A threshold was reached: a meaningful change. `duration` nil = stays until `end()` (the final warning).
    func alert(_ content: LowBatteryContent, for duration: TimeInterval?, now: Date = Date()) {
        self.content = content
        revision += 1
        if let duration {
            expiresAt = now.addingTimeInterval(duration)
            expiry.schedule(after: duration) { [weak self] in self?.end() }
        } else {
            expiresAt = nil
            expiry.cancel()
        }
    }

    /// Already below the final threshold at launch: visible, but no new revision (so no peek at launch).
    func showQuietly(_ content: LowBatteryContent) {
        expiry.cancel()
        expiresAt = nil
        self.content = content
    }

    /// New level or time estimate while visible: not a meaningful change.
    func update(_ content: LowBatteryContent) {
        guard isActive, self.content != content else { return }
        self.content = content
    }

    func end() {
        expiry.cancel()
        content = nil
        expiresAt = nil
    }

    // MARK: Presentations

    func compactLeading() -> some View { LowBatteryGlyph(content: content) }
    func compactTrailing() -> some View { LowBatteryLevel(content: content) }
    func minimal() -> some View { LowBatteryGlyph(content: content, isMinimal: true) }
    func peekRow() -> some View { LowBatteryPeekRow(content: content, openBatterySettings: openBatterySettings) }

    // MARK: Copy

    /// The peek subtitle: "10% · 35m left" next to the Low Power Mode button; "Low Power Mode is on" when the
    /// button is not needed (the level then ends the row in `numeral`, DESIGN.md §9.3).
    static func subtitle(_ content: LowBatteryContent) -> String {
        content.isLowPowerMode
            ? SystemCopy.lowPowerModeIsOn
            : SystemCopy.levelAndStatus(SystemCopy.percent(content.percent), timeStatus(content))
    }

    /// "35m left", or "Calculating…" while macOS estimates.
    static func timeStatus(_ content: LowBatteryContent, spoken: Bool = false) -> String {
        content.minutesToEmpty.map { SystemCopy.timeLeft(SystemCopy.duration(minutes: $0, spoken: spoken)) } ?? SystemCopy.calculating
    }
}

extension LowBatteryContent.Level {
    /// `warning` for a first warning, `danger` at the final one (DESIGN.md §2.1 semantic colours).
    func color(_ palette: CrannyPalette) -> Color { self == .critical ? palette.danger : palette.warning }
    /// The stepped glyph that goes with the colour (Differentiate Without Color: never colour alone).
    var symbol: String { self == .critical ? "battery.0percent" : "battery.25percent" }
}

// MARK: - Views

private struct LowBatteryGlyph: View {
    @Environment(\.cranny) private var theme
    let content: LowBatteryContent?
    var isMinimal = false

    var body: some View {
        let level = content?.level ?? .critical
        let color = level.color(theme.palette)
        HStack(spacing: 1) {
            BandSymbol(name: level.symbol, color: color)
            if !isMinimal { BandSymbol(name: "exclamationmark", color: color) }
        }
        .scaleEffect(isMinimal ? 0.72 : 1)
    }
}

private struct LowBatteryLevel: View {
    @Environment(\.cranny) private var theme
    let content: LowBatteryContent?
    var body: some View {
        BandLevel(percent: content?.percent ?? 0, color: (content?.level ?? .critical).color(theme.palette))
    }
}

private struct LowBatteryPeekRow: View {
    @Environment(\.cranny) private var theme
    let content: LowBatteryContent?
    let openBatterySettings: @MainActor () -> Void

    var body: some View {
        let p = theme.palette
        if let content {
            let color = content.level.color(p)
            PeekRowLayout(title: SystemCopy.lowBattery, subtitle: LowBatteryActivity.subtitle(content),
                          subtitleColor: content.isLowPowerMode ? p.caution : nil) {
                PeekTile(tint: color) {
                    BatteryGlyph(percent: content.percent, fill: color)
                }
            } trailing: {
                if content.isLowPowerMode {
                    Text(SystemCopy.percent(content.percent))
                        .crannyFont(.numeral)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(content.percent)))
                        .accessibilityHidden(true)
                } else {
                    Button(action: openBatterySettings) {
                        Text(verbatim: SystemCopy.lowPowerModeButton)
                    }
                    .buttonStyle(CrannyChipButtonStyle(tint: p.caution))
                    .frame(minHeight: HitTarget.nook.height)
                    .contentShape(Rectangle())
                    .help(SystemCopy.batterySettings)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Low battery · final warning") {
    ActivityPreviewBoard(activity: LowBatteryActivity.sample(.critical))
}

#Preview("Low battery · first warning, Low Power Mode on") {
    ActivityPreviewBoard(activity: LowBatteryActivity.sample(.warning, lowPowerMode: true))
}

// CrannySystemActivities/UI/ChargingActivity.swift — "Charging" (DESIGN.md §9.2): P1, transient for the peek
// duration (2.6 s by default) on every plug and unplug; `delight = .chargeSweep` on plug-in.
//   compact   bolt.fill in `success` | "82%"        (unplugged: the code-drawn battery | "82%")
//   peek      battery 24 × 12 tile · "Charging" / "1h 20m until full" · "82%" in `numeral`
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class ChargingActivity: LiveActivity {
    let id: ActivityID = .charging
    let priority: ActivityPriority = .alert
    let slot: SlotWidth = .short
    private(set) var content: ChargingContent?
    private(set) var revision = 0
    private(set) var expiresAt: Date?
    @ObservationIgnored private let expiry = ActivityExpiry()

    var isActive: Bool { content != nil }

    /// Light while on power (DESIGN.md §5.2); unplugging has no light of its own.
    var palette: AmbientPalette? { content?.isOnPower == true ? .charging : nil }
    /// Played by NotchUI when `revision` changes while visible: only plug-ins sweep.
    var delight: DelightMoment? { content?.isOnPower == true ? .chargeSweep : nil }

    var accessibilityLabel: String { content.map(Self.title) ?? SystemCopy.charging }
    var accessibilityValue: String? {
        guard let content else { return nil }
        let level = SystemCopy.percent(content.percent)
        guard let detail = Self.detail(content, spoken: true) else { return level }
        return SystemCopy.list([level, detail])
    }

    // MARK: Driving (PowerModel, samples)

    /// A plug or unplug: a meaningful change (new revision), shown for `duration` seconds (nil = until `end()`).
    func present(_ content: ChargingContent, for duration: TimeInterval?, now: Date = Date()) {
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

    /// New numbers while visible (time estimate arrived, charging started): not a meaningful change.
    func update(_ content: ChargingContent) {
        guard isActive, self.content != content else { return }
        self.content = content
    }

    func end() {
        expiry.cancel()
        content = nil
        expiresAt = nil
    }

    // MARK: Presentations

    func compactLeading() -> some View { ChargingGlyph(content: content) }
    func compactTrailing() -> some View { ChargingLevel(content: content) }
    func minimal() -> some View { ChargingGlyph(content: content, isMinimal: true) }
    func peekRow() -> some View { ChargingPeekRow(content: content) }

    // MARK: Copy

    static func title(_ content: ChargingContent) -> String {
        switch content.phase {
        case .charging: SystemCopy.charging
        case .charged: SystemCopy.fullyCharged
        case .notCharging: SystemCopy.pluggedIn
        case .onBattery: SystemCopy.onBattery
        }
    }

    /// The peek subtitle; `spoken` uses full words for VoiceOver.
    static func detail(_ content: ChargingContent, spoken: Bool = false) -> String? {
        switch content.phase {
        case .charging:
            content.minutes.map { SystemCopy.untilFull(SystemCopy.duration(minutes: $0, spoken: spoken)) } ?? SystemCopy.calculating
        case .charged:
            SystemCopy.connectedToPower
        case .notCharging:
            SystemCopy.notCharging
        case .onBattery:
            content.minutes.map { SystemCopy.timeLeft(SystemCopy.duration(minutes: $0, spoken: spoken)) } ?? SystemCopy.calculating
        }
    }
}

// MARK: - Views

/// Leading: the bolt in `success` while charging (secondary when power does not charge); unplugged, the
/// exact battery. The satellite shows the same glyph, smaller.
private struct ChargingGlyph: View {
    @Environment(\.cranny) private var theme
    let content: ChargingContent?
    var isMinimal = false

    var body: some View {
        let p = theme.palette
        let u = theme.notchUnit * (isMinimal ? 0.85 : 1)
        Group {
            if let content, !content.isOnPower {
                BatteryGlyph(percent: content.percent, fill: p.label,
                             size: CGSize(width: (22 * u).rounded(), height: (11 * u).rounded()))
            } else {
                BandSymbol(name: "bolt.fill", color: content?.phase == .notCharging ? p.secondaryLabel : p.success)
                    .scaleEffect(isMinimal ? 0.85 : 1)
            }
        }
        .animation(theme.animation(.contentSwap), value: content?.phase)
    }
}

private struct ChargingLevel: View {
    let content: ChargingContent?
    var body: some View { BandLevel(percent: content?.percent ?? 0) }
}

private struct ChargingPeekRow: View {
    @Environment(\.cranny) private var theme
    let content: ChargingContent?

    var body: some View {
        let p = theme.palette
        if let content {
            PeekRowLayout(title: ChargingActivity.title(content), subtitle: ChargingActivity.detail(content)) {
                let charges = content.phase == .charging || content.phase == .charged
                PeekTile(tint: charges ? p.success : nil) {
                    BatteryGlyph(percent: content.percent, fill: charges ? p.success : p.label, showsBolt: content.phase == .charging)
                }
            } trailing: {
                Text(SystemCopy.percent(content.percent))
                    .crannyFont(.numeral)
                    .foregroundStyle(p.label)
                    .lineLimit(1)
                    .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(content.percent)))
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Previews

#Preview("Charging · compact, satellite and peek") {
    ActivityPreviewBoard(activity: ChargingActivity.sample(.charging))
}

#Preview("Charging · plugged in, not charging") {
    ActivityPreviewBoard(activity: ChargingActivity.sample(.notCharging))
}

#Preview("Charging · unplugged") {
    ActivityPreviewBoard(activity: ChargingActivity.sample(.onBattery))
}

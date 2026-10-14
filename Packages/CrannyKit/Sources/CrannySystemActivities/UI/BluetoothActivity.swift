// CrannySystemActivities/UI/BluetoothActivity.swift — "Bluetooth device" (DESIGN.md §9.2): P1, transient for
// the peek duration when an accessory connects.
//   compact   device glyph | 12-pt battery ring + "84%", or ✓ when the level is unknown
//   peek      glyph tile · name / "Connected" · L / R / Case rings with %, or the single level in `numeral`
// Slot: medium, not DESIGN.md's short — ring + "84%" measures 44 pt, the short slot holds 32 (see the report).
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class BluetoothActivity: LiveActivity {
    let id: ActivityID = .bluetoothDevice
    let priority: ActivityPriority = .alert
    let slot: SlotWidth = .medium
    private(set) var accessory: Accessory?
    private(set) var revision = 0
    private(set) var expiresAt: Date?
    @ObservationIgnored private let expiry = ActivityExpiry()

    var isActive: Bool { accessory != nil }

    var accessibilityLabel: String {
        SystemCopy.deviceConnected(accessory?.name ?? SystemCopy.genericName(.other))
    }
    var accessibilityValue: String? {
        guard let batteries = accessory?.batteries else { return nil }
        if batteries.hasParts {
            return SystemCopy.list(AccessoryPart.allCases.compactMap { part in
                batteries.level(part).map { SystemCopy.part(part, SystemCopy.percent($0.percent)) }
            })
        }
        return batteries.summary.map { SystemCopy.percent($0.percent) } ?? SystemCopy.batteryUnknown
    }

    // MARK: Driving (AccessoryModel, samples)

    /// A new connection: a meaningful change, shown for `duration` seconds (nil = until `end()`).
    func present(_ accessory: Accessory, for duration: TimeInterval?, now: Date = Date()) {
        self.accessory = accessory
        revision += 1
        if let duration {
            expiresAt = now.addingTimeInterval(duration)
            expiry.schedule(after: duration) { [weak self] in self?.end() }
        } else {
            expiresAt = nil
            expiry.cancel()
        }
    }

    /// Battery levels arrived for the device on screen: not a meaningful change.
    func update(_ accessory: Accessory) {
        guard self.accessory?.id == accessory.id, self.accessory != accessory else { return }
        self.accessory = accessory
    }

    func end() {
        expiry.cancel()
        accessory = nil
        expiresAt = nil
    }

    // MARK: Presentations

    func compactLeading() -> some View { DeviceGlyph(accessory: accessory, revision: revision) }
    func compactTrailing() -> some View { DeviceLevel(batteries: accessory?.batteries ?? .unknown) }
    func minimal() -> some View { DeviceGlyph(accessory: accessory, revision: revision, isMinimal: true) }
    func peekRow() -> some View { DevicePeekRow(accessory: accessory) }
}

// MARK: - Views

/// The device glyph; it bounces once per new connection (never under Reduce Motion, DESIGN.md §14.1).
private struct DeviceGlyph: View {
    @Environment(\.cranny) private var theme
    let accessory: Accessory?
    let revision: Int
    var isMinimal = false

    var body: some View {
        BandSymbol(name: accessory?.symbol ?? DeviceSymbols.symbol(for: .other, isApple: false))
            .scaleEffect(isMinimal ? 0.8 : 1)
            .symbolEffect(.bounce, options: .nonRepeating, value: theme.reduceMotion ? 0 : revision)
    }
}

/// Trailing: ring + level, or ✓ when the device reports no level.
private struct DeviceLevel: View {
    @Environment(\.cranny) private var theme
    let batteries: AccessoryBatteries

    var body: some View {
        if let level = batteries.summary {
            BandLevel(percent: level.percent, showsRing: true)
        } else {
            BandSymbol(name: "checkmark.circle.fill", color: theme.palette.success)
        }
    }
}

private struct DevicePeekRow: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    let accessory: Accessory?

    var body: some View {
        let p = theme.palette
        if let accessory {
            PeekRowLayout(title: displayName(accessory), subtitle: SystemCopy.connected) {
                PeekTile(tint: p.info) {
                    Image(systemName: accessory.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(p.label)
                }
            } trailing: {
                let batteries = accessory.batteries
                if batteries.hasParts {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(AccessoryPart.allCases, id: \.self) { part in
                            if let level = batteries.level(part) { BatteryPartGauge(part: part, level: level) }
                        }
                    }
                } else if let level = batteries.summary {
                    Text(SystemCopy.percent(level.percent))
                        .crannyFont(.numeral)
                        .foregroundStyle(p.label)
                        .lineLimit(1)
                        .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(level.percent)))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(p.success)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Demo mode with redaction hides the device's own name, which often contains its owner's.
    private func displayName(_ accessory: Accessory) -> String {
        guard context.redactsPersonalData else { return accessory.name }
        return DeviceSymbols.product(vendorID: accessory.vendorID, productID: accessory.productID)?.model
            ?? SystemCopy.genericName(accessory.kind)
    }
}

// MARK: - Previews

#Preview("Bluetooth · AirPods") {
    ActivityPreviewBoard(activity: BluetoothActivity.sample(.airPods))
}

#Preview("Bluetooth · Magic Trackpad") {
    ActivityPreviewBoard(activity: BluetoothActivity.sample(.trackpad))
}

#Preview("Bluetooth · level unknown") {
    ActivityPreviewBoard(activity: BluetoothActivity.sample(.headphones))
}

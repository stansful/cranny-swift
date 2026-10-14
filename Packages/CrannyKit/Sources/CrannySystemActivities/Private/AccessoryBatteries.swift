// CrannySystemActivities/Private/AccessoryBatteries.swift — accessory batteries through the PRIVATE
// `IOPSCopyPowerSourcesByType(4)` (ARCHITECTURE.md §7.12): the data behind `pmset -g accps` and the Batteries
// widget, including AirPods left / right / case. No TCC prompt [VERIFIED R3 §3].
//
// Resolved with `dlsym` (never linked); without it, Bluetooth accessories show without battery levels.
// The parser is pure: tests feed it dictionaries captured on macOS 27. Names and identifiers in those
// dictionaries can be personal, so nothing here logs them.
import CrannyCore
import Foundation
import IOKit.ps
import os

nonisolated private let log = Log.logger(.bluetooth)

/// One IOPS accessory source.
nonisolated struct PowerSourceAccessory: Equatable, Sendable {
    nonisolated enum Part: Equatable, Sendable { case single, left, right, chargingCase, combined }

    var name: String
    var category: String?
    var part: Part
    var level: BatteryLevel
    var vendorID: Int?
    var productID: Int?
    /// Shared by the parts of one device (AirPods buds and their case).
    var groupID: String?
}

/// The batteries of one device, grouped from its sources.
nonisolated struct AccessoryBatteryReport: Equatable, Sendable {
    var name: String
    var category: String?
    var vendorID: Int?
    var productID: Int?
    var batteries: AccessoryBatteries

    var kind: AccessoryKind? {
        DeviceSymbols.product(vendorID: vendorID, productID: productID)?.kind ?? DeviceSymbols.kind(forCategory: category)
    }
}

nonisolated enum AccessoryPowerSources {
    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    /// IOKit's private power-source type for accessories (IOKitUser: `kIOPSSourceForAccessories`).
    private static let accessoriesType: Int32 = 4

    private static let copyByType: CopyByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else {
            log.info("IOPSCopyPowerSourcesByType unavailable: accessories show without battery levels")
            return nil
        }
        return unsafeBitCast(symbol, to: CopyByType.self)
    }()

    /// The private symbol resolved on this OS.
    static var isAvailable: Bool { copyByType != nil }

    /// Every accessory battery right now (IPC to powerd: call off the main actor). Empty when unavailable.
    static func read() -> [AccessoryBatteryReport] {
        guard let copyByType, let blob = copyByType(accessoriesType)?.takeRetainedValue() else { return [] }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let descriptions = list.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
        return group(parse(descriptions))
    }

    @concurrent static func snapshot() async -> [AccessoryBatteryReport] { read() }

    // MARK: Parsing (pure)

    /// Flattens IOPS accessory descriptions; the "Combined Parts" of AirPods become left/right sources.
    static func parse(_ descriptions: [[String: Any]]) -> [PowerSourceAccessory] {
        descriptions.flatMap { description -> [PowerSourceAccessory] in
            guard let top = source(description) else { return [] }
            let parts = (description["Combined Parts"] as? [[String: Any]] ?? []).compactMap { sub in
                source(sub).map { part in
                    var part = part
                    part.groupID = part.groupID ?? top.groupID
                    return part
                }
            }
            return [top] + parts
        }
    }

    private static func source(_ d: [String: Any]) -> PowerSourceAccessory? {
        guard IOPSValue.bool(d[kIOPSIsPresentKey]) ?? true,
              let current = IOPSValue.int(d[kIOPSCurrentCapacityKey]) else { return nil }
        let maximum = IOPSValue.int(d[kIOPSMaxCapacityKey]) ?? 100
        let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
        let part: PowerSourceAccessory.Part = switch (d["Part Identifier"] as? String)?.lowercased() {
        case "left": .left
        case "right": .right
        case "case": .chargingCase
        case "combined": .combined
        default: .single
        }
        return PowerSourceAccessory(
            name: (d[kIOPSNameKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            category: d["Accessory Category"] as? String,
            part: part,
            level: BatteryLevel(percent: percent, isCharging: IOPSValue.bool(d[kIOPSIsChargingKey]) ?? false),
            vendorID: IOPSValue.int(d[kIOPSVendorIDKey]),
            productID: IOPSValue.int(d[kIOPSProductIDKey]),
            groupID: d["Group Identifier"] as? String)
    }

    /// One report per device: sources with the same group identifier (else the same name and product) merge.
    static func group(_ sources: [PowerSourceAccessory]) -> [AccessoryBatteryReport] {
        var order: [String] = []
        var bySource: [String: [PowerSourceAccessory]] = [:]
        for source in sources {
            let key = source.groupID.map { "group:\($0)" } ?? "name:\(source.name)|\(source.productID ?? -1)"
            if bySource[key] == nil { order.append(key) }
            bySource[key, default: []].append(source)
        }
        return order.compactMap { key in
            guard let members = bySource[key], let first = members.first else { return nil }
            // The device's own name and category come from a bud/combined/single source, never the case.
            let device = members.first { $0.part != .chargingCase } ?? first
            var batteries = AccessoryBatteries()
            for member in members {
                switch member.part {
                case .single, .combined: batteries.main = member.level
                case .left: batteries.left = member.level
                case .right: batteries.right = member.level
                case .chargingCase: batteries.chargingCase = member.level
                }
            }
            return AccessoryBatteryReport(name: device.name, category: device.category,
                                          vendorID: device.vendorID ?? first.vendorID,
                                          productID: device.productID ?? first.productID, batteries: batteries)
        }
    }
}

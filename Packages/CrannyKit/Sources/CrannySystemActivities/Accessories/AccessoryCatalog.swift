// CrannySystemActivities/Accessories/AccessoryCatalog.swift — builds the `Accessory` the Bluetooth activity
// shows from the permission-free sources (pure, unit-tested):
//   • Core Audio says WHAT connected (headphones), IOPS accessories add batteries, matched by name.
//   • IOKit HID says a Magic accessory connected; IOPS adds batteries matched by vendor + product ID.
//   • IOBluetooth (opt-in) says any device connected, with its own private battery levels.
// IOPS alone never means "connected": it also lists AirPods that are only nearby (Bluetooth LE).
import Foundation

nonisolated enum AccessoryCatalog {
    /// Case-, width- and punctuation-insensitive name used to match sources ("AirPods Pro 🅛" = "airpods pro").
    static func normalizedName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let words = folded.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
        return words.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    }

    // MARK: A new connection

    static func accessory(audio device: AudioOutputDevice, reports: [AccessoryBatteryReport]) -> Accessory {
        let report = report(named: device.name, in: reports)
        return Accessory(id: "audio:\(device.id)", name: device.name, kind: report?.kind ?? .headphones,
                         vendorID: report?.vendorID, productID: report?.productID,
                         batteries: report?.batteries ?? .unknown)
    }

    static func accessory(hid peripheral: HIDPeripheral, reports: [AccessoryBatteryReport]) -> Accessory {
        let report = report(vendorID: peripheral.vendorID, productID: peripheral.productID, in: reports)
            ?? report(named: peripheral.name, in: reports)
        let kind = DeviceSymbols.kind(forCategory: peripheral.category) ?? report?.kind ?? .other
        return Accessory(id: "hid:\(peripheral.id)", name: peripheral.name, kind: kind,
                         vendorID: peripheral.vendorID, productID: peripheral.productID,
                         batteries: batteries(report: report, hid: peripheral))
    }

    static func accessory(bluetooth device: BluetoothDeviceInfo, reports: [AccessoryBatteryReport]) -> Accessory {
        let report = report(named: device.name, in: reports)
        return Accessory(id: "bluetooth:\(device.id)", name: device.name, kind: report?.kind ?? device.kind,
                         vendorID: report?.vendorID, productID: report?.productID,
                         batteries: report.map(\.batteries).flatMap { $0.isEmpty ? nil : $0 } ?? device.batteries)
    }

    // MARK: While shown

    /// New battery levels for an accessory that is already on screen (identity, name and kind never change).
    static func refreshed(_ accessory: Accessory, reports: [AccessoryBatteryReport], hid: [HIDPeripheral],
                          bluetooth: [BluetoothDeviceInfo]) -> Accessory {
        var out = accessory
        let byProduct = report(vendorID: accessory.vendorID, productID: accessory.productID, in: reports)
        let report = byProduct ?? report(named: accessory.name, in: reports)
        if accessory.id.hasPrefix("hid:") {
            let peripheral = hid.first { "hid:\($0.id)" == accessory.id }
            out.batteries = batteries(report: report, hid: peripheral)
        } else if accessory.id.hasPrefix("bluetooth:") {
            let device = bluetooth.first { "bluetooth:\($0.id)" == accessory.id }
            out.batteries = report.map(\.batteries).flatMap { $0.isEmpty ? nil : $0 } ?? device?.batteries ?? accessory.batteries
        } else if let report {
            out.batteries = report.batteries
        }
        if out.vendorID == nil, out.productID == nil, let report {
            out.vendorID = report.vendorID
            out.productID = report.productID
        }
        return out
    }

    // MARK: Matching

    static func report(named name: String, in reports: [AccessoryBatteryReport]) -> AccessoryBatteryReport? {
        let key = normalizedName(name)
        guard !key.isEmpty else { return nil }
        return reports.first { normalizedName($0.name) == key }
    }

    static func report(vendorID: Int?, productID: Int?, in reports: [AccessoryBatteryReport]) -> AccessoryBatteryReport? {
        guard let vendorID, let productID else { return nil }
        let matches = reports.filter { $0.vendorID == vendorID && $0.productID == productID }
        return matches.count == 1 ? matches.first : nil       // two identical devices: let the name decide
    }

    /// IOPS levels when known, else the HID registry's own `BatteryPercent`.
    private static func batteries(report: AccessoryBatteryReport?, hid: HIDPeripheral?) -> AccessoryBatteries {
        if let report, !report.batteries.isEmpty { return report.batteries }
        return AccessoryBatteries(main: hid?.batteryPercent.map { BatteryLevel(percent: $0) })
    }
}

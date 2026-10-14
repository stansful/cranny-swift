// CrannySystemActivities/Accessories/Accessory.swift — a connected Bluetooth accessory as the Bluetooth
// activity shows it: a name, what kind of device it is and the batteries we know about (ARCHITECTURE.md §7.3).
import Foundation

/// One battery: a single-battery device, one earbud, or a charging case.
nonisolated struct BatteryLevel: Equatable, Sendable {
    var percent: Int
    var isCharging: Bool

    init(percent: Int, isCharging: Bool = false) {
        self.percent = min(max(percent, 0), 100)
        self.isCharging = isCharging
    }
}

/// One of the separately powered parts of a pair of earbuds.
nonisolated enum AccessoryPart: CaseIterable, Sendable { case left, right, chargingCase }

/// Every battery of one accessory. AirPods report left, right and case (plus a combined level).
nonisolated struct AccessoryBatteries: Equatable, Sendable {
    /// A single-battery device, or the combined level of a pair of earbuds.
    var main: BatteryLevel?
    var left: BatteryLevel?
    var right: BatteryLevel?
    var chargingCase: BatteryLevel?

    init(main: BatteryLevel? = nil, left: BatteryLevel? = nil, right: BatteryLevel? = nil, chargingCase: BatteryLevel? = nil) {
        self.main = main; self.left = left; self.right = right; self.chargingCase = chargingCase
    }

    static let unknown = AccessoryBatteries()

    /// Shows L / R / Case gauges rather than one value.
    var hasParts: Bool { left != nil || right != nil || chargingCase != nil }

    func level(_ part: AccessoryPart) -> BatteryLevel? {
        switch part {
        case .left: left
        case .right: right
        case .chargingCase: chargingCase
        }
    }
    var isEmpty: Bool { main == nil && !hasParts }

    /// The one value the band shows: the combined level, else the emptier earbud (the case never counts).
    var summary: BatteryLevel? {
        if let main { return main }
        switch (left, right) {
        case let (l?, r?): return l.percent <= r.percent ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }
}

/// What a device is, for its glyph and its generic name.
nonisolated enum AccessoryKind: String, Equatable, Sendable, CaseIterable {
    case headphones, earbuds, speaker, keyboard, mouse, trackpad, gameController, other
}

/// A connected accessory.
nonisolated struct Accessory: Equatable, Sendable, Identifiable {
    /// Stable for the connection: "audio:<device UID>", "hid:<registry entry ID>", "bluetooth:<address>".
    var id: String
    /// The device's own name ("AirPods Pro", or the name the user gave it).
    var name: String
    var kind: AccessoryKind
    /// Bluetooth SIG / USB vendor; Apple is 76.
    var vendorID: Int?
    var productID: Int?
    var batteries: AccessoryBatteries

    init(id: String, name: String, kind: AccessoryKind, vendorID: Int? = nil, productID: Int? = nil,
         batteries: AccessoryBatteries = .unknown) {
        self.id = id; self.name = name; self.kind = kind
        self.vendorID = vendorID; self.productID = productID; self.batteries = batteries
    }

    /// SF Symbol (DESIGN.md §14.1; restricted symbols only for their products).
    var symbol: String { DeviceSymbols.symbol(vendorID: vendorID, productID: productID, kind: kind) }
}

// CrannySystemActivities/Accessories/HIDPeripheralWatcher.swift — Apple's Magic Keyboard, Mouse and Trackpad,
// permission-free: IOKit matching notifications on `AppleDeviceManagementHIDEventService`, whose registry
// entries publish `BatteryPercent`, `Product`, `ProductID` and `Transport` [VERIFIED R3 §3, macOS 27].
//
// Threading: confined to `queue`. The notification port delivers there, every registry read happens there,
// and results leave as Sendable values through `onChange` (the caller hops to the main actor).
//
// Energy: the built-in keyboard and trackpad also match the service (they re-match around sleep and wake) and
// `parse` drops them, so a drain that changed nothing an accessory list shows is not reported.
import CrannyCore
import Foundation
import IOKit
import os

nonisolated private let log = Log.logger(.bluetooth)

/// A Bluetooth HID accessory with a battery.
nonisolated struct HIDPeripheral: Equatable, Sendable, Identifiable {
    /// IORegistry entry ID: stable while connected.
    var id: UInt64
    var name: String
    var category: String?
    var vendorID: Int?
    var productID: Int?
    var batteryPercent: Int?

    /// Keeps external Bluetooth accessories only (the built-in keyboard/trackpad also matches the service).
    static func parse(_ properties: [String: Any], id: UInt64) -> HIDPeripheral? {
        let transport = (properties["Transport"] as? String) ?? ""
        guard !(IOPSValue.bool(properties["Built-In"]) ?? false),
              transport.localizedCaseInsensitiveContains("bluetooth") else { return nil }
        let name = ((properties["Product"] as? String) ?? "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return HIDPeripheral(id: id, name: name, category: properties["Accessory Category"] as? String,
                             vendorID: IOPSValue.int(properties["VendorID"]), productID: IOPSValue.int(properties["ProductID"]),
                             batteryPercent: IOPSValue.int(properties["BatteryPercent"]))
    }
}

nonisolated final class HIDPeripheralWatcher: @unchecked Sendable {   // confined to `queue` (see the top)
    private static let serviceClass = "AppleDeviceManagementHIDEventService"
    private static let keys = ["Built-In", "Transport", "Product", "Accessory Category", "VendorID", "ProductID", "BatteryPercent"]

    private let queue = DispatchQueue(label: "app.cranny.system.hid", qos: .utility)
    /// Called on `queue` with a report number (increasing, so the receiver can drop reports that arrive late).
    private let onChange: @Sendable (Int, [HIDPeripheral]) -> Void
    private var sequence = 0
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var devices: [UInt64: HIDPeripheral] = [:]
    /// The list reported last (nil before the baseline, which is always reported).
    private var lastReported: [HIDPeripheral]?

    init(onChange: @escaping @Sendable (Int, [HIDPeripheral]) -> Void) { self.onChange = onChange }

    /// Starts matching notifications; the first report lists the accessories already connected.
    /// The port's context pointer is unretained: `stop()` destroys the port before this object can go away
    /// (the owner keeps it until then, and `stop()`'s block retains it).
    func start() {
        queue.async { [self] in
            guard port == nil, let created = IONotificationPortCreate(kIOMainPortDefault) else { return }
            port = created
            IONotificationPortSetDispatchQueue(created, queue)
            let context = Unmanaged.passUnretained(self).toOpaque()
            let added: IOServiceMatchingCallback = { context, iterator in
                guard let context else { return }
                Unmanaged<HIDPeripheralWatcher>.fromOpaque(context).takeUnretainedValue().drain(iterator, added: true)
            }
            let removed: IOServiceMatchingCallback = { context, iterator in
                guard let context else { return }
                Unmanaged<HIDPeripheralWatcher>.fromOpaque(context).takeUnretainedValue().drain(iterator, added: false)
            }
            let status = IOServiceAddMatchingNotification(created, kIOFirstMatchNotification, IOServiceMatching(Self.serviceClass),
                                                          added, context, &addedIterator)
            IOServiceAddMatchingNotification(created, kIOTerminatedNotification, IOServiceMatching(Self.serviceClass),
                                             removed, context, &removedIterator)
            if status != KERN_SUCCESS { log.error("HID matching notification failed: \(status, privacy: .public)") }
            // Draining arms the notifications; the first drain is the baseline.
            drain(removedIterator, added: false, report: false)
            drain(addedIterator, added: true)
        }
    }

    func stop() {
        queue.async { [self] in
            if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
            if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
            if let port { IONotificationPortDestroy(port) }
            port = nil
            devices = [:]
            lastReported = nil
        }
    }

    private func drain(_ iterator: io_iterator_t, added: Bool, report: Bool = true) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            if added {
                devices[id] = Self.read(service, id: id)
            } else {
                devices[id] = nil
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        guard report else { return }
        let list = devices.values.sorted { $0.id < $1.id }
        guard list != lastReported else { return }      // e.g. only the built-in devices re-matched
        lastReported = list
        sequence += 1
        onChange(sequence, list)
    }

    // MARK: Registry reads

    /// Every connected accessory right now (battery levels change without notifications; IPC: off the main actor).
    static func readAll() -> [HIDPeripheral] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [HIDPeripheral] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            if let peripheral = read(service, id: id) { out.append(peripheral) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return out.sorted { $0.id < $1.id }
    }

    @concurrent static func snapshot() async -> [HIDPeripheral] { readAll() }

    private static func read(_ service: io_service_t, id: UInt64) -> HIDPeripheral? {
        var properties: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                properties[key] = value
            }
        }
        return HIDPeripheral.parse(properties, id: id)
    }
}

// CrannyEffects/Layer/AmbientGPU.swift — which GPU draws the effects (ARCHITECTURE.md §9.2 energy rules).
//
// Never `MTLCreateSystemDefaultDevice()`: on Macs with automatic graphics switching it returns the discrete GPU and
// switches the system to it (MTLDevice.h), which would keep the discrete GPU powered for as long as a device is held.
// `MTLCopyAllDevices()` and `CGDirectDisplayCopyCurrentMetalDevice` never switch GPUs, so the choice stays ours.
import CoreGraphics
import Foundation
import Metal

nonisolated enum AmbientGPU {
    /// What the policy needs to know about one Metal device.
    struct Candidate: Equatable, Sendable {
        var id: UInt64
        var isLowPower: Bool
        var isRemovable: Bool
        var isHeadless: Bool

        init(id: UInt64, isLowPower: Bool, isRemovable: Bool = false, isHeadless: Bool = false) {
            self.id = id; self.isLowPower = isLowPower; self.isRemovable = isRemovable; self.isHeadless = isHeadless
        }

        init(_ device: any MTLDevice) {
            self.init(id: device.registryID, isLowPower: device.isLowPower, isRemovable: device.isRemovable,
                      isHeadless: device.isHeadless)
        }
    }

    /// The device to draw with, as an index into `candidates`:
    /// 1. the built-in low-power (integrated) GPU when the Mac has one, so ambient light never powers up or pins a
    ///    discrete GPU (dual-GPU MacBook Pros, Intel Macs);
    /// 2. otherwise the GPU driving the panel's display (`displayDevice`), so frames need no copy between GPUs;
    /// 3. otherwise the first built-in GPU that drives displays, then any GPU.
    static func choose(_ candidates: [Candidate], displayDevice: UInt64?) -> Int? {
        if let index = candidates.firstIndex(where: { $0.isLowPower && !$0.isRemovable && !$0.isHeadless }) {
            return index
        }
        if let displayDevice, let index = candidates.firstIndex(where: { $0.id == displayDevice }) { return index }
        if let index = candidates.firstIndex(where: { !$0.isRemovable && !$0.isHeadless }) { return index }
        return candidates.isEmpty ? nil : 0
    }

    /// Whether holding `chosen` could keep a discrete GPU powered. False for a low-power GPU and for a Mac's only GPU;
    /// such a renderer may stay alive between opens, any other is released as soon as no view uses it.
    static func mayPinDiscreteGPU(_ chosen: Candidate, deviceCount: Int) -> Bool {
        !chosen.isLowPower && deviceCount > 1
    }

    /// The Metal device for effects on `displayID` (nil: the main display), or nil when this Mac has none.
    static func device(forDisplay displayID: CGDirectDisplayID? = nil) -> (any MTLDevice)? {
        let devices = MTLCopyAllDevices()
        let display = CGDirectDisplayCopyCurrentMetalDevice(displayID ?? CGMainDisplayID())?.registryID
        guard let index = choose(devices.map(Candidate.init), displayDevice: display) else { return nil }
        return devices[index]
    }

    /// The number of Metal devices in this Mac (for `mayPinDiscreteGPU`).
    static var deviceCount: Int { MTLCopyAllDevices().count }
}
